module IF_stage (
    input  wire        clk,
    input  wire        reset,
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
    
    output wire [63:0] IF_to_ID_bus,

    // 控制冒险
    input  wire        br_taken_cancel
);

wire        IF_allowin;
wire        IF_readygo;        
wire        to_IF_valid; // IF前的预取指令阶段（伪流水级）pre-IF级（发出请求）是否完成了地址请求
reg         IF_valid;

reg  [31:0] pc;
wire [31:0] seq_pc;
wire [31:0] nextpc;
wire [31:0] inst;

assign IF_allowin       = !IF_valid || IF_readygo && ID_allowin;
assign IF_readygo       = 1'b1;
assign IF_to_ID_valid   = IF_valid && IF_readygo;
assign to_IF_valid      = ~reset;   // pre-IF级（发出请求）是否完成了地址请求

always @(posedge clk) begin
    if (reset) begin
        IF_valid <= 1'b0;
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
assign inst_sram_en     = !reset && IF_allowin; // inst_sram chip enable
assign inst_sram_wdata  = 32'b0;
assign inst             = inst_sram_rdata;
assign inst_sram_addr   = nextpc;

assign seq_pc       = pc + 3'h4;
assign nextpc       = br_taken ? br_target : seq_pc;

assign IF_to_ID_bus = {pc[31:0], inst[31:0]};

always @(posedge clk) begin
    if (reset) begin
        pc <= 32'h1bfffffc; //trick: to make nextpc be 0x1c000000 during reset
    end 
    else if(IF_allowin) begin
        pc <= nextpc;
    end
end



endmodule