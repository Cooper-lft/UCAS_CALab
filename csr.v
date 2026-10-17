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

    // ertn在WB生效：后续由CSR模块将PRMD.PPLV/PIE恢复至CRMD.PLV/IE。
    input  wire                   ertn_flush,  // WB发出的返回生效信号，同时用于流水线清空
    output wire [31:0]            ertn_entry   // 返回目标地址，后续由CSR.ERA提供给IF级
);

// exp12第一步仅预留接口；CSR存储、读写和ertn状态恢复留到下一步实现。
// csr_rvalue、ertn_entry当前刻意不驱动，不能据此执行CSR功能仿真。

endmodule
