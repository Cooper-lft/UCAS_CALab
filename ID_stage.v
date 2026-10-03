module ID_stage (
    input  wire        clk,
    input  wire        reset,
    
    input  wire        IF_to_ID_valid,
    input  wire [63:0] IF_to_ID_bus,
    
    input  wire        EX_allowin,
    output wire [151:0] ID_to_EX_bus,
    output wire        ID_to_EX_valid,
    
    output wire        ID_allowin,
    // form WB stage
    input  wire        WB_rf_we,
    input  wire [ 4:0] WB_rf_waddr,
    input  wire [31:0] WB_rf_wdata,

    output wire        br_taken,
    output wire [31:0] br_target,

    // 判断数据相关的信号，来自EX,MEM,WB级（也被用于前递的判断）
    input  wire        EX_valid,
    input  wire [ 4:0] EX_dest,
    input  wire        EX_rf_we,
    input  wire        load_in_EX,
    input  wire [31:0] EX_wdata_forward,

    input  wire        MEM_valid,
    input  wire [ 4:0] MEM_dest,
    input  wire        MEM_rf_we,
    input  wire [31:0] MEM_wdata_forward,

    input  wire        WB_valid,
    // WB的写使能和目的寄存器号已经在前面声明过了，WB_rf_we, WB_rf_waddr

    // 处理控制冒险
    output wire        br_taken_cancel
);

wire        ID_readygo;
reg [63:0]  ID_data; // from IF
reg         ID_valid;

// 检测数据冲突
/* 
wire    rj_wait;
wire    rk_wait;
wire    rd_wait;
*/
wire    data_hazard;

// WB级前递的数据：
wire [31:0] WB_wdata_forward;
assign WB_wdata_forward = WB_rf_wdata;

assign ID_allowin   = !ID_valid || ID_readygo && EX_allowin;
assign ID_readygo   = !data_hazard;
assign ID_to_EX_valid = ID_valid && ID_readygo;
always @(posedge clk) begin
    if (reset) begin
        ID_valid <= 1'b0;
    end
    else if (br_taken_cancel) begin  // 控制冒险
        ID_valid <= 1'b0;
    end
    else if (ID_allowin) begin
        ID_valid <= IF_to_ID_valid;
    end

    if (IF_to_ID_valid && ID_allowin) begin
        ID_data <= IF_to_ID_bus;
    end
end

wire [31:0] ID_pc;
wire [31:0] inst;

assign {ID_pc,
        inst}       = ID_data;

wire        ID_rf_we;
wire [ 4:0] ID_dest;
wire        ID_sel_rf_res;
wire [31:0] ID_alu_src1;
wire [31:0] ID_alu_src2;
wire [11:0] ID_alu_op;  
wire [31:0] ID_data_sram_wdata;  
wire [ 3:0] ID_data_sram_we;
wire        ID_data_sram_en;

assign ID_to_EX_bus = {ID_pc,
                       ID_rf_we,
                       ID_dest,
                       ID_sel_rf_res,
                       ID_alu_src1,
                       ID_alu_src2,
                       ID_alu_op,
                       ID_data_sram_wdata,
                       ID_data_sram_we,
                       ID_data_sram_en};


// decode
wire        src1_is_pc;
wire        src1_is_0;      // lu12i指令的alu的操作数1应该是0而不是pc或者是寄存器的值，操作数2是立即数
wire        src2_is_imm;
wire        dst_is_r1;
wire        gr_we;          // 寄存器堆写使能
wire        mem_we;
wire        src_reg_is_rd;  // 源目的寄存器是来自rd字段的，即从寄存器堆中读出rd字段的寄存器号的数据(因为可能来自rk字段，当然也可能是立即数)
wire [4: 0] dest;
wire [31:0] rj_value;
wire [31:0] rkd_value;
wire [31:0] imm;
wire [31:0] br_offs;
wire [31:0] jirl_offs;

wire [ 5:0] op_31_26;
wire [ 3:0] op_25_22;
wire [ 1:0] op_21_20;
wire [ 4:0] op_19_15;
wire [ 4:0] rd;
wire [ 4:0] rj;
wire [ 4:0] rk;
wire [11:0] i12;
wire [19:0] i20;
wire [15:0] i16;
wire [25:0] i26;

wire [63:0] op_31_26_d;
wire [15:0] op_25_22_d;
wire [ 3:0] op_21_20_d;
wire [31:0] op_19_15_d;

