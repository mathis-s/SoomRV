
module CacheLineManager
(
    input logic clk,
    input logic rst,

    IF_CTable.HOST IF_ct,

    input wire IN_flush,
    input wire IN_storeBusy,
    output wire OUT_busy,

    input CacheLineSetDirty IN_setDirty,

    input CacheTableRead IN_ctRead[NUM_CT_READS-1:0],
    output logic OUT_ctReadReady[NUM_CT_READS-1:0],
    output CacheTableResult OUT_ctResult[NUM_CT_READS-1:0],

    input CacheMiss IN_miss,
    output logic OUT_missReady,

    input Prefetch IN_prefetch,
    output logic OUT_prefetchReady,
    output Prefetch_ACK OUT_prefetchAck,

    output MemController_Req OUT_memc,
    input MemController_Res IN_memc
);

localparam SIZE = (1<<(`CACHE_SIZE_E - `CLSIZE_E));

// Find unused ct read port for prefetcher cache table accesses.
logic[NUM_CT_READS-1:0] readUnused_c;
always_comb begin
    for (int i = 0; i < NUM_CT_READS; i++) begin
        readUnused_c[i] = !IN_ctRead[i].valid && OUT_ctReadReady[i];
    end
end

CacheTableRead ctRead_c[NUM_CT_READS-1:0];
always_comb
    for (int i = 0; i < NUM_CT_READS; i++)
        ctRead_c[i] = readUnused_c[i] ? PF_ctRead : IN_ctRead[i];

CacheTableRead ctRead_r[NUM_CT_READS-1:0];
always_ff@(posedge clk) begin
    for (integer i = 0; i < NUM_CT_READS; i=i+1) begin
        ctRead_r[i] <= ctRead_c[i];
    end
end

typedef logic[$clog2(NUM_CT_READS)-1:0] ReadIdx;

ReadIdx readIdx_c;
logic _unusedSignal;
PriorityEncoder#(NUM_CT_READS, 1) penc(readUnused_c, '{readIdx_c}, '{_unusedSignal});
ReadIdx readIdx_r[1:0];
always_ff@(posedge clk) readIdx_r <= {readIdx_r[0], readIdx_c};

CacheTableRead PF_ctRead;
CacheMiss PF_miss;
PrefetchExecutor prefetchExec
(
    .clk(clk),
    .rst(rst),

    .IN_prefetch(IN_prefetch),
    .OUT_prefetchReady(OUT_prefetchReady),

    .OUT_ctRead(PF_ctRead),
    .IN_ctReadReady(|readUnused_c),
    .IN_ctResult(OUT_ctResult[readIdx_r[1]]),

    .OUT_miss(PF_miss),
    .IN_missReady(!IN_miss.valid && OUT_missReady),

    .OUT_prefetchAck(OUT_prefetchAck)
);

wire CacheMiss miss = IN_miss.valid ? IN_miss : PF_miss;

reg[SIZE-1:0] dirty;

reg initialFlush;
reg flushQueued;
wire flushReady = !IN_storeBusy;
wire flushActive = (
    state == FLUSH || state == FLUSH_WAIT ||
    state == FLUSH_READ0 || state == FLUSH_READ1 || state == FLUSH_FINALIZE);
assign OUT_busy = flushQueued || flushActive;

reg flushDone;
reg[`CACHE_SIZE_E-`CLSIZE_E-$clog2(`CASSOC)-1:0] flushIdx;
reg[$clog2(`CASSOC)-1:0] flushAssocIdx;

