
`include "mycpu.h"

module csr (
    input  wire                   clk,
    input  wire                   reset,

    // 以下请求均来自WB级，仅在有效指令到达WB时使能。
    // csr_re/csr_we为0时应忽略对应编号和数据，无需要求它们也变为0。
    input  wire                   csr_re,      // 读使能；csrrd、csrwr、csrxchg均需读取旧值
    input  wire [`CSR_NUM_WD-1:0] csr_num,     // 读写共用的CSR编号，不是内存字节地址
    output wire [31:0]            csr_rvalue,  // 组合读出的CSR旧值，供WB写回通用寄存器rd
    input  wire                   csr_we,      // 写使能；仅csrwr、csrxchg更新CSR
    input  wire [31:0]            csr_wmask,   // 写掩码：1表示请求更新该位，仍需遵守CSR各位的读写属性
    input  wire [31:0]            csr_wvalue,  // 写入值，来自指令执行前的GR[rd]

    // wb_ex为1表示本拍有异常需要提交；wb_pc是异常指令自身的PC。
    // wb_ecode/wb_esubcode描述异常原因，例如syscall对应6'h0b和9'b0。
    input  wire                   wb_ex,
    input  wire [31:0]            wb_pc,
    input  wire [5:0]             wb_ecode,
    input  wire [8:0]             wb_esubcode,
    output wire [31:0]            ex_entry,    // 普通异常入口，由EENTRY提供

    // ertn在WB生效：后续由CSR模块将PRMD.PPLV/PIE恢复至CRMD.PLV/IE。
    input  wire                   ertn_flush,  // WB发出的返回生效信号，同时用于流水线清空
    output wire [31:0]            ertn_entry   // 返回目标地址，后续由CSR.ERA提供给IF级
);

// 以下两行保留原接口预留阶段的说明；本版已在下方补齐CSR存储和输出逻辑。
// exp12第一步仅预留接口；CSR存储、读写和ertn状态恢复留到下一步实现。
// csr_rvalue、ertn_entry当前刻意不驱动，不能据此执行CSR功能仿真。

// crmd：挡墙特权级plv，中断使能ie，直接访问da，映射地址pg，
// PLV对应[1:0]，IE对应[2]；DA/PG对应[3]/[4]，选择地址翻译模式。
// DATF对应[6:5]、DATM对应[8:7]，分别记录直接地址翻译模式下取指和数据访存的属性。
reg [1:0] crmd_plv;
reg       crmd_ie;
reg       crmd_da;
reg       crmd_pg;
reg [1:0] crmd_datf;
reg [1:0] crmd_datm;
// 异常前的特权级。
// PPLV/PIE对应PRMD[1:0]/[2]，供ertn恢复到CRMD。
reg [1:0] prmd_pplv;
reg       prmd_pie;
// estat 当前的方法
// ESTAT：软件中断状态、异常码；本实验尚未接入其它中断源。
// sw_is对应[1:0]；ecode/esubcode分别对应[21:16]/[30:22]。
reg [1:0] estat_sw_is;  
reg [5:0] estat_ecode;
reg [8:0] estat_esubcode;
// 异常返回地址
reg [31:0] era;

// 异常入口地址
reg [25:0] eentry_va;   
// 异常处理程序所用地址
// SAVE0~3：软件暂存数据；异常和ertn不会自动修改它们。
reg [31:0] save0;
reg [31:0] save1;
reg [31:0] save2;
reg [31:0] save3;

// 正常的csrwr/csrxchg允许写入；异常提交或ertn生效时，屏蔽软件写请求。
wire csr_write;
assign csr_write = csr_we && !wb_ex && !ertn_flush;

// 普通异常仅修改PLV/IE，保留DA/PG/DATF/DATM；TLB相关异常留待后续实验。
// CRMD的PLV/IE更新优先级：复位 > 异常提交 > ertn恢复 > CSR掩码写。
always @(posedge clk) begin
    if (reset) begin
        // 复位后进入特权级0、关闭中断，并使用直接地址翻译模式。
        crmd_plv  <= 2'b0;
        crmd_ie   <= 1'b0;
        crmd_da   <= 1'b1;
        crmd_pg   <= 1'b0;
        crmd_datf <= 2'b0;
        crmd_datm <= 2'b0;
    end
    else begin
        if (wb_ex) begin
            // 进入异常处理时提升至特权级0，并暂时关闭中断。
            crmd_plv <= 2'b0;
            crmd_ie  <= 1'b0;
        end
        else if (ertn_flush) begin
            // 异常返回清空指令
            crmd_plv <= prmd_pplv;
            crmd_ie  <= prmd_pie;
        end
        else if (csr_write && csr_num == `CSR_CRMD) begin
            // 掩码为1的位采用新值，为0的位保留旧值；其它CSR字段同样处理。
            crmd_plv <= (crmd_plv & ~csr_wmask[1:0]) | (csr_wvalue[1:0] & csr_wmask[1:0]);
            crmd_ie  <= (crmd_ie & ~csr_wmask[2]) | (csr_wvalue[2] & csr_wmask[2]);
        end

        if (csr_write && csr_num == `CSR_CRMD) begin
            crmd_da   <= (crmd_da & ~csr_wmask[3]) | (csr_wvalue[3] & csr_wmask[3]);
            crmd_pg   <= (crmd_pg & ~csr_wmask[4]) | (csr_wvalue[4] & csr_wmask[4]);
            crmd_datf <= (crmd_datf & ~csr_wmask[6:5]) | (csr_wvalue[6:5] & csr_wmask[6:5]);
            crmd_datm <= (crmd_datm & ~csr_wmask[8:7]) | (csr_wvalue[8:7] & csr_wmask[8:7]);
        end
    end
