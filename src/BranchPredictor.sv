module BranchPredictor
#(
    parameter NUM_IN=2
)
(
    input wire clk,
    input wire rst,
    output wire OUT_stall,

    input wire IN_clearICache,
    
    input wire IN_mispredFlush,
    input wire IN_mispr,
    input FetchID_t IN_misprFetchID,
    input BHist_t IN_misprHist,
    input RetStackIdx_t IN_misprRIdx,
    
    // IF interface
    input wire IN_pcValid,
    input wire[31:0] IN_pc,
    input FetchID_t IN_fetchID,
    input FetchID_t IN_comFetchID,
    output reg OUT_branchTaken,
    output BHist_t OUT_branchHistory,
    output BranchPredInfo OUT_branchInfo,
    output reg OUT_multipleBranches,
    output wire[30:0] OUT_lateRetAddr,
    
    output PredBranch OUT_predBr,
    input ReturnDecUpdate IN_retDecUpd,
    
    // Branch XU interface
    input BTUpdate IN_btUpdates[NUM_IN-1:0],
    
    
    // Branch ROB Interface
    input BPUpdate IN_bpUpdate
);


BHist_t gHistory;
BHist_t gHistoryCom;

// Try to find valid branch target update
BTUpdate btUpdate;
always_comb begin
    btUpdate = 'x;
    btUpdate.valid = 0;
    for (integer i = 0; i < NUM_IN; i=i+1) begin
        if (IN_btUpdates[i].valid)
            btUpdate = IN_btUpdates[i];
    end
end

wire[30:0] branchAddr = IN_pc[31:1];

assign OUT_branchHistory = gHistory;

reg BTB_branchTaken;
always_comb begin
    if (BTB_br.valid && (!RET_br.valid || RET_br.offs > BTB_br.offs)) begin
        OUT_predBr = BTB_br;
        OUT_branchTaken = BTB_br.valid && (BTB_br.isJump || TAGE_taken);
        BTB_branchTaken = BTB_br.valid && (BTB_br.isJump || TAGE_taken);
        OUT_multipleBranches = !OUT_branchTaken && (BTB_multipleBranches || RET_br.valid);

        OUT_branchInfo.predicted = 1;
        OUT_branchInfo.taken = OUT_branchTaken;
        OUT_branchInfo.isJump = OUT_predBr.isJump;
    end
    else begin
        OUT_predBr = RET_br;
        OUT_branchTaken = RET_br.valid;
        OUT_multipleBranches = 0;

        OUT_branchInfo.predicted = RET_br.valid;
        OUT_branchInfo.taken = RET_br.valid;
        OUT_branchInfo.isJump = 1;

        BTB_branchTaken = 0;
    end
end

PredBranch BTB_br;
wire BTB_isCall;

wire BTB_multipleBranches;
BranchTargetBuffer btb
(
    .clk(clk),
    .rst(rst || IN_clearICache),
    .IN_pcValid(IN_pcValid),
    .IN_pc(IN_pc[31:1]),
    .OUT_branchFound(BTB_br.valid),
    .OUT_branchDst(BTB_br.dst),
    .OUT_branchSrcOffs(BTB_br.offs),
    .OUT_branchIsJump(BTB_br.isJump),
    .OUT_branchIsCall(BTB_isCall),
    .OUT_branchCompr(BTB_br.compr),

    .OUT_multipleBranches(BTB_multipleBranches),
    .IN_BPT_branchTaken(BTB_branchTaken),
    .IN_btUpdate(btUpdate)
);

wire TAGE_taken;
TagePredictor tagePredictor
(
    .clk(clk),
    .rst(rst),
    
    .IN_predAddr(branchAddr),
    .IN_predHistory(gHistory),
    .OUT_predTageID(OUT_branchInfo.tageID),
    .OUT_altPred(OUT_branchInfo.altPred),
    .OUT_predTaken(TAGE_taken),
    
    .IN_writeValid(IN_bpUpdate.valid && IN_bpUpdate.bpi.predicted && !IN_mispredFlush && !IN_bpUpdate.bpi.isJump),
    .IN_writeAddr(IN_bpUpdate.pc[30:0]),
    .IN_writeHistory(IN_bpUpdate.history),
    .IN_writeTageID(IN_bpUpdate.bpi.tageID),
    .IN_writeTaken(IN_bpUpdate.branchTaken),
    .IN_writeAltPred(IN_bpUpdate.bpi.altPred),
    .IN_writePred(IN_bpUpdate.bpi.taken)
);

PredBranch RET_br;
ReturnStack retStack
(
    .clk(clk),
    .rst(rst),
    .OUT_stall(OUT_stall),

    .IN_valid(IN_pcValid),
    .IN_pc(IN_pc[31:1]),
    .IN_fetchID(IN_fetchID),
    .IN_comFetchID(IN_comFetchID),
    .IN_misprFetchID(IN_misprFetchID),
    .IN_brValid(BTB_br.valid),
    .IN_brOffs(BTB_br.offs),
    .IN_isCall(BTB_isCall),
    .OUT_lateRetAddr(OUT_lateRetAddr),

    .IN_setIdx(IN_mispr),
    .IN_idx(IN_misprRIdx),
    
    .OUT_curIdx(OUT_branchInfo.rIdx),
    .OUT_predBr(RET_br),

    .IN_returnUpd(IN_retDecUpd)
);

always_ff@(posedge clk) begin

    if (rst) begin
        gHistory <= 0;
        gHistoryCom <= 0;
    end
    else begin
        if (OUT_predBr.valid && !OUT_predBr.isJump)
            gHistory <= {gHistory[$bits(BHist_t)-2:0], OUT_branchTaken};
        
        if (IN_bpUpdate.valid && !IN_mispredFlush) begin
            gHistoryCom <= {gHistoryCom[$bits(BHist_t)-2:0], IN_bpUpdate.branchTaken};
        end
    end
    
    if (!rst && IN_mispr) begin
        gHistory <= IN_misprHist;
    end
end

endmodule
