module PrefetchExecutor
(
    input logic clk,
    input logic rst,

    input Prefetch IN_prefetch,
    output logic OUT_prefetchReady,

    output CacheTableRead OUT_ctRead,
    input logic IN_ctReadReady,
    input CacheTableResult IN_ctResult,

    output CacheMiss OUT_miss,
    input logic IN_missReady,

    output Prefetch_ACK OUT_prefetchAck
);

always_comb begin
    OUT_ctRead = CacheTableRead'{valid: 0, default: 'x};
    if (IN_prefetch.valid && OUT_prefetchReady) begin
        OUT_ctRead = CacheTableRead'{
            addr: IN_prefetch.addr[0+:`VIRT_IDX_LEN],
            valid: 1
        };
    end
end

typedef struct packed
{
    logic[$clog2(`CASSOC)-1:0] idx;
    logic valid;
} IdxN;

logic[`CASSOC-1:0] assocHitUnary_c;
always_comb begin
    for(integer j = 0; j < `CASSOC; j=j+1)
        assocHitUnary_c[j] = IN_ctResult.data[j].valid && IN_ctResult.data[j].addr == pfOp[1].addr[31:`VIRT_IDX_LEN];
end
IdxN assocHit_c;
OHEncoder#(`CASSOC, 1) ohEnc(assocHitUnary_c, assocHit_c.idx, assocHit_c.valid);

CacheMiss miss;
always_comb begin
    miss = CacheMiss'{valid: 0, default: 'x};
    if (pfOp[1].valid && !assocHit_c.valid) begin
        miss = CacheMiss'{
            writeAddr: {IN_ctResult.data[IN_ctResult.assocCnt].addr, pfOp[1].addr[0+:`VIRT_IDX_LEN]},
            missAddr: {pfOp[1].addr},
            assoc: IN_ctResult.assocCnt,
            mtype: IN_ctResult.data[IN_ctResult.assocCnt].valid ? REGULAR : REGULAR_NO_EVICT,
            valid: 1
        };
    end
end
assign OUT_miss = miss;

Prefetch pfOp[1:0];
always_ff@(posedge clk) begin
    OUT_prefetchAck <= Prefetch_ACK'{valid: 0, default: 'x};
    if (rst) begin
        for (int i = 0; i < 2; i=i+1)
            pfOp[i] <= Prefetch'{valid: 0, default: 'x};
    end
    else begin
        for (int i = 0; i < 2; i=i+1)
            pfOp[i] <= Prefetch'{valid: 0, default: 'x};

        if (IN_prefetch.valid && OUT_prefetchReady) begin
            pfOp[0] <= IN_prefetch;
        end

        if (pfOp[0].valid) begin
            pfOp[1] <= pfOp[0];
        end

        if (pfOp[1].valid) begin
            if (assocHit_c.valid) begin
                OUT_prefetchAck <= Prefetch_ACK'{existing: 1, valid: 1};
            end
            else if (IN_missReady) begin
                OUT_prefetchAck <= Prefetch_ACK'{existing: 0, valid: 1};
            end
            else begin
                // fail
            end
        end
    end
end

assign OUT_prefetchReady = IN_ctReadReady;


endmodule
