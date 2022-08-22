module IntALULight
(
    input wire clk,
    input wire en,
    input wire rst,

    input wire IN_valid,
    input wire IN_wbStall,
    input wire IN_invalidate,
    input wire[5:0] IN_invalidateSqN,
    
    input wire[31:0] IN_operands[2:0],
    input OPCode_INT IN_opcode,
    input wire[5:0] IN_tagDst,
    input wire[4:0] IN_nmDst,
    input reg[5:0] IN_sqN,

    output wire OUT_wbReq,
    output reg OUT_valid,

    output reg[31:0] OUT_result,
    output reg[5:0] OUT_tagDst,
    output reg[4:0] OUT_nmDst,
    output reg[5:0] OUT_sqN
);

assign OUT_wbReq = IN_valid;

reg[31:0] resC;
always_comb begin
    // optimize this depending on how good of a job synthesis does
    case (IN_opcode)
        INT_AUIPC,
        INT_ADD: resC = IN_operands[0] + IN_operands[1];
        INT_XOR: resC = IN_operands[0] ^ IN_operands[1];
        INT_OR: resC = IN_operands[0] | IN_operands[1];
        INT_AND: resC = IN_operands[0] & IN_operands[1];
        INT_SLL: resC = IN_operands[0] << IN_operands[1][4:0];
        INT_SRL: resC = IN_operands[0] >> IN_operands[1][4:0];
        INT_SLT: resC = {31'b0, ($signed(IN_operands[0]) < $signed(IN_operands[1]))};
        INT_SLTU: resC = {31'b0, IN_operands[0] < IN_operands[1]};
        INT_SUB: resC = IN_operands[0] - IN_operands[1];
        INT_SRA: resC = IN_operands[0] >>> IN_operands[1][4:0];

        INT_LUI: resC = IN_operands[1];
        default: resC = 'bx;
    endcase
end 


always_ff@(posedge clk) begin
    if (IN_valid && !IN_wbStall && (!IN_invalidate || $signed(IN_sqN - IN_invalidateSqN) <= 0)) begin
        OUT_valid <= 1;
        OUT_tagDst <= IN_tagDst;
        OUT_nmDst <= IN_nmDst;
        OUT_result <= resC;
        OUT_sqN <= IN_sqN;
    end
    else
        OUT_valid <= 0;
        
end
endmodule
