module ReturnStack
#(
    parameter SIZE=4,
    parameter RQSIZE=4,
    parameter RET_PRED_SIZE=32,
    parameter RET_PRED_ASSOC=2,
    parameter RET_PRED_TAG_LEN=10
)
(
    input wire clk,
    input wire rst,
    output reg OUT_stall,
    
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

    input wire IN_mispr,
    input RetStackAction IN_misprAct,
    input RetStackIdx_t IN_misprIdx,
    input FetchID_t IN_misprFetchID,

    output RetStackIdx_t OUT_curIdx,
    output PredBranch OUT_predBr,
    input ReturnDecUpdate IN_returnUpd
);

localparam RET_PRED_LEN = RET_PRED_SIZE / RET_PRED_ASSOC;

typedef struct packed
{
    logic[RET_PRED_TAG_LEN-1:0] tag;
    FetchOff_t offs; // offset of second halfword if 32 bit, otherwise first
    logic compr;
    logic used;
    logic valid;
} RetPredEntry;

typedef struct packed
{
    logic[30:0] addr;
    RetStackIdx_t idx;
    FetchID_t fetchID;
} RetRecQEntry;

RetPredEntry rtable[RET_PRED_LEN-1:0][RET_PRED_ASSOC-1:0];

reg[$clog2(RET_PRED_LEN)-1:0] lookupIdx;
reg[RET_PRED_TAG_LEN-1:0] lookupTag;
FetchOff_t lookupOffs;

reg[$clog2(RET_PRED_LEN)-1:0] decodeIdx;
reg[RET_PRED_TAG_LEN-1:0] decodeTag;
FetchOff_t decodeOffs;

reg[$clog2(RET_PRED_ASSOC)-1:0] insertAssocIdx;
reg insertAssocIdxValid;
localparam PC_SHIFT = $bits(FetchOff_t);
always_comb begin
    lookupIdx = IN_pc[PC_SHIFT+:$clog2(RET_PRED_LEN)] ^ IN_pc[3+PC_SHIFT+:$clog2(RET_PRED_LEN)];
    lookupTag = IN_pc[PC_SHIFT+:RET_PRED_TAG_LEN] ^ IN_pc[RET_PRED_TAG_LEN+PC_SHIFT+:RET_PRED_TAG_LEN];
    lookupOffs = IN_pc[$bits(FetchOff_t)-1:0];

    decodeIdx = IN_returnUpd.addr[PC_SHIFT+:$clog2(RET_PRED_LEN)] ^ IN_returnUpd.addr[3+PC_SHIFT+:$clog2(RET_PRED_LEN)];
    decodeTag = IN_returnUpd.addr[PC_SHIFT+:RET_PRED_TAG_LEN] ^ IN_returnUpd.addr[RET_PRED_TAG_LEN+PC_SHIFT+:RET_PRED_TAG_LEN];
    decodeOffs = IN_returnUpd.addr[$bits(FetchOff_t)-1:0];
    
    insertAssocIdxValid = 0;
    insertAssocIdx = 'x;
    for (integer i = 0; i < RET_PRED_ASSOC; i=i+1)
        if (!rtable[decodeIdx][i].used || !rtable[decodeIdx][i].valid) begin
            insertAssocIdx = i[$clog2(RET_PRED_ASSOC)-1:0];
            insertAssocIdxValid = 1;
        end
end

reg[30:0] rstack[SIZE-1:0] /* verilator public */;

reg[$clog2(RQSIZE)-1:0] qindex;
reg[$clog2(RQSIZE)-1:0] qindexEnd;
RetRecQEntry rrqueue[RQSIZE-1:0]; // return addr recovery


reg forwardRindex;
RetStackAction recAct;

// On mispredict it takes a cycle to read the old return stack index,
// so we forward it combinatorially.
RetStackIdx_t rindexReg;
RetStackIdx_t rindex;

wire[30:0] addrToPush = {IN_lastPC[30:$bits(FetchOff_t)], IN_branch.offs} + 1;

always_comb begin
    rindex = rindexReg;
    if (forwardRindex) begin
        rindex = IN_misprIdx;
    end
    else if (IN_branch.valid && IN_branch.isCall) begin
        rindex = rindex + 1;
    end
    else if (IN_branch.valid && IN_branch.isRet) begin
        rindex = rindex - 1;
    end
end

