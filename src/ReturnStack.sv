module ReturnStack#(parameter SIZE=4, parameter RET_PRED_SIZE=8, parameter RET_PRED_ASSOC=2, parameter RET_PRED_TAG_LEN=8)
(
    input wire clk,
    input wire rst,
    
    // IFetch time push/pop
    input wire IN_valid,
    input wire[30:0] IN_pc,
    input wire IN_brValid,
    input FetchOff_t IN_brOffs,
    input wire IN_isCall,

    input wire IN_setIdx,
    input RetStackIdx_t IN_idx,

    output RetStackIdx_t OUT_curIdx,
    output PredBranch OUT_predBr,
    input ReturnDecUpd IN_returnUpd
);

localparam RET_PRED_LEN = RET_PRED_SIZE / RET_PRED_ASSOC;

typedef struct packed
{
    logic[RET_PRED_TAG_LEN-1:0] tag;
    FetchOff_t offs; // offset of second halfword if 32 bit, otherwise first
    logic used;
    logic compr;
    logic valid;
} RetPredEntry;

RetPredEntry rtable[RET_PRED_LEN-1:0][RET_PRED_ASSOC-1:0];

reg[$clog2(RET_PRED_LEN)-1:0] lookupIdx;
reg[RET_PRED_TAG_LEN-1:0] lookupTag;
FetchOff_t lookupOffs;

reg[$clog2(RET_PRED_LEN)-1:0] decodeIdx;
reg[RET_PRED_TAG_LEN-1:0] decodeTag;
FetchOff_t decodeOffs;
always_comb begin
    lookupIdx = IN_pc[$bits(FetchOff_t)+:$clog2(RET_PRED_LEN)];
    lookupTag = IN_pc[$clog2(RET_PRED_LEN)+$bits(FetchOff_t)+:RET_PRED_TAG_LEN];
    lookupOffs = IN_pc[$bits(FetchOff_t)-1:0];

    decodeIdx = IN_returnUpd.addr[$bits(FetchOff_t)+:$clog2(RET_PRED_LEN)];
    decodeTag = IN_returnUpd.addr[$clog2(RET_PRED_LEN)+$bits(FetchOff_t)+:RET_PRED_TAG_LEN];
    decodeOffs = IN_returnUpd.addr[$bits(FetchOff_t)-1:0];
end


reg[30:0] rstack[SIZE-1:0];
RetStackIdx_t rindex;
reg[$clog2(RET_PRED_ASSOC)-1:0] lookupAssocIdx;
always_comb begin

    OUT_curIdx = rindex;
    OUT_predBr.dst = rstack[rindex];
    
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
                // TODO: only clean with matching tag
                for (integer i = 0; i < RET_PRED_LEN; i=i+1)
                    rtable[decodeIdx][i].valid <= 0;
            end
            
            if (IN_returnUpd.isCall) begin
                rstack[IN_returnUpd.idx + 1] <= IN_returnUpd.addr + 1;
                rindex <= IN_returnUpd.idx + 1;
            end
            else if (IN_returnUpd.isRet) begin
                rindex <= IN_returnUpd.idx - 1;

                // Try to insert into rtable
                // FIXME: this might double insert
                begin
                    reg inserted = 0;
                    for (integer i = 0; i < RET_PRED_ASSOC; i=i+1) begin
                        if (!inserted && (!rtable[decodeIdx][i].valid || !rtable[decodeIdx][i].used)) begin
                            inserted = 1;
                            rtable[decodeIdx][i].valid <= 1;
                            rtable[decodeIdx][i].tag <= decodeTag;
                            rtable[decodeIdx][i].compr <= IN_returnUpd.compr;
                            rtable[decodeIdx][i].offs <= decodeOffs;
                            rtable[decodeIdx][i].used <= 0;
                        end
                    end
                end

            end
        end
        else begin
            if (OUT_predBr.valid && (!IN_brValid || IN_brOffs >= OUT_predBr.offs)) begin
                rtable[lookupIdx][lookupAssocIdx].used <= 1;
                rindex <= rindex - 1;
            end
            else if (IN_brValid && IN_isCall) begin
                rstack[rindex + 1] <= {IN_pc[30:$bits(FetchOff_t)], IN_brOffs} + 1;
                rindex <= rindex + 1;
            end
        end
    end
end

endmodule
