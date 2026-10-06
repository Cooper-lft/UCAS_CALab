module EX_stage (
    input  wire        clk,
    input  wire        reset,

    input  wire [157:0] ID_to_EX_bus,
    input  wire         ID_to_EX_valid,
    input  wire         MEM_allowin,

    output wire         EX_allowin,
    output wire         EX_to_MEM_valid,
    output wire [ 70:0] EX_to_MEM_bus,
    output wire         EX_data_sram_en,
    output wire [  3:0] EX_data_sram_we,
    output wire [ 31:0] EX_data_sram_addr,
    output wire [ 31:0] EX_data_sram_wdata,

    // data_harzard detect & forwarding path
    output wire         es_valid,
    output wire [  4:0] es_dest,
    output wire         es_rf_we,
    output wire         load_in_EX,         // 目前在前递实现下，只有load-use类当load在EX级且use指令在ID级时，要停顿，该信号用于检测load指令是否在EX级
    output wire [ 31:0] EX_wdata_forward    // 由EX级前递的数据
);
    
wire        EX_readygo;    
reg         EX_valid;
reg [157:0] EX_data;

// 除法
reg         div_done;
reg  [31:0] div_result_r;       // 除法器当拍结果的缓存
wire [31:0] div_result_now;     // 除法器当拍获得的结果
wire        div_result_valid;
// 用触发器保存除法器中被除数和除数各自的握手信号
reg         dividend_signed_handshake;
reg         dividend_unsigned_handshake;
reg         divisor_signed_handshake;
reg         divisor_unsigned_handshake;
reg         div_sent;           // 表明除法器的两个输入已经被除法器接收
wire        div_req;            // 表明此时需要发送除法器输入数据有效的信号
wire        div_input_handshake;
wire        div_out_valid;
wire [63:0] div_out_data;
// 被除数
wire [31:0] dividend_tdata;
wire        dividend_tvalid_signed;
wire        dividend_tready_signed;
wire        dividend_tvalid_unsigned;
wire        dividend_tready_unsigned;
// 除数
wire [31:0] divisor_tdata;  
wire        divisor_tvalid_signed;
wire        divisor_tready_signed;  
wire        divisor_tvalid_unsigned;
wire        divisor_tready_unsigned;  
// 除法器结果
wire [63:0] dout_tdata_signed;
wire        dout_tvalid_signed;
wire [63:0] dout_tdata_unsigned;
wire        dout_tvalid_unsigned;  
// 商和余数：
wire [31:0] quotient;   // 商
wire [31:0] remainder;  // 余数
wire [31:0] div_result; // 除法最终的结果，跟alu的结果（包含可能的乘法结果）进行选择

wire [31:0] EX_alu_src1;
wire [31:0] EX_alu_src2;
wire [14:0] EX_alu_op;
wire [ 3:0] EX_mem_we;
wire        EX_mem_en;
wire        EX_is_div;      // 除法或取余指令
wire        EX_div_signed;  // 有符号运算(求商或者取余)
wire        EX_div_is_mod;  // 选择余数，否则选择商

wire [31:0] EX_pc;
wire        EX_rf_we;
wire [ 4:0] EX_dest;
wire        EX_sel_rf_res;
wire [31:0] EX_alu_res;
wire [31:0] EX_wdata;

// EX_readygo置1，要不然是非除法指令，要不然是除法指令且结果已经拿到下，下一拍就能送入MEM级(div_result_valid)或者EX级中有除法器结果的缓存（div_done）
assign EX_readygo       = !EX_is_div || div_done || div_result_valid;
assign EX_to_MEM_valid  = EX_valid && EX_readygo;
assign EX_allowin       = !EX_valid || EX_to_MEM_valid && MEM_allowin;
always @(posedge clk) begin
    if (reset) begin
        EX_valid <= 1'b0;
    end
    else if (EX_allowin) begin
        EX_valid <= ID_to_EX_valid;
    end
    
    if (EX_allowin && ID_to_EX_valid) begin
        EX_data <= ID_to_EX_bus;
    end
end

assign EX_to_MEM_bus    = {EX_pc,
                            EX_rf_we,
                            EX_dest,
                            EX_sel_rf_res,
                            EX_wdata
                            };

assign EX_wdata         = (EX_is_div)? div_result : EX_alu_res;
assign {EX_pc,
        EX_rf_we,
        EX_dest,
        EX_sel_rf_res,
        EX_alu_src1,
        EX_alu_src2,
        EX_alu_op,
        EX_data_sram_wdata,
        EX_mem_we,
        EX_mem_en,
        EX_is_div,
        EX_div_signed,
        EX_div_is_mod}      = EX_data;

