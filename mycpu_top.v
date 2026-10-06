module mycpu_top(
    input  wire        clk,
    input  wire        resetn,
    // inst sram interface
    output wire        inst_sram_en,
    output wire [ 3:0] inst_sram_we,
    output wire [31:0] inst_sram_addr,
    output wire [31:0] inst_sram_wdata,
    input  wire [31:0] inst_sram_rdata,
    // data sram interface
    output wire        data_sram_en,
    output wire [ 3:0] data_sram_we,
    output wire [31:0] data_sram_addr,
    output wire [31:0] data_sram_wdata,
    input  wire [31:0] data_sram_rdata,
    // trace debug interface
    output wire [31:0] debug_wb_pc,
    output wire [ 3:0] debug_wb_rf_we,
    output wire [ 4:0] debug_wb_rf_wnum,
    output wire [31:0] debug_wb_rf_wdata
);
reg         reset;
always @(posedge clk) reset <= ~resetn;

wire        br_taken;
wire [31:0] br_target;
wire        ID_allowin;
wire        IF_to_ID_valid;
wire [63:0] IF_to_ID_bus;
wire         br_taken_cancel;
IF_stage u_IF_stage (
    .clk            (clk            ),
    .reset          (reset          ),
    .br_taken       (br_taken       ),
    .br_target      (br_target      ),
    .ID_allowin     (ID_allowin     ),
    .IF_to_ID_valid (IF_to_ID_valid ),
    .inst_sram_rdata(inst_sram_rdata),
    .inst_sram_wdata(inst_sram_wdata),
    .inst_sram_addr (inst_sram_addr ),
    .inst_sram_en   (inst_sram_en   ),
    .inst_sram_we   (inst_sram_we   ),
    .IF_to_ID_bus   (IF_to_ID_bus   ),
    .br_taken_cancel(br_taken_cancel)
    );

wire         EX_allowin;
wire [157:0] ID_to_EX_bus;
wire         ID_to_EX_valid;
wire         WB_rf_we;
wire [  4:0] WB_rf_waddr;
wire [ 31:0] WB_rf_wdata;

wire         EX_valid;
wire [  4:0] EX_dest;
wire         EX_rf_we;
wire         load_in_EX;
wire [ 31:0] EX_wdata_forward;

wire         MEM_valid;
wire [  4:0] MEM_dest;
wire         MEM_rf_we;
wire [ 31:0] MEM_wdata_forward;
wire         WB_valid;
ID_stage u_ID_stage (
    .clk                (clk              ),
    .reset              (reset            ),
    .IF_to_ID_valid     (IF_to_ID_valid   ),
    .IF_to_ID_bus       (IF_to_ID_bus     ),
    .EX_allowin         (EX_allowin       ),
    .ID_to_EX_bus       (ID_to_EX_bus     ),
    .ID_to_EX_valid     (ID_to_EX_valid   ),
    .ID_allowin         (ID_allowin       ),
    .WB_rf_we           (WB_rf_we         ),
    .WB_rf_waddr        (WB_rf_waddr      ),
    .WB_rf_wdata        (WB_rf_wdata      ),
    
    .br_taken           (br_taken         ),
    .br_target          (br_target        ),
    
    .EX_valid           (EX_valid         ),
    .EX_dest            (EX_dest          ),
    .EX_rf_we           (EX_rf_we         ),
    .load_in_EX         (load_in_EX       ),
    .EX_wdata_forward   (EX_wdata_forward ),
    
    .MEM_valid          (MEM_valid        ),
    .MEM_dest           (MEM_dest         ),
    .MEM_rf_we          (MEM_rf_we        ),
    .MEM_wdata_forward  (MEM_wdata_forward),
    
    .WB_valid           (WB_valid         ),
    
    .br_taken_cancel    (br_taken_cancel  )
    );

wire         MEM_allowin;
wire         EX_to_MEM_valid;
wire [ 70:0] EX_to_MEM_bus;
wire         EX_data_sram_en;
wire [  3:0] EX_data_sram_we;
wire [ 31:0] EX_data_sram_addr;
wire [ 31:0] EX_data_sram_wdata;
EX_stage u_EX_stage (
    .clk                (clk                ),
    .reset              (reset              ),
    .ID_to_EX_bus       (ID_to_EX_bus       ),
    .ID_to_EX_valid     (ID_to_EX_valid     ),
    .MEM_allowin        (MEM_allowin        ),
    .EX_allowin         (EX_allowin         ),
    .EX_to_MEM_valid    (EX_to_MEM_valid    ),
    .EX_to_MEM_bus      (EX_to_MEM_bus      ),
    .EX_data_sram_en    (EX_data_sram_en    ),
    .EX_data_sram_we    (EX_data_sram_we    ),
    .EX_data_sram_addr  (EX_data_sram_addr  ),
    .EX_data_sram_wdata (EX_data_sram_wdata ),
    .es_valid           (EX_valid           ),
    .es_dest            (EX_dest            ),
    .es_rf_we           (EX_rf_we           ),
    .load_in_EX         (load_in_EX         ),
    .EX_wdata_forward   (EX_wdata_forward   )
    );
assign data_sram_en         = EX_data_sram_en;
assign data_sram_we         = EX_data_sram_we;
assign data_sram_addr       = EX_data_sram_addr;
assign data_sram_wdata      = EX_data_sram_wdata;

wire        WB_allowin;
wire [31:0] MEM_data_sram_rdata;
wire        MEM_to_WB_valid;
wire [69:0] MEM_to_WB_bus;
MEM_stage u_MEM_stage (
    .clk                    (clk                    ),
    .reset                  (reset                  ),
    
    .EX_to_MEM_valid        (EX_to_MEM_valid        ),
    .WB_allowin             (WB_allowin             ),
    .EX_to_MEM_bus          (EX_to_MEM_bus          ),
    .MEM_data_sram_rdata    (MEM_data_sram_rdata    ),
    
    .MEM_allowin            (MEM_allowin            ),
    .MEM_to_WB_valid        (MEM_to_WB_valid        ),
    .MEM_to_WB_bus          (MEM_to_WB_bus          ),
    
    .ms_valid               (MEM_valid              ),
    .ms_dest                (MEM_dest               ),
    .ms_rf_we               (MEM_rf_we              ),
    .MEM_wdata_forward      (MEM_wdata_forward      )
    );
assign MEM_data_sram_rdata  = data_sram_rdata;

wire [31:0] WB_pc;
wire [ 4:0] WB_dest;
wire [31:0] WB_res;
WB_stage u_WB_stage (
    .clk                (clk            ),
    .reset              (reset          ),
    .MEM_to_WB_valid    (MEM_to_WB_valid),
    .MEM_to_WB_bus      (MEM_to_WB_bus  ),
    .WB_allowin         (WB_allowin     ),
    .WB_pc              (WB_pc          ),
    .WB_rf_we           (WB_rf_we       ),
    .WB_dest            (WB_dest        ),
    .WB_res             (WB_res         ),
    .ws_valid           (WB_valid       )  
    );
assign WB_rf_wdata          = WB_res;
assign WB_rf_waddr          = WB_dest;

assign debug_wb_pc          = WB_pc;
assign debug_wb_rf_we       = {4{WB_rf_we}};
assign debug_wb_rf_wnum     = WB_dest;
assign debug_wb_rf_wdata    = WB_res;

endmodule
