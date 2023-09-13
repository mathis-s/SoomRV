module LoadStoreUnit
#(
    parameter SIZE=(1<<(`CACHE_SIZE_E - `CLSIZE_E)),
    localparam TOTAL_UOPS = 2
)
(
    input wire clk,
    input wire rst,

    input wire IN_flush,
    input wire IN_SQ_empty,
    output wire OUT_busy,

    input BranchProv IN_branch,
    output reg OUT_ldAGUStall,
    output reg OUT_ldStall,
    output wire OUT_stStall,
    
    // regular loads come through these two
    // structs. uopELd provides the lower 12 addr bits
    // one cycle early.
    input ELD_UOp IN_uopELd,
    input LD_UOp IN_aguLd,

    input LD_UOp IN_uopLd, // special loads (page walk, non-speculative)
    output LD_UOp OUT_uopLdSq,
    output LD_Ack OUT_ldAck,

    input ST_UOp IN_uopSt,

    IF_Cache.HOST IF_cache,
    IF_MMIO.HOST IF_mmio,
    IF_CTable.HOST IF_ct,
    
    input StFwdResult IN_stFwd,
    output ST_Ack OUT_stAck,

    output MemController_Req OUT_memc,
    output MemController_Req OUT_BLSU_memc,
    input MemController_Res IN_memc,

    output RES_UOp OUT_uopLd
);

MemController_Req BLSU_memc;
MemController_Req LSU_memc;
assign OUT_memc = LSU_memc;
assign OUT_BLSU_memc = BLSU_memc;

wire isCacheBypassLdUOp = 
    `ENABLE_EXT_MMIO && uopLd_0.valid && uopLd_0.isMMIO && uopLd_0.exception == AGU_NO_EXCEPTION &&
    uopLd_0.addr >= `EXT_MMIO_START_ADDR && uopLd_0.addr < `EXT_MMIO_END_ADDR;
wire isCacheBypassStUOp = 
    `ENABLE_EXT_MMIO && IN_uopSt.valid && IN_uopSt.isMMIO && 
    IN_uopSt.addr >= `EXT_MMIO_START_ADDR && IN_uopSt.addr < `EXT_MMIO_END_ADDR;

wire ignoreSt = isCacheBypassStUOp;

wire BLSU_stStall;
wire BLSU_ldStall;
LD_UOp BLSU_uopLd;
wire[31:0] BLSU_ldResult;
BypassLSU bypassLSU
(
    .clk(clk),
    .rst(rst),
    
    .IN_branch(IN_branch),
    .IN_uopLdEn(isCacheBypassLdUOp),
    .OUT_ldStall(BLSU_ldStall),
    .IN_uopLd(uopLd_0),

    .IN_uopStEn(isCacheBypassStUOp),
    .OUT_stStall(BLSU_stStall),
    .IN_uopSt(IN_uopSt),

    .IN_ldStall(ldOps[1].valid),
    .OUT_uopLd(BLSU_uopLd),
    .OUT_ldData(BLSU_ldResult),

    .OUT_memc(BLSU_memc),
    .IN_memc(IN_memc)
);

// stall only affects start of ld/st pipelines.
wire[1:0] stall;
assign stall[0] = cacheTableWrite || flushActive;
assign stall[1] = (OUT_stStall) || cacheTableWrite || flushActive;
assign OUT_stStall = (isCacheBypassStUOp ? BLSU_stStall : (cacheTableWrite || flushActive)) && IN_uopSt.valid;

LD_UOp LMQ_ld;
LD_UOp uopLd;
assign OUT_uopLdSq = uopLd_0;

ST_UOp uopSt;
assign uopSt = IN_uopSt;

