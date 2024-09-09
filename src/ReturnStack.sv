module ReturnStack
#(
    parameter SIZE=`RETURN_SIZE,
    parameter RQSIZE=`RETURN_RQ_SIZE
)
(
    input wire clk,
    input wire rst,
    output wire OUT_stall,

    // IFetch time push/pop
    input wire IN_valid,
    input wire[30:0] IN_pc,
    input FetchID_t IN_fetchID,
    input FetchID_t IN_comFetchID,

    input wire[30:0] IN_lastPC,
    input PredBranch IN_branch,

    output reg[30:0] OUT_curRetAddr,
    // Low effort prediction for returns that are detected late, in decode.
    output wire[30:0] OUT_lateRetAddr,

    input RetStackIdx_t IN_recoveryIdx,
    input DecodeBranchProv IN_mispr,

    output RetStackIdx_t OUT_curIdx,
    output PredBranch OUT_predBr,
    input ReturnDecUpdate IN_returnUpd
);

typedef struct packed
{
    logic[30:0] addr;
    RetStackIdx_t idx;
    FetchOff_t offs;
    FetchID_t fetchID;
} RetRecQEntry;

reg[30:0] rstack[SIZE-1:0] /* verilator public */;
reg[31:0] rstack_dbg[SIZE-1:0];
always_comb begin
    for (integer i = 0; i < SIZE; i=i+1)
        rstack_dbg[i] = {rstack[i], 1'b0};
end

reg[$clog2(RQSIZE)-1:0] qindex;
reg[$clog2(RQSIZE)-1:0] qindexEnd;
RetRecQEntry rrqueue[RQSIZE-1:0]; // return addr recovery


reg forwardRindex;
RetStackAction recAct;

wire[30:0] addrToPush = {IN_lastPC[30:$bits(FetchOff_t)], IN_branch.offs} + 1;

// On mispredict it takes a cycle to read the old return stack index,
// so we forward it combinatorially.
RetStackIdx_t rindexReg;
RetStackIdx_t rindex;
always_comb begin
    rindex = rindexReg;
    if (forwardRindex) begin
        rindex = IN_recoveryIdx;
    end
    else if (IN_branch.valid && IN_branch.btype == BT_CALL && lastValid) begin
        rindex = rindex + 1;
    end
    else if (IN_branch.valid && IN_branch.btype == BT_RETURN && lastValid) begin
        rindex = rindex - 1;
    end
end

always_ff@(posedge clk) begin
    if (IN_valid) begin
        OUT_curIdx <= rindex;

        if (IN_mispr.taken) begin
            OUT_curRetAddr <= 'x;
            OUT_predBr.dst <= 'x;
        end
        else if (IN_branch.valid && IN_branch.btype == BT_CALL) begin
            // If the immediately preceding prediction was a call,
            // we need to forward the return address.
            OUT_curRetAddr <= addrToPush;
            OUT_predBr.dst <= addrToPush;
        end
        else begin
            OUT_curRetAddr <= rstack[rindex];
            OUT_predBr.dst <= rstack[rindex];
        end

        OUT_predBr.valid <= 1;
        OUT_predBr.taken <= 1;
        OUT_predBr.dirOnly <= 0;
        OUT_predBr.btype <= BT_RETURN;
        OUT_predBr.offs <= 'x;
        OUT_predBr.compr <= 'x;
        OUT_predBr.multiple <= 'x;
    end
end

assign OUT_lateRetAddr = OUT_curRetAddr;

reg recoveryInProgress;
assign OUT_stall = recoveryInProgress;
FetchID_t recoveryID;
FetchID_t recoveryBase;
FetchOff_t recoveryOffs;
FetchID_t lastInvalComFetchID;
logic recoveryOverwOwn;

reg lastValid;

typedef struct packed
{
    reg[30:0] addr;
    RetStackIdx_t rIdx;
    FetchID_t fetchID;
    FetchOff_t offs;
    logic valid;
} PostRecSave;

PostRecSave postRecSave;

always_ff@(posedge clk) begin

    forwardRindex <= 0;

    if (rst) begin
        qindex <= 0;
        qindexEnd <= 0;
        recoveryInProgress <= 0;
        lastInvalComFetchID <= 0;
        lastValid <= 0;

        postRecSave <= PostRecSave'{valid: 0, default: 'x};
    end
    else begin

        lastValid <= IN_valid;

        if (IN_mispr.taken) begin
            reg startRecovery = qindex != qindexEnd;

            forwardRindex <= 1;
            recAct <= IN_mispr.retAct;
            recoveryInProgress <= startRecovery;
            recoveryID <= IN_mispr.fetchID;
            recoveryBase <= lastInvalComFetchID;
            recoveryOffs <= IN_mispr.fetchOffs;
            recoveryOverwOwn <= IN_mispr.isFetchBranch && !IN_returnUpd.valid;

            lastValid <= 0;

            postRecSave <= PostRecSave'{valid: 0, default: 'x};
            if (IN_mispr.isFetchBranch && IN_returnUpd.valid) begin
                if (startRecovery) begin
                    postRecSave.valid <= 1;
                    postRecSave.fetchID <= IN_mispr.fetchID;
                    postRecSave.offs <= IN_mispr.fetchOffs;
                    postRecSave.rIdx <= IN_returnUpd.idx + RetStackIdx_t'(1);
                    postRecSave.addr <= IN_returnUpd.addr + 1;
                end
                else begin
                    rrqueue[qindex].fetchID <= IN_mispr.fetchID;
                    rrqueue[qindex].offs <= IN_mispr.fetchOffs;
                    rrqueue[qindex].idx <= IN_returnUpd.idx + RetStackIdx_t'(1);
                    rrqueue[qindex].addr <= rstack[IN_returnUpd.idx + RetStackIdx_t'(1)];
                    qindex <= qindex + 1;

                    rstack[IN_returnUpd.idx + RetStackIdx_t'(1)] <= IN_returnUpd.addr + 1;
                end

            end
        end
        else begin
            rindexReg <= rindex;
            // Recover entries by copying from rrqueue back to stack after mispredict
            if (recoveryInProgress) begin

                if (qindex != qindexEnd &&
                    // fine-grained compare based on fetch offs
                    ( ((rrqueue[qindex-1].fetchID - recoveryBase) > (recoveryID - recoveryBase)) ||
                    ((rrqueue[qindex-1].fetchID - recoveryBase) == (recoveryID - recoveryBase) &&
                        (recoveryOverwOwn ?
                            (rrqueue[qindex-1].offs >= recoveryOffs) :
                            (rrqueue[qindex-1].offs >  recoveryOffs))
                    ))
                ) begin
                    rstack[rrqueue[qindex-1].idx] <= rrqueue[qindex-1].addr;
                    rrqueue[qindex-1] <= 'x;
                    qindex <= qindex - 1; // entry restored, ok to overwrite
                end
                else begin
                    recoveryInProgress <= 0;
                    if (postRecSave.valid) begin
                        postRecSave <= PostRecSave'{valid: 0, default: 'x};

                        rrqueue[qindex].fetchID <= postRecSave.fetchID;
                        rrqueue[qindex].offs <= postRecSave.offs;
                        rrqueue[qindex].idx <= postRecSave.rIdx;
                        rrqueue[qindex].addr <= rstack[postRecSave.rIdx];
                        rstack[postRecSave.rIdx] <= postRecSave.addr;
                        qindex <= qindex + 1;
                    end
                end
            end

            // Delete committed (ie correctly speculated) entries from rrqueue
            if (!recoveryInProgress && lastInvalComFetchID != IN_comFetchID) begin

                // Unlike SqNs, fetchIDs are not given an extra bit of range for the sake
                // of easy ordering comparison. Thus, we have to do all comparisons relative
                // to some base. We use the last checked fetchID as the base.
                if (qindex != qindexEnd &&
                    (rrqueue[qindexEnd].fetchID - lastInvalComFetchID) < (IN_comFetchID - lastInvalComFetchID)
                ) begin
                    lastInvalComFetchID <= rrqueue[qindexEnd].fetchID;
                    rrqueue[qindexEnd] <= 'x;
                    if (qindex != qindexEnd)
                        qindexEnd <= qindexEnd + 1;
                end
                // There has been no speculated return in [lastInvalComFetchID, IN_comFetchID),
                // nothing to do.
                else lastInvalComFetchID <= IN_comFetchID;
            end

            if (lastValid) begin
                if (IN_branch.valid && IN_branch.btype == BT_RETURN) begin

                end
                else if (IN_branch.valid && IN_branch.btype == BT_CALL) begin
                    rstack[rindex] <= addrToPush;

                    // Store the overwritten address in the return recovery queue
                    if (qindexEnd != qindex + 1'b1) begin
                        rrqueue[qindex].fetchID <= IN_fetchID;
                        rrqueue[qindex].offs <= IN_branch.offs;
                        rrqueue[qindex].idx <= rindex;
                        rrqueue[qindex].addr <= rstack[rindex];
                        qindex <= qindex + 1;
                    end

                end
            end
        end
    end
end

endmodule
