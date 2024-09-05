module BranchPredictor
#(
    parameter NUM_IN=2
)
(
    input wire clk,
    input wire rst,
    input wire en1,

    output wire OUT_stall,
    input DecodeBranchProv IN_mispr,

    // IF interface
    input wire IN_pcValid,

    output FetchLimit OUT_fetchLimit,
    input FetchID_t IN_fetchID,
    input FetchID_t IN_comFetchID,

    output reg[30:0] OUT_pc,
    output FetchOff_t OUT_lastOffs,

    output wire[30:0] OUT_curRetAddr,
    output wire[30:0] OUT_lateRetAddr,
    output RetStackIdx_t OUT_rIdx,

    output PredBranch OUT_predBr,

    input ReturnDecUpdate IN_retDecUpd,

    // PC File read interface
    output PCFileReadReq OUT_pcFileRead,
    input PCFileEntry IN_pcFileRData,

    // Branch XU interface
    input BTUpdate IN_btUpdates[NUM_IN-1:0],

    // Branch ROB Interface
    input BPUpdate IN_bpUpdate
);

assign OUT_stall = RET_stall;

typedef struct packed
{
    TageID_t tageID;
    logic altPred;

    BHist_t history;
    RetStackIdx_t rIdx;
    logic isRegularBranch;
    logic predTaken;
    FetchOff_t predOffs;
    logic pred;
} BPBackup;

BPBackup bpBackup;
always_comb begin
    bpBackup.history = history;
    bpBackup.rIdx = RET_idx;
    bpBackup.isRegularBranch = OUT_predBr.btype == BT_BRANCH;
    bpBackup.predTaken = OUT_predBr.taken;
    bpBackup.predOffs = OUT_predBr.offs;
    bpBackup.pred = OUT_predBr.valid;
    bpBackup.tageID = TAGE_tageID;
    bpBackup.altPred = TAGE_altPred;
end

BPBackup bpFileRData;