// Both load and store read from cache table
always_comb begin
    IF_ct.re[0] = uopLd.valid && !uopLd.isMMIO && uopLd.exception == AGU_NO_EXCEPTION;
    IF_ct.raddr[0] = uopLd.addr[11:0];
    
    IF_ct.re[1] = uopSt.valid && !uopSt.isMMIO && !stall[1] && !ignoreSt;
    IF_ct.raddr[1] = uopSt.addr[11:0];
    
    // During a flush, we read from the cache table at the flush iterator
    if (flushActive) begin
        IF_ct.re[0] = !cacheTableWrite;
        IF_ct.raddr[0] = {flushIdx, {`CLSIZE_E{1'b0}}};
    end
end

// Loads also speculatively load from all possible locations
always_comb begin
    IF_cache.re = !(uopLd.valid && !uopLd.isMMIO && uopLd.exception == AGU_NO_EXCEPTION);
    IF_cache.raddr = uopLd.addr[11:0];
end

// Select load to execute
// 1. previous miss from load miss queue
// 2. special load (page walk, non-speculative or external)
// 3. regular load
always_comb begin
    uopLd = 'x;
    uopLd.valid = 0;

    OUT_ldStall = IN_uopLd.valid;
    OUT_ldAGUStall = IN_uopELd.valid;
    LMQ_dequeue = 0;
    
    // Only addr[11:0] is well defined, the rest is 
    // still being calculated (for regular loads at least) and will
    // only be available in the next cycle.

    if (stall[0]) begin
        // do not issue load
    end
    else if (LMQ_ld.valid && 
        (!IN_branch.taken || LMQ_ld.external || $signed(LMQ_ld.sqN - IN_branch.sqN) <= 0)
    ) begin
        uopLd = LMQ_ld;
        LMQ_dequeue = 1;
    end
    else if (IN_uopLd.valid &&
        (!IN_branch.taken || IN_uopLd.external || $signed(IN_uopLd.sqN - IN_branch.sqN) <= 0)
    ) begin
        uopLd = IN_uopLd;
        OUT_ldStall = 0;
    end
    else if (IN_uopELd.valid
    ) begin
        uopLd.valid = 1;
        uopLd.external = 0;
        uopLd.addr[11:0] = IN_uopELd.addr;

        uopLd.isMMIO = 0; // assume that this is not MMIO such that cache is read
        uopLd.exception = AGU_NO_EXCEPTION; // assume no exception

        OUT_ldAGUStall = 0;
    end
end

reg regularLd;
always_ff@(posedge clk)
    if (rst) regularLd <= 0;
    else regularLd <= IN_uopELd.valid && !OUT_ldAGUStall;

LD_UOp uopLd_0;
always_comb begin
    
    uopLd_0 = ldOps[0];

    // For regular loads, we only get the full address and other
    // info now.
    if (regularLd) begin
        assert(rst || !IN_aguLd.valid || IN_aguLd.addr[11:0] == uopLd_0.addr[11:0]);
        uopLd_0 = 'x;
        uopLd_0.valid = 0;
        if (IN_aguLd.valid)
            uopLd_0 = IN_aguLd;
    end
end

// Load from internal MMIO
// This is executed one cycle later than loads from cache
// as internal MMIO only has a read delay of one cycle.
always_comb begin
    IF_mmio.re = 1;
    IF_mmio.raddr = 'x;
    IF_mmio.rsize = 'x;

    if (uopLd_0.valid && uopLd_0.isMMIO && !isCacheBypassLdUOp) begin
        IF_mmio.re = 0;
        IF_mmio.raddr = uopLd_0.addr;
        IF_mmio.rsize = uopLd_0.size;
    end
end

// Stores to internal MMIO are uncached, they run right away
always_comb begin
    IF_mmio.we = 1;
    IF_mmio.waddr = 'x;
    IF_mmio.wdata = 'x;
    IF_mmio.wmask = 'x;

    if (uopSt.valid && uopSt.isMMIO) begin
        IF_mmio.we = 0;
        IF_mmio.waddr = uopSt.addr;
        IF_mmio.wdata = uopSt.data;
        IF_mmio.wmask = uopSt.wmask;
    end
end

// delay lines, waiting for cache response
LD_UOp ldOps[1:0];
ST_UOp stOps[1:0];

reg loadWasExtIOBusy;

// Load Pipeline
always_ff@(posedge clk) begin
    if (rst) begin
        for (integer i = 1; i < 3; i=i+1)
            ldOps[i].valid <= 0;
    end
    else begin
        ldOps[0] <= 'x;
        ldOps[0].valid <= 0;
        ldOps[1] <= 'x;
        ldOps[1].valid <= 0;
        
        // Progress the delay line
        if (uopLd.valid)
            ldOps[0] <= uopLd;
        
        if (uopLd_0.valid && (!IN_branch.taken || uopLd_0.external || $signed(uopLd_0.sqN - IN_branch.sqN) <= 0) &&
            // if the BLSU is busy, we place the OP in the Load Miss Queue.
            (!isCacheBypassLdUOp || BLSU_ldStall)) begin
            ldOps[1] <= uopLd_0;
            loadWasExtIOBusy <= isCacheBypassLdUOp;
        end
    end
end

reg[$clog2(`CASSOC)-1:0] assocCnt;

