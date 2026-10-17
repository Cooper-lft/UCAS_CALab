`include "mycpu.h"

module EX_stage (
    input  wire        clk,
    input  wire        reset,
    input  wire        ertn_flush,  // 来自WB：清除本级valid及除法控制状态，并禁止访存
    input  wire        ertn_in_MEM, // MEM中有有效ertn，禁止EX年轻指令发出访存或除法请求
    // step3扩展接口：目前顶层均接0，尚未接入异常检测和异常信息传递。
    input  wire        ex_exception,  // EX当前指令自身有异常，禁止其发出请求
    input  wire        mem_exception, // MEM中有有效异常指令，未来由MEM_valid与异常标记共同产生
    input  wire        wb_exception,  // WB中有有效异常指令，未来由WB_valid与异常标记共同产生

    input  wire [`ID_TO_EX_BUS_WD-1:0] ID_to_EX_bus,
    input  wire         ID_to_EX_valid,
    input  wire         MEM_allowin,

    output wire         EX_allowin,
    output wire         EX_to_MEM_valid,
    output wire [`EX_TO_MEM_BUS_WD-1:0] EX_to_MEM_bus,
    output wire         EX_data_sram_en,
    output wire [  3:0] EX_data_sram_we,
    output wire [ 31:0] EX_data_sram_addr,
    output wire [ 31:0] EX_data_sram_wdata,

    // data_harzard detect & forwarding path
    output wire         es_valid,
    output wire [  4:0] es_dest,
    output wire         es_rf_we,
    output wire         load_in_EX,        // EX中有有效load，用于ID的load-use停顿判断
    output wire [ 31:0] EX_wdata_forward,   // 由EX级前递的数据
    output wire         csr_in_EX    // 已结合EX_valid的CSR指令标记，通知ID返回值尚未就绪
);
    
wire        EX_readygo;    
reg         EX_valid;
reg [`ID_TO_EX_BUS_WD-1:0] EX_data;

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
wire [`ALU_OP_WD-1:0] EX_alu_op;
wire [ 3:0] EX_mem_we;
wire        EX_mem_en;
wire        EX_is_div;      // 除法或取余指令
wire        EX_div_signed;  // 有符号运算(求商或者取余)
wire        EX_div_is_mod;  // 选择余数，否则选择商
wire [ 1:0] EX_mem_size;
wire        EX_load_unsigned;
wire [31:0] EX_store_data;  // store 从ID接收的原始rd数据
wire [ 3:0] EX_store_mask;

wire [31:0] EX_pc;
wire        EX_rf_we;
wire [ 4:0] EX_dest;
wire        EX_sel_rf_res;
wire [31:0] EX_alu_res;
wire [31:0] EX_wdata;
// 从ID锁存并传至MEM的CSR信息；EX本级不读写CSR。
wire        EX_csr_re;       // 该指令需在WB读CSR并返回旧值
wire        EX_csr_we;       // 该指令需在WB更新CSR
wire [`CSR_NUM_WD-1:0] EX_csr_num; // CSR编号
wire [31:0] EX_csr_wmask;    // ID已取得的写掩码
wire [31:0] EX_csr_wvalue;   // ID已取得的写入值，后续不再重新读取GR[rd]
wire        EX_is_ertn;      // ertn标记随指令流向WB

wire        EX_request_allowed; // 本拍允许访存或启动除法；地址和数据无需因取消而清零
// MEM中的ertn提前阻止年轻指令发出请求；WB仍通过ertn_flush统一清除valid。
// 异常输入仅预留请求保护条件；step3还需接入异常传递、报告及冲刷逻辑。
assign EX_request_allowed = EX_valid && !reset &&
                            !ex_exception && !mem_exception && !wb_exception &&
                            !ertn_in_MEM && !ertn_flush;

