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
    input FetchBranchProv IN_mispr,

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

reg[$clog2(RQSIZE):0] qindex_r;
reg[$clog2(RQSIZE):0] qindexEnd_r;

wire[$clog2(RQSIZE)-1:0] qindex = qindex_r[$clog2(RQSIZE)-1:0];
wire[$clog2(RQSIZE)-1:0] qindexEnd = qindexEnd_r[$clog2(RQSIZE)-1:0];

RetRecQEntry rrqueue[RQSIZE-1:0]; // return addr recovery

reg forwardRindex;

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
assign OUT_stall = recoveryInProgress && (recoveryContinue_c || postRecSave.valid);
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

wire queueEmpty = qindex_r == qindexEnd_r;
wire queueFull = qindex_r == (qindexEnd_r + $bits(qindex_r)'(RQSIZE));

logic recoveryContinue_c;
always_comb begin
    FetchID_t queueRel = (rrqueue[qindex-1].fetchID - recoveryBase);
    FetchID_t recRel = (recoveryID - recoveryBase);

    recoveryContinue_c = !queueEmpty &&
        (queueRel >  recRel ||
        (queueRel == recRel &&
            (recoveryOverwOwn ?
                (rrqueue[qindex-1].offs >= recoveryOffs) :
                (rrqueue[qindex-1].offs >  recoveryOffs))
        ));
end

always_ff@(posedge clk or posedge rst) begin

    forwardRindex <= 0;

    if (rst) begin
        qindex_r <= 0;
        qindexEnd_r <= 0;
        recoveryInProgress <= 0;
        lastInvalComFetchID <= 0;
        lastValid <= 0;

        postRecSave <= PostRecSave'{valid: 0, default: 'x};

        rindexReg <= 0;
        for (integer i = 0; i < SIZE; i=i+1)
            rstack[i] <= 0;
    end
    else begin

        lastValid <= IN_valid;

        if (IN_mispr.taken) begin
            reg doPostRecSave = IN_mispr.isFetchBranch && IN_returnUpd.valid;
            reg startRecovery = !queueEmpty || doPostRecSave;

            forwardRindex <= 1;
            recoveryInProgress <= startRecovery;
            recoveryID <= IN_mispr.fetchID;
            recoveryBase <= IN_comFetchID;
            recoveryOffs <= IN_mispr.fetchOffs;
            recoveryOverwOwn <= IN_mispr.isFetchBranch && !IN_returnUpd.valid;

            lastValid <= 0;

            postRecSave <= PostRecSave'{valid: 0, default: 'x};
            if (doPostRecSave) begin
                postRecSave.valid <= 1;
                postRecSave.fetchID <= IN_mispr.fetchID;
                postRecSave.offs <= IN_mispr.fetchOffs;
                postRecSave.rIdx <= IN_returnUpd.idx + RetStackIdx_t'(1);
                postRecSave.addr <= IN_returnUpd.addr + 1;
            end
        end
        else begin
            rindexReg <= rindex;
            // Recover entries by copying from rrqueue back to stack after mispredict
            if (recoveryInProgress) begin
                if (recoveryContinue_c) begin
                    rstack[rrqueue[qindex-1].idx] <= rrqueue[qindex-1].addr;
                    rrqueue[qindex-1] <= 'x;
                    qindex_r <= qindex_r - 1; // entry restored, ok to overwrite
                end
                else begin
                    recoveryInProgress <= 0;
                    if (postRecSave.valid) begin
                        postRecSave <= PostRecSave'{valid: 0, default: 'x};

                        if (!queueFull) begin
                            rrqueue[qindex].fetchID <= postRecSave.fetchID;
                            rrqueue[qindex].offs <= postRecSave.offs;
                            rrqueue[qindex].idx <= postRecSave.rIdx;
                            rrqueue[qindex].addr <= rstack[postRecSave.rIdx];
                            rstack[postRecSave.rIdx] <= postRecSave.addr;
                            qindex_r <= qindex_r + 1;
                        end
                    end
                end
            end
            else if (lastValid) begin
                assert(!recoveryInProgress);
                if (IN_branch.valid && IN_branch.btype == BT_RETURN) begin

                end
                else if (IN_branch.valid && IN_branch.btype == BT_CALL) begin
                    rstack[rindex] <= addrToPush;

                    // Store the overwritten address in the return recovery queue
                    if (!queueFull) begin
                        rrqueue[qindex].fetchID <= IN_fetchID;
                        rrqueue[qindex].offs <= IN_branch.offs;
                        rrqueue[qindex].idx <= rindex;
                        rrqueue[qindex].addr <= rstack[rindex];
                        qindex_r <= qindex_r + 1;
                    end
                end
            end
        end

        // Delete committed (ie correctly speculated) entries from rrqueue
        if (lastInvalComFetchID != IN_comFetchID) begin

            // Unlike SqNs, fetchIDs are not given an extra bit of range for the sake
            // of easy ordering comparison. Thus, we have to do all comparisons relative
            // to some base. We use the last checked fetchID as the base.
            if (!queueEmpty &&
                (rrqueue[qindexEnd].fetchID - lastInvalComFetchID) < (IN_comFetchID - lastInvalComFetchID)
            ) begin
                lastInvalComFetchID <= rrqueue[qindexEnd].fetchID;
                rrqueue[qindexEnd] <= 'x;
                qindexEnd_r <= qindexEnd_r + 1;
            end
            // There has been no speculated return in [lastInvalComFetchID, IN_comFetchID),
            // nothing to do.
            else lastInvalComFetchID <= IN_comFetchID;
        end

    end
end

endmodule
