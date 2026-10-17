`include "mycpu.h"

module MEM_stage (
    input  wire        clk,
    input  wire        reset,
    input  wire        ertn_flush, // 来自WB：清除本级valid，禁止将年轻指令送入WB

    input  wire        EX_to_MEM_valid,
    input  wire        WB_allowin,
    input  wire [`EX_TO_MEM_BUS_WD-1:0] EX_to_MEM_bus,
    input  wire [31:0] MEM_data_sram_rdata,

    output wire        MEM_allowin,
    output wire        MEM_to_WB_valid,
    output wire [`MEM_TO_WB_BUS_WD-1:0] MEM_to_WB_bus,

    // data_harzard detect & forward path
    output wire        ms_valid,
    output wire [ 4:0] ms_dest,
    output wire        ms_rf_we,
    output wire [31:0] MEM_wdata_forward,
    output wire        csr_in_MEM, // 已结合MEM_valid的CSR标记，通知ID继续等待WB返回值
    output wire        ertn_in_MEM // 已结合MEM_valid的ertn标记，阻止年轻指令进入EX
);

wire       MEM_readygo;
reg        MEM_valid;
reg [`EX_TO_MEM_BUS_WD-1:0] MEM_data;

assign MEM_readygo      = 1'b1;
assign MEM_to_WB_valid  = MEM_valid && MEM_readygo && !ertn_flush;
assign MEM_allowin      = !MEM_valid || MEM_to_WB_valid && WB_allowin; 
always @(posedge clk) begin
    if (reset || ertn_flush) begin
        MEM_valid <= 1'b0;
    end
    else if (MEM_allowin) begin
        MEM_valid <= EX_to_MEM_valid;
    end

    if (MEM_allowin && EX_to_MEM_valid) begin
        MEM_data <= EX_to_MEM_bus;
    end
end

wire [31:0] MEM_pc;
wire        MEM_rf_we;
wire [ 4:0] MEM_dest;
wire        MEM_sel_rf_res;
wire [31:0] MEM_alu_res;
wire [31:0] MEM_res;
wire [ 1:0] MEM_mem_size;
wire        MEM_load_unsigned;
wire [ 1:0] MEM_addr_low;   // load 锁存的有效地址低两位
wire [ 7:0] MEM_load_byte;  // load 选择所需字节
wire [15:0] MEM_load_half;  // load 选择所需半字
wire [31:0] MEM_load_res;   // load 最终加载值
// 从EX锁存并传至WB的CSR信息；MEM本级只传递，不执行CSR访问。
wire        MEM_csr_re;       // WB需读取CSR旧值
wire        MEM_csr_we;       // WB需更新CSR
wire [`CSR_NUM_WD-1:0] MEM_csr_num; // CSR编号
wire [31:0] MEM_csr_wmask;    // 随指令传递的写掩码
wire [31:0] MEM_csr_wvalue;   // 随指令传递的写入值
wire        MEM_is_ertn;      // 到WB后产生返回生效信号

assign {MEM_pc,
        MEM_rf_we,
        MEM_dest,
        MEM_sel_rf_res,
        MEM_alu_res,
        MEM_mem_size,
        MEM_load_unsigned,
        MEM_addr_low,
        MEM_csr_re,
        MEM_csr_we,
        MEM_csr_num,
        MEM_csr_wmask,
        MEM_csr_wvalue,
        MEM_is_ertn}         = MEM_data;

assign MEM_to_WB_bus        = {MEM_pc,
                              MEM_rf_we,
                              MEM_dest,
                              MEM_res,
                              MEM_csr_re,
                              MEM_csr_we,
                              MEM_csr_num,
                              MEM_csr_wmask,
                              MEM_csr_wvalue,
                              MEM_is_ertn};
                            // when MEM_sel_rf_res == 1, final result is from data_sram(load inst)
assign MEM_load_byte        = (MEM_addr_low == 2'b00) ? MEM_data_sram_rdata[ 7:0]  :
                              (MEM_addr_low == 2'b01) ? MEM_data_sram_rdata[15:8]  :
                              (MEM_addr_low == 2'b10) ? MEM_data_sram_rdata[23:16] :
                                                        MEM_data_sram_rdata[31:24];
assign MEM_load_half        = MEM_addr_low[1] ? MEM_data_sram_rdata[31:16] : MEM_data_sram_rdata[15:0];
assign MEM_load_res         = (MEM_mem_size == 2'b01) ? {{24{!MEM_load_unsigned && MEM_load_byte[7]}}, MEM_load_byte} :  // 字节符号或零扩展。
                              (MEM_mem_size == 2'b10) ? {{16{!MEM_load_unsigned && MEM_load_half[15]}}, MEM_load_half} : // 半字符号或零扩展。
                                                        MEM_data_sram_rdata;

assign MEM_res              = (MEM_sel_rf_res) ? MEM_load_res : MEM_alu_res;

// forward
assign ms_valid             = MEM_valid;
assign ms_dest              = MEM_dest;
assign ms_rf_we             = MEM_rf_we;
assign MEM_wdata_forward    = MEM_res;
assign csr_in_MEM           = MEM_valid && MEM_csr_re;
assign ertn_in_MEM          = MEM_valid && MEM_is_ertn;

endmodule
