`ifndef MYCPU_H
`define MYCPU_H

`define ALU_OP_WD           15  // ALU操作控制向量的位数
`define CSR_NUM_WD          14  // CSR编号位数，对应CSR指令的inst[23:10]

// 随指令从ID传至WB的附加信息，共81位；各级打包、解包必须保持相同顺序：
// {读CSR标记, 写CSR标记, CSR编号, 写掩码, 写入值, ertn标记}
`define CSR_BUS_WD          (1 + 1 + `CSR_NUM_WD + 32 + 32 + 1)

// 原总线字段宽度 + CSR附加信息；146表示ID总线中除ALU控制向量外的原字段总宽度。
// IF->ID仍为64位；ID->EX、EX->MEM、MEM->WB分别为242、157、151位。
`define IF_TO_ID_BUS_WD     64
`define ID_TO_EX_BUS_WD     (146 + `ALU_OP_WD + `CSR_BUS_WD)
`define EX_TO_MEM_BUS_WD    (76 + `CSR_BUS_WD)
`define MEM_TO_WB_BUS_WD    (70 + `CSR_BUS_WD)

`define CSR_OPCODE          8'h04        // 三条CSR指令共有的inst[31:24]编码
`define INST_ERTN           32'h06483800  // ertn无操作数，直接匹配完整指令码

`endif
