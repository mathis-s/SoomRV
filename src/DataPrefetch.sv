module DataPrefetch
(
    input logic clk,
    input logic rst,

    input AGU_UOp IN_aguOps[NUM_AGUS-1:0],

    input CacheMiss IN_miss,
    output Prefetch OUT_prefetch,
    input logic IN_prefetchReady,
    input Prefetch_ACK IN_prefetchAck
);


PrefetchMiss prefetchMiss;
always_comb begin
    prefetchMiss = PrefetchMiss'{
        addr: IN_miss.missAddr[31:`CLSIZE_E],
        write: 0,
        read: 0,
        valid: IN_miss.valid
    };
end

PrefetchAccess prefetchAccess[NUM_AGUS-1:0];
always_comb begin
    for (int i = 0; i < NUM_AGUS; i++)
        prefetchAccess[i] = PrefetchAccess'{
            addr: IN_aguOps[i].addr[31:`CLSIZE_E],
            w: 0,
            r: 0,
            valid: IN_aguOps[i].valid
        };
end

PrefetchPattern pattern;

PrefetchPatternDetector patternDetector
(
    .clk(clk),
    .rst(rst),

    .IN_miss(prefetchMiss),
    .OUT_pattern(pattern)
);

PrefetchIssuer issuer
(
    .clk(clk),
    .rst(rst),
    .IN_access(prefetchAccess),
    .IN_pattern(pattern),
    .OUT_prefetch(OUT_prefetch),
    .IN_prefetchReady(IN_prefetchReady),
    .IN_prefetchAck(IN_prefetchAck)
);

always_ff@(posedge clk) begin
    if (pattern.valid) begin
        //$display("pattern addr=%x stride=%x", {pattern.addr, 6'b0}, pattern.stride);
    end
end

endmodule