reg[$clog2(RET_PRED_ASSOC)-1:0] lookupAssocIdx;
always_ff@(posedge clk) begin
    if (IN_valid) begin
        OUT_curIdx <= rindex;

        if (IN_branch.valid && IN_branch.isCall) begin
            // If the immediately preceeding prediction was a call,
            // we need to forward the return address.
            OUT_curRetAddr <= addrToPush;
            OUT_predBr.dst <= addrToPush;
        end
        else begin
            OUT_curRetAddr <= rstack[rindex];
            OUT_predBr.dst <= rstack[rindex];
        end

        OUT_predBr.taken <= 1;
        OUT_predBr.isJump <= 1;
        OUT_predBr.isCall <= 0;
        OUT_predBr.isRet <= 1;
        OUT_predBr.valid <= 0;
        OUT_predBr.offs <= 'x;
        OUT_predBr.compr <= 'x;
        OUT_predBr.multiple <= 'x;

        lookupAssocIdx <= 'x;
        
        for (integer i = 0; i < RET_PRED_ASSOC; i=i+1) begin
            if (rtable[lookupIdx][i].valid && 
                rtable[lookupIdx][i].tag == lookupTag && 
                rtable[lookupIdx][i].offs >= lookupOffs &&
                (!OUT_predBr.valid || OUT_predBr.offs > rtable[lookupIdx][i].offs)
            ) begin
                OUT_predBr.valid <= 1;
                OUT_predBr.offs <= rtable[lookupIdx][i].offs;
                OUT_predBr.compr <= rtable[lookupIdx][i].compr;
                lookupAssocIdx <= i[$clog2(RET_PRED_ASSOC)-1:0];
            end
        end
    end
end

assign OUT_lateRetAddr = OUT_curRetAddr;

reg recoveryInProgress;
FetchID_t recoveryID;
FetchID_t recoveryBase;
FetchID_t lastInvalComFetchID;

always_ff@(posedge clk) begin
    
    forwardRindex <= 0;
    
    if (rst) begin
        for (integer i = 0; i < RET_PRED_LEN; i=i+1)
            for (integer j = 0; j < RET_PRED_ASSOC; j=j+1)
                rtable[i][j].valid <= 0;

        qindex <= 0;
        qindexEnd <= 0;
        recoveryInProgress = 0;
        OUT_stall <= 0;
        lastInvalComFetchID <= 0;
    end
    else begin
        
        if (IN_mispr) begin
            forwardRindex <= 1;
            recAct <= IN_misprAct;
            recoveryInProgress = 1;
            recoveryID = IN_misprFetchID;
            recoveryBase = lastInvalComFetchID;
            OUT_stall <= 1;
        end
        else rindexReg <= rindex;
        
        // Recover entries by copying from rrqueue back to stack after mispredict
        if (recoveryInProgress) begin
            if (qindex == qindexEnd) begin
                recoveryInProgress = 0;
                OUT_stall <= 0;
            end
            else begin
                if (((rrqueue[qindex-1].fetchID - recoveryBase)) >= ((recoveryID - recoveryBase))) begin
                    rstack[rrqueue[qindex-1].idx] <= rrqueue[qindex-1].addr;
                    rrqueue[qindex-1] <= 'x;
                    qindex <= qindex - 1; // entry restored, ok to overwrite
                end
                else begin
                    recoveryInProgress = 0;
                    OUT_stall <= 0;
                end
            end
        end
        
        // Delete committed (ie correctly speculated) entries from rrqueue
        if (!recoveryInProgress && lastInvalComFetchID != IN_comFetchID) begin
            
            // Unlike SqNs, fetchIDs are not given an extra bit of range for the sake
            // of easy ordering comparison. Thus, we have to do all comparisons relative
            // to some base. We use the last checked fetchID as the base.
            if (((rrqueue[qindexEnd].fetchID - lastInvalComFetchID)) < ((IN_comFetchID - lastInvalComFetchID))
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
        
        if (IN_returnUpd.valid) begin
            if (IN_returnUpd.cleanRet) begin
                for (integer i = 0; i < RET_PRED_ASSOC; i=i+1) begin
                    if (rtable[decodeIdx][i].tag == decodeTag)
                        rtable[decodeIdx][i].valid <= 0;
                end
            end
            else if (IN_returnUpd.isCall) begin
                rstack[IN_returnUpd.idx + 1] <= IN_returnUpd.addr + 1;
            end
            else if (IN_returnUpd.isRet) begin

                // Try to insert into rtable
                if (insertAssocIdxValid) begin
                    rtable[decodeIdx][insertAssocIdx].valid <= 1;
                    rtable[decodeIdx][insertAssocIdx].tag <= decodeTag;
                    rtable[decodeIdx][insertAssocIdx].compr <= IN_returnUpd.compr;
                    rtable[decodeIdx][insertAssocIdx].offs <= decodeOffs;
                    rtable[decodeIdx][insertAssocIdx].used <= 1;
                end
                else begin
                    for (integer i = 0; i < RET_PRED_ASSOC; i=i+1)
                        rtable[decodeIdx][i].used <= 0;
                end
            end
        end
        else if (!IN_mispr) begin
            if (IN_branch.valid && IN_branch.isRet) begin
                
                rtable[lookupIdx][lookupAssocIdx].used <= 1;
                
                // Store the popped address in the return recovery queue
                rrqueue[qindex].fetchID <= IN_fetchID;
                rrqueue[qindex].idx <= rindexReg;
                rrqueue[qindex].addr <= IN_branch.dst;
                qindex <= qindex + 1;
                
                // overwrite old backups if full, even if they're
                // not committed yet.
                if (qindexEnd == qindex + 1'b1)
                    qindexEnd <= qindexEnd + 1;
            end
            else if (IN_branch.valid && IN_branch.isCall) begin
                rstack[rindex] <= addrToPush;
            end
        end
    end
end

endmodule
