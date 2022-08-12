module IntALU
(
   input wire clk,
   input wire rst,

   input wire[31:0] IN_operands[2:0],
   input OPCode_INT IN_opcode,
   input wire[5:0] IN_tagDst,

   output reg[31:0] OUT_result,
   output reg[5:0] OUT_tagDst
);

wire resC[31:0];
always@(*) begin
    // optimize this depending on how good of a job synthesis does
    case (IN_opcode)
        INT_AUIPC,
        INT_ADD: resC <= IN_operands[0] + IN_operands[1];
        INT_XOR: resC <= IN_operands[0] ^ IN_operands[1];
        INT_OR: resC <= IN_operands[0] | IN_operands[1];
        INT_AND: resC <= IN_operands[0] & IN_operands[1];
        INT_SLL: resC <= IN_operands[0] << IN_operands[1][4:0];
        INT_SRL: resC <= IN_operands[0] >> IN_operands[1][4:0];
        INT_SLT: resC <= $signed(IN_operands[0]) < $signed(IN_operands[1]);
        INT_SLTU: resC <= IN_operands[0] < IN_operands[1];
        INT_SUB: resC <= IN_operands[0] - IN_operands[1];
        INT_SRA: resC <= IN_operands[0] >>> IN_operands[1][4:0];

        INT_BEQ: resC <= IN_operands[0] == IN_operands[1];
        INT_BNE: resC <= IN_operands[0] == IN_operands[1];
        INT_BLT: resC <= $signed(IN_operands[0]) < $signed(IN_operands[1]);
        INT_BGE: resC <= $signed(IN_operands[0]) >= $signed(IN_operands[1]);
        INT_BLTU: resC <= IN_operands[0] < IN_operands[1];
        INT_BGEU: resC <= IN_operands[0] >= IN_operands[1];
        INT_LUI: resC <= IN_operands[1];
        INT_JALR,
        INT_JAL: resC <= IN_operands[0] + 4;
    endcase 
end

always@(posedge clk) begin
    OUT_result <= resC;
    OUT_tagDst <= IN_tagDst;
end
endmodule;