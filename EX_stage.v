module EX_stage (
    input  wire        clk,
    input  wire        reset,

    input  wire [151:0] ID_to_EX_bus,
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
    
wire EX_readygo;    
reg  EX_valid;
reg [151:0] EX_data;

assign EX_readygo       = 1'b1;
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

wire [31:0] EX_pc;
wire        EX_rf_we;
wire [ 4:0] EX_dest;
wire        EX_sel_rf_res;
wire [31:0] EX_alu_res;
assign EX_to_MEM_bus    = {EX_pc,
                            EX_rf_we,
                            EX_dest,
                            EX_sel_rf_res,
                            EX_alu_res
                            };

wire [31:0] EX_alu_src1;
wire [31:0] EX_alu_src2;
wire [11:0] EX_alu_op;
wire [ 3:0] EX_mem_we;
wire        EX_mem_en;

assign {EX_pc,
        EX_rf_we,
        EX_dest,
        EX_sel_rf_res,
        EX_alu_src1,
        EX_alu_src2,
        EX_alu_op,
        EX_data_sram_wdata,
        EX_mem_we,
        EX_mem_en}       = EX_data;

assign EX_data_sram_we  = {4{EX_valid}} & EX_mem_we;
assign EX_data_sram_en  = EX_valid && EX_mem_en;

alu u_alu(
    .alu_op     (EX_alu_op  ),
    .alu_src1   (EX_alu_src1),
    .alu_src2   (EX_alu_src2),
    .alu_result (EX_alu_res )
    );

assign EX_data_sram_addr    = EX_alu_res;

assign  es_valid    = EX_valid;
assign  es_rf_we    = EX_rf_we;
assign  es_dest     = EX_dest;

// 前递判断中，目前只有load-use类存在RAW数据冲突，即如果load指令在EX级且有指令在ID级要读load指令写的寄存器，
// 那么需要让ID级指令停下直到EX级的load指令进入MEM级。
// 所以新增一个load_in_EX 信号
assign  load_in_EX          = EX_data_sram_en && !EX_data_sram_we;
assign  EX_wdata_forward    = EX_alu_res;

endmodule