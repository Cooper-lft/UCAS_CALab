module ID_stage (
    input  wire        clk,
    input  wire        reset,
    
    input  wire        IF_to_ID_valid,
    input  wire [63:0] IF_to_ID_bus,
    
    input  wire        EX_allowin,
    output wire [157:0] ID_to_EX_bus,
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
wire        data_hazard;
// 用于解决时序违例，而让涉及前递的跳转指令阻塞在ID级直到EX级指令流入MEM级
wire        br_block;
wire        br_need_rj;
wire        br_need_rd;
wire [31:0] rj_value_mem_wb;
wire [31:0] rkd_value_mem_wb;

// WB级前递的数据：
wire [31:0] WB_wdata_forward;
assign WB_wdata_forward = WB_rf_wdata;

assign ID_allowin   = !ID_valid || ID_readygo && EX_allowin;
assign ID_readygo   = !data_hazard && !br_block;
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
wire [14:0] ID_alu_op;  
wire [31:0] ID_data_sram_wdata;  
wire [ 3:0] ID_data_sram_we;
wire        ID_data_sram_en;
wire        ID_is_div;      // 除法或取余指令
wire        ID_div_signed;  // 有符号运算(求商或者取余)
wire        ID_div_is_mod;  // 选择余数，否则选择商

assign ID_to_EX_bus = {ID_pc,
                       ID_rf_we,
                       ID_dest,
                       ID_sel_rf_res,
                       ID_alu_src1,
                       ID_alu_src2,
                       ID_alu_op,
                       ID_data_sram_wdata,
                       ID_data_sram_we,
                       ID_data_sram_en,
                       ID_is_div,
                       ID_div_signed,
                       ID_div_is_mod};


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
wire        inst_slti;
wire        inst_sltui;
wire        inst_andi;
wire        inst_ori;
wire        inst_xori;
wire        inst_sll_w;
wire        inst_srl_w;
wire        inst_sra_w;
wire        inst_pcaddu12i;
wire        inst_div_w;
wire        inst_div_wu;
wire        inst_mod_w;
wire        inst_mod_wu;
wire        inst_mul;
wire        inst_mulh;
wire        inst_mulhu;

wire        need_ui5;
wire        need_ui12;
wire        need_si12;
wire        need_si16;
wire        need_si20;
wire        need_si26;
wire        src2_is_4;

wire [ 4:0] rf_raddr1;
wire [31:0] rf_rdata1;
wire [ 4:0] rf_raddr2;
wire [31:0] rf_rdata2;

wire        rj_eq_rd;

// 检查数据冲突
wire [ 4:0] WB_dest;
wire        rj_used;
wire        rk_used;
wire        rd_used;

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
// exp10:
assign inst_slti   = op_31_26_d[6'h00] & op_25_22_d[4'h8];
assign inst_sltui  = op_31_26_d[6'h00] & op_25_22_d[4'h9];
assign inst_andi   = op_31_26_d[6'h00] & op_25_22_d[4'hd];
assign inst_ori    = op_31_26_d[6'h00] & op_25_22_d[4'he];
assign inst_xori   = op_31_26_d[6'h00] & op_25_22_d[4'hf];
assign inst_sll_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0e];
assign inst_srl_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0f];
assign inst_sra_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h10];
assign inst_pcaddu12i = op_31_26_d[6'h07] & ~inst[25];
assign inst_div_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h00];
assign inst_div_wu = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h02];
assign inst_mod_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h01];
assign inst_mod_wu = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h03];
assign inst_mul    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h18];
assign inst_mulh   = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h19];
assign inst_mulhu  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h1a];
//---------------------------------------
assign ID_alu_op[ 0] = inst_add_w | inst_addi_w | inst_ld_w | inst_st_w
                    | inst_jirl | inst_bl | inst_pcaddu12i;
assign ID_alu_op[ 1] = inst_sub_w;
assign ID_alu_op[ 2] = inst_slt | inst_slti;
assign ID_alu_op[ 3] = inst_sltu | inst_sltui;
assign ID_alu_op[ 4] = inst_and | inst_andi;
assign ID_alu_op[ 5] = inst_nor;
assign ID_alu_op[ 6] = inst_or | inst_ori;
assign ID_alu_op[ 7] = inst_xor | inst_xori;
assign ID_alu_op[ 8] = inst_slli_w | inst_sll_w;
assign ID_alu_op[ 9] = inst_srli_w | inst_srl_w;
assign ID_alu_op[10] = inst_srai_w | inst_sra_w;
assign ID_alu_op[11] = inst_lu12i_w;
assign ID_alu_op[12] = inst_mul;
assign ID_alu_op[13] = inst_mulh;
assign ID_alu_op[14] = inst_mulhu;
// 立即数
assign need_ui5   =  inst_slli_w | inst_srli_w | inst_srai_w;
assign need_ui12  =  inst_andi | inst_ori | inst_xori;
assign need_si12  =  inst_addi_w | inst_ld_w | inst_st_w | inst_slti | inst_sltui;
assign need_si16  =  inst_jirl | inst_beq | inst_bne;
assign need_si20  =  inst_lu12i_w | inst_pcaddu12i;
assign need_si26  =  inst_b | inst_bl;
assign src2_is_4  =  inst_jirl | inst_bl;