// EX_readygo置1，要不然是非除法指令，要不然是除法指令且结果已经拿到下，下一拍就能送入MEM级(div_result_valid)或者EX级中有除法器结果的缓存（div_done）
assign EX_readygo       = !EX_is_div || div_done || div_result_valid;
assign EX_to_MEM_valid  = EX_valid && EX_readygo && !ertn_flush;
assign EX_allowin       = !EX_valid || EX_to_MEM_valid && MEM_allowin;
always @(posedge clk) begin
    if (reset || ertn_flush) begin
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
                            EX_wdata,
                            EX_mem_size,
                            EX_load_unsigned,
                            EX_alu_res[1:0],    // 地址最低两位
                            EX_csr_re,
                            EX_csr_we,
                            EX_csr_num,
                            EX_csr_wmask,
                            EX_csr_wvalue,
                            EX_is_ertn
                            };

assign EX_wdata         = (EX_is_div)? div_result : EX_alu_res;
assign {EX_pc,
        EX_rf_we,
        EX_dest,
        EX_sel_rf_res,
        EX_alu_src1,
        EX_alu_src2,
        EX_alu_op,
        EX_store_data,
        EX_mem_we,
        EX_mem_en,
        EX_is_div,
        EX_div_signed,
        EX_div_is_mod,
        EX_mem_size,
        EX_load_unsigned,
        EX_csr_re,
        EX_csr_we,
        EX_csr_num,
        EX_csr_wmask,
        EX_csr_wvalue,
        EX_is_ertn}            = EX_data;

assign EX_store_mask        = (EX_mem_size == 2'b01) ? (4'b0001 << EX_alu_res[1:0]) :
                              (EX_mem_size == 2'b10) ? (EX_alu_res[1] ? 4'b1100 : 4'b0011) :
                              4'b1111;
assign EX_data_sram_we      = {4{EX_request_allowed}} & EX_mem_we & EX_store_mask;
assign EX_data_sram_wdata   = (EX_mem_size == 2'b01) ? {4{EX_store_data[7:0]}} :
                              (EX_mem_size == 2'b10) ? {2{EX_store_data[15:0]}} :
                              EX_store_data;
assign EX_data_sram_en      = EX_request_allowed && EX_mem_en;
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

// 向ID报告结果尚未就绪的指令：load要等MEM，CSR要等WB。
// 根据指令属性判断load，避免将是否允许发出访存请求混入类型判断。
assign  load_in_EX          = EX_valid && EX_sel_rf_res;
assign  EX_wdata_forward    = EX_wdata;
assign  csr_in_EX           = EX_valid && EX_csr_re;

// 除法器：
// 被较老ertn取消的除法不能进入除法器，避免冲刷后仍返回旧结果。
// 未发出的年轻除法等待WB冲刷；step3需另外处理自身带异常指令的放行条件。
assign div_req                  = EX_request_allowed && EX_is_div && !div_done && !div_sent;
assign dividend_tvalid_signed   = div_req   && EX_div_signed;
assign divisor_tvalid_signed    = dividend_tvalid_signed;
assign dividend_tvalid_unsigned = div_req   && !EX_div_signed;
assign divisor_tvalid_unsigned  = dividend_tvalid_unsigned;
assign div_input_handshake      = div_req   &&
                                ((EX_div_signed) ?
                                (dividend_tready_signed   && divisor_tready_signed   ) :
                                (dividend_tready_unsigned && divisor_tready_unsigned ));


always @(posedge clk) begin
    if (reset || ertn_flush || EX_allowin)
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

assign      div_result_valid    = EX_valid && !reset && !ertn_flush && EX_is_div && div_sent && div_out_valid;
assign      div_result_now      = (EX_div_is_mod) ? remainder : quotient;
assign      div_result          = (div_done) ? div_result_r : div_result_now; // 如果div_done为1，说明除法器得到结果且并没有在得到结果的下一拍将结果送入MEM级
always @(posedge clk) begin
    if(reset || ertn_flush || EX_allowin) begin
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
