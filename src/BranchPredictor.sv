module BranchPredictor
#(
    parameter NUM_IN=2,
    parameter NUM_ENTRIES=32,
    parameter ID_BITS=16
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
    input BPUpdate IN_bpUpdate,
    
    output reg OUT_CSR_branchCommitted
);

integer i;

BHist_t gHistory;
BHist_t gHistoryCom;

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

wire[30:0] branchAddr = IN_pc[31:1];//(OUT_branchCompr ? OUT_branchSrc[31:1] : OUT_branchSrc[31:1] - 1);

assign OUT_branchHistory = gHistory;
assign OUT_branchInfo.predicted = OUT_branchFound;
assign OUT_branchInfo.taken = OUT_branchTaken;
assign OUT_branchInfo.isJump = OUT_isJump;

assign OUT_branchTaken = OUT_branchFound && (OUT_isJump ? 1 : tageTaken);

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

wire tageTaken;
TagePredictor tagePredictor
(
    .clk(clk),
    .rst(rst),
    
    .IN_predAddr(branchAddr),
    .IN_predHistory(gHistory),
    .OUT_predTageID(OUT_branchInfo.tageID),
    .OUT_predUseful(OUT_branchInfo.tageUseful),
    .OUT_predTaken(tageTaken),
    
    .IN_writeValid(IN_bpUpdate.valid && IN_bpUpdate.bpi.predicted && !IN_mispredFlush),
    .IN_writeAddr(IN_bpUpdate.pc[30:0]),
    .IN_writeHistory(IN_bpUpdate.history),
    .IN_writeTageID(IN_bpUpdate.bpi.tageID),
    .IN_writeTaken(IN_bpUpdate.branchTaken),
    .IN_writeUseful(IN_bpUpdate.bpi.tageUseful),
    .IN_writePred(IN_bpUpdate.bpi.taken)
);


always_ff@(posedge clk) begin

    if (rst) begin
        gHistory <= 0;
        gHistoryCom <= 0;
        OUT_CSR_branchCommitted <= 0;
    end
    else begin
        if (OUT_branchFound && !OUT_isJump)
            gHistory <= {gHistory[$bits(BHist_t)-2:0], OUT_branchTaken};
        
        if (IN_bpUpdate.valid && !IN_mispredFlush) begin
            gHistoryCom <= {gHistoryCom[$bits(BHist_t)-2:0], IN_bpUpdate.branchTaken};
            OUT_CSR_branchCommitted <= 1;
        end
        else OUT_CSR_branchCommitted <= 0;
    end
    
    if (!rst && IN_branch.taken) begin
        gHistory <= IN_branch.history;
    end
end

endmodule
