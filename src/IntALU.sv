module IntALU
(
    input wire clk,
    input wire en,
    input wire rst,

    input wire IN_wbStall,
    input EX_UOp IN_uop,
    input IN_invalidate,
    input[5:0] IN_invalidateSqN,
    
    output wire OUT_wbReq,
    output reg OUT_valid,

    output reg OUT_branchTaken,
    output reg[31:0] OUT_branchAddress,
    output reg[5:0] OUT_branchSqN,

    output reg[31:0] OUT_result,
    output reg[5:0] OUT_tagDst,
    output reg[4:0] OUT_nmDst,
    output reg[5:0] OUT_sqN,
    output Flags OUT_flags
);

wire[31:0] srcA =  IN_uop.zcFwdSrcA ? OUT_result : IN_uop.srcA;
wire[31:0] srcB =  IN_uop.zcFwdSrcB ? OUT_result : IN_uop.srcB;
wire[31:0] imm =  IN_uop.imm;

assign OUT_wbReq = IN_uop.valid && en;

reg[31:0] resC;
Flags flags;

always_comb begin
    // optimize this depending on how good of a job synthesis does
    case (IN_uop.opcode)
        INT_AUIPC,
        INT_ADD: resC = srcA + srcB;
        INT_XOR: resC = srcA ^ srcB;
        INT_OR: resC = srcA | srcB;
        INT_AND: resC = srcA & srcB;
        INT_SLL: resC = srcA << srcB[4:0];
        INT_SRL: resC = srcA >> srcB[4:0];
        INT_SLT: resC = {31'b0, ($signed(srcA) < $signed(srcB))};
        INT_SLTU: resC = {31'b0, srcA < srcB};
        INT_SUB: resC = srcA - srcB;
        INT_SRA: resC = srcA >>> srcB[4:0];
        INT_LUI: resC = srcB;
        INT_JALR,
        INT_JAL: resC = srcA + 4;
        INT_SYS: resC = 0;
        default: resC = 'bx;
    endcase
    
    case (IN_uop.opcode)
        INT_UNDEFINED,
        INT_SYS: flags = FLAGS_BRK;
        default: flags = FLAGS_NONE;
    endcase
end 


always_comb begin
    case (IN_uop.opcode)
        INT_JAL,
        INT_JALR: branchTaken = 1;
        INT_BEQ: branchTaken = (srcA == srcB);
        INT_BNE: branchTaken = (srcA != srcB);
        INT_BLT: branchTaken = ($signed(srcA) < $signed(srcB));
        INT_BGE: branchTaken = !($signed(srcA) < $signed(srcB));
        INT_BLTU: branchTaken = (srcA < srcB);
        INT_BGEU: branchTaken = !(srcA < srcB);
        default: branchTaken = 0;
    endcase
end


reg branchTaken;

always_ff@(posedge clk) begin
    
    if (rst) begin
        OUT_valid <= 0;
    end
    else begin
        if (IN_uop.valid && en && !IN_wbStall && (!IN_invalidate || $signed(IN_uop.sqN - IN_invalidateSqN) <= 0)) begin
        
            OUT_branchSqN <= IN_uop.sqN;

            if (branchTaken) begin
                OUT_branchTaken <= 1;
                // TODO: jalr has different addr here
                if (IN_uop.opcode == INT_JALR)
                    OUT_branchAddress <= srcB + imm;
                else
                    OUT_branchAddress <= imm;
            end
            else begin
                OUT_branchTaken <= 0;
                OUT_branchAddress <= 32'bx;
                OUT_branchSqN <= 6'bx;
            end

            
            OUT_tagDst <= IN_uop.tagDst;
            OUT_nmDst <= IN_uop.nmDst;
            OUT_result <= resC;
            OUT_sqN <= IN_uop.sqN;
            OUT_flags <= flags;
            OUT_valid <= 1;
        end
        else begin
            OUT_branchTaken <= 0;
            OUT_valid <= 0;
        end
    end
end
endmodule
