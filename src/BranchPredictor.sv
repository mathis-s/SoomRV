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
    input RetStackAction IN_misprRetAct,
    input HistoryAction IN_misprHistAct,
    input wire[30:0] IN_misprDst,
    
    // IF interface
    input wire IN_pcValid,
    
    input FetchID_t IN_fetchID,
    input FetchID_t IN_comFetchID,

    output reg[30:0] OUT_pc,
    output FetchOff_t OUT_lastOffs,

    output wire[30:0] OUT_curRetAddr,
    output wire[30:0] OUT_lateRetAddr,
    output RetStackIdx_t OUT_rIdx,
    
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
    bpBackup.history = history;
    bpBackup.rIdx = OUT_rIdx; //1.449044
    bpBackup.isJump = OUT_predBr.isJump;
    bpBackup.predTaken = OUT_predBr.taken;
    bpBackup.predOffs = OUT_predBr.offs;
    bpBackup.pred = OUT_predBr.valid;
    bpBackup.tageID = TAGE_tageID;
    bpBackup.altPred = TAGE_altPred;
end

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
    .IN_wdata(bpBackup)
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

wire[30:0] branchAddr = OUT_pc;

reg[30:0] pcReg;
reg[30:0] pcRegNoInc;

reg ignorePred;
always_comb begin

    OUT_predBr = '0;
    OUT_predBr.dst = OUT_curRetAddr;
    OUT_predBr.offs = 3'b111;

    OUT_pc = pcReg; // current cycle's PC
    OUT_lastOffs = 3'b111; // last valid offset for last cycle's PC
    
    if (ignorePred) begin
        // ignore
    end
    else if (BTB_br.valid && (!RET_br.valid || RET_br.offs > BTB_br.offs)) begin
        OUT_predBr = BTB_br;
        OUT_predBr.taken = BTB_br.isJump || TAGE_taken;
        OUT_predBr.multiple = !OUT_predBr.taken && (BTB_br.multiple || RET_br.valid);

        if (OUT_predBr.taken) begin
            OUT_pc = OUT_predBr.dst;
            OUT_lastOffs = OUT_predBr.offs;
        end
        if (OUT_predBr.multiple && OUT_predBr.offs != 3'b111) begin
            OUT_lastOffs = OUT_predBr.offs;
            OUT_pc = {pcRegNoInc[30:3], OUT_predBr.offs + 1'b1};
        end
    end
    else if (RET_br.valid) begin
        OUT_predBr = RET_br;
        OUT_pc = OUT_predBr.dst;
        OUT_lastOffs = OUT_predBr.offs;
    end
end

PredBranch BTB_br;
assign BTB_br.taken = 'x;
assign BTB_br.isRet = 0;

wire BTB_multipleBranches;
BranchTargetBuffer btb
(
    .clk(clk),
    .rst(rst),
    .IN_pcValid(IN_pcValid),
    .IN_pc(OUT_pc),
    .OUT_branchFound(BTB_br.valid),
    .OUT_branchDst(BTB_br.dst),
    .OUT_branchSrcOffs(BTB_br.offs),
    .OUT_branchIsJump(BTB_br.isJump),
    .OUT_branchIsCall(BTB_br.isCall),
    .OUT_branchCompr(BTB_br.compr),

    .OUT_multipleBranches(BTB_br.multiple),
    .IN_btUpdate(btUpdate)
);

wire TAGE_taken;
TageID_t TAGE_tageID;
wire TAGE_altPred;
TagePredictor tagePredictor
(
    .clk(clk),
    .rst(rst),
    
    .IN_predValid(IN_pcValid),
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
assign OUT_rIdx = RET_idx;
ReturnStack retStack
(
    .clk(clk),
    .rst(rst),
    .OUT_stall(RET_stall),

    .IN_valid(IN_pcValid),
    .IN_pc(OUT_pc),
    .IN_fetchID(IN_fetchID),
    .IN_comFetchID(IN_comFetchID),
    
    .IN_lastPC(pcRegNoInc),
    .IN_branch(OUT_predBr),

    .OUT_curRetAddr(OUT_curRetAddr),
    .OUT_lateRetAddr(OUT_lateRetAddr),

    .IN_mispr(IN_mispr),
    .IN_misprAct(IN_misprRetAct),
    .IN_misprIdx(recRIdx),
    .IN_misprFetchID(IN_misprFetchID),
    
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

RetStackIdx_t recRIdx;
always_comb begin
    recRIdx = bpBackupRec.rIdx;
    // Apply new push/pop
    case (recovery.retAct)
        RET_POP: recRIdx = recRIdx - 1;
        RET_PUSH: recRIdx = recRIdx + 1;
        default: ;
    endcase
end

BHist_t lookupHistory;
always_comb begin
    lookupHistory = history;
    if (recovery.valid)
        lookupHistory = recHistory;
    else if (OUT_predBr.valid && !OUT_predBr.isJump && !ignorePred)
        lookupHistory = {lookupHistory[$bits(BHist_t)-2:0], OUT_predBr.taken};
end

BHist_t history;
always_ff@(posedge clk) begin
    
    recovery <= 'x;
    recovery.valid <= 0;

    update <= 'x;
    update.valid <= 0;

    if (rst) begin
        pcReg <= 31'(`ENTRY_POINT >> 1);
        ignorePred <= 1;
    end
    else begin
        if (IN_pcValid) begin
            pcReg <= {OUT_pc[30:3] + 1'b1, 3'b0};
            pcRegNoInc <= OUT_pc;
            ignorePred <= 0;
        end
        if (IN_mispr) begin
            recovery.valid <= 1;
            recovery.fetchID <= IN_misprFetchID;
            recovery.retAct <= IN_misprRetAct;
            recovery.histAct <= IN_misprHistAct;
            
            pcReg <= IN_misprDst;
            ignorePred <= 1;
        end

        history <= lookupHistory;

        if (IN_bpUpdate0.valid)
            update <= IN_bpUpdate0;
    end
end

endmodule