assign EX_data_sram_we      = {4{EX_valid}} & EX_mem_we;
assign EX_data_sram_en      = EX_valid && EX_mem_en;
assign EX_data_sram_addr    = EX_alu_res;
alu u_alu(
    .alu_op     (EX_alu_op  ),
    .alu_src1   (EX_alu_src1),
    .alu_src2   (EX_alu_src2),
    .alu_result (EX_alu_res )
    );

assign  es_valid    = EX_valid;
assign  es_rf_we    = EX_rf_we;
assign  es_dest     = EX_dest;

// 前递判断中，目前只有load-use类存在RAW数据冲突，即如果load指令在EX级且有指令在ID级要读load指令写的寄存器，
// 那么需要让ID级指令停下直到EX级的load指令进入MEM级。
// 所以新增一个load_in_EX 信号
assign  load_in_EX          = EX_data_sram_en && !EX_data_sram_we;
assign  EX_wdata_forward    = EX_wdata;

// 除法器：
assign div_req                  = EX_valid  && !reset && EX_is_div && !div_done && !div_sent;
assign dividend_tvalid_signed   = div_req   && EX_div_signed;
assign divisor_tvalid_signed    = dividend_tvalid_signed;
assign dividend_tvalid_unsigned = div_req   && !EX_div_signed;
assign divisor_tvalid_unsigned  = dividend_tvalid_unsigned;
assign div_input_handshake      = div_req   &&
                                ((EX_div_signed) ?
                                (dividend_tready_signed   && divisor_tready_signed   ) :
                                (dividend_tready_unsigned && divisor_tready_unsigned ));


always @(posedge clk) begin
    if (reset || EX_allowin)
        div_sent <= 1'b0;
    else if (div_input_handshake)
        div_sent <= 1'b1;
end

assign      dividend_tdata      = EX_alu_src1;
assign      divisor_tdata       = EX_alu_src2;

assign      div_out_valid       = (EX_div_signed) ? dout_tvalid_signed: dout_tvalid_unsigned;
assign      div_out_data        = (EX_div_signed) ? dout_tdata_signed : dout_tdata_unsigned;
assign      quotient            = div_out_data[63:32];
assign      remainder           = div_out_data[31:0];

assign      div_result_valid    = EX_valid && !reset && EX_is_div && div_sent && div_out_valid;
assign      div_result_now      = (EX_div_is_mod) ? remainder : quotient;
assign      div_result          = (div_done) ? div_result_r : div_result_now; // 如果div_done为1，说明除法器得到结果且并没有在得到结果的下一拍将结果送入MEM级
always @(posedge clk) begin
    if(reset || EX_allowin) begin
        div_done        <= 1'b0;
    end
    else if(div_result_valid && !div_done) begin
        div_done        <= 1'b1;
        div_result_r    <= div_result_now;          // 除法器的结果存到寄存器中作为缓存（如果结果不能及时被流入MEM级）
    end
end

// 有符号除法
mydiv_sign u_div_sign(
    .s_axis_divisor_tdata   (divisor_tdata          ),
    .s_axis_divisor_tready  (divisor_tready_signed  ),
    .s_axis_divisor_tvalid  (divisor_tvalid_signed  ),
    .s_axis_dividend_tdata  (dividend_tdata         ),
    .s_axis_dividend_tready (dividend_tready_signed ),
    .s_axis_dividend_tvalid (dividend_tvalid_signed ),
    .aclk                   (clk                    ),
    .m_axis_dout_tdata      (dout_tdata_signed      ),
    .m_axis_dout_tvalid     (dout_tvalid_signed     )
    );

// 无符号除法
mydiv_unsign u_div_unsign(
    .s_axis_divisor_tdata   (divisor_tdata              ),
    .s_axis_divisor_tready  (divisor_tready_unsigned    ),
    .s_axis_divisor_tvalid  (divisor_tvalid_unsigned    ),
    .s_axis_dividend_tdata  (dividend_tdata             ),
    .s_axis_dividend_tready (dividend_tready_unsigned   ),
    .s_axis_dividend_tvalid (dividend_tvalid_unsigned   ),
    .aclk                   (clk                        ),
    .m_axis_dout_tdata      (dout_tdata_unsigned        ),
    .m_axis_dout_tvalid     (dout_tvalid_unsigned       )
    );



endmodule