module EX_stage (
    input  wire         clk,
    input  wire         reset,

    input  wire [154:0] ID_to_EX_bus,
    input  wire         ID_to_EX_valid,
    input  wire         MEM_allowin,

    output wire         EX_allowin,
    output wire         EX_to_MEM_valid,
    output wire [70:0]  EX_to_MEM_bus,
    output wire         EX_data_sram_en,
    output wire [3:0]   EX_data_sram_we,
    output wire [31:0]  EX_data_sram_addr,
    output wire [31:0]  EX_data_sram_wdata,

    output wire         es_valid,
    output wire [4:0]   es_dest,
    output wire         es_rf_we,
    output wire         load_in_EX,
    output wire [31:0]  EX_wdata_forward
);

wire EX_readygo;
reg EX_valid;
reg [154:0] EX_data;

wire [31:0] EX_pc;
wire EX_rf_we;
wire [4:0] EX_dest;
wire EX_sel_rf_res;
wire [2:0] EX_div_op;
wire [31:0] EX_alu_src1;
wire [31:0] EX_alu_src2;
wire [11:0] EX_alu_op;
wire [3:0] EX_mem_we;
wire EX_mem_en;
wire [31:0] EX_alu_res;
wire [31:0] EX_result;

wire EX_is_div;
wire EX_div_unsigned;
wire EX_is_mod;
assign EX_is_div       = EX_div_op[0];
assign EX_div_unsigned = EX_div_op[1];
assign EX_is_mod       = EX_div_op[2];

assign {EX_pc,
        EX_rf_we,
        EX_dest,
        EX_sel_rf_res,
        EX_div_op,
        EX_alu_src1,
        EX_alu_src2,
        EX_alu_op,
        EX_data_sram_wdata,
        EX_mem_we,
        EX_mem_en} = EX_data;

reg div_done; 
reg [31:0] div_result_r;
wire div_result_valid;
wire [31:0] div_result_now;
wire [31:0] div_result;

// Use a newly returned result immediately, or a previously buffered result.
assign EX_readygo      = !EX_is_div || div_done || div_result_valid;
assign EX_to_MEM_valid = EX_valid && EX_readygo;
assign EX_allowin      = !EX_valid || (EX_to_MEM_valid && MEM_allowin);

always @(posedge clk) begin
    if (reset)
        EX_valid <= 1'b0;
    else if (EX_allowin)
        EX_valid <= ID_to_EX_valid;

    if (!reset && EX_allowin && ID_to_EX_valid)
        EX_data <= ID_to_EX_bus;
end

alu u_alu (
    .alu_op     (EX_alu_op),
    .alu_src1   (EX_alu_src1),
    .alu_src2   (EX_alu_src2),
    .alu_result (EX_alu_res)
);

assign EX_data_sram_we   = {4{EX_valid && !reset}} & EX_mem_we;
assign EX_data_sram_en   = EX_valid && !reset && EX_mem_en;
assign EX_data_sram_addr = EX_alu_res;

// Keep the original load detection; division is stalled by EX_readygo.
assign load_in_EX = EX_data_sram_en && !EX_data_sram_we;

// Dividend input channels.
wire [31:0] dividend_tdata;
wire dividend_tvalid_signed;
wire dividend_tready_signed;
wire dividend_tvalid_unsigned;
wire dividend_tready_unsigned;

// Divisor input channels.
wire [31:0] divisor_tdata;
wire divisor_tvalid_signed;
wire divisor_tready_signed;
wire divisor_tvalid_unsigned;
wire divisor_tready_unsigned;

wire [63:0] dout_tdata_signed;
wire dout_tvalid_signed;
wire [63:0] dout_tdata_unsigned;
wire dout_tvalid_unsigned;

reg div_sent;
wire div_req;
wire div_input_fire;

assign dividend_tdata = EX_alu_src1;
assign divisor_tdata  = EX_alu_src2;

// NonBlocking mode accepts an operation only when BOTH inputs are valid
// at the same clock edge, with both ready signals asserted if present.
// Keep the operand pair together until that joint acceptance occurs.
assign div_req = EX_valid && !reset && EX_is_div && !div_done && !div_sent;
assign dividend_tvalid_signed   = div_req && !EX_div_unsigned;
assign divisor_tvalid_signed    = dividend_tvalid_signed;
assign dividend_tvalid_unsigned = div_req && EX_div_unsigned;
assign divisor_tvalid_unsigned  = dividend_tvalid_unsigned;

assign div_input_fire = div_req &&
    (EX_div_unsigned
     ? (dividend_tready_unsigned && divisor_tready_unsigned)
     : (dividend_tready_signed   && divisor_tready_signed));

always @(posedge clk) begin
    if (reset || EX_allowin)
        div_sent <= 1'b0;
    else if (div_input_fire)
        div_sent <= 1'b1;
end

wire div_out_valid;
wire [63:0] div_out_data;
wire [31:0] quotient;
wire [31:0] remainder;

assign div_out_valid = EX_div_unsigned ? dout_tvalid_unsigned
                                      : dout_tvalid_signed;
assign div_out_data = EX_div_unsigned ? dout_tdata_unsigned
                                     : dout_tdata_signed;
assign quotient  = div_out_data[63:32];
assign remainder = div_out_data[31:0];
assign div_result_valid = EX_valid && !reset && EX_is_div
                       && div_sent && div_out_valid;
assign div_result_now = EX_is_mod ? remainder : quotient;
assign div_result = div_done ? div_result_r : div_result_now;

// MEM ready: EX_result bypasses this register and transfers at this edge.
// MEM blocked: capture the one-cycle IP result and keep it until EX leaves.
always @(posedge clk) begin
    if (reset) begin
        div_done     <= 1'b0;
        div_result_r <= 32'b0;
    end
    else if (EX_allowin) begin
        div_done <= 1'b0;
    end
    else if (div_result_valid && !div_done) begin
        div_done     <= 1'b1;
        div_result_r <= div_result_now;
    end
end

assign EX_result = EX_is_div ? div_result : EX_alu_res;
assign EX_to_MEM_bus = {EX_pc, EX_rf_we, EX_dest,
                        EX_sel_rf_res, EX_result};
assign EX_wdata_forward = EX_result;
assign es_valid = EX_valid;
assign es_dest  = EX_dest;
assign es_rf_we = EX_rf_we;

mydiv_sign u_div_sign (
    .aclk                   (clk),
    .aresetn                (~reset),
    .s_axis_divisor_tdata    (divisor_tdata),
    .s_axis_divisor_tready   (divisor_tready_signed),
    .s_axis_divisor_tvalid   (divisor_tvalid_signed),
    .s_axis_dividend_tdata   (dividend_tdata),
    .s_axis_dividend_tready  (dividend_tready_signed),
    .s_axis_dividend_tvalid  (dividend_tvalid_signed),
    .m_axis_dout_tdata       (dout_tdata_signed),
    .m_axis_dout_tvalid      (dout_tvalid_signed)
);

mydiv_unsign u_div_unsign (
    .aclk                   (clk),
    .aresetn                (~reset),
    .s_axis_divisor_tdata    (divisor_tdata),
    .s_axis_divisor_tready   (divisor_tready_unsigned),
    .s_axis_divisor_tvalid   (divisor_tvalid_unsigned),
    .s_axis_dividend_tdata   (dividend_tdata),
    .s_axis_dividend_tready  (dividend_tready_unsigned),
    .s_axis_dividend_tvalid  (dividend_tvalid_unsigned),
    .m_axis_dout_tdata       (dout_tdata_unsigned),
    .m_axis_dout_tvalid      (dout_tvalid_unsigned)
);

endmodule