module MEM_stage (
    input  wire        clk,
    input  wire        reset,

    input  wire        EX_to_MEM_valid,
    input  wire        WB_allowin,
    input  wire [75:0] EX_to_MEM_bus,
    input  wire [31:0] MEM_data_sram_rdata,

    output wire        MEM_allowin,
    output wire        MEM_to_WB_valid,
    output wire [69:0] MEM_to_WB_bus,

    // data_harzard detect & forward path
    output wire        ms_valid,
    output wire [ 4:0] ms_dest,
    output wire        ms_rf_we,
    output wire [31:0] MEM_wdata_forward
);

wire       MEM_readygo;
reg        MEM_valid;
reg [75:0] MEM_data;

assign MEM_readygo      = 1'b1;
assign MEM_to_WB_valid  = MEM_valid && MEM_readygo;
assign MEM_allowin      = !MEM_valid || MEM_to_WB_valid && WB_allowin; 
always @(posedge clk) begin
    if (reset) begin
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

assign {MEM_pc,
        MEM_rf_we,
        MEM_dest,
        MEM_sel_rf_res,
        MEM_alu_res,
        MEM_mem_size,
        MEM_load_unsigned,
        MEM_addr_low}        = MEM_data;

assign MEM_to_WB_bus        = {MEM_pc,
                              MEM_rf_we,
                              MEM_dest,
                              MEM_res};
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

endmodule