FetchID_t bpFileRAddr;
logic bpFileRE;
RegFile#($bits(BPBackup), 1 << $bits(FetchID_t), 1, 1) bpFile
(
    .clk(clk),

    .IN_re({bpFileRE}),
    .IN_raddr({bpFileRAddr}),
    .OUT_rdata({bpFileRData}),

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

logic[30:0] recoveredPC;
always_comb begin
    recoveredPC = {IN_pcFileRData.pc[30:$bits(FetchOff_t)], recovery.fetchOffs};
    case (recovery.tgtSpec)
        BR_TGT_CUR32: recoveredPC = recoveredPC - 1;
        BR_TGT_CUR16: recoveredPC = recoveredPC;
        BR_TGT_NEXT:  recoveredPC = recoveredPC + 1;
        BR_TGT_MANUAL: ;
    endcase
end

wire[30:0] branchAddr = OUT_pc;
always_comb begin

    OUT_predBr = '0;
    OUT_predBr.dst = OUT_curRetAddr;
    OUT_predBr.offs = {$bits(FetchOff_t){1'b1}};

    OUT_pc = pcReg; // current cycle's PC
    OUT_lastOffs = {$bits(FetchOff_t){1'b1}};; // last valid offset for last cycle's PC

    if (ignorePred) begin
        if (recovery.tgtSpec != BR_TGT_MANUAL)
            OUT_pc = recoveredPC;
    end
    else if (BTB_br.valid && BTB_br.btype != BT_RETURN) begin
        OUT_predBr = BTB_br;
        OUT_predBr.taken |= TAGE_taken;
        OUT_predBr.multiple = !OUT_predBr.taken && BTB_br.multiple;

        if (OUT_predBr.taken) begin
            OUT_pc = OUT_predBr.dst;
            OUT_lastOffs = OUT_predBr.offs;
        end
        if (OUT_predBr.multiple && OUT_predBr.offs != {$bits(FetchOff_t){1'b1}}) begin
            OUT_lastOffs = OUT_predBr.offs;
            OUT_pc = {pcRegNoInc[30:$bits(FetchOff_t)], OUT_predBr.offs + 1'b1};
        end
    end
    else if (BTB_br.valid && BTB_br.btype == BT_RETURN && RET_br.valid) begin
        OUT_predBr = BTB_br;
        OUT_predBr.taken = 1;
        OUT_predBr.multiple = 0;
        OUT_predBr.dst = OUT_curRetAddr;

        OUT_pc = OUT_predBr.dst;
        OUT_lastOffs = OUT_predBr.offs;
    end
    else if (TAGE_tageID > 0) begin
        // No target found, but we still output the direction prediction.
        OUT_predBr.valid = 1;
        OUT_predBr.btype = BT_BRANCH;
        OUT_predBr.dirOnly = 1;
        OUT_predBr.taken = TAGE_taken;
    end
end

PredBranch BTB_br;
BranchTargetBuffer btb
(
    .clk(clk),
    .rst(rst),
    .IN_pcValid(IN_pcValid),
    .IN_pc(OUT_pc),
    .OUT_branch(BTB_br),
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

    .IN_writeValid(bpUpdateActive.valid),
    // we use the fetch PC rather than the actual PC as the update
    // address, as this is where the prediction will be made next time.
    .IN_writeAddr(IN_pcFileRData.pc),
    .IN_writeHistory(updHistory),
    .IN_writeTageID(bpFileRData.tageID),
    .IN_writeTaken(bpUpdateActive.branchTaken),
    .IN_writeAltPred(bpFileRData.altPred),
    .IN_writePred(bpFileRData.predTaken)
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
    .IN_recoveryIdx(recRIdx),

    .OUT_curIdx(RET_idx),
    .OUT_predBr(RET_br),

    .IN_returnUpd(IN_retDecUpd)
);

// Mispredict Recovery
BHist_t recHistory;
always_comb begin
    recHistory = bpFileRData.history;

    // Restore prediction of earlier instruction in same packet
    if (bpFileRData.pred && recovery.fetchOffs > bpFileRData.predOffs)
        recHistory = {recHistory[$bits(BHist_t)-2:0], bpFileRData.predTaken};

    if (recovery.histAct == HIST_WRITE_0 || recovery.histAct == HIST_WRITE_1)
        recHistory = {recHistory[$bits(BHist_t)-2:0], recovery.histAct == HIST_WRITE_1};
    if (recovery.histAct == HIST_APPEND_1 || recovery.histAct == HIST_APPEND_0)
        recHistory = {recHistory[$bits(BHist_t)-2:0], recovery.histAct == HIST_APPEND_1};
end

RetStackIdx_t recRIdx;
always_comb begin
    recRIdx = bpFileRData.rIdx;
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
    else if (OUT_predBr.valid && OUT_predBr.btype == BT_BRANCH && !OUT_predBr.dirOnly)
        lookupHistory = {lookupHistory[$bits(BHist_t)-2:0], OUT_predBr.taken};
end

// Branch Target Updates
BHist_t updHistory;
always_comb begin
    updHistory = bpFileRData.history;
    if (bpFileRData.pred && bpFileRData.isRegularBranch && bpUpdateActive.fetchOffs > bpFileRData.predOffs)
        updHistory = {updHistory[$bits(BHist_t)-2:0], bpFileRData.predTaken};
end

logic updFIFO_deq;
BPUpdate bpUpdate;
FIFO#($bits(BPUpdate)-1, 4, 1, 0) updFIFO
(
    .clk(clk),
    .rst(rst),
    .free(),

    .IN_valid(IN_bpUpdate.valid),
    .IN_data(IN_bpUpdate[$bits(BPUpdate)-1:1]),
    .OUT_ready(),

    .OUT_valid(bpUpdate[0]),
    .IN_ready(updFIFO_deq),
    .OUT_data(bpUpdate[$bits(BPUpdate)-1:1])
);

BPUpdate bpUpdateActive;
always_ff@(posedge clk) begin
    bpUpdateActive <= BPUpdate'{valid: 0, default: 'x};
    if (!rst && updFIFO_deq)
        bpUpdateActive <= bpUpdate;
end
always_comb begin
    OUT_fetchLimit = FetchLimit'{valid: 0, default: 'x};
    // Prevent fetching that would override PC&BP file entries
    // still needed for branch direction updates.
    if (bpUpdate.valid) begin
        OUT_fetchLimit.valid = 1;
        OUT_fetchLimit.fetchID = bpUpdate.fetchID;
    end
    else if (IN_bpUpdate.valid) begin
        OUT_fetchLimit.valid = 1;
        OUT_fetchLimit.fetchID = IN_bpUpdate.fetchID;
    end
end

// Reads from BP File and the frontend's PC File Port
// These two reads are always from the same address, used
// for mispredict recovery and branch direction updates.
// Mispredicts always have priority, updates are buffered.
always_comb begin
    OUT_pcFileRead.addr = 'x;
    OUT_pcFileRead.valid = 0;

    bpFileRAddr = 'x;
    bpFileRE = 0;

    updFIFO_deq = 0;

    // On mispredict, read history of instruction to revert to.
    // If not manually specified, we also read the PC.
    if (IN_mispr.taken) begin
        bpFileRAddr = IN_mispr.fetchID;
        bpFileRE = 1;
        // Read PC of instruction we revert to
        if (IN_mispr.tgtSpec != BR_TGT_MANUAL) begin
            OUT_pcFileRead.addr = IN_mispr.fetchID;
            OUT_pcFileRead.valid = 1;
        end
    end
    else if (bpUpdate.valid) begin
        updFIFO_deq = 1;
        bpFileRAddr = bpUpdate.fetchID;
        bpFileRE = 1;
        OUT_pcFileRead.addr = bpUpdate.fetchID;
        OUT_pcFileRead.valid = 1;
    end
end

typedef struct packed
{
    BranchTargetSpec tgtSpec;
    FetchID_t fetchID;
    FetchOff_t fetchOffs;
    RetStackAction retAct;
    HistoryAction histAct;
    logic valid;
} Recovery;
Recovery recovery;

BHist_t history;
reg[30:0] pcReg;
reg[30:0] pcRegNoInc;
reg ignorePred;
always_ff@(posedge clk) begin
    recovery <= Recovery'{valid: 0, default: 'x};

    if (rst) begin
        pcReg <= 31'(`ENTRY_POINT >> 1);
        ignorePred <= 1;
    end
    else begin
        if (IN_pcValid) begin
            pcReg <= {OUT_pc[30:$bits(FetchOff_t)] + 1'b1, $bits(FetchOff_t)'(1'b0)};
            pcRegNoInc <= OUT_pc;
            ignorePred <= 0;
            history <= lookupHistory;
        end
        else if (recovery.valid) begin
            history <= recHistory;
            if (recovery.tgtSpec != BR_TGT_MANUAL)
                pcReg <= recoveredPC;
        end

        if (IN_mispr.taken) begin
            recovery.valid <= 1;
            recovery.tgtSpec <= IN_mispr.tgtSpec;
            recovery.fetchID <= IN_mispr.fetchID;
            recovery.retAct <= IN_mispr.retAct;
            recovery.histAct <= IN_mispr.histAct;
            recovery.fetchOffs <= IN_mispr.fetchOffs;

            pcReg <= IN_mispr.tgtSpec == BR_TGT_MANUAL ? IN_mispr.dst : 'x;
            ignorePred <= 1;
        end
    end
end

endmodule
