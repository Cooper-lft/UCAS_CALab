`ifndef MYCPU_H
`define MYCPU_H

`define ALU_OP_WD           15  // ALU操作控制向量的位数
`define CSR_NUM_WD          14  // CSR编号位数，对应CSR指令的inst[23:10]

// 随指令从ID传至WB的附加信息，共81位；
// {读CSR标记, 写CSR标记, CSR编号, 写掩码, 写入值, ertn标记}
`define CSR_BUS_WD          (1 + 1 + `CSR_NUM_WD + 32 + 32 + 1)

// exp13异常标志：{INT, ADEF, INE, BRK, SYS, ALE}
`define EXCEPTION_BUS_WD    6
`define EXC_INT             5
`define EXC_ADEF            4
`define EXC_INE             3
`define EXC_BRK             2
`define EXC_SYS             1
`define EXC_ALE             0
// 原总线字段宽度 + CSR附加信息；146表示ID总线中除ALU控制向量外的原字段总宽度。
// IF->ID为65位：原PC/指令加ADEF。ID->EX、EX->MEM、MEM->WB为248、195、189位。
// EX之后另带完整32位数据访存地址，不能用load结果或地址低两位替代BADV输入。
`define IF_TO_ID_BUS_WD     (64 + 1)
`define ID_TO_EX_BUS_WD     (146 + `ALU_OP_WD + `CSR_BUS_WD + `EXCEPTION_BUS_WD)
`define EX_TO_MEM_BUS_WD    (76 + `CSR_BUS_WD + `EXCEPTION_BUS_WD + 32)
`define MEM_TO_WB_BUS_WD    (70 + `CSR_BUS_WD + `EXCEPTION_BUS_WD + 32)

`define CSR_OPCODE          8'h04           // 三条CSR指令共有的inst[31:24]编码
`define INST_ERTN           32'h06483800    // ertn无操作数，直接匹配完整指令码
`define ECODE_INT           6'h00           // 中断也是异常；不能用异常码是否为0判断有无异常
`define ECODE_ADE           6'h08           // 本阶段仅实现取指地址错ADEF，子码为0
`define ECODE_ALE           6'h09           // load/store地址非对齐
`define ECODE_SYS           6'h0b           // SYS系统调用异常码
`define ECODE_BRK           6'h0c           // break断点异常
`define ECODE_INE           6'h0d           // 未匹配当前已实现指令的译码
`define ESUBCODE_SYS        9'h000          // SYS异常子码，与指令低15位code无关

`define CSR_CRMD    14'h0000
`define CSR_PRMD    14'h0001
`define CSR_ECFG    14'h0004
`define CSR_ESTAT   14'h0005
`define CSR_ERA     14'h0006
`define CSR_BADV    14'h0007
`define CSR_EENTRY  14'h000c
`define CSR_SAVE0   14'h0030
`define CSR_SAVE1   14'h0031
`define CSR_SAVE2   14'h0032
`define CSR_SAVE3   14'h0033
`define CSR_TID     14'h0040
`define CSR_TCFG    14'h0041
`define CSR_TVAL    14'h0042
`define CSR_TICLR   14'h0044

// 教材7.3.4：写这些CSR可能改变中断是否发生、某一路中断是否允许响应或全局是否允许响应。
// 在写入尚未生效时，ID需暂停，等CSR更新后再判断中断；这里直接检查CSR编号，
// 不再细分写掩码是否真的修改了相关位，也不把尚未写入的状态提前传给ID使用。
// TCFG控制定时器，TICLR清除定时器中断，因此写它们也可能改变中断判断结果。
`define CSR_INT_RELATED(num) (((num) == `CSR_CRMD) || ((num) == `CSR_ECFG) || \
                              ((num) == `CSR_ESTAT) || ((num) == `CSR_TCFG) || \
                              ((num) == `CSR_TICLR))

`endif
