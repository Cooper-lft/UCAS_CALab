`include "mycpu.vh"

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
    // 编号、掩码和数据无需在无效拍清零，CSR模块仅在对应使能有效时使用它们。
    output wire        csr_re,      // 读CSR旧值，供三条CSR指令写回rd
    output wire        csr_we,      // 本拍有效CSR写操作，在时钟沿更新CSR
    output wire [`CSR_NUM_WD-1:0] csr_num, // 本次访问的CSR编号
    output wire [31:0] csr_wmask,   // 本次写操作的逐位掩码
    output wire [31:0] csr_wvalue,  // 本次写操作的数据，来自ID取得的GR[rd]
    input  wire [31:0] csr_rvalue,  // CSR模块返回的旧值，也作为WB前递数据
    output wire        ertn_flush,   // 有效ertn到达WB时拉高，触发返回、状态恢复及清空
    output wire        wb_ex,       // 有效异常指令到达WB，统一报告异常并清空年轻指令
    output wire [5:0]  wb_ecode,    // 异常类型编码，送CSR.ESTAT
    output wire [8:0]  wb_esubcode, // 本阶段所有已实现异常的子码均为0，包括ADEF
    output wire [31:0] wb_vaddr,    // 交给CSR的完整数据地址；ADEF应改用wb_pc更新BADV
    // WB中的CSR写指令或ertn将在本周期结束的时钟沿更新中断使能或中断状态。
    // ID在本周期内看到的仍是更新前的值，所以即使前面的指令已经到WB，ID也不能提前发射。
    // CSR写入生效后再判断中断；若是ertn，当前ID指令会被ertn_flush取消。
    output wire        int_state_pending_WB
);

wire       WB_readygo;
reg        WB_valid;
reg [`MEM_TO_WB_BUS_WD-1:0] WB_data;
wire        pipeline_flush;

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
wire [`EXCEPTION_BUS_WD-1:0] WB_exception_flags;
wire        WB_has_exception;
wire [31:0] WB_vaddr;

assign WB_readygo       = 1'b1;
assign WB_allowin       = !WB_valid || WB_readygo;
assign pipeline_flush   = wb_ex || ertn_flush;
// 异常/返回优先清除valid和流水数据，不让年轻指令在同一边沿替换进来
always @(posedge clk) begin
    if (reset || pipeline_flush) begin
        WB_valid <= 1'b0;
    end
    else if (WB_allowin) begin
        WB_valid <= MEM_to_WB_valid;
    end

    if (reset || pipeline_flush) begin
        WB_data <= {`MEM_TO_WB_BUS_WD{1'b0}};
    end
    else if (WB_allowin && MEM_to_WB_valid) begin
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
        WB_is_ertn,
        WB_exception_flags,
        WB_vaddr} = WB_data;

// 数据直接输出；无效拍的值无意义，由写使能、前递valid及调试端有效性判断屏蔽。
assign WB_pc       = WB_pc_r;
assign WB_rf_we    = WB_valid && WB_gr_we && !WB_is_ertn && !wb_ex && !reset;
assign WB_dest     = WB_dest_r;
// 三条CSR指令均返回CSR旧值；后续CSR模块应先组合读旧值，再在时钟沿完成写入。
assign WB_res      = WB_csr_re ? csr_rvalue : WB_normal_res;

// valid为0时，流水寄存器中的残留控制位不得触发CSR读写或ertn返回。
// CSR写使能不依赖rd是否为r0：即使丢弃读回值，指令仍可更新CSR。
assign csr_re      = WB_valid && WB_csr_re && !pipeline_flush && !reset;
assign csr_we      = WB_valid && WB_csr_we && !pipeline_flush && !reset;
assign csr_num     = WB_csr_num;
assign csr_wmask   = WB_csr_wmask;
assign csr_wvalue  = WB_csr_wvalue;
assign WB_has_exception = WB_exception_flags[`EXC_INT]  |
                          WB_exception_flags[`EXC_ADEF] |
                          WB_exception_flags[`EXC_INE]  |
                          WB_exception_flags[`EXC_BRK]  |
                          WB_exception_flags[`EXC_SYS]  |
                          WB_exception_flags[`EXC_ALE];
assign wb_ex       = WB_valid && WB_has_exception && !reset;
// 手册6.2.2：同一条指令INT优先，其后为取指、译码、执行异常;(译码级例外)INE/BRK/SYS译码互斥。
// 不同指令的异常由顺序到达WB及冲刷保证较老指令优先，不能用类型优先级越过较老指令。
assign wb_ecode    = WB_exception_flags[`EXC_INT]  ? `ECODE_INT :
                     WB_exception_flags[`EXC_ADEF] ? `ECODE_ADE :
                     WB_exception_flags[`EXC_INE]  ? `ECODE_INE :
                     WB_exception_flags[`EXC_BRK]  ? `ECODE_BRK :
                     WB_exception_flags[`EXC_SYS]  ? `ECODE_SYS :
                     WB_exception_flags[`EXC_ALE]  ? `ECODE_ALE : `ECODE_INT;
assign wb_esubcode = 9'b0;
assign wb_vaddr    = WB_vaddr;
assign ertn_flush  = WB_valid && WB_is_ertn && !wb_ex && !reset;
assign int_state_pending_WB = WB_valid && !reset && !WB_has_exception &&
                              (WB_is_ertn || (WB_csr_we && `CSR_INT_RELATED(WB_csr_num)));

assign ws_valid     = WB_valid;

endmodule
