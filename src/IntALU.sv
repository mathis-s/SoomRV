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
    output reg OUT_branchCompr,
    
    output wire[31:0] OUT_zcFwdResult,
    output wire[5:0] OUT_zcFwdTag,
    output wire OUT_zcFwdValid,

    output RES_UOp OUT_uop
);
integer i = 0;

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


wire[5:0] resLzTz;

reg[31:0] srcAbitRev;
always_comb begin
    for (i = 0; i < 32; i=i+1)
        srcAbitRev[i] = srcA[31-i];
end
LZCnt lzc (
    .in(IN_uop.opcode == INT_CLZ ? srcA : srcAbitRev),
    .out(resLzTz)
);

wire[5:0] resPopCnt;
PopCnt popc
(
    .a(IN_uop.srcA),
    .res(resPopCnt)
);

wire lessThan = ($signed(srcA) < $signed(srcB));
wire lessThanU = (srcA < srcB);

wire[31:0] pcPlus2 = IN_uop.pc + 2;
wire[31:0] pcPlus4 = IN_uop.pc + 4;

always_comb begin
    // optimize this depending on how good of a job synthesis does
    case (IN_uop.opcode)
        INT_AUIPC: resC = IN_uop.pc + imm;
        INT_ADD: resC = srcA + srcB;
        INT_XOR: resC = srcA ^ srcB;
        INT_OR: resC = srcA | srcB;
        INT_AND: resC = srcA & srcB;
        INT_SLL: resC = srcA << srcB[4:0];
        INT_SRL: resC = srcA >> srcB[4:0];
        INT_SLT: resC = {31'b0, lessThan};
        INT_SLTU: resC = {31'b0, lessThanU};
        INT_SUB: resC = srcA - srcB;
        INT_SRA: resC = srcA >>> srcB[4:0];
        INT_LUI: resC = srcB;
        INT_JALR,
        INT_JAL: resC = (IN_uop.compressed ? pcPlus2 : pcPlus4);
        INT_SYS: resC = 32'bx;
        INT_SH1ADD: resC = srcB + (srcA << 1);
        INT_SH2ADD: resC = srcB + (srcA << 2);
        INT_SH3ADD: resC = srcB + (srcA << 3);
        INT_ANDN: resC = srcA & (~srcB);
        INT_ORN: resC = srcA | (~srcB);
        INT_XNOR: resC = srcA ^ (~srcB);
        INT_SE_B: resC = {{24{srcA[7]}}, srcA[7:0]};
        INT_SE_H: resC = {{16{srcA[15]}}, srcA[15:0]};
        INT_ZE_H: resC = {16'b0, srcA[15:0]};
        INT_CLZ, 
        INT_CTZ: resC = {26'b0, resLzTz};
        INT_CPOP: resC = {26'b0, resPopCnt};
        INT_ORC_B: resC = {{{4'd8}{|srcA[31:24]}}, {{4'd8}{|srcA[23:16]}}, {{4'd8}{|srcA[15:8]}}, {{4'd8}{|srcA[7:0]}}};
        INT_MAX: resC = lessThan ? srcB : srcA;
        INT_MAXU: resC = lessThanU ? srcB : srcA;
        INT_MIN: resC = lessThan ? srcA : srcB;
        INT_MINU: resC = lessThanU ? srcA : srcB;
        INT_REV8: resC = {srcA[7:0], srcA[15:8], srcA[23:16], srcA[31:24]};
        default: resC = 32'bx;
    endcase
    
    case (IN_uop.opcode)
        INT_UNDEFINED: flags = FLAGS_EXCEPT;
        INT_SYS: flags = imm[0] ? FLAGS_BRK : FLAGS_TRAP;
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
        INT_BLT: branchTaken = lessThan;
        INT_BGE: branchTaken = !lessThan;
        INT_BLTU: branchTaken = lessThanU;
        INT_BGEU: branchTaken = !lessThanU;
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
        OUT_branchTaken <= 0;
        OUT_isBranch <= 0;
        OUT_branchMispred <= 0;
    end
    else begin
        if (IN_uop.valid && en && !IN_wbStall && (!IN_invalidate || $signed(IN_uop.sqN - IN_invalidateSqN) <= 0)) begin
            OUT_branchSqN <= IN_uop.sqN;
            OUT_branchLoadSqN <= IN_uop.loadSqN;
            OUT_branchStoreSqN <= IN_uop.storeSqN;
            
            OUT_isBranch <= isBranch;
            if (isBranch) begin
                // Uncompressed branches are predicted only when their second halfword is fetched
                OUT_branchSource <= (IN_uop.compressed ? IN_uop.pc : (pcPlus2));
                OUT_branchID <= IN_uop.branchID;
                OUT_branchIsJump <= (IN_uop.opcode == INT_JAL);
                OUT_branchTaken <= branchTaken;
                OUT_branchCompr <= IN_uop.compressed;
                
                if (branchTaken != IN_uop.branchPred) begin
                    OUT_branchMispred <= 1;
                    if (branchTaken)
                        OUT_branchAddress <= (IN_uop.pc + imm);
                    else if (IN_uop.compressed)
                        OUT_branchAddress <= pcPlus2;
                    else
                        OUT_branchAddress <= pcPlus4;
                end
                else
                    OUT_branchMispred <= 0;
            end
            // Register jumps are not predicted currently
            else if (IN_uop.opcode == INT_JALR) begin
                OUT_branchAddress <= srcA + srcB;
                OUT_branchMispred <= 1;
            end
            else
                OUT_branchMispred <= 0;
            
            OUT_uop.isBranch <= isBranch;
            OUT_uop.branchTaken <= branchTaken;
            OUT_uop.branchID <= IN_uop.branchID;
            
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
            OUT_uop.valid <= 0;
            OUT_isBranch <= 0;
        end
    end
end
endmodule
