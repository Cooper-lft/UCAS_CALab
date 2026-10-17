`include "mycpu.h"

module IF_stage (
    input  wire        clk,
    input  wire        reset,
    input  wire        wb_ex,       // WB异常提交，强制重定向并取消旧路径
    input  wire [31:0] ex_entry,    // CSR.EENTRY给出的异常入口
    input  wire        ertn_flush,  // 来自WB：丢弃当前旧指令，并立即改从返回地址取指
    input  wire [31:0] ertn_entry,  // 来自CSR模块：ertn返回地址，后续由ERA提供
    // branch form ID
    input  wire        br_taken,
    input  wire [31:0] br_target,    
    // IF to ID signal
    input  wire        ID_allowin,
    output wire        IF_to_ID_valid,
    // inst sram
    input  wire [31:0] inst_sram_rdata,
    output wire [31:0] inst_sram_wdata,
    output wire [31:0] inst_sram_addr,
    output wire        inst_sram_en, // 片选信号
    output wire [ 3:0] inst_sram_we,
    
    output wire [`IF_TO_ID_BUS_WD-1:0] IF_to_ID_bus,

    // 控制冒险
    input  wire        br_taken_cancel
);

wire        IF_allowin;
wire        IF_readygo;
wire        pipeline_flush; // 异常与返回均需取消旧指令并强制取新目标
wire        to_IF_valid;    // IF前的预取指令阶段（伪流水级）pre-IF级（发出请求）是否完成了地址请求
reg         IF_valid;

reg  [31:0] pc;
wire [31:0] seq_pc;
wire [31:0] nextpc;
wire [31:0] inst;

assign IF_allowin       = !IF_valid || IF_readygo && ID_allowin;
assign IF_readygo       = 1'b1;
assign pipeline_flush   = wb_ex || ertn_flush;
// 返回生效当拍不再向ID提交旧路径上的指令。
assign IF_to_ID_valid   = IF_valid && IF_readygo && !pipeline_flush; // 屏蔽清空当拍的旧指令
assign to_IF_valid      = ~reset;   // pre-IF级（发出请求）是否完成了地址请求

always @(posedge clk) begin
    if (reset) begin
        IF_valid <= 1'b0;
    end
    else if (pipeline_flush) begin // 清空优先于ID停顿和普通分支
        // 旧路径由IF_to_ID_valid屏蔽；同一边沿请求新入口，不可再丢弃新返回指令
        IF_valid <= 1'b1;
    end
    else if (IF_allowin) begin
        IF_valid <= to_IF_valid;
    end
    else if (br_taken_cancel) begin
        IF_valid <= 1'b0;               
    end
    // 如果IF级取指令不能一拍回来，但ID的跳转指令所产生的取消IF级的指令信号生效时，
    // 下一拍取消信号就消失了（因为如果这一周期取消信号生效，则ID此时allowin拉高）， 
    // 所以需要让IF级知道将要取回来的指令是无效的，故让IF_valid下一拍拉低
end

assign inst_sram_we     = 4'b0;
assign inst_sram_en     = !reset && (IF_allowin || pipeline_flush); // 异常入口/返回请求不受ID停顿阻挡
assign inst_sram_wdata  = 32'b0;
assign inst             = inst_sram_rdata;
assign inst_sram_addr   = nextpc;

assign seq_pc       = pc + 3'h4;
// 异常提交 > ertn返回 > ID普通分支 > 顺序PC
assign nextpc       = wb_ex ? ex_entry :
                      ertn_flush ? ertn_entry :
                      br_taken ? br_target : seq_pc;

assign IF_to_ID_bus = {pc[31:0], inst[31:0]};

always @(posedge clk) begin
    if (reset) begin
        pc <= 32'h1bfffffc; //trick: to make nextpc be 0x1c000000 during reset
    end 
    else if(pipeline_flush || IF_allowin) begin
        pc <= nextpc;
    end
end



endmodule
