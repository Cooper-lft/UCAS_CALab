module MEM_stage (
    input  wire        clk,
    input  wire        reset,

    input  wire        EX_to_MEM_valid,
    input  wire        WB_allowin,
    input  wire [70:0] EX_to_MEM_bus,
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
reg [70:0] MEM_data;

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

assign {MEM_pc,
        MEM_rf_we,
        MEM_dest,
        MEM_sel_rf_res,
        MEM_alu_res}        = MEM_data;

assign MEM_to_WB_bus        = {MEM_pc,
                              MEM_rf_we,
                              MEM_dest,
                              MEM_res};

                            // when MEM_sel_rf_res == 1, final result is from data_sram(load inst)
assign MEM_res              = (MEM_sel_rf_res)? MEM_data_sram_rdata : MEM_alu_res;

// forward
assign ms_valid             = MEM_valid;
assign ms_dest              = MEM_dest;
assign ms_rf_we             = MEM_rf_we;
assign MEM_wdata_forward    = MEM_res;

endmodule