wire        inst_add_w;
wire        inst_sub_w;
wire        inst_slt;
wire        inst_sltu;
wire        inst_nor;
wire        inst_and;
wire        inst_or;
wire        inst_xor;
wire        inst_slli_w;
wire        inst_srli_w;
wire        inst_srai_w;
wire        inst_addi_w;
wire        inst_ld_w;
wire        inst_st_w;
wire        inst_jirl;
wire        inst_b;
wire        inst_bl;
wire        inst_beq;
wire        inst_bne;
wire        inst_lu12i_w;

wire        need_ui5;
wire        need_si12;
wire        need_si16;
wire        need_si20;
wire        need_si26;
wire        src2_is_4;

wire [ 4:0] rf_raddr1;
wire [31:0] rf_rdata1;
wire [ 4:0] rf_raddr2;
wire [31:0] rf_rdata2;

assign op_31_26  = inst[31:26];
assign op_25_22  = inst[25:22];
assign op_21_20  = inst[21:20];
assign op_19_15  = inst[19:15];

assign rd   = inst[ 4: 0];
assign rj   = inst[ 9: 5];
assign rk   = inst[14:10];

assign i12  = inst[21:10];
assign i20  = inst[24: 5];
assign i16  = inst[25:10];
assign i26  = {inst[ 9: 0], inst[25:10]};

decoder_6_64 u_dec0(.in(op_31_26 ), .out(op_31_26_d ));
decoder_4_16 u_dec1(.in(op_25_22 ), .out(op_25_22_d ));
decoder_2_4  u_dec2(.in(op_21_20 ), .out(op_21_20_d ));
decoder_5_32 u_dec3(.in(op_19_15 ), .out(op_19_15_d ));

