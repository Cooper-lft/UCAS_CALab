`include "mycpu.h"

module WB_stage (
    input  wire        clk,
    input  wire        reset,

    input  wire        MEM_to_WB_valid,
    input  wire [`MEM_TO_WB_BUS_WD-1:0] MEM_to_WB_bus,

    output wire        WB_allowin,
    output wire [31:0] WB_pc,
    
    output wire        WB_rf_we,
    output wire [ 4:0] WB_dest,
    output wire [31:0] WB_res,
    output wire        ws_valid,

    // 对CSR模块的实际访问接口：使能信号已结合WB_valid和reset。
    output wire        csr_re,      // 读CSR旧值，供三条CSR指令写回rd
    output wire        csr_we,      // 本拍有效CSR写操作，在时钟沿更新CSR
    output wire [`CSR_NUM_WD-1:0] csr_num, // 本次访问的CSR编号
    output wire [31:0] csr_wmask,   // 本次写操作的逐位掩码
    output wire [31:0] csr_wvalue,  // 本次写操作的数据，来自ID取得的GR[rd]
    input  wire [31:0] csr_rvalue,  // CSR模块返回的旧值，也作为WB前递数据
    output wire        ertn_flush   // 有效ertn到达WB时拉高，触发返回、状态恢复及清空
);

wire       WB_readygo;
reg        WB_valid;
reg [`MEM_TO_WB_BUS_WD-1:0] WB_data;

wire [31:0] WB_pc_r;
wire        WB_gr_we;
wire [ 4:0] WB_dest_r;
wire [31:0] WB_normal_res;   // 原有运算/访存结果，CSR指令改选csr_rvalue写回
// WB_前缀信号来自流水寄存器，尚未结合valid；无效拍也可能保留旧指令信息。
wire        WB_csr_re;       // 当前锁存指令的读CSR标记
wire        WB_csr_we;       // 当前锁存指令的写CSR标记
wire [`CSR_NUM_WD-1:0] WB_csr_num; // 当前锁存指令的CSR编号
wire [31:0] WB_csr_wmask;    // 从ID一路携带至此的写掩码
wire [31:0] WB_csr_wvalue;   // 从ID一路携带至此的写入值
wire        WB_is_ertn;      // 当前锁存指令是否为ertn

assign WB_readygo       = 1'b1;
assign WB_allowin       = !WB_valid || WB_readygo;
always @(posedge clk) begin
    if (reset || ertn_flush) begin
        WB_valid <= 1'b0;
    end
    else if (WB_allowin) begin
        WB_valid <= MEM_to_WB_valid;
    end

    if (WB_allowin && MEM_to_WB_valid) begin
        WB_data <= MEM_to_WB_bus;
    end
end

assign {WB_pc_r,
        WB_gr_we,
        WB_dest_r,
        WB_normal_res,
        WB_csr_re,
        WB_csr_we,
        WB_csr_num,
        WB_csr_wmask,
        WB_csr_wvalue,
        WB_is_ertn} = WB_data;

assign WB_pc       = WB_valid ? WB_pc_r : 32'b0;
assign WB_rf_we    = WB_valid && WB_gr_we && !WB_is_ertn && !reset;
assign WB_dest     = WB_valid ? WB_dest_r : 5'b0;
// 三条CSR指令均返回CSR旧值；后续CSR模块应先组合读旧值，再在时钟沿完成写入。
assign WB_res      = !WB_valid ? 32'b0 :
                     WB_csr_re ? csr_rvalue : WB_normal_res;

// valid为0时，流水寄存器中的残留控制位不得触发CSR读写或ertn返回。
// CSR写使能不依赖rd是否为r0：即使丢弃读回值，指令仍可更新CSR。
assign csr_re      = WB_valid && WB_csr_re && !reset;
assign csr_we      = WB_valid && WB_csr_we && !reset;
assign csr_num     = WB_valid ? WB_csr_num : {`CSR_NUM_WD{1'b0}};
assign csr_wmask   = csr_we ? WB_csr_wmask : 32'b0;
assign csr_wvalue  = csr_we ? WB_csr_wvalue : 32'b0;
assign ertn_flush  = WB_valid && WB_is_ertn && !reset;

assign ws_valid     = WB_valid;

endmodule
