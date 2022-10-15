module BranchPredictor
#(
    parameter NUM_IN=2,
    parameter NUM_ENTRIES=32,
    parameter ID_BITS=8
)
(
    input wire clk,
    input wire rst,
    input wire IN_mispredFlush,
    input BranchProv IN_branch,
    
    // IF interface
    input wire IN_pcValid,
    input wire[31:0] IN_pc,
    output wire OUT_branchTaken,
    output wire OUT_isJump,
    output wire[31:0] OUT_branchSrc,
    output wire[31:0] OUT_branchDst,
    output BHist_t OUT_branchHistory,
    output BranchPredInfo OUT_branchInfo,
    output wire OUT_multipleBranches,
    output wire OUT_branchFound,
    output wire OUT_branchCompr,
    
    // Branch XU interface
    input BTUpdate IN_btUpdates[NUM_IN-1:0],
    
    
    // Branch ROB Interface
    input CommitUOp IN_comUOp,
    
    output reg OUT_CSR_branchCommitted
);

integer i;

reg[ID_BITS-1:0] gHistory;
reg[ID_BITS-1:0] gHistoryCom;

// Try to find valid branch target update
BTUpdate btUpdate;
always_comb begin
    btUpdate = 67'bx;
    btUpdate.valid = 0;
    for (i = 0; i < NUM_IN; i=i+1) begin
        if (IN_btUpdates[i].valid)
            btUpdate = IN_btUpdates[i];
    end
end

wire[11:0] branchAddr = (OUT_branchCompr ? OUT_branchSrc[12:1] : OUT_branchSrc[12:1] - 1);
reg[ID_BITS-1:0] branchAddrInv;
always_comb
    for (i = 0; i < ID_BITS; i=i+1)
        branchAddrInv[ID_BITS - i - 1] = branchAddr[i];
        
wire useful = tagePred != initialPred;
wire tageValid;

assign OUT_branchHistory = gHistory;
assign OUT_branchInfo.branchPos = OUT_branchSrc[2:1];
assign OUT_branchInfo.predicted = OUT_branchFound;
assign OUT_branchInfo.taken = OUT_branchFound && (OUT_branchTaken || OUT_isJump);
assign OUT_branchInfo.tageValid = tageValid;
assign OUT_branchInfo.tageUseful = useful;


wire initialPred;
wire tagePred;
assign OUT_branchTaken = tageValid ? tagePred : initialPred;

assign OUT_branchDst[0] = 1'b0;
assign OUT_branchSrc[0] = 1'b0;
BranchTargetBuffer btb
(
    .clk(clk),
    .rst(rst),
    .IN_pcValid(IN_pcValid),
    .IN_pc(IN_pc[31:1]),
    .OUT_branchFound(OUT_branchFound),
    .OUT_branchDst(OUT_branchDst[31:1]),
    .OUT_branchSrc(OUT_branchSrc[31:1]),
    .OUT_branchIsJump(OUT_isJump),
    .OUT_branchCompr(OUT_branchCompr),
    .OUT_multipleBranches(OUT_multipleBranches),
    .IN_BPT_branchTaken(OUT_branchTaken),
    .IN_btUpdate(btUpdate)
);

BranchPredictionTable bpt
(
    .clk(clk),
    .rst(rst),
    .IN_readAddr(branchAddr[9:0]),
    .OUT_taken(initialPred),
    .IN_writeEn(IN_comUOp.valid && IN_comUOp.isBranch && IN_comUOp.predicted && !IN_mispredFlush),
    .IN_writeAddr(IN_comUOp.pc[9:0]),
    .IN_writeTaken(IN_comUOp.branchTaken)
);


TageTable tage
(
    .clk(clk),
    .rst(rst),
    .IN_readAddr(branchAddr[7:0] ^ gHistory),
    .IN_readTag(branchAddr[7:0]),
    .OUT_readValid(tageValid),
    .OUT_readTaken(tagePred),
    
    .IN_writeAddr(IN_comUOp.pc[ID_BITS-1:0] ^ IN_comUOp.branchID[7:0]),
    .IN_writeTag(IN_comUOp.pc[ID_BITS-1:0][7:0]),
    .IN_writeTaken(IN_comUOp.branchTaken),
    .IN_writeValid(IN_comUOp.valid && IN_comUOp.isBranch && IN_comUOp.predicted && !IN_mispredFlush),
    .IN_writeNew(!IN_comUOp.branchID[8]),
    .IN_writeUseful(IN_comUOp.branchID[8] ? (IN_comUOp.branchID[9] && IN_comUOp.branchTaken == IN_comUOp.branchID[10]) : (IN_comUOp.branchTaken != IN_comUOp.branchID[10]))
);

always_ff@(posedge clk) begin

    if (rst) begin
        gHistory <= 0;
        gHistoryCom <= 0;
        OUT_CSR_branchCommitted <= 0;
    end
    else begin
        if (OUT_branchFound && !OUT_isJump)
            gHistory <= {gHistory[ID_BITS-2:0], OUT_branchTaken};
        
        if (IN_comUOp.valid && IN_comUOp.isBranch && !IN_mispredFlush) begin
            gHistoryCom <= {gHistoryCom[ID_BITS-2:0], IN_comUOp.branchTaken};
            OUT_CSR_branchCommitted <= 1;
        end
        else OUT_CSR_branchCommitted <= 0;
    end
    
    if (!rst && IN_branch.taken) begin
        if (IN_branch.predicted)
            gHistory <= {IN_branch.branchID[6:0], IN_branch.branchTaken};
        else
            gHistory <= IN_branch.branchID[7:0];
    end
end

endmodule