assign inst_add_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h00];
assign inst_sub_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h02];
assign inst_slt    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h04];
assign inst_sltu   = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h05];
assign inst_nor    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h08];
assign inst_and    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h09];
assign inst_or     = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0a];
assign inst_xor    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0b];
assign inst_slli_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h01];
assign inst_srli_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h09];
assign inst_srai_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h11];
assign inst_addi_w = op_31_26_d[6'h00] & op_25_22_d[4'ha];
assign inst_ld_w   = op_31_26_d[6'h0a] & op_25_22_d[4'h2];
assign inst_st_w   = op_31_26_d[6'h0a] & op_25_22_d[4'h6];
assign inst_jirl   = op_31_26_d[6'h13];
assign inst_b      = op_31_26_d[6'h14];
assign inst_bl     = op_31_26_d[6'h15];
assign inst_beq    = op_31_26_d[6'h16];
assign inst_bne    = op_31_26_d[6'h17];
assign inst_lu12i_w= op_31_26_d[6'h05] & ~inst[25];

assign ID_alu_op[ 0] = inst_add_w | inst_addi_w | inst_ld_w | inst_st_w
                    | inst_jirl | inst_bl;
assign ID_alu_op[ 1] = inst_sub_w;
assign ID_alu_op[ 2] = inst_slt;
assign ID_alu_op[ 3] = inst_sltu;
assign ID_alu_op[ 4] = inst_and;
assign ID_alu_op[ 5] = inst_nor;
assign ID_alu_op[ 6] = inst_or;
assign ID_alu_op[ 7] = inst_xor;
assign ID_alu_op[ 8] = inst_slli_w;
assign ID_alu_op[ 9] = inst_srli_w;
assign ID_alu_op[10] = inst_srai_w;
assign ID_alu_op[11] = inst_lu12i_w;

assign need_ui5   =  inst_slli_w | inst_srli_w | inst_srai_w;
assign need_si12  =  inst_addi_w | inst_ld_w | inst_st_w;
assign need_si16  =  inst_jirl | inst_beq | inst_bne;
assign need_si20  =  inst_lu12i_w;
assign need_si26  =  inst_b | inst_bl;
assign src2_is_4  =  inst_jirl | inst_bl;

assign imm = src2_is_4 ? 32'h4                      :
             need_si20 ? {i20[19:0], 12'b0}         :
/*need_ui5 || need_si12*/{{20{i12[11]}}, i12[11:0]} ;

assign br_offs = need_si26 ? {{ 4{i26[25]}}, i26[25:0], 2'b0} :
                             {{14{i16[15]}}, i16[15:0], 2'b0} ;

assign jirl_offs = {{14{i16[15]}}, i16[15:0], 2'b0};

assign src_reg_is_rd = inst_beq | inst_bne | inst_st_w;

assign src1_is_pc    = inst_jirl | inst_bl;
assign src1_is_0     = inst_lu12i_w;    // lu12i指令的alu的操作数1应该是0而不是pc或者是寄存器的值，操作数2是立即数

assign src2_is_imm   = inst_slli_w |
                       inst_srli_w |
                       inst_srai_w |
                       inst_addi_w |
                       inst_ld_w   |
                       inst_st_w   |
                       inst_lu12i_w|
                       inst_jirl   |
                       inst_bl     ;

assign ID_sel_rf_res    = inst_ld_w;
assign dst_is_r1        = inst_bl;

assign gr_we            = ~inst_st_w & ~inst_beq & ~inst_bne & ~inst_b;
assign mem_we           = inst_st_w;
assign ID_dest          = dst_is_r1 ? 5'd1 : rd;
assign ID_rf_we         = gr_we && ID_valid;

assign rf_raddr1 = rj;
assign rf_raddr2 = src_reg_is_rd ? rd :rk;
regfile u_regfile(
    .clk   (clk        ),
    .raddr1(rf_raddr1  ),
    .rdata1(rf_rdata1  ),
    .raddr2(rf_raddr2  ),
    .rdata2(rf_rdata2  ),
    .we    (WB_rf_we   ),
    .waddr (WB_rf_waddr),
    .wdata (WB_rf_wdata)
    );


wire rj_eq_rd;
assign rj_eq_rd = (rj_value == rkd_value);
assign br_taken = (   inst_beq  &&  rj_eq_rd
                   || inst_bne  && !rj_eq_rd
                   || inst_jirl
                   || inst_bl
                   || inst_b
                  ) && ID_valid;
assign br_target = (inst_beq || inst_bne || inst_bl || inst_b) ? (ID_pc + br_offs) :
                                                   /*inst_jirl*/ (rj_value + jirl_offs);

assign ID_alu_src1 = (src1_is_pc) ? ID_pc[31:0] : 
                     (src1_is_0 ) ? 32'b0 : rj_value;
assign ID_alu_src2 = src2_is_imm ? imm : rkd_value;

assign ID_data_sram_we      = {4{mem_we && ID_valid}};
assign ID_data_sram_en      = ID_valid && (inst_st_w || inst_ld_w); 
assign ID_data_sram_wdata   = rkd_value;

// 检查数据冲突
wire [ 4:0] WB_dest;
wire        rj_used;
wire        rk_used;
wire        rd_used;
assign  WB_dest = WB_rf_waddr;

// 目前只有load-use类会发生数据冲突(EX级有load指令，且发生了RAW)
assign data_hazard = ID_valid && load_in_EX && (EX_dest != 5'b0) && (
                    rk_used && (EX_dest == rk) ||
                    rd_used && (EX_dest == rd) ||
                    rj_used && (EX_dest == rj)
                    );

assign rj_used = inst_add_w  |
                 inst_sub_w  |
                 inst_slt    |
                 inst_sltu   |
                 inst_nor    |
                 inst_and    |
                 inst_or     |
                 inst_xor    |
                 inst_slli_w |
                 inst_srli_w |
                 inst_srai_w |
                 inst_addi_w |
                 inst_ld_w   |
                 inst_st_w   |
                 inst_jirl   |
                 inst_beq    |
                 inst_bne;

assign rk_used = inst_add_w |
                 inst_sub_w |
                 inst_slt   |
                 inst_sltu  |
                 inst_nor   |
                 inst_and   |
                 inst_or    |
                 inst_xor;

assign rd_used = inst_st_w |
                 inst_beq  |
                 inst_bne;
/* 这是阻塞实现的逻辑，但是前递实现下需要修改
assign  data_hazard = ID_valid && (rj_wait || rk_wait || rd_wait);

// 表明ID级处的指令要用指令哪一个字段（rj，rk，rd）代表的寄存器号读取数据
wire        rj_used;
wire        rk_used;
wire        rd_used;
// rj_used表明ALU的src1是寄存器的值，rk/rd_used表明ALU的src2是寄存器的值
assign rj_used = inst_add_w  |
                 inst_sub_w  |
                 inst_slt    |
                 inst_sltu   |
                 inst_nor    |
                 inst_and    |
                 inst_or     |
                 inst_xor    |
                 inst_slli_w |
                 inst_srli_w |
                 inst_srai_w |
                 inst_addi_w |
                 inst_ld_w   |
                 inst_st_w   |
                 inst_jirl   |
                 inst_beq    |
                 inst_bne;

assign rk_used = inst_add_w |
                 inst_sub_w |
                 inst_slt   |
                 inst_sltu  |
                 inst_nor   |
                 inst_and   |
                 inst_or    |
                 inst_xor;

assign rd_used = inst_st_w |
                 inst_beq  |
                 inst_bne;

assign  rj_wait     = rj_used       &&
                      (rj != 5'b0 ) &&
                      (
                        EX_valid && EX_rf_we && (EX_dest != 5'b0) && EX_dest == rj ||
                        MEM_valid && MEM_rf_we && (MEM_dest != 5'b0) && MEM_dest == rj ||
                        WB_valid && WB_rf_we && (WB_dest != 5'b0) && WB_dest == rj 
                      ); 

assign  rk_wait     = rk_used           &&
                      (rk != 5'b0 )     &&
                      (!src_reg_is_rd)  &&
                      (
                        EX_valid    && EX_rf_we     && (EX_dest != 5'b0)    && EX_dest == rk    ||
                        MEM_valid   && MEM_rf_we    && (MEM_dest != 5'b0)   && MEM_dest == rk   ||
                        WB_valid    && WB_rf_we     && (WB_dest != 5'b0)    && WB_dest == rk 
                      ); 

assign  rd_wait     = rd_used           &&
                      (rd != 5'b0 )     &&
                      (src_reg_is_rd)   &&
                      (
                        EX_valid    && EX_rf_we     && (EX_dest != 5'b0)    && EX_dest == rd    ||
                        MEM_valid   && MEM_rf_we    && (MEM_dest != 5'b0)   && MEM_dest == rd   ||
                        WB_valid    && WB_rf_we     && (WB_dest != 5'b0)    && WB_dest == rd 
                      ); 
*/
// 存在前递的表征信号：
wire    EX_forward_valid_prefix;
wire    EX_forward_src1;     // EX级存在前递，说明EX级指令有效, 且EX级有寄存器写使能，且写的目的寄存器号不是0, 然后再比对是rj还是rkd
wire    EX_forward_src2_rk;
wire    EX_forward_src2_rd;
wire    EX_forward_src2;

wire    MEM_forward_valid_prefix;
wire    MEM_forward_src1;
wire    MEM_forward_src2_rk;
wire    MEM_forward_src2_rd;
wire    MEM_forward_src2;

wire    WB_forward_valid_prefix;
wire    WB_forward_src1;
wire    WB_forward_src2_rk;
wire    WB_forward_src2_rd;
wire    WB_forward_src2;

assign  EX_forward_valid_prefix     = EX_valid  &&  EX_rf_we   &&  EX_dest  != 5'b0;
assign  EX_forward_src1             = EX_forward_valid_prefix  &&  EX_dest  == rj;
assign  EX_forward_src2_rk          = EX_forward_valid_prefix  &&  EX_dest  == rk; 
assign  EX_forward_src2_rd          = EX_forward_valid_prefix  &&  EX_dest  == rd;
assign  EX_forward_src2             = (rk_used && EX_forward_src2_rk) || (rd_used && EX_forward_src2_rd);

assign  MEM_forward_valid_prefix    = MEM_valid &&  MEM_rf_we   &&  MEM_dest != 5'b0;
assign  MEM_forward_src1            = MEM_forward_valid_prefix  &&  MEM_dest == rj;
assign  MEM_forward_src2_rk         = MEM_forward_valid_prefix  &&  MEM_dest == rk;
assign  MEM_forward_src2_rd         = MEM_forward_valid_prefix  &&  MEM_dest == rd;
assign  MEM_forward_src2            = (rk_used && MEM_forward_src2_rk) || (rd_used && MEM_forward_src2_rd);

assign  WB_forward_valid_prefix     = WB_valid  &&  WB_rf_we   &&  WB_dest  != 5'b0;
assign  WB_forward_src1             = WB_forward_valid_prefix  &&  WB_dest  == rj;
assign  WB_forward_src2_rk          = WB_forward_valid_prefix  &&  WB_dest  == rk;
assign  WB_forward_src2_rd          = WB_forward_valid_prefix  &&  WB_dest  == rd;
assign  WB_forward_src2             = (rk_used && WB_forward_src2_rk) || (rd_used && WB_forward_src2_rd);

// 前递的数据选择,四选一优先级多路选择器
assign rj_value  = (EX_forward_src1 )? EX_wdata_forward  :
                   (MEM_forward_src1)? MEM_wdata_forward :
                   (WB_forward_src1 )? WB_wdata_forward  :
                    rf_rdata1;
assign rkd_value = (EX_forward_src2 )? EX_wdata_forward  :
                   (MEM_forward_src2)? MEM_wdata_forward :
                   (WB_forward_src2 )? WB_wdata_forward  :
                    rf_rdata2;

// 控制冒险
assign  br_taken_cancel = !data_hazard && br_taken; // 表明IF级已经取到的指令（或者还在取回来路上的）需要被取消
endmodule