assign imm = src2_is_4 ? 32'h4                      :
             need_si20 ? {i20[19:0], 12'b0}         :
             need_ui5  ? {27'b0, inst[14:10]}       :
             need_ui12 ? {20'b0, i12[11:0]}         :
                         {{20{i12[11]}}, i12[11:0]} ;

assign br_offs = need_si26 ? {{ 4{i26[25]}}, i26[25:0], 2'b0} :
                             {{14{i16[15]}}, i16[15:0], 2'b0} ;

assign jirl_offs = {{14{i16[15]}}, i16[15:0], 2'b0};

assign src_reg_is_rd = inst_beq | inst_bne | inst_st_w;

assign src1_is_pc    = inst_jirl | inst_bl | inst_pcaddu12i;
assign src1_is_0     = inst_lu12i_w;    // lu12i指令的alu的操作数1应该是0而不是pc或者是寄存器的值，操作数2是立即数

assign src2_is_imm   = inst_slli_w |
                       inst_srli_w |
                       inst_srai_w |
                       inst_addi_w |
                       inst_slti   |
                       inst_sltui  |
                       inst_andi   |
                       inst_ori    |
                       inst_xori   |
                       inst_ld_w   |
                       inst_st_w   |
                       inst_lu12i_w|
                       inst_pcaddu12i |
                       inst_jirl   |
                       inst_bl     ;

assign ID_sel_rf_res    = inst_ld_w;
assign dst_is_r1        = inst_bl;

// 涉及寄存器堆写操作
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


assign rj_eq_rd = (rj_value_mem_wb == rkd_value_mem_wb);
assign br_taken = (   inst_beq  &&  rj_eq_rd
                   || inst_bne  && !rj_eq_rd
                   || inst_jirl
                   || inst_bl
                   || inst_b
                  ) && ID_valid && ID_readygo && EX_allowin; // 注意只有在ID级指令能流向EX级时，br_taken才可能有效
assign br_target = (inst_beq || inst_bne || inst_bl || inst_b) ? (ID_pc + br_offs) :
                                                   /*inst_jirl*/ (rj_value_mem_wb + jirl_offs);
// 复用原有MEM,WB前递通路，涉及前递的跳转指令的寄存器值只用MEM,WB级前递结果和寄存器堆的结果，不用EX级结果，避免时序违例
assign rj_value_mem_wb  = (MEM_forward_src1) ? MEM_wdata_forward :
                          (WB_forward_src1 ) ? WB_wdata_forward  :
                           rf_rdata1;
assign rkd_value_mem_wb = (MEM_forward_src2) ? MEM_wdata_forward :
                          (WB_forward_src2 ) ? WB_wdata_forward  :
                           rf_rdata2;

assign ID_alu_src1 = (src1_is_pc) ? ID_pc[31:0] : 
                     (src1_is_0 ) ? 32'b0 : rj_value;
assign ID_alu_src2 = (src2_is_imm)? imm   : rkd_value;

assign ID_data_sram_we      = {4{mem_we && ID_valid}};
assign ID_data_sram_en      = ID_valid && (inst_st_w || inst_ld_w); 
assign ID_data_sram_wdata   = rkd_value;

// 除法相关的信号：
assign ID_is_div     = inst_div_w | inst_div_wu | inst_mod_w | inst_mod_wu;
assign ID_div_signed = inst_div_w | inst_mod_w;
assign ID_div_is_mod = inst_mod_w | inst_mod_wu;

assign  WB_dest    = WB_rf_waddr;

// 目前只有load-use类会发生数据冲突(EX级有load指令，且发生了RAW)
assign data_hazard = ID_valid && load_in_EX && (EX_dest != 5'b0) && (
                     rk_used && (EX_dest == rk) ||
                     rd_used && (EX_dest == rd) ||
                     rj_used && (EX_dest == rj)
                     );

// 跳转指令中需要rj前递结果的（注意包含jirl）
assign  br_need_rj = inst_beq || inst_bne || inst_jirl;
// 跳转指令中需要rd前递结果的
assign  br_need_rd = inst_beq || inst_bne;
// 如果涉及前递的跳转指令需要当前EX级的前递结果，则让ID级跳转指令阻塞
assign  br_block   = ID_valid && EX_valid && EX_rf_we && (EX_dest != 5'b0) &&
                     ( (br_need_rj && (EX_dest == rj)) ||
                       (br_need_rd && (EX_dest == rd)) 
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
                 inst_slti   |
                 inst_sltui  |
                 inst_andi   |
                 inst_ori    |
                 inst_xori   |
                 inst_sll_w  |
                 inst_srl_w  |
                 inst_sra_w  |
                 inst_ld_w   |
                 inst_st_w   |
                 inst_jirl   |
                 inst_beq    |
                 inst_bne    |
                 inst_div_w  | 
                 inst_div_wu | 
                 inst_mod_w  |
                 inst_mod_wu |
                 inst_mul    |
                 inst_mulh   |
                 inst_mulhu;

assign rk_used = inst_add_w  |
                 inst_sub_w  |
                 inst_slt    |
                 inst_sltu   |
                 inst_nor    |
                 inst_and    |
                 inst_or     |
                 inst_xor    |
                 inst_sll_w  |
                 inst_srl_w  |
                 inst_sra_w  |
                 inst_div_w  | 
                 inst_div_wu | 
                 inst_mod_w  |
                 inst_mod_wu |
                 inst_mul    |
                 inst_mulh   |
                 inst_mulhu;                

assign rd_used = inst_st_w |
                 inst_beq  |
                 inst_bne;

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
assign br_taken_cancel = br_taken;  // 表明IF级已经取到的指令（或者还在取回来路上的）需要被取消

endmodule