end

always @(posedge clk) begin
    if (reset) begin
        prmd_pplv <= 2'b0;
        prmd_pie  <= 1'b0;
    end
    else if (wb_ex) begin
        prmd_pplv <= crmd_plv;
        prmd_pie  <= crmd_ie;
    end
    else if (csr_write && csr_num == `CSR_PRMD) begin
        prmd_pplv <= (prmd_pplv & ~csr_wmask[1:0]) | (csr_wvalue[1:0] & csr_wmask[1:0]);
        prmd_pie  <= (prmd_pie & ~csr_wmask[2]) | (csr_wvalue[2] & csr_wmask[2]);
    end
end

// estat只有is[1:0]可由csr指令写入；Ecode/EsubCode由异常提交更新。
always @(posedge clk) begin
    if (reset) begin
        estat_sw_is    <= 2'b0;
        estat_ecode    <= 6'b0;
        estat_esubcode <= 9'b0;
    end
    else begin
        if (csr_write && csr_num == `CSR_ESTAT)
            estat_sw_is <= (estat_sw_is & ~csr_wmask[1:0]) | (csr_wvalue[1:0] & csr_wmask[1:0]);
        if (wb_ex) begin
            estat_ecode    <= wb_ecode;
            estat_esubcode <= wb_esubcode;
        end
    end
end

always @(posedge clk) begin
    if (reset)
        era <= 32'b0;
    else if (wb_ex) //高优先级
        era <= wb_pc;
    else if (csr_write && csr_num == `CSR_ERA)
        era <= (era & ~csr_wmask) | (csr_wvalue & csr_wmask);
end

// eentry最低6位只读为0，仅存储地址的高26位。
always @(posedge clk) begin
    if (reset)
        eentry_va <= 26'b0;
    else if (csr_write && csr_num == `CSR_EENTRY)
        eentry_va <= (eentry_va & ~csr_wmask[31:6]) | (csr_wvalue[31:6] & csr_wmask[31:6]);
end

// SAVE0~3：按csr_num选中一个寄存器，再对其32位数据进行掩码写。
always @(posedge clk) begin
    if (reset) begin
        save0 <= 32'b0;
        save1 <= 32'b0;
        save2 <= 32'b0;
        save3 <= 32'b0;
    end
    else if (csr_write) begin
        case (csr_num)
            `CSR_SAVE0:
                save0 <= (save0 & ~csr_wmask) | (csr_wvalue & csr_wmask);

            `CSR_SAVE1:
                save1 <= (save1 & ~csr_wmask) | (csr_wvalue & csr_wmask);

            `CSR_SAVE2:
                save2 <= (save2 & ~csr_wmask) | (csr_wvalue & csr_wmask);

            `CSR_SAVE3:
                save3 <= (save3 & ~csr_wmask) | (csr_wvalue & csr_wmask);
        endcase
    end
end


wire [31:0] crmd_value;
wire [31:0] prmd_value;
wire [31:0] estat_value;
wire [31:0] csr_read_data;

assign crmd_value = {23'b0, crmd_datm, crmd_datf, crmd_pg, crmd_da, crmd_ie, crmd_plv};
assign prmd_value = {29'b0, prmd_pie, prmd_pplv};
// ESTAT依次为：保留位、异常子码、异常码、保留位、其它中断位、软件中断位。
assign estat_value = {1'b0, estat_esubcode, estat_ecode, 3'b0, 11'b0, estat_sw_is};

assign csr_read_data = ({32{csr_num == `CSR_CRMD  }} & crmd_value)
                     | ({32{csr_num == `CSR_PRMD  }} & prmd_value)
                     | ({32{csr_num == `CSR_ESTAT }} & estat_value)
                     | ({32{csr_num == `CSR_ERA   }} & era)
                     | ({32{csr_num == `CSR_EENTRY}} & {eentry_va, 6'b0})
                     | ({32{csr_num == `CSR_SAVE0 }} & save0)
                     | ({32{csr_num == `CSR_SAVE1 }} & save1)
                     | ({32{csr_num == `CSR_SAVE2 }} & save2)
                     | ({32{csr_num == `CSR_SAVE3 }} & save3);
// 当csr-re = 1  的时候才进行并
assign csr_rvalue = {32{csr_re}} & csr_read_data;
// 返回地址与异常入口持续输出，不受csr_re或当前csr_num的影响。
assign ertn_entry = era;
assign ex_entry   = {eentry_va, 6'b0};

endmodule
