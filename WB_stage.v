module WB_stage (
    input  wire        clk,
    input  wire        reset,

    input  wire        MEM_to_WB_valid,
    input  wire [69:0] MEM_to_WB_bus,    

    output wire        WB_allowin,
    output wire [31:0] WB_pc,
    
    output wire        WB_rf_we,
    output wire [ 4:0] WB_dest,
    output wire [31:0] WB_res,
    output wire        ws_valid
);

wire       WB_readygo;
reg        WB_valid;
reg [69:0] WB_data;

assign WB_readygo       = 1'b1;
assign WB_allowin       = !WB_valid || WB_readygo;
always @(posedge clk) begin
    if (reset) begin
        WB_valid <= 1'b0;
    end
    else if (WB_allowin) begin
        WB_valid <= MEM_to_WB_valid;
    end

    if (WB_allowin && MEM_to_WB_valid) begin
        WB_data <= MEM_to_WB_bus;
    end
end

assign {WB_pc,
        WB_rf_we,
        WB_dest,
        WB_res}     = WB_data & {70{WB_valid}};

assign ws_valid     = WB_valid;

endmodule