typedef enum logic[3:0]
{
    REGULAR, REGULAR_NO_EVICT, TRANS_IN_PROG, MGMT_CLEAN, MGMT_INVAL, MGMT_FLUSH, IO_BUSY, CONFLICT, SQ_CONFLICT
} MissType;

typedef struct packed
{
    logic[31:0] oldAddr;
    logic[31:0] missAddr;
    logic[$clog2(`CASSOC)-1:0] assoc;
    MissType mtype;
    logic valid;
} CacheMiss;

CacheMiss miss[1:0];

// Load Result Output
LD_UOp curLd;
always_comb begin
    // Load output is combination of ldOps[1] (the op that accessed cache 2 cycles ago)
    // and the loaded result (or an internal/external MMIO load).
    LD_UOp ld = ldOps[1].valid ? ldOps[1] : BLSU_uopLd;
    reg isExtMMIO = !ldOps[1].valid;
    reg isIntMMIO = ldOps[1].valid && ldOps[1].isMMIO;
    reg noEvict = !IF_ct.rdata[0][assocCnt].valid;
    reg doCacheLoad = 1;

    curLd = ld;
    
    OUT_uopLd = 'x;
    OUT_uopLd.valid = 0;
    miss[0] = 'x;
    miss[0].valid = 0;

    if (ld.valid && !rst) begin
        reg cacheHit = 0;
        reg[31:0] readData = 'x;

        if (isExtMMIO) begin
            readData = BLSU_ldResult;
        end
        else if (isIntMMIO) begin
            readData = IF_mmio.rdata;
        end
        else begin
            for (integer i = 0; i < `CASSOC; i=i+1) begin
                if (IF_ct.rdata[0][i].valid && IF_ct.rdata[0][i].addr == ld.addr[31:12]) begin
                    assert(!cacheHit); // multiple hits are invalid
                    cacheHit = 1;
                    doCacheLoad = 0;
                    readData = IF_cache.rdata[i];
                end
            end
            
            // check if cache line is currently being transferred
            for (integer i = 0; i < 4; i=i+1) begin
                if (IN_memc.transfers[i].valid && IN_memc.transfers[i].cacheID == 0 &&
                    IN_memc.transfers[i].newAddr[31:`CLSIZE_E] == ld.addr[31:`CLSIZE_E]
                ) begin
                    doCacheLoad = 0;
                    cacheHit = 0;
                end
            end
            if (LSU_memc.cmd != MEMC_NONE && 
                LSU_memc.extAddr[31-2:`CLSIZE_E-2] == ld.addr[31:`CLSIZE_E]
            ) begin
                doCacheLoad = 0;
                cacheHit = 0;
            end
            
            // don't care if cache is hit if this is a complete forward
            if (!(isExtMMIO || isIntMMIO) && IN_stFwd.mask == 4'b1111) begin
                cacheHit = 1;
                doCacheLoad = 0;
            end
        end

        if ((cacheHit || ld.exception != AGU_NO_EXCEPTION || isExtMMIO || isIntMMIO) && 
            (!loadWasExtIOBusy || isExtMMIO) &&
            (ld.exception != AGU_NO_EXCEPTION || isExtMMIO || isIntMMIO || !IN_stFwd.conflict)
        ) begin
            // Use forwarded store data if available
            if (!(isExtMMIO || isIntMMIO)) begin
                for (integer i = 0; i < `CASSOC; i=i+1) begin
                    if (IN_stFwd.mask[i]) readData[i*8+:8] = IN_stFwd.data[i*8+:8];
                end
            end
            
            OUT_uopLd.valid = 1;
            OUT_uopLd.storeSqN = 'x;
            OUT_uopLd.tagDst = ld.tagDst;
            OUT_uopLd.sqN = ld.sqN;
            OUT_uopLd.doNotCommit = ld.doNotCommit;
            //OUT_uopLd.external = ld.external;
            
            case (ld.exception)
                AGU_NO_EXCEPTION: OUT_uopLd.flags = FLAGS_NONE;
                AGU_ADDR_MISALIGN: OUT_uopLd.flags = FLAGS_LD_MA;
                AGU_ACCESS_FAULT: OUT_uopLd.flags = FLAGS_LD_AF;
                AGU_PAGE_FAULT: OUT_uopLd.flags = FLAGS_LD_PF;
            endcase

            case (ld.size)
                0: OUT_uopLd.result = 
                    {{24{ld.signExtend ? readData[8*(ld.addr[1:0])+7] : 1'b0}},
                    readData[8*(ld.addr[1:0])+:8]};

                1: OUT_uopLd.result = 
                    {{16{ld.signExtend ? readData[16*(ld.addr[1])+15] : 1'b0}},
                    readData[16*(ld.addr[1])+:16]};

                2: OUT_uopLd.result = readData;
                default: assert(0);
            endcase
        end
        else begin
            miss[0].valid = 1;
            if (IN_stFwd.conflict)
                miss[0].mtype = SQ_CONFLICT;
            else if (loadWasExtIOBusy)
                miss[0].mtype = IO_BUSY;
            else if (doCacheLoad)
                miss[0].mtype = noEvict ? REGULAR_NO_EVICT : REGULAR;
            else
                miss[0].mtype = TRANS_IN_PROG;
            miss[0].oldAddr = {IF_ct.rdata[0][assocCnt].addr, 12'b0};
            miss[0].missAddr = ld.addr;
            miss[0].assoc = assocCnt;
        end
    end
end

// Store Pipeline
reg[1:0] stConflictMiss;
reg[1:0] stConflictMiss_c;
reg stallStConflict;
always_ff@(posedge clk) begin
    if (rst) begin
        for (integer i = 0; i < 2; i=i+1)
            stOps[i].valid <= 0;
        stallStConflict <= 0;
    end
    else begin
        reg uopStStall = (isCacheBypassStUOp ? BLSU_stStall : stall[1]);

        stOps[0] <= 'x;
        stOps[0].valid <= 0;
        stOps[1] <= 'x;
        stOps[1].valid <= 0;
        
        // While a store is stalled, accumulate occurring conflicts
        if (uopSt.valid && uopStStall)
            stallStConflict <= stallStConflict | stConflictMiss_c[0];
        else stallStConflict <= 0;
        
        // Progress the delay line
        if (uopSt.valid && !uopStStall) begin
            stOps[0] <= uopSt;
            stConflictMiss[0] <= stConflictMiss_c[0] || stallStConflict;
        end
        
        if (stOps[0].valid) begin
            stOps[1] <= stOps[0];
            stConflictMiss[1] <= stConflictMiss_c[1];
        end
    end
end

// Store
reg setDirty;
reg[$clog2(SIZE)-1:0] setDirtyIdx;
always_comb begin
    ST_UOp st = stOps[1];
    reg cacheHit = 0;
    reg doCacheLoad = 1;
    reg[$clog2(`CASSOC)-1:0] cacheHitAssoc = 'x;
    reg noEvict = !IF_ct.rdata[1][assocCnt].valid;

    IF_cache.waddr = 'x;
    IF_cache.wassoc = 'x;
    IF_cache.wdata = 'x;
    IF_cache.wmask = 'x;
    IF_cache.we = 1;
    miss[1] = 'x;
    miss[1].valid = 0;

    setDirty = 0;
    setDirtyIdx = 'x;

    if (st.valid && !rst) begin
        
        // check for hit in cache table
        for (integer i = 0; i < `CASSOC; i=i+1) begin
            if (IF_ct.rdata[1][i].valid && IF_ct.rdata[1][i].addr == st.addr[31:12]) begin
                assert(!cacheHit); // multiple hits are invalid
                doCacheLoad = 0;
                cacheHit = 1;
                cacheHitAssoc = i[$clog2(`CASSOC)-1:0];
            end
        end

        // check if cache line is currently being transferred
        for (integer i = 0; i < 4; i=i+1) begin
            if (IN_memc.transfers[i].valid && IN_memc.transfers[i].cacheID == 0 &&
                IN_memc.transfers[i].newAddr[31:`CLSIZE_E] == st.addr[31:`CLSIZE_E]
            ) begin
                doCacheLoad = 0;
            cacheHit = 0;
            cacheHitAssoc = 'x;
        end
        end
        if (LSU_memc.cmd != MEMC_NONE && 
            LSU_memc.extAddr[31-2:`CLSIZE_E-2] == st.addr[31:`CLSIZE_E]
        ) begin
            doCacheLoad = 0;
            cacheHit = 0;
            cacheHitAssoc = 'x;
        end
        
        if (stConflictMiss[1]) begin
            miss[1].valid = 1;
            miss[1].oldAddr = 'x;
            miss[1].missAddr = 'x;
            miss[1].assoc = 'x;
            miss[1].mtype = CONFLICT;
        end
        else if (st.isMMIO) begin
            // nothing to do for MMIO
        end
        else if (st.wmask == 0) begin
            // Management Ops
            if (cacheHit) begin
                miss[1].valid = 1;
                miss[1].oldAddr = st.addr;
                miss[1].missAddr = st.addr;
                miss[1].assoc = cacheHitAssoc;
                case (st.data[1:0])
                    0: miss[1].mtype = MGMT_CLEAN;
                    1: miss[1].mtype = MGMT_INVAL;
                    2: miss[1].mtype = MGMT_FLUSH;
                    default: assert(0);
                endcase
            end
        end
        else begin
            // Unlike loads, we can only run stores
            // now that we're sure they hit cache.
            if (cacheHit) begin
                IF_cache.we = 0;
                IF_cache.waddr = st.addr[11:0];
                IF_cache.wassoc = cacheHitAssoc;
                IF_cache.wdata = st.data;
                IF_cache.wmask = st.wmask;
                setDirty = 1;
                setDirtyIdx = {cacheHitAssoc, st.addr[11:`CLSIZE_E]};
            end
            else begin
                miss[1].valid = 1;
                miss[1].mtype = doCacheLoad ? (noEvict ? REGULAR_NO_EVICT : REGULAR) : TRANS_IN_PROG;
                miss[1].oldAddr = {IF_ct.rdata[1][assocCnt].addr, 12'b0};
                miss[1].missAddr = st.addr;
                miss[1].assoc = assocCnt;
            end
        end
    end
end

// Store Conflict Misses
always_comb begin
    stConflictMiss_c[0] = (redoStore &&
        (stOps[1].addr[31:`CLSIZE_E] == uopSt.addr[31:`CLSIZE_E] ||
            stOps[1].isMMIO && uopSt.isMMIO));

    stConflictMiss_c[1] = (redoStore &&
        (stOps[1].addr[31:`CLSIZE_E] == stOps[0].addr[31:`CLSIZE_E] ||
            (stOps[1].isMMIO && stOps[0].isMMIO))) || 
        stConflictMiss[0];
end


// Cache Transfer State Machine
enum logic[3:0]
{
    IDLE, EVICT_RQ, EVICT_ACTIVE, LOAD_RQ, LOAD_ACTIVE, REPLACE_RQ, REPLACE_ACTIVE,
    FLUSH, FLUSH_RQ, FLUSH_ACTIVE, FLUSH_READ0, FLUSH_READ1, FLUSH_WAIT
} state;

reg LMQ_dequeue;

wire loadIsRegularMiss = miss[0].valid && miss[0].mtype != SQ_CONFLICT && miss[0].mtype != IO_BUSY;
wire LMQ_full;
LoadMissQueue#(4) loadMissQueue
(
    .clk(clk),
    .rst(rst),
    
    .IN_ready(state == IDLE),
    .IN_branch(IN_branch),
    
    .OUT_full(LMQ_full),

    .IN_memc(IN_memc),

    .IN_ld(curLd),
    .IN_enqueue(loadIsRegularMiss),

    .OUT_ld(LMQ_ld),
    .IN_dequeue(LMQ_dequeue)
);

always_comb begin
    OUT_ldAck = 'x;
    // We have to decide whether to place a missing load into the quick-to-react
    // load miss queue or back in the (slow) load buffer. If the LMQ is full, LB
    // is always chosen as fallback. Otherwise, regular misses are placed
    // in the LMQ.
    if (miss[0].valid &&
        (miss[0].mtype == SQ_CONFLICT ||
        miss[0].mtype == IO_BUSY ||
        (loadIsRegularMiss && LMQ_full))
    ) begin
        OUT_ldAck.valid = 1;
        OUT_ldAck.fail = 1;
        OUT_ldAck.external = curLd.external;
        OUT_ldAck.loadSqN = curLd.loadSqN;
    end
end

wire redoStore = stOps[1].valid &&
    (miss[1].valid ?
        (miss[1].mtype == REGULAR || miss[1].mtype == REGULAR_NO_EVICT || miss[1].mtype == IO_BUSY || miss[1].mtype == CONFLICT || miss[1].mtype == TRANS_IN_PROG) : 
        (!stOps[1].isMMIO && IF_cache.wbusy));

assign OUT_stAck.id = stOps[1].id;
assign OUT_stAck.valid = stOps[1].valid;
assign OUT_stAck.fail = redoStore;

// Cache Table Writes
reg cacheTableWrite;
always_comb begin
    reg temp = 0;
    cacheTableWrite = 0;
    IF_ct.we = 0;
    IF_ct.waddr = 'x;
    IF_ct.wassoc = 'x;
    IF_ct.wdata = 'x;
    
    if (!rst && state == IDLE) begin
        for (integer i = 0; i < 2; i=i+1) begin
            if (miss[i].valid && !temp && miss[i].mtype != IO_BUSY && miss[i].mtype != CONFLICT && miss[i].mtype != SQ_CONFLICT && miss[i].mtype != TRANS_IN_PROG) begin
                temp = 1;
                // Immediately write the new cache table entry (about to be loaded)
                // on a miss. We still need to intercept and pass through or stop
                // loads at the new address until the cache line is entirely loaded.
                case (miss[i].mtype)
                    REGULAR_NO_EVICT,
                    REGULAR: begin
                        IF_ct.we = 1;
                        IF_ct.waddr = miss[i].missAddr[11:0];
                        IF_ct.wassoc = miss[i].assoc;
                        IF_ct.wdata.addr = miss[i].missAddr[31:12];
                        IF_ct.wdata.valid = 1;
                        cacheTableWrite = 1;
                    end
                    
                    MGMT_INVAL,
                    MGMT_FLUSH: begin
                        IF_ct.we = 1;
                        IF_ct.waddr = miss[i].missAddr[11:0];
                        IF_ct.wassoc = miss[i].assoc;
                        IF_ct.wdata.addr = 0;
                        IF_ct.wdata.valid = 0;
                        cacheTableWrite = 1;
                    end
                    // MGMT_CLEAN does not modify cache table
                    default: ;
                endcase
            end
        end
    end
    else if (!rst && state == FLUSH) begin
        if (!flushDone) begin
            IF_ct.we = 1;
            IF_ct.waddr = {flushIdx, {`CLSIZE_E{1'b0}}};
            IF_ct.wassoc = flushAssocIdx;
            IF_ct.wdata.addr = 0;
            IF_ct.wdata.valid = 0;
            cacheTableWrite = 1;
        end
    end
end

// keep track of dirtyness here 
// (otherwise1 we would need a separate write port to cache table)
reg[SIZE-1:0] dirty;

reg flushQueued;
wire busy = (uopLd.valid || uopSt.valid || uopLd_0.valid || curLd.valid || stOps[0].valid || stOps[1].valid);
wire flushReady = IN_SQ_empty && !busy;
wire flushActive = (
    state == FLUSH || 
    state == FLUSH_READ0 || state == FLUSH_READ1);
assign OUT_busy = busy || flushQueued || flushActive;

reg flushDone;
reg[`CACHE_SIZE_E-`CLSIZE_E-$clog2(`CASSOC)-1:0] flushIdx;
reg[$clog2(`CASSOC)-1:0] flushAssocIdx;

// Cache<->Memory Transfer State Machine
CacheMiss curCacheMiss;
reg[$clog2(`CASSOC)-1:0] replaceAssoc;
always_ff@(posedge clk) begin
    
    // For now, we ignore MemC stalls and assume the command
    // was accepted. If not, both loads and stores are eventually
    // re-run. This is just problematic for MMIO and management ops.
    LSU_memc <= 'x;
    LSU_memc.cmd <= MEMC_NONE;

    if (rst) begin
        state <= IDLE;
        replaceAssoc <= 0;
        flushQueued <= 0;
    end
    else begin

        if (IN_flush) flushQueued <= 1;
        if (setDirty) dirty[setDirtyIdx] <= 1;

        case (state)
            IDLE: begin
                reg temp = 0;
                for (integer i = 0; i < 2; i=i+1) begin

                    reg[$clog2(SIZE)-1:0] missIdx = {miss[i].assoc, miss[i].missAddr[11:`CLSIZE_E]};
                    MissType missType = miss[i].mtype;

                    if (miss[i].valid && !temp && miss[i].mtype != IO_BUSY && miss[i].mtype != CONFLICT && miss[i].mtype != SQ_CONFLICT) begin
                        temp = 1;
                        curCacheMiss <= miss[i];
                        assocCnt <= assocCnt + 1;
                        
                        // if not dirty, do not copy back to main memory
                        if (missType == REGULAR && !dirty[missIdx] && (!setDirty || setDirtyIdx != missIdx))
                            missType = REGULAR_NO_EVICT;
                        
                        // new cache line is not dirty
                        dirty[missIdx] <= 0;
                        
                        case (missType)
                            REGULAR: begin
                                LSU_memc.cmd <= MEMC_CP_CACHE_TO_EXT;
                                LSU_memc.sramAddr <= {miss[i].assoc, miss[i].missAddr[11:2]};
                                LSU_memc.extAddr <= {miss[i].oldAddr[31:12], miss[i].missAddr[11:2]};
                                LSU_memc.cacheID <= 0;
                                LSU_memc.rqID <= 0;
                            end

                            REGULAR_NO_EVICT: begin
                                LSU_memc.cmd <= MEMC_CP_EXT_TO_CACHE;
                                LSU_memc.sramAddr <= {miss[i].assoc, miss[i].missAddr[11:2]};
                                LSU_memc.extAddr <= {miss[i].missAddr[31:2]};
                                LSU_memc.cacheID <= 0;
                                LSU_memc.rqID <= 0;
                            end

                            MGMT_CLEAN,
                            MGMT_FLUSH: begin
                                LSU_memc.cmd <= MEMC_CP_CACHE_TO_EXT;
                                LSU_memc.sramAddr <= {miss[i].assoc, miss[i].missAddr[11:2]};
                                LSU_memc.extAddr <= {miss[i].oldAddr[31:12], miss[i].missAddr[11:2]};
                                LSU_memc.cacheID <= 0;
                                LSU_memc.rqID <= 0;
                            end
                            
                            default: ; // MGMT_INVAL does not evict the cache line
                        endcase
                    end
                end

                if (!temp) begin
                    if (flushQueued && flushReady) begin
                        state <= FLUSH_READ1;
                        flushQueued <= 0;
                        flushIdx <= 0;
                        flushAssocIdx <= 0;
                        flushDone <= 0;
                    end
                end
            end

            FLUSH_READ0, FLUSH_READ1: begin
                // wait two cycles to read from cache table...
                state <= (state == FLUSH_READ0) ? FLUSH : FLUSH_READ0;
            end
            FLUSH: begin
                if (flushDone) begin
                    state <= IDLE;
                end
                else begin
                    
                    CTEntry entry = IF_ct.rdata[0][flushAssocIdx];
                    if (entry.valid && dirty[{flushAssocIdx, flushIdx}]) begin
                        LSU_memc.cmd <= MEMC_CP_CACHE_TO_EXT;
                        LSU_memc.sramAddr <= {flushAssocIdx, flushIdx, {(`CLSIZE_E-2){1'b0}}};
                        LSU_memc.extAddr <= {entry.addr, flushIdx, {(`CLSIZE_E-2){1'b0}}};
                        LSU_memc.cacheID <= 0;
                        LSU_memc.rqID <= 0;
                    end
                    else if (&flushAssocIdx) state <= FLUSH_READ1;

                    {flushDone, flushIdx, flushAssocIdx} <= {flushIdx, flushAssocIdx} + 1;
                end
            end
            default: state <= IDLE;
        endcase
    end
end

endmodule
