module IntALU
(
    input wire clk,
    input wire en,
    input wire rst,

    input wire IN_valid,
    input wire IN_wbStall,
    input wire[31:0] IN_operands[2:0],
    input OPCode_INT IN_opcode,
    input wire[5:0] IN_tagDst,
    input wire[4:0] IN_nmDst,
    input reg[5:0] IN_sqN,

    output wire OUT_wbReq,
    output reg OUT_valid,

    output reg OUT_isBranch,
    output reg OUT_branchTaken,
    output reg[31:0] OUT_branchAddress,
    output reg[5:0] OUT_branchSqN,

    output reg[31:0] OUT_result,
    output reg[5:0] OUT_tagDst,
    output reg[4:0] OUT_nmDst,
    output reg[5:0] OUT_sqN,
    output Flags OUT_flags
);

assign OUT_wbReq = IN_valid;

reg[31:0] resC;
Flags flags;

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
        INT_JALR,
        INT_JAL: resC = IN_operands[0] + 4;
        INT_SYS: resC = 0;
        default: resC = 'bx;
    endcase
    
    case (IN_opcode)
        INT_UNDEFINED,
        INT_SYS: flags = FLAGS_BRK;
        default: flags = FLAGS_NONE;
    endcase
end 


always_comb begin
    case (IN_opcode)
        INT_JAL,
        INT_JALR: branchTaken = 1;
        INT_BEQ: branchTaken = (IN_operands[0] == IN_operands[1]);
        INT_BNE: branchTaken = (IN_operands[0] != IN_operands[1]);
        INT_BLT: branchTaken = ($signed(IN_operands[0]) < $signed(IN_operands[1]));
        INT_BGE: branchTaken = !($signed(IN_operands[0]) < $signed(IN_operands[1]));
        INT_BLTU: branchTaken = (IN_operands[0] < IN_operands[1]);
        INT_BGEU: branchTaken = !(IN_operands[0] < IN_operands[1]);
        default: branchTaken = 0;
    endcase
end


reg branchTaken;
wire isBranch =
        IN_opcode == INT_BEQ || 
        IN_opcode == INT_BNE || 
        IN_opcode == INT_BLT || 
        IN_opcode == INT_BGE || 
        IN_opcode == INT_BLTU || 
        IN_opcode == INT_BGEU || 
        IN_opcode == INT_JAL || 
        IN_opcode == INT_JALR;


always_ff@(posedge clk) begin
    
    if (rst) begin
        OUT_valid <= 0;
    end
    else begin
        if (IN_valid && !IN_wbStall && (!OUT_branchTaken || $signed(IN_sqN - OUT_branchSqN) <= 0)) begin
            
            OUT_isBranch <= isBranch;
            
            if (isBranch)
                OUT_branchSqN <= IN_sqN;
            else
                OUT_branchSqN <= 6'bx;

            if (branchTaken) begin
                OUT_branchTaken <= 1;
                // TODO: jalr has different addr here
                if (IN_opcode == INT_JALR)
                    OUT_branchAddress <= IN_operands[1] + IN_operands[2];
                else
                    OUT_branchAddress <= IN_operands[2];
            end
            else begin
                OUT_branchTaken <= 0;
                OUT_branchAddress <= 32'bx;
                OUT_branchSqN <= 6'bx;
            end

            
            OUT_tagDst <= IN_tagDst;
            OUT_nmDst <= IN_nmDst;
            OUT_result <= resC;
            OUT_sqN <= IN_sqN;
            OUT_flags <= flags;
            OUT_valid <= 1;
        end
        else begin
            OUT_branchTaken <= 0;
            OUT_valid <= 0;
        end
    end
end

//always_ff@(posedge clk) begin
//    OUT_tagDst <= IN_valid ? IN_tagDst : 0;
//    OUT_nmDst <= IN_nmDst;
//    OUT_result <= resC;
//    
//end
endmodule
