module BranchPredictor
#(
    parameter NUM_IN=2
)
(
    input wire clk,
    input wire rst,
    input wire en1,

    output wire OUT_stall,
    input wire IN_clearICache,
    
    input wire IN_mispredFlush,
    input wire IN_mispr,
    input FetchID_t IN_misprFetchID,
    input RetStackIdx_t IN_misprRIdx,
    input RetStackAction IN_misprRetAct,
    input HistoryAction IN_misprHistAct,
    
    // IF interface
    input wire IN_pcValid,
    input wire[31:0] IN_pc,
    input FetchID_t IN_fetchID,
    input FetchID_t IN_comFetchID,
    output reg OUT_branchTaken,
    output BranchPredInfo OUT_branchInfo,
    output reg OUT_multipleBranches,
    output wire[30:0] OUT_curRetAddr,
    output wire[30:0] OUT_lateRetAddr,
    
    output PredBranch OUT_predBr,
    input ReturnDecUpdate IN_retDecUpd,
    
    // Branch XU interface
    input BTUpdate IN_btUpdates[NUM_IN-1:0],
    
    
    // Branch ROB Interface
    input BPUpdate0 IN_bpUpdate0,
    input BPUpdate1 IN_bpUpdate1
);

assign OUT_stall = RET_stall;

typedef struct packed
{
    TageID_t tageID;
    logic altPred;

    BHist_t history;
    RetStackIdx_t rIdx;
    logic isJump;
    logic predTaken;
    FetchOff_t predOffs;
    logic pred;
} BPBackup;

BPBackup bpBackup;
always_comb begin
    bpBackup.history = lookupHistory;
    bpBackup.rIdx = RET_idx;
    bpBackup.isJump = OUT_branchInfo.isJump;
    bpBackup.predTaken = OUT_branchInfo.taken;
    bpBackup.predOffs = OUT_predBr.offs;
    bpBackup.pred = OUT_branchInfo.predicted;
    bpBackup.tageID = TAGE_tageID;
    bpBackup.altPred = TAGE_altPred;
end
BPBackup bpBackupLast;

BPBackup bpBackupRec;
BPBackup bpBackupUpd;
RegFile#($bits(BPBackup), 1 << $bits(FetchID_t), 2, 1) bpFile
(
    .clk(clk),
    
    .IN_re({IN_mispr, IN_bpUpdate0.valid}),
    .IN_raddr({IN_misprFetchID, IN_bpUpdate0.fetchID}),
    .OUT_rdata({bpBackupRec, bpBackupUpd}),
    
    .IN_we(en1),
    .IN_waddr(IN_fetchID),
    .IN_wdata(bpBackupLast)
);

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

reg BTB_branchTaken;
always_comb begin
    OUT_branchInfo.rIdx = RET_idx;

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
TageID_t TAGE_tageID;
wire TAGE_altPred;
TagePredictor tagePredictor
(
    .clk(clk),
    .rst(rst),
    
    .IN_predAddr(branchAddr),
    .IN_predHistory(lookupHistory),
    .OUT_predTageID(TAGE_tageID),
    .OUT_altPred(TAGE_altPred),
    .OUT_predTaken(TAGE_taken),
    
    .IN_writeValid(IN_bpUpdate1.valid),
    .IN_writeAddr(IN_bpUpdate1.pc[30:0]),
    .IN_writeHistory(updHistory),
    .IN_writeTageID(bpBackupUpd.tageID),
    .IN_writeTaken(update.branchTaken),
    .IN_writeAltPred(bpBackupUpd.altPred),
    .IN_writePred(bpBackupUpd.predTaken)
);

PredBranch RET_br;
wire RET_stall;
RetStackIdx_t RET_idx;
ReturnStack retStack
(
    .clk(clk),
    .rst(rst),
    .OUT_stall(RET_stall),

    .IN_valid(IN_pcValid),
    .IN_pc(IN_pc[31:1]),
    .IN_fetchID(IN_fetchID),
    .IN_comFetchID(IN_comFetchID),
    .IN_misprFetchID(IN_misprFetchID),
    .IN_brValid(BTB_br.valid),
    .IN_brOffs(BTB_br.offs),
    .IN_isCall(BTB_isCall),
    .OUT_curRetAddr(OUT_curRetAddr),
    .OUT_lateRetAddr(OUT_lateRetAddr),

    .IN_setIdx(IN_mispr),
    .IN_idx(IN_misprRIdx),
    
    .OUT_curIdx(RET_idx),
    .OUT_predBr(RET_br),

    .IN_returnUpd(IN_retDecUpd)
);

BPUpdate0 update;
BHist_t updHistory;
always_comb begin
    updHistory = bpBackupUpd.history;
    //if (bpBackupUpd.pred && !bpBackupUpd.isJump && update.fetchOffs > bpBackupUpd.predOffs)
    //    updHistory = {updHistory[$bits(BHist_t)-2:0], bpBackupUpd.predTaken};
end

typedef struct packed
{
    logic valid;
    FetchID_t fetchID;
    FetchOff_t fetchOffs;
    RetStackAction retAct;
    HistoryAction histAct;
} Recovery;
Recovery recovery;
BHist_t recHistory;
always_comb begin
    recHistory = bpBackupRec.history;

    case (recovery.histAct)
        HIST_WRITE_0,
        HIST_WRITE_1: recHistory = {recHistory[$bits(BHist_t)-2:0], recovery.histAct == HIST_WRITE_1 ? 1'b1 : 1'b0};
        default: begin
            if (bpBackupRec.pred && bpBackupRec.predOffs <= recovery.fetchOffs)
                recHistory = {recHistory[$bits(BHist_t)-2:0], bpBackupRec.predTaken};
        end
    endcase

    if (recovery.histAct == HIST_APPEND_1)
        recHistory = {recHistory[$bits(BHist_t)-2:0], 1'b1};
end

BHist_t lookupHistory;
always_comb begin
    lookupHistory = history;
    if (recovery.valid)
        lookupHistory = recHistory;
end

BHist_t history;
always_ff@(posedge clk) begin
    
    recovery <= 'x;
    recovery.valid <= 0;

    update <= 'x;
    update.valid <= 0;

    if (rst) begin
    end
    else begin
        if (IN_pcValid)
            bpBackupLast <= bpBackup;

        if (IN_mispr) begin
            recovery.valid <= 1;
            recovery.fetchID <= IN_misprFetchID;
            recovery.retAct <= IN_misprRetAct;
            recovery.histAct <= IN_misprHistAct;
        end
        if (recovery.valid)
            history <= recHistory;

        if (IN_bpUpdate0.valid)
            update <= IN_bpUpdate0;

        if (OUT_predBr.valid && !OUT_predBr.isJump)
            history <= {lookupHistory[$bits(BHist_t)-2:0], OUT_branchTaken};
    end
end

endmodule