typedef struct packed
{
    CTEntry data;
    logic[$clog2(`CASSOC)-1:0] assoc;
    logic[`VIRT_IDX_LEN-1:0] addr;
    logic valid;
} CacheTableWrite;

// Cache Table Write
CacheTableWrite ctWrite_c;
always_comb begin;
    ctWrite_c = CacheTableWrite'{valid: 0, default: 'x};

    if (state == IDLE && forwardMiss) begin
        // Immediately write the new cache table entry (about to be loaded)
        // on a miss. We still need to intercept and pass through or stop
        // loads at the new address until the cache line is entirely loaded.
        case (miss.mtype)
            REGULAR_NO_EVICT,
            REGULAR: begin
                ctWrite_c = CacheTableWrite'{
                    data:  CTEntry'{addr: miss.missAddr[31:`VIRT_IDX_LEN], valid: 1},
                    assoc: miss.assoc,
                    addr:  miss.missAddr[`VIRT_IDX_LEN-1:0],
                    valid: 1
                };
            end

            MGMT_INVAL,
            MGMT_FLUSH: begin
                ctWrite_c = CacheTableWrite'{
                    data:  CTEntry'{valid: 0, default: 'x},
                    assoc: miss.assoc,
                    addr:  miss.missAddr[`VIRT_IDX_LEN-1:0],
                    valid: 1
                };
            end
            // MGMT_CLEAN does not modify cache table
            default: ;
        endcase
    end
    else if (state == FLUSH) begin
        if (!flushDone) begin
            ctWrite_c = CacheTableWrite'{
                data:  CTEntry'{valid: 0, default: 'x},
                assoc: flushAssocIdx,
                addr:  {flushIdx, {`CLSIZE_E{1'b0}}},
                valid: 1
            };
        end
    end
end
always_comb begin
    IF_ct.we = ctWrite_c.valid;
    IF_ct.waddr = ctWrite_c.addr;
    IF_ct.wassoc = ctWrite_c.assoc;
    IF_ct.wdata = ctWrite_c.data;
    IF_ct.widx = (ctWrite_c.assoc + 1'b1);
end

localparam WRITE_FWD_CYCLES = 2;
CacheTableWrite ctWrite_sr[WRITE_FWD_CYCLES-1:0];
assign ctWrite_sr[0] = ctWrite_c;
always_ff@(posedge clk) begin
    for (integer i = 0; i < WRITE_FWD_CYCLES - 1; i=i+1) begin
        ctWrite_sr[i+1] <= ctWrite_sr[i];
    end
end

// Cache Table Reads
always_comb begin
    for (integer i = 0; i < NUM_CT_READS; i=i+1) begin
        IF_ct.re[i] = ctRead_c[i].valid;
        IF_ct.raddr[i] = ctRead_c[i].addr;
        OUT_ctReadReady[i] = 1;
    end

    // During a flush, we read from the cache table at the flush iterator
    if (state == FLUSH_READ0) begin
        IF_ct.re[0] = 1;
        IF_ct.raddr[0] = {flushIdx, {`CLSIZE_E{1'b0}}};
        OUT_ctReadReady[0] = 0;
    end

    if (ctWrite_c.valid)
        for (integer i = 0; i < NUM_CT_READS; i=i+1)
            OUT_ctReadReady[i] = 0;
end

typedef struct packed
{
    CTEntry data;
    logic[`CASSOC-1:0] mask;
    logic valid;
} CacheTableReadFwd;

CacheTableReadFwd readFwds[NUM_CT_READS-1:0];
always_ff@(posedge clk) begin
    for (integer i = 0; i < NUM_CT_READS; i=i+1) begin
        readFwds[i] <= CacheTableReadFwd'{valid: 0, mask: 0, default: 'x};
        for (integer j = 0; j < WRITE_FWD_CYCLES; j=j+1) begin
            if (ctWrite_sr[j].valid && ctRead_r[i].valid &&
                ctWrite_sr[j].addr[`VIRT_IDX_LEN-1:`CLSIZE_E] == ctRead_r[i].addr[`VIRT_IDX_LEN-1:`CLSIZE_E]
            ) begin
                readFwds[i] <= CacheTableReadFwd'{
                    data:  ctWrite_sr[j].data,
                    mask:  `CASSOC'(1) << ctWrite_sr[j].assoc,
                    valid: 1
                };
            end
        end
    end
end

always_comb begin
    for (integer i = 0; i < NUM_CT_READS; i=i+1) begin
        OUT_ctResult[i].data = IF_ct.rdata[i];
        OUT_ctResult[i].assocCnt = IF_ct.ridx[i] + readFwds[i].valid;
        for (integer j = 0; j < `CASSOC; j=j+1)
            if (readFwds[i].mask[j]) begin
                OUT_ctResult[i].data[j] = readFwds[i].data;
            end
    end
end

// Check for conflicts
logic missEvictConflict;
always_comb begin
    missEvictConflict = 0;

    // read after write
    for (integer j = 0; j < `AXI_NUM_TRANS; j=j+1) begin
        if (miss.valid &&
            IN_memc.transfers[j].valid &&
            IN_memc.transfers[j].writeAddr[31:`CLSIZE_E] == miss.missAddr[31:`CLSIZE_E]
        ) begin
            missEvictConflict = 1;
        end
    end
    if ((OUT_memc.cmd == MEMC_REPLACE || OUT_memc.cmd == MEMC_CP_CACHE_TO_EXT) &&
        miss.valid && OUT_memc.writeAddr[31:`CLSIZE_E] == miss.missAddr[31:`CLSIZE_E])
        missEvictConflict = 1;

    // write after read
    for (integer j = 0; j < `AXI_NUM_TRANS; j=j+1) begin
        if (miss.valid &&
            IN_memc.transfers[j].valid &&
            IN_memc.transfers[j].readAddr[31:`CLSIZE_E] == miss.writeAddr[31:`CLSIZE_E]
        ) begin
            missEvictConflict = 1;
        end
    end

    if ((OUT_memc.cmd == MEMC_REPLACE || OUT_memc.cmd == MEMC_CP_EXT_TO_CACHE) &&
        miss.valid && OUT_memc.readAddr[31:`CLSIZE_E] == miss.writeAddr[31:`CLSIZE_E])
        missEvictConflict = 1;
end

wire canOutputMiss = (OUT_memc.cmd == MEMC_NONE || !IN_memc.stall[1]);
assign OUT_missReady = canOutputMiss && !missEvictConflict;
wire forwardMiss = OUT_missReady && miss.valid &&
    miss.mtype != CONFLICT && miss.mtype != TRANS_IN_PROG;

// Cache Transfer State Machine
enum logic[3:0]
{
    IDLE, FLUSH, FLUSH_READ0, FLUSH_READ1, FLUSH_WAIT, FLUSH_FINALIZE
} state;
always_ff@(posedge clk /*or posedge rst*/) begin

    if (rst) begin
        state <= IDLE;
        flushQueued <= 1;
        initialFlush <= 1;
        OUT_memc <= MemController_Req'{cmd: MEMC_NONE, default: 'x};

        flushIdx <= 'x;
        flushAssocIdx <= 'x;
        flushDone <= 'x;
    end
    else begin
        if (canOutputMiss) begin
            OUT_memc <= 'x;
            OUT_memc.cmd <= MEMC_NONE;
        end
        if (IN_flush) flushQueued <= 1;
        if (IN_setDirty.valid) dirty[IN_setDirty.idx] <= 1;

        case (state)
            IDLE: begin

                reg[$clog2(SIZE)-1:0] missIdx = {miss.assoc, miss.missAddr[`VIRT_IDX_LEN-1:`CLSIZE_E]};
                MissType missType = miss.mtype;

                if (forwardMiss) begin

                    //$display("Miss %d", miss.missAddr >> `CLSIZE_E);

                    // if not dirty, do not copy back to main memory
                    if (missType == REGULAR && !dirty[missIdx] && (!IN_setDirty.valid || IN_setDirty.idx != missIdx))
                        missType = REGULAR_NO_EVICT;

                    case (missType)
                        REGULAR: begin
                            OUT_memc.cmd <= MEMC_REPLACE;
                            OUT_memc.cacheAddr <= {miss.assoc, miss.missAddr[`VIRT_IDX_LEN-1:2]};
                            OUT_memc.writeAddr <= {miss.writeAddr[31:`VIRT_IDX_LEN], miss.missAddr[`VIRT_IDX_LEN-1:2], 2'b0};
                            OUT_memc.readAddr <= {miss.missAddr[31:2], 2'b0};
                            OUT_memc.cacheID <= 0;
                            OUT_memc.mask <= 0;
                        end

                        REGULAR_NO_EVICT: begin
                            OUT_memc.cmd <= MEMC_CP_EXT_TO_CACHE;
                            OUT_memc.cacheAddr <= {miss.assoc, miss.missAddr[`VIRT_IDX_LEN-1:2]};
                            OUT_memc.writeAddr <= 'x;
                            OUT_memc.readAddr <= {miss.missAddr[31:2], 2'b0};
                            OUT_memc.cacheID <= 0;
                            OUT_memc.mask <= 0;
                        end

                        MGMT_CLEAN,
                        MGMT_FLUSH: begin
                            OUT_memc.cmd <= MEMC_CP_CACHE_TO_EXT;
                            OUT_memc.cacheAddr <= {miss.assoc, miss.missAddr[`VIRT_IDX_LEN-1:2]};
                            OUT_memc.writeAddr <= {miss.writeAddr[31:`VIRT_IDX_LEN], miss.missAddr[`VIRT_IDX_LEN-1:2], 2'b0};
                            OUT_memc.readAddr <= 'x;
                            OUT_memc.cacheID <= 0;
                            OUT_memc.mask <= 0;
                        end
                        default: ; // MGMT_INVAL does not evict the cache line
                    endcase

                    // We can forward a single store to the memory controller, which will then splice
                    // the store value into the data stream from external RAM.
                    /*if ((missType == REGULAR || missType == REGULAR_NO_EVICT) && stOps[1].valid && fuseStoreMiss) begin
                        OUT_memc.mask <= stOps[1].wmask;
                        OUT_memc.data <= stOps[1].data;
                        dirty[missIdx] <= 1;
                    end
                    else*/ begin
                        // new cache line is not dirty
                        dirty[missIdx] <= 0;
                    end
                end

                if (flushQueued && flushReady) begin
                    state <= FLUSH_WAIT;
                    flushQueued <= 0;
                    flushIdx <= 0;
                    flushAssocIdx <= 0;
                    flushDone <= 0;
                end
            end

            FLUSH_WAIT: begin
                state <= FLUSH_READ0;
                if (OUT_memc.cmd != MEMC_NONE)
                    state <= FLUSH_WAIT;
                for (integer i = 0; i < `AXI_NUM_TRANS; i=i+1)
                    if (IN_memc.transfers[i].valid) state <= FLUSH_WAIT;
            end
            FLUSH_READ0: begin
                state <= FLUSH_READ1;
            end
            FLUSH_READ1: begin
                state <= FLUSH;
            end
            FLUSH: begin
                if (flushDone) begin
                    state <= FLUSH_FINALIZE;
                    initialFlush <= 0;
                end
                else if (OUT_memc.cmd == MEMC_NONE || !IN_memc.stall[1]) begin
                    CTEntry entry = IF_ct.rdata[0][flushAssocIdx];

                    if (entry.valid && dirty[{flushAssocIdx, flushIdx}] && !initialFlush) begin
                        OUT_memc.cmd <= MEMC_CP_CACHE_TO_EXT;
                        OUT_memc.cacheAddr <= {flushAssocIdx, flushIdx, {(`CLSIZE_E-2){1'b0}}};
                        OUT_memc.writeAddr <= {entry.addr, flushIdx, {(`CLSIZE_E){1'b0}}};
                        OUT_memc.readAddr <= 'x;
                        OUT_memc.cacheID <= 0;
                        OUT_memc.mask <= 0;
                    end

                    {flushDone, flushIdx, flushAssocIdx} <= {flushIdx, flushAssocIdx} + 1;
                    if (flushAssocIdx == $clog2(`CASSOC)'(`CASSOC-1)) state <= FLUSH_READ0;
                end
            end
            FLUSH_FINALIZE: begin
                state <= IDLE;
                for (integer i = 0; i < `AXI_NUM_TRANS; i=i+1)
                    if (IN_memc.transfers[i].valid)
                        state <= FLUSH_FINALIZE;
            end
            default: state <= IDLE;
        endcase
    end
end

endmodule
