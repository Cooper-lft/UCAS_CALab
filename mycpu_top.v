`include "mycpu.h"

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

// WB统一访问CSR；CSR返回旧值给WB，并提供ertn的返回地址给IF。
wire        ertn_flush;  // WB -> 各流水级/CSR：返回生效，取消年轻指令并恢复状态
wire [31:0] ertn_entry;  // CSR -> IF：返回目标地址，后续由ERA提供
wire        wb_ex;       // WB -> 各流水级/CSR：正式提交SYS异常。
wire [5:0]  wb_ecode;    // WB -> CSR：异常一级编码。
wire [8:0]  wb_esubcode; // WB -> CSR：异常子码。
wire [31:0] ex_entry;    // CSR -> IF：EENTRY异常入口。
wire        mem_ex;      // MEM -> EX：较老syscall待提交，提前屏蔽访存。
wire        csr_re;      // WB -> CSR：有效的读请求
wire        csr_we;      // WB -> CSR：有效的写请求
wire [`CSR_NUM_WD-1:0] csr_num; // WB -> CSR：读写共用的编号
wire [31:0] csr_rvalue;  // CSR -> WB：更新前的旧值，写回rd并供WB前递使用
wire [31:0] csr_wmask;   // WB -> CSR：逐位写掩码
wire [31:0] csr_wvalue;  // WB -> CSR：来自原GR[rd]的写入数据
// EX/MEM反馈给ID的指令类型标记，均已结合所在级的valid。
wire        csr_in_EX;  // CSR返回值尚未就绪，相关的ID指令需等待
wire        csr_in_MEM; // CSR仍需等到WB才能提供返回值
wire        ertn_in_MEM;// MEM -> EX：禁止年轻访存或除法请求，等待WB统一清空

csr u_csr (
    .clk        (clk        ),
    .reset      (reset      ),
    .csr_re     (csr_re     ),
    .csr_num    (csr_num    ),
    .csr_rvalue (csr_rvalue ),
    .csr_we     (csr_we     ),
    .csr_wmask  (csr_wmask  ),
    .csr_wvalue (csr_wvalue ),
    .wb_ex      (wb_ex      ),
    .wb_pc      (WB_pc      ),
    .wb_ecode   (wb_ecode   ),
    .wb_esubcode(wb_esubcode),
    .ex_entry   (ex_entry   ),
    .ertn_flush (ertn_flush ),
    .ertn_entry (ertn_entry )
    );

wire        br_taken;
wire [31:0] br_target;
wire        ID_allowin;
wire        IF_to_ID_valid;
wire [`IF_TO_ID_BUS_WD-1:0] IF_to_ID_bus;
wire         br_taken_cancel;
IF_stage u_IF_stage (
    .clk            (clk            ),
    .reset          (reset          ),
    .wb_ex          (wb_ex          ), 
    .ex_entry       (ex_entry       ),
    .ertn_flush     (ertn_flush     ),
    .ertn_entry     (ertn_entry     ),
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
wire [`ID_TO_EX_BUS_WD-1:0] ID_to_EX_bus;
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
    .wb_ex              (wb_ex            ),
    .ertn_flush         (ertn_flush       ),
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
    .csr_in_EX          (csr_in_EX        ),
    .EX_wdata_forward   (EX_wdata_forward ),
    
    .MEM_valid          (MEM_valid        ),
    .MEM_dest           (MEM_dest         ),
    .MEM_rf_we          (MEM_rf_we        ),
    .csr_in_MEM         (csr_in_MEM       ),
    .MEM_wdata_forward  (MEM_wdata_forward),
    
    .WB_valid           (WB_valid         ),
    
    .br_taken_cancel    (br_taken_cancel  )
    );

wire         MEM_allowin;
wire         EX_to_MEM_valid;
wire [`EX_TO_MEM_BUS_WD-1:0] EX_to_MEM_bus;
wire         EX_data_sram_en;
wire [  3:0] EX_data_sram_we;
wire [ 31:0] EX_data_sram_addr;
wire [ 31:0] EX_data_sram_wdata;
EX_stage u_EX_stage (
    .clk                (clk                ),
    .reset              (reset              ),
    .wb_ex              (wb_ex              ),
    .mem_ex             (mem_ex             ),
    .ertn_flush         (ertn_flush         ),
    .ertn_in_MEM        (ertn_in_MEM        ),
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
    .EX_wdata_forward   (EX_wdata_forward   ),
    .csr_in_EX          (csr_in_EX          )
    );
assign data_sram_en         = EX_data_sram_en;
assign data_sram_we         = EX_data_sram_we;
assign data_sram_addr       = EX_data_sram_addr;
assign data_sram_wdata      = EX_data_sram_wdata;

wire        WB_allowin;
wire [31:0] MEM_data_sram_rdata;
wire        MEM_to_WB_valid;
wire [`MEM_TO_WB_BUS_WD-1:0] MEM_to_WB_bus;
MEM_stage u_MEM_stage (
    .clk                    (clk                    ),
    .reset                  (reset                  ),
    .wb_ex                  (wb_ex                  ),
    .ertn_flush             (ertn_flush             ),
    
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
    .MEM_wdata_forward      (MEM_wdata_forward      ),
    .csr_in_MEM             (csr_in_MEM             ),
    .ertn_in_MEM            (ertn_in_MEM            ),
    .mem_ex                 (mem_ex                 )
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
    .ws_valid           (WB_valid       ),
    .csr_re             (csr_re         ),
    .csr_we             (csr_we         ),
    .csr_num            (csr_num        ),
    .csr_wmask          (csr_wmask      ),
    .csr_wvalue         (csr_wvalue     ),
    .csr_rvalue         (csr_rvalue     ),
    .ertn_flush         (ertn_flush     ),
    .wb_ex              (wb_ex          ),
    .wb_ecode           (wb_ecode       ),
    .wb_esubcode        (wb_esubcode    )
    );
assign WB_rf_wdata          = WB_res;
assign WB_rf_waddr          = WB_dest;

assign debug_wb_pc          = WB_pc;
assign debug_wb_rf_we       = {4{WB_rf_we}};
assign debug_wb_rf_wnum     = WB_dest;
assign debug_wb_rf_wdata    = WB_res;

endmodule
