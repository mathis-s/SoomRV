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

wire acceptPrefetch = state == IDLE && !OUT_prefetchAck.valid;

always_comb begin
    OUT_ctRead = CacheTableRead'{valid: 0, default: 'x};
    if (IN_prefetch.valid && acceptPrefetch) begin
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
        assocHitUnary_c[j] = IN_ctResult.data[j].valid && IN_ctResult.data[j].addr == IN_prefetch.addr[31:`VIRT_IDX_LEN];
end
IdxN assocHit_c;
OHEncoder#(`CASSOC, 1) ohEnc(assocHitUnary_c, assocHit_c.idx, assocHit_c.valid);

reg[$clog2(`CASSOC)-1:0] assocCnt;
always_ff@(posedge clk /*or posedge rst*/)
    assocCnt <= rst ? 0 : assocCnt + 1;

CacheMiss miss;
always_comb begin
    miss = CacheMiss'{valid: 0, default: 'x};
    if (state == EVAL0 && !assocHit_c.valid) begin
        miss = CacheMiss'{
            writeAddr: {IN_ctResult.data[assocCnt].addr, IN_prefetch.addr[0+:`VIRT_IDX_LEN]},
            missAddr: {IN_prefetch.addr},
            assoc: assocCnt,
            mtype: IN_ctResult.data[assocCnt].valid ? REGULAR : REGULAR_NO_EVICT,
            valid: 1
        };
    end
end
assign OUT_miss = miss;

enum logic[1:0]
{
    IDLE, WAIT, EVAL0
} state;

always_ff@(posedge clk /*or posedge rst*/) begin
    OUT_prefetchAck <= Prefetch_ACK'{valid: 0, default: 'x};
    OUT_prefetchReady <= 0;

    if (rst) begin
        state <= IDLE;
    end
    else begin
        case (state)
            default: begin
                // We assume IN_prefetch stays constant until we ack with ready.
                if (IN_prefetch.valid && IN_ctReadReady && acceptPrefetch)
                    state <= WAIT;
            end

            WAIT: state <= EVAL0;

            EVAL0: begin
                if (assocHit_c.valid) begin
                    OUT_prefetchAck <= Prefetch_ACK'{existing: 1, valid: 1};
                    OUT_prefetchReady <= 1;
                    state <= IDLE;
                end
                else if (IN_missReady) begin
                    OUT_prefetchAck <= Prefetch_ACK'{existing: 0, valid: 1};
                    OUT_prefetchReady <= 1;
                    state <= IDLE;
                end
                else begin
                    state <= IDLE;
                end
            end

        endcase
    end
end

endmodule
