module alu(
  input  wire [14:0] alu_op,
  input  wire [31:0] alu_src1,
  input  wire [31:0] alu_src2,
  output wire [31:0] alu_result
);

wire op_add;   
wire op_sub;   
wire op_slt;  
wire op_sltu;  
wire op_and;   
wire op_nor;   
wire op_or;    
wire op_xor;   
wire op_sll;   
wire op_srl;   
wire op_sra;   
wire op_lui;  
wire op_mul;   
wire op_mulh;  
wire op_mulh_u;//unsigned multiply, high 32 bits

// control code decomposition
assign op_add     = alu_op[ 0];
assign op_sub     = alu_op[ 1];
assign op_slt     = alu_op[ 2];
assign op_sltu    = alu_op[ 3];
assign op_and     = alu_op[ 4];
assign op_nor     = alu_op[ 5];
assign op_or      = alu_op[ 6];
assign op_xor     = alu_op[ 7];
assign op_sll     = alu_op[ 8];
assign op_srl     = alu_op[ 9];
assign op_sra     = alu_op[10];
assign op_lui     = alu_op[11];
assign op_mul     = alu_op[12];
assign op_mulh    = alu_op[13];
assign op_mulh_u  = alu_op[14];

wire [31:0] add_sub_result;
wire [31:0] slt_result;
wire [31:0] sltu_result;
wire [31:0] and_result;
wire [31:0] nor_result;
wire [31:0] or_result;
wire [31:0] xor_result;
wire [31:0] lui_result;
wire [31:0] sll_result;
wire [63:0] sr64_result;
wire [31:0] sr_result;


// 32-bit adder
wire [31:0] adder_a;
wire [31:0] adder_b;
wire        adder_cin;
wire [31:0] adder_result;
wire        adder_cout;

assign adder_a   = alu_src1;
assign adder_b   = (op_sub | op_slt | op_sltu) ? ~alu_src2 : alu_src2;  //src1 - src2 rj-rk
assign adder_cin = (op_sub | op_slt | op_sltu) ? 1'b1      : 1'b0;
assign {adder_cout, adder_result} = adder_a + adder_b + adder_cin;

// ADD, SUB result
assign add_sub_result = adder_result;

// SLT result
assign slt_result[31:1] = 31'b0;   //rj < rk 1
assign slt_result[0]    = (alu_src1[31] & ~alu_src2[31])
                        | ((alu_src1[31] ~^ alu_src2[31]) & adder_result[31]);

// SLTU result
assign sltu_result[31:1] = 31'b0;
assign sltu_result[0]    = ~adder_cout;

// bitwise operation
assign and_result = alu_src1 & alu_src2;
assign or_result  = alu_src1 | alu_src2;
assign nor_result = ~or_result;
assign xor_result = alu_src1 ^ alu_src2;
assign lui_result = alu_src2;


// SLL result
assign sll_result = alu_src1 << alu_src2[4:0];   //rj << i5

// SRL, SRA result
assign sr64_result = {{32{op_sra & alu_src1[31]}}, alu_src1[31:0]} >> alu_src2[4:0]; //rj >> i5


assign sr_result   = sr64_result[31:0];


wire mul_signed;
wire signed [32:0] mul_src1;
wire signed [32:0] mul_src2;
wire signed [65:0] mul_product;

assign mul_signed = op_mul | op_mulh;
assign mul_src1 = {mul_signed & alu_src1[31], alu_src1};
assign mul_src2 = {mul_signed & alu_src2[31], alu_src2};
assign mul_product = mul_src1 * mul_src2;

assign alu_result = ({32{op_add|op_sub}} & add_sub_result)
                  | ({32{op_slt       }} & slt_result)
                  | ({32{op_sltu      }} & sltu_result)
                  | ({32{op_and       }} & and_result)
                  | ({32{op_nor       }} & nor_result)
                  | ({32{op_or        }} & or_result)
                  | ({32{op_xor       }} & xor_result)
                  | ({32{op_lui       }} & lui_result)
                  | ({32{op_sll       }} & sll_result)
                  | ({32{op_srl|op_sra}} & sr_result)
                  | ({32{op_mul       }} & mul_product[31:0])
                  | ({32{op_mulh|op_mulh_u}} & mul_product[63:32]);

endmodule