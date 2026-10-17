`ifndef MYCPU_H
`define MYCPU_H

`define ALU_OP_WD           15  // ALU操作控制向量的位数
`define CSR_NUM_WD          14  // CSR编号位数，对应CSR指令的inst[23:10]

// 随指令从ID传至WB的附加信息，共81位；各级打包、解包必须保持相同顺序：
// {读CSR标记, 写CSR标记, CSR编号, 写掩码, 写入值, ertn标记}
`define CSR_BUS_WD          (1 + 1 + `CSR_NUM_WD + 32 + 32 + 1)

// 原总线字段宽度 + CSR附加信息；146表示ID总线中除ALU控制向量外的原字段总宽度。
// IF->ID仍为64位；ID->EX、EX->MEM、MEM->WB分别为243、158、152位。
`define EXCEPTION_BUS_WD    1       // 仅传递is_syscall，在WB统一编码异常原因。
`define IF_TO_ID_BUS_WD     64
`define ID_TO_EX_BUS_WD     (146 + `ALU_OP_WD + `CSR_BUS_WD + `EXCEPTION_BUS_WD)
`define EX_TO_MEM_BUS_WD    (76 + `CSR_BUS_WD + `EXCEPTION_BUS_WD)
`define MEM_TO_WB_BUS_WD    (70 + `CSR_BUS_WD + `EXCEPTION_BUS_WD)

`define CSR_OPCODE          8'h04           // 三条CSR指令共有的inst[31:24]编码
`define INST_ERTN           32'h06483800    // ertn无操作数，直接匹配完整指令码
`define ECODE_SYS           6'h0b           // SYS系统调用异常码
`define ESUBCODE_SYS        9'h000          // SYS异常子码，与指令低15位code无关

`define CSR_CRMD    14'h0000
`define CSR_PRMD    14'h0001
`define CSR_ESTAT   14'h0005
`define CSR_ERA     14'h0006
`define CSR_EENTRY  14'h000c
`define CSR_SAVE0   14'h0030
`define CSR_SAVE1   14'h0031
`define CSR_SAVE2   14'h0032
`define CSR_SAVE3   14'h0033

`endif
