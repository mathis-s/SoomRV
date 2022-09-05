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
    
    output reg OUT_isBranch,
    output reg OUT_branchTaken,
    output reg OUT_branchMispred,
    output reg[31:0] OUT_branchSource,
    output reg[31:0] OUT_branchAddress,
    output reg OUT_branchIsJump,
    output reg[5:0] OUT_branchID,
    output reg[5:0] OUT_branchSqN,
    output reg[5:0] OUT_branchLoadSqN,
    output reg[5:0] OUT_branchStoreSqN,
    
    output wire[31:0] OUT_zcFwdResult,
    output wire[5:0] OUT_zcFwdTag,
    output wire OUT_zcFwdValid,

    output RES_UOp OUT_uop
);

wire[31:0] srcA = IN_uop.srcA;
wire[31:0] srcB = IN_uop.srcB;
wire[31:0] imm = IN_uop.imm;

assign OUT_wbReq = IN_uop.valid && en;

reg[31:0] resC;
Flags flags;

assign OUT_zcFwdResult = resC;
assign OUT_zcFwdTag = IN_uop.tagDst;
// maybe invalidate?
assign OUT_zcFwdValid = IN_uop.valid && en && IN_uop.nmDst != 0;//&& !IN_wbStall;

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


reg isBranch;

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
    
    isBranch =
        (IN_uop.opcode == INT_JAL ||
        //IN_uop.opcode == INT_JALR || (not predicted by bp)
        IN_uop.opcode == INT_BEQ ||
        IN_uop.opcode == INT_BNE ||
        IN_uop.opcode == INT_BLT ||
        IN_uop.opcode == INT_BGE ||
        IN_uop.opcode == INT_BLTU ||
        IN_uop.opcode == INT_BGEU);
        
end


reg branchTaken;

always_ff@(posedge clk) begin
    
    if (rst) begin
        OUT_uop.valid <= 0;
        //OUT_valid <= 0;
    end
    else begin
        if (IN_uop.valid && en && !IN_wbStall && (!IN_invalidate || $signed(IN_uop.sqN - IN_invalidateSqN) <= 0)) begin
        
            OUT_branchSqN <= IN_uop.sqN;
            OUT_branchLoadSqN <= IN_uop.loadSqN;
            OUT_branchStoreSqN <= IN_uop.storeSqN;
            
            OUT_isBranch <= isBranch;
            if (isBranch) begin
                OUT_branchSource <= IN_uop.pc;
                OUT_branchID <= IN_uop.branchID;
                OUT_branchIsJump <= (IN_uop.opcode == INT_JAL);
                OUT_branchTaken <= branchTaken;
                
                if (branchTaken != IN_uop.branchPred) begin
                    OUT_branchMispred <= 1;
                    if (branchTaken)
                        OUT_branchAddress <= imm;
                    else
                        OUT_branchAddress <= (IN_uop.pc + 4);
                end
                else
                    OUT_branchMispred <= 0;
            end
            // Register jumps are not predicted currently
            else if (IN_uop.opcode == INT_JALR) begin
                OUT_branchAddress <= srcB + imm;
                OUT_branchMispred <= 1;
            end
            else
                OUT_branchMispred <= 0;

            OUT_uop.tagDst <= IN_uop.tagDst;
            OUT_uop.nmDst <= IN_uop.nmDst;
            OUT_uop.result <= resC;
            OUT_uop.sqN <= IN_uop.sqN;
            OUT_uop.flags <= flags;
            OUT_uop.valid <= 1;
            OUT_uop.pc <= IN_uop.pc;
        end
        else begin
            OUT_branchMispred <= 0;
            //OUT_valid <= 0;
            OUT_uop.valid <= 0;
            OUT_isBranch <= 0;
        end
    end
end
endmodule
