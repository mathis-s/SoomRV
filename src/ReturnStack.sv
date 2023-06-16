module ReturnStack#(parameter SIZE=4, parameter RET_PRED_SIZE=16, parameter RET_PRED_ASSOC=2, parameter RET_PRED_TAG_LEN=10)
(
    input wire clk,
    input wire rst,
    
    // IFetch time push/pop
    input wire IN_valid,
    input wire[30:0] IN_pc,
    input wire IN_brValid,
    input FetchOff_t IN_brOffs,
    input wire IN_isCall,

    // Low effort prediction for returns that are detected late, in decode.
    output reg[30:0] OUT_lateRetAddr,

    input wire IN_setIdx,
    input RetStackIdx_t IN_idx,

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

reg[30:0] rstackBackup;
reg[1:0] rstackBackupIdx;

reg[30:0] rstack[SIZE-1:0];

reg qindex;
RetStackIdx_t rindex;
reg[$clog2(RET_PRED_ASSOC)-1:0] lookupAssocIdx;
always_comb begin

    OUT_curIdx = rindex;
    OUT_predBr.dst = rstack[rindex];
    OUT_lateRetAddr = rstack[rindex];
    
    OUT_predBr.isJump = 1;
    OUT_predBr.valid = 0;
    OUT_predBr.offs = 'x;
    OUT_predBr.compr = 'x;

    lookupAssocIdx = 'x;
    
    if (IN_valid) begin
        for (integer i = 0; i < RET_PRED_ASSOC; i=i+1) begin
            if (rtable[lookupIdx][i].valid && 
                rtable[lookupIdx][i].tag == lookupTag && 
                rtable[lookupIdx][i].offs >= lookupOffs &&
                (!OUT_predBr.valid || OUT_predBr.offs > rtable[lookupIdx][i].offs)) begin
                OUT_predBr.valid = 1;
                OUT_predBr.offs = rtable[lookupIdx][i].offs;
                OUT_predBr.compr = rtable[lookupIdx][i].compr;
                lookupAssocIdx = i[$clog2(RET_PRED_ASSOC)-1:0];
            end
        end
    end
end

always_ff@(posedge clk) begin
    if (rst) begin
        for (integer i = 0; i < RET_PRED_LEN; i=i+1)
            for (integer j = 0; j < RET_PRED_ASSOC; j=j+1)
                rtable[i][j].valid <= 0;
        
        // Not strictly necessary
        for (integer i = 0; i < SIZE; i=i+1)
            rstack[i] <= 0;
    end
    else begin

        if (IN_setIdx) begin
            rindex <= IN_idx;
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
                rindex <= IN_returnUpd.idx + 1;
            end
            else if (IN_returnUpd.isRet) begin
                rindex <= IN_returnUpd.idx - 1;

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
        else begin
            if (OUT_predBr.valid && (!IN_brValid || IN_brOffs >= OUT_predBr.offs)) begin
                rtable[lookupIdx][lookupAssocIdx].used <= 1;
                rindex <= rindex - 1;
                rstackBackup <= OUT_predBr.dst;
                rstackBackupIdx <= rindex;
            end
            else if (IN_brValid && IN_isCall) begin
                rstack[rindex + 1] <= {IN_pc[30:$bits(FetchOff_t)], IN_brOffs} + 1;
                rindex <= rindex + 1;
            end
        end
    end
end

endmodule
