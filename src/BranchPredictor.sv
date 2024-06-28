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
    output logic OUT_pcFileRE,
    output FetchID_t OUT_pcFileRAddr,
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
    logic isJump;
    logic predTaken;
    FetchOff_t predOffs;
    logic pred;
} BPBackup;

BPBackup bpBackup;
always_comb begin
    bpBackup.history = history;
    bpBackup.rIdx = OUT_rIdx;
    bpBackup.isJump = OUT_predBr.isJump;
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
    else if (BTB_br.valid && (!RET_br.valid || RET_br.offs > BTB_br.offs)) begin
        OUT_predBr = BTB_br;
        OUT_predBr.taken = BTB_br.isJump || TAGE_taken;
        OUT_predBr.multiple = !OUT_predBr.taken && (BTB_br.multiple || RET_br.valid);

        if (OUT_predBr.taken) begin
            OUT_pc = OUT_predBr.dst;
            OUT_lastOffs = OUT_predBr.offs;
        end
        if (OUT_predBr.multiple && OUT_predBr.offs != {$bits(FetchOff_t){1'b1}}) begin
            OUT_lastOffs = OUT_predBr.offs;
            OUT_pc = {pcRegNoInc[30:$bits(FetchOff_t)], OUT_predBr.offs + 1'b1};
        end
    end
    else if (RET_br.valid) begin
        OUT_predBr = RET_br;
        OUT_pc = OUT_predBr.dst;
        OUT_lastOffs = OUT_predBr.offs;
    end
    //else if (TAGE_taken) begin
    //    // No target found, but we still output the taken
    //    // direction prediction.
    //    OUT_predBr.valid = 1;
    //    OUT_predBr.dirOnly = 1;
    //    OUT_predBr.taken = 1;
    //end
end

PredBranch BTB_br;
assign BTB_br.taken = 'x;
assign BTB_br.isRet = 0;
assign BTB_br.dirOnly = 0;

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

    .IN_mispr(IN_mispr.taken),
    .IN_misprAct(IN_mispr.retAct),
    .IN_misprIdx(recRIdx),
    .IN_misprFetchID(IN_mispr.fetchID),
    
    .OUT_curIdx(RET_idx),
    .OUT_predBr(RET_br),

    .IN_returnUpd(IN_retDecUpd)
);

// Mispredict Recovery
BHist_t recHistory;
always_comb begin
    recHistory = bpFileRData.history;

    case (recovery.histAct)
        HIST_WRITE_0,
        HIST_WRITE_1: recHistory = {recHistory[$bits(BHist_t)-2:0], recovery.histAct == HIST_WRITE_1 ? 1'b1 : 1'b0};
        default: begin
            if (bpFileRData.pred && recovery.fetchOffs > bpFileRData.predOffs)
                recHistory = {recHistory[$bits(BHist_t)-2:0], bpFileRData.predTaken};
        end
    endcase

    if (recovery.histAct == HIST_APPEND_1)
        recHistory = {recHistory[$bits(BHist_t)-2:0], 1'b1};
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
    else if (OUT_predBr.valid && !OUT_predBr.isJump && !OUT_predBr.dirOnly)
        lookupHistory = {lookupHistory[$bits(BHist_t)-2:0], OUT_predBr.taken};
end

// Branch Target Updates
BHist_t updHistory;
always_comb begin
    updHistory = bpFileRData.history;
    if (bpFileRData.pred && !bpFileRData.isJump && bpUpdateActive.fetchOffs > bpFileRData.predOffs)
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
    OUT_pcFileRAddr = 'x;
    OUT_pcFileRE = 0;
    
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
            OUT_pcFileRAddr = IN_mispr.fetchID;
            OUT_pcFileRE = 1;
        end
    end
    else if (bpUpdate.valid) begin
        updFIFO_deq = 1;
        bpFileRAddr = bpUpdate.fetchID;
        bpFileRE = 1;
        OUT_pcFileRAddr = bpUpdate.fetchID;
        OUT_pcFileRE = 1;
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
        end
        else if (recovery.valid && recovery.tgtSpec != BR_TGT_MANUAL) begin
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

        history <= lookupHistory;
    end
end

endmodule
