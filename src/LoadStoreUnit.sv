
// [0] -> transfer exists; [1] -> allow pass thru
function automatic logic[1:0] CheckTransfers(MemController_Req memcReq, MemController_Res memcRes, CacheID_t cacheID, logic[31:0] addr, logic isStore);
    logic[1:0] rv = 0;

    for (integer i = 0; i < `AXI_NUM_TRANS; i=i+1) begin
        if (memcRes.transfers[i].valid &&
            memcRes.transfers[i].cacheID == cacheID &&
            memcRes.transfers[i].readAddr[31:`CLSIZE_E] == addr[31:`CLSIZE_E]
        ) begin
            rv[0] = 1;
            rv[1] = (memcRes.transfers[i].progress) >
                ({1'b0, addr[`CLSIZE_E-1:2]} - {1'b0, memcRes.transfers[i].readAddr[`CLSIZE_E-1:2]});
        end
    end

    if ((memcReq.cmd == MEMC_REPLACE || memcReq.cmd == MEMC_CP_EXT_TO_CACHE) &&
        memcReq.readAddr[31:`CLSIZE_E] == addr[31:`CLSIZE_E] &&
        memcReq.cacheID == cacheID
    ) begin
        rv = 2'b01;
    end

    return rv;
endfunction

module LoadStoreUnit
#(
    parameter SIZE=(1<<(`CACHE_SIZE_E - `CLSIZE_E))
)
(
    input wire clk,
    input wire rst,

    input wire IN_flush,
    input wire IN_SQ_empty,
    output wire OUT_busy,

    input BranchProv IN_branch,
    output reg OUT_ldAGUStall[NUM_AGUS-1:0],
    output reg OUT_ldStall[NUM_AGUS-1:0],
    output wire OUT_stStall,

    // regular loads come through these two
    // structs. uopELd provides the lower 12 addr bits
    // one cycle early.
    input ELD_UOp IN_uopELd[NUM_AGUS-1:0],
    input LD_UOp IN_aguLd[NUM_AGUS-1:0],

    input LD_UOp IN_uopLd[NUM_AGUS-1:0], // special loads (page walk, non-speculative)
    output LD_UOp OUT_uopLdSq[NUM_AGUS-1:0],
    output LD_Ack OUT_ldAck[NUM_AGUS-1:0],

    input ST_UOp IN_uopSt,

    IF_Cache.HOST IF_cache,
    IF_MMIO.HOST IF_mmio,
    IF_CTable.HOST IF_ct,

    input StFwdResult IN_sqStFwd[NUM_AGUS-1:0],
    input StFwdResult IN_sqbStFwd[NUM_AGUS-1:0],
    output ST_Ack OUT_stAck,

    output MemController_Req OUT_memc,
    output MemController_Req OUT_BLSU_memc,
    input MemController_Res IN_memc,

    input wire[NUM_AGUS-1:0] IN_ready,
    output RES_UOp OUT_uopLd[NUM_AGUS-1:0]
);

LoadResUOp ldResUOp[NUM_AGUS-1:0];

MemController_Req BLSU_memc;
MemController_Req LSU_memc;
assign OUT_memc = LSU_memc;
assign OUT_BLSU_memc = BLSU_memc;

logic[NUM_AGUS-1:0] isCacheBypassLdUOp;
always_comb begin
    for (integer i = 0; i < NUM_AGUS; i=i+1)
        isCacheBypassLdUOp[i] =
            `ENABLE_EXT_MMIO && uopLd_0[i].valid && uopLd_0[i].isMMIO && uopLd_0[i].exception == AGU_NO_EXCEPTION &&
            uopLd_0[i].addr >= `EXT_MMIO_START_ADDR && uopLd_0[i].addr < `EXT_MMIO_END_ADDR;
end


wire isCacheBypassStUOp =
    `ENABLE_EXT_MMIO && IN_uopSt.valid && IN_uopSt.isMMIO &&
    IN_uopSt.addr >= `EXT_MMIO_START_ADDR && IN_uopSt.addr < `EXT_MMIO_END_ADDR;

wire ignoreSt = isCacheBypassStUOp;

wire[$clog2(NUM_AGUS)-1:0] blsuLdIdx;
wire blsuLdIdxValid;
 OHEncoder#(NUM_AGUS, 1) ohEnc(
    .IN_idxOH(isCacheBypassLdUOp), .OUT_idx(blsuLdIdx), .OUT_valid(blsuLdIdxValid));

wire BLSU_stStall;
wire BLSU_ldStall;
LD_UOp BLSU_uopLd;
wire[31:0] BLSU_ldResult;
BypassLSU bypassLSU
(
    .clk(clk),
    .rst(rst),

    .IN_branch(IN_branch),
    .IN_uopLdEn(blsuLdIdxValid),
    .OUT_ldStall(BLSU_ldStall),
    .IN_uopLd(uopLd_0[blsuLdIdx]),

    .IN_uopStEn(isCacheBypassStUOp && !OUT_stStall),
    .OUT_stStall(BLSU_stStall),
    .IN_uopSt(IN_uopSt),

    .IN_ldStall(!blsuLoadHandled),
    .OUT_uopLd(BLSU_uopLd),
    .OUT_ldData(BLSU_ldResult),

    .OUT_memc(BLSU_memc),
    .IN_memc(IN_memc)
);

StFwdResult stFwd[NUM_AGUS-1:0];
always_comb begin
    for (integer i = 0; i < NUM_AGUS; i=i+1) begin
        stFwd[i] = IN_sqbStFwd[i];
        stFwd[i].mask |= IN_sqStFwd[i].mask;
        stFwd[i].conflict |= IN_sqStFwd[i].conflict;
        for (integer j = 0; j < 4; j=j+1)
            if (IN_sqStFwd[i].mask[j])
                stFwd[i].data[8*j+:8] = IN_sqStFwd[i].data[8*j+:8];
    end
end

// During a cache table write cycle, we cannot issue a store as
// the cache table write port is the same as the store read port.
// Loads work fine but require write forwaring in the cache table.
assign OUT_stStall = ((isCacheBypassStUOp ? BLSU_stStall : (cacheTableWrite || flushActive)) || !uopStPortValid) && IN_uopSt.valid;

reg[$clog2(NUM_AGUS)-1:0] uopStPort;
reg uopStPortValid;

always_comb begin
    uopStPort = 0;
    uopStPortValid = 0;
    if (!uopLd[0].valid) begin
        uopStPortValid = 1;
    end
end

LD_UOp uopLd[NUM_AGUS-1:0];
always_comb
    for (integer i = 0; i < NUM_AGUS; i=i+1)
        OUT_uopLdSq[i] = uopLd_0[i];

ST_UOp uopSt;
assign uopSt = IN_uopSt;

// Both load and store read from cache table
always_comb begin

    IF_ct.re[0] = uopLd[0].valid && !uopLd[0].isMMIO && uopLd[0].exception == AGU_NO_EXCEPTION;
    IF_ct.raddr[0] = uopLd[0].addr[`VIRT_IDX_LEN-1:0];

    IF_ct.re[1] = uopLd[1].valid && !uopLd[1].isMMIO && uopLd[1].exception == AGU_NO_EXCEPTION;
    IF_ct.raddr[1] = uopLd[1].addr[`VIRT_IDX_LEN-1:0];

    if (uopStPortValid) begin
        IF_ct.re[uopStPort] = uopSt.valid && !uopSt.isMMIO && !(isCacheBypassStUOp || OUT_stStall) && !ignoreSt;
        IF_ct.raddr[uopStPort] = uopSt.addr[`VIRT_IDX_LEN-1:0];
    end

    // During a flush, we read from the cache table at the flush iterator
    if (state == FLUSH_READ0) begin
        IF_ct.re[0] = 1;
        IF_ct.raddr[0] = {flushIdx, {`CLSIZE_E{1'b0}}};
    end
end

reg[$clog2(NUM_AGUS)-1:0] startIdx;
always_ff@(posedge clk)
    startIdx <= rst ? 0 : (startIdx + 1);

// Stores only go through port 0. To still make port
// pressure even we shuffle incoming loads.
reg[NUM_AGUS-1:0][$clog2(NUM_AGUS)-1:0] idxs_c;
always_comb begin
    for (integer i = 0; i < NUM_AGUS; i=i+1)
        idxs_c[i] = startIdx + $clog2(NUM_AGUS)'(i);
end

reg[NUM_AGUS-1:0][$clog2(NUM_AGUS)-1:0] idxs_r;
always_ff@(posedge clk) idxs_r <= idxs_c;

reg[NUM_AGUS-1:0] regularLd_c;
reg[NUM_AGUS-1:0] regularLd_r;
always_ff@(posedge clk) regularLd_r <= rst ? '0 : regularLd_c;

// Select load to execute
// 1. special load (page walk, non-speculative or external)
// 2. regular load
always_comb begin

    for (integer i = 0; i < NUM_AGUS; i=i+1) begin
        OUT_ldStall[i] = IN_uopLd[i].valid;
        OUT_ldAGUStall[i] = IN_uopELd[i].valid;
    end

    for (integer i = NUM_AGUS-1; i >= 0; i=i-1) begin
        reg[$clog2(NUM_AGUS)-1:0] idx = idxs_c[i];

        uopLd[i] = 'x;
        uopLd[i].valid = 0;
        regularLd_c[i] = 0;

        // Only addr[11:0] is well defined, the rest is
        // still being calculated (for regular loads at least) and will
        // only be available in the next cycle.

        if (flushActive) begin
            // do not issue load
        end
        else if (i[$clog2(NUM_AGUS)-1:0] == stOpPort[1] && stOps[1].valid) begin
            // port is being used by store during store's write cycle
        end
        else if (i == 1 && cacheTableWrite) begin
            // cache table port is being used to handle cache miss
        end
        else if (IN_uopLd[idx].valid &&
            (!IN_branch.taken || IN_uopLd[idx].external || $signed(IN_uopLd[idx].sqN - IN_branch.sqN) <= 0) &&
            (!IF_cache.busy[i] || IF_cache.rbusyBank[i] != IN_uopLd[idx].addr[2 + $clog2(`CWIDTH) +: $clog2(`CBANKS)])
        ) begin
            // todo: do not check busy for MMIO and forwards
            uopLd[i] = IN_uopLd[idx];
            OUT_ldStall[idx] = 0;
        end
        else if (IN_uopELd[idx].valid &&
            (!IF_cache.busy[i] || IF_cache.rbusyBank[i] != IN_uopELd[idx].addr[2 + $clog2(`CWIDTH) +: $clog2(`CBANKS)])
        ) begin
            uopLd[i].valid = 1;
            uopLd[i].external = 0;
            uopLd[i].addr[11:0] = IN_uopELd[idx].addr;

            uopLd[i].isMMIO = 0; // assume that this is not MMIO such that cache is read
            uopLd[i].exception = AGU_NO_EXCEPTION; // assume no exception

            OUT_ldAGUStall[idx] = 0;
            regularLd_c[i] = 1;
        end
    end
end

LD_UOp uopLd_0[NUM_AGUS-1:0];
always_comb begin
    for (integer i = 0; i < NUM_AGUS; i=i+1) begin
        reg[$clog2(NUM_AGUS)-1:0] idx = idxs_r[i];
        uopLd_0[i] = ldOps[i][0];

        // For regular loads, we only get the full address and other
        // info now.
        if (regularLd_r[i]) begin
            assert(rst || !IN_aguLd[idx].valid || IN_aguLd[idx].addr[11:0] == uopLd_0[i].addr[11:0]);

            uopLd_0[i] = 'x;
            uopLd_0[i].valid = 0;
            if (IN_aguLd[idx].valid)
                uopLd_0[i] = IN_aguLd[idx];
        end
    end
end

// Load from internal MMIO
// This is executed one cycle later than loads from cache
// as internal MMIO only has a read delay of one cycle.
always_comb begin
    IF_mmio.re = 1;
    IF_mmio.raddr = 'x;
    IF_mmio.rsize = 'x;

    for (integer i = 0; i < NUM_AGUS; i=i+1)
        if (uopLd_0[i].valid && uopLd_0[i].isMMIO && !isCacheBypassLdUOp[i]) begin
            IF_mmio.re = 0;
            IF_mmio.raddr = uopLd_0[i].addr;
            IF_mmio.rsize = uopLd_0[i].size;
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
        IF_mmio.wdata = uopSt.data[31:0];
        IF_mmio.wmask = uopSt.wmask[3:0];
    end
end

// delay lines, waiting for cache response
LD_UOp ldOps[NUM_AGUS-1:0][1:0];
ST_UOp stOps[1:0];
reg[$clog2(NUM_AGUS)-1:0] stOpPort[1:0];

reg loadWasExtIOBusy[NUM_AGUS-1:0];
reg[1:0] loadCacheAccessFailed[NUM_AGUS-1:0];

// Load Pipeline
always_ff@(posedge clk) begin

    for (integer i = 0; i < NUM_AGUS; i=i+1)
        for (integer j = 0; j < 2; j=j+1) begin
            ldOps[i][j] <= 'x;
            ldOps[i][j].valid <= 0;
        end

    if (rst) ;
    else begin
        for (integer i = 0; i < NUM_AGUS; i=i+1) begin
            // Progress the delay line
            if (uopLd[i].valid) begin
                ldOps[i][0] <= uopLd[i];
                loadCacheAccessFailed[i][0] <= IF_cache.busy[i];
            end

            if (uopLd_0[i].valid && (!IN_branch.taken || uopLd_0[i].external || $signed(uopLd_0[i].sqN - IN_branch.sqN) <= 0) &&
                // if the BLSU is busy, we place the OP in the Load Miss Queue.
                (!isCacheBypassLdUOp[i] || BLSU_ldStall)
            ) begin
                ldOps[i][1] <= uopLd_0[i];
                loadWasExtIOBusy[i] <= isCacheBypassLdUOp[i];
                loadCacheAccessFailed[i][1] <= loadCacheAccessFailed[i][0];
            end
        end
    end
end

// Cache Access
always_comb begin
    // Loads speculatively load from all possible locations
    for (integer i = 0; i < NUM_AGUS; i=i+1) begin

        IF_cache.addr[i] = 'x;
        IF_cache.wdata[i] = 'x;
        IF_cache.wmask[i] = 'x;
        IF_cache.wassoc[i] = 'x;
        IF_cache.we[i] = 1;
        IF_cache.re[i] = 1;

        IF_cache.re[i] = !(uopLd[i].valid && !uopLd[i].isMMIO && uopLd[i].exception == AGU_NO_EXCEPTION);
        IF_cache.addr[i] = uopLd[i].addr[`VIRT_IDX_LEN-1:0];
    end

    if (storeWriteToCache) begin
        IF_cache.we[stOpPort[1]] = 0;
        IF_cache.re[stOpPort[1]] = 0;
        IF_cache.addr[stOpPort[1]] = stOps[1].addr[`VIRT_IDX_LEN-1:0];
        IF_cache.wassoc[stOpPort[1]] = storeWriteAssoc;
        IF_cache.wdata[stOpPort[1]] = stOps[1].data;
        IF_cache.wmask[stOpPort[1]] = stOps[1].wmask;
    end
end


typedef enum logic[3:0]
{
    REGULAR, REGULAR_NO_EVICT, TRANS_IN_PROG, MGMT_CLEAN, MGMT_INVAL, MGMT_FLUSH, IO_BUSY, SQ_CONFLICT
} MissType;

typedef struct packed
{
    logic[31:0] writeAddr;
    logic[31:0] missAddr;
    logic[$clog2(`CASSOC)-1:0] assoc;
    MissType mtype;
    logic valid;
} CacheMiss;

CacheMiss miss[NUM_AGUS-1:0];

reg storeWriteToCache;
reg[$clog2(`CASSOC)-1:0] storeWriteAssoc;

reg setDirty;
reg[$clog2(SIZE)-1:0] setDirtyIdx;
// Process Cache Table Read Responses
LD_UOp curLd[NUM_AGUS-1:0];
reg blsuLoadHandled;
always_comb begin

    blsuLoadHandled = 0;

    setDirty = 0;
    setDirtyIdx = 'x;

    storeWriteToCache = 0;
    storeWriteAssoc = 'x;

    for (integer i = 0; i < NUM_AGUS; i=i+1)
        ldResUOp[i] = LoadResUOp'{valid: 0, default: 'x};

    for (integer i = 0; i < NUM_AGUS; i=i+1) begin
        miss[i] = 'x;
        miss[i].valid = 0;
    end

    for (integer i = 0; i < NUM_AGUS; i=i+1) begin

        // only one of these is valid
        LD_UOp ld = ldOps[i][1];
        ST_UOp st = (i[$clog2(NUM_AGUS)-1:0] == stOpPort[1]) ? stOps[1] : ST_UOp'{valid: 0, default: 'x};
        assert(!(ld.valid && st.valid));

        if (!ld.valid && !st.valid && !blsuLoadHandled)
            ld = BLSU_uopLd;

        curLd[i] = ld;

        if (rst) ; // todo: really needed?
        else if (st.valid) begin
            reg cacheHit = 0;
            reg cacheTableHit = 1;
            reg doCacheLoad = 1;
            reg[$clog2(`CASSOC)-1:0] cacheHitAssoc = 'x;
            reg noEvict = !IF_ct.rdata[i][assocCnt].valid;

            // check for hit in cache table
            for (integer j = 0; j < `CASSOC; j=j+1) begin
                if (IF_ct.rdata[i][j].valid && IF_ct.rdata[i][j].addr == st.addr[31:`VIRT_IDX_LEN]) begin
                    assert(!cacheHit); // multiple hits are invalid
                    doCacheLoad = 0;
                    cacheHit = 1;
                    cacheHitAssoc = j[$clog2(`CASSOC)-1:0];
                    cacheTableHit = 1;
                end
            end

            // check if address is already being transferred
            begin
                reg transferExists;
                reg allowPassThru;
                {allowPassThru, transferExists} = CheckTransfers(LSU_memc, IN_memc, 0, st.addr, 1);
                if (transferExists) begin
                    doCacheLoad = 0; // this is only needed for one cycle
                    cacheHit &= allowPassThru;
                end
            end

            // check for conflict with currently issued MemC_Cmd
            if (cacheHit &&
                LSU_memc.cmd != MEMC_NONE &&
                LSU_memc.cacheAddr[`CACHE_SIZE_E-3:`CLSIZE_E-2] == {cacheHitAssoc, st.addr[`VIRT_IDX_LEN-1:`CLSIZE_E]}
            ) begin
                cacheHit = 0;
                cacheHitAssoc = 'x;
                cacheTableHit = 1;
                doCacheLoad = 0;
            end

            if (st.isMMIO) begin
                // nothing to do for MMIO
            end
            else if (st.wmask == 0) begin
                // Management Ops
                if (cacheTableHit) begin
                    miss[i].valid = 1;
                    miss[i].writeAddr = st.addr;
                    miss[i].missAddr = st.addr;
                    miss[i].assoc = cacheHitAssoc;
                    case (st.data[1:0])
                        0: miss[i].mtype = MGMT_CLEAN;
                        1: miss[i].mtype = MGMT_INVAL;
                        2: miss[i].mtype = MGMT_FLUSH;
                        default: assert(0);
                    endcase
                end
            end
            else begin
                // Unlike loads, we can only run stores
                // now that we're sure they hit cache.
                if (cacheHit) begin
                    storeWriteToCache = 1;
                    storeWriteAssoc = cacheHitAssoc;
                    setDirty = 1;
                    setDirtyIdx = {cacheHitAssoc, st.addr[`VIRT_IDX_LEN-1:`CLSIZE_E]};
                end
                else begin
                    miss[i].valid = 1;
                    miss[i].mtype = doCacheLoad ? (noEvict ? REGULAR_NO_EVICT : REGULAR) : TRANS_IN_PROG;
                    miss[i].writeAddr = {IF_ct.rdata[i][assocCnt].addr, st.addr[`VIRT_IDX_LEN-1:0]};
                    miss[i].missAddr = st.addr;
                    miss[i].assoc = assocCnt;
                end
            end
        end
        else if (ld.valid) begin
            reg isExtMMIO = !ldOps[i][1].valid;
            reg isIntMMIO = ld.valid && ld.isMMIO;
            reg noEvict = !IF_ct.rdata[i][assocCnt].valid;
            reg doCacheLoad = 1;

            reg cacheHit = 0;
            reg[31:0] readData = 'x;

            if (ld.dataValid) begin
                readData = ld.data;
            end
            else if (isExtMMIO) begin
                readData = BLSU_ldResult;
                blsuLoadHandled = 1;
            end
            else if (isIntMMIO) begin
                readData = IF_mmio.rdata;
            end
            else begin
                for (integer j = 0; j < `CASSOC; j=j+1) begin
                    if (IF_ct.rdata[i][j].valid && IF_ct.rdata[i][j].addr == ld.addr[31:`VIRT_IDX_LEN]) begin
                        cacheHit = 1;
                        doCacheLoad = 0;
                        readData = IF_cache.rdata[i][j];
                    end
                end

                // check if address is already being transferred
                begin
                    reg transferExists;
                    reg allowPassThru;
                    {allowPassThru, transferExists} = CheckTransfers(LSU_memc, IN_memc, 0, ld.addr, 0);
                    if (transferExists) begin
                        doCacheLoad = 0;
                        cacheHit &= allowPassThru;
                    end
                end

                // don't care if cache is hit if this is a complete forward
                if (!(isExtMMIO || isIntMMIO) && stFwd[i].mask == 4'b1111) begin
                    cacheHit = 1;
                    doCacheLoad = 0;
                end
            end

            // defaults
            ldResUOp[i].doNotCommit = ld.doNotCommit;
            ldResUOp[i].external = ld.external;
            ldResUOp[i].sqN = ld.sqN;
            ldResUOp[i].tagDst = ld.tagDst;
            ldResUOp[i].exception = ld.exception;
            ldResUOp[i].sext = ld.signExtend;
            ldResUOp[i].size = ld.size;
            ldResUOp[i].addr = ld.addr;

            if ((!loadCacheAccessFailed[i][1] || ld.exception != AGU_NO_EXCEPTION || isExtMMIO || isIntMMIO || ld.dataValid) &&
                (cacheHit || ld.exception != AGU_NO_EXCEPTION || isExtMMIO || isIntMMIO || ld.dataValid) &&
                (!loadWasExtIOBusy[i] || isExtMMIO) &&
                (ld.exception != AGU_NO_EXCEPTION || isExtMMIO || isIntMMIO || !stFwd[i].conflict)
            ) begin
                // Use forwarded store data if available
                if (!(isExtMMIO || isIntMMIO)) begin
                    for (integer j = 0; j < 4; j=j+1) begin
                        if (stFwd[i].mask[j]) readData[j*8+:8] = stFwd[i].data[j*8+:8];
                    end
                end

                ldResUOp[i].valid = 1;
                ldResUOp[i].dataAvail = 1;
                ldResUOp[i].fwdMask = 4'b1111;
                ldResUOp[i].data = readData;
            end
            else begin
                // Signal Miss
                miss[i].valid = 1;
                if (stFwd[i].conflict)
                    miss[i].mtype = SQ_CONFLICT;
                else if (loadWasExtIOBusy[i])
                    miss[i].mtype = IO_BUSY;
                else if (doCacheLoad)
                    miss[i].mtype = noEvict ? REGULAR_NO_EVICT : REGULAR;
                else if (loadCacheAccessFailed[i][1])
                    miss[i].mtype = IO_BUSY;
                else
                    miss[i].mtype = TRANS_IN_PROG;
                miss[i].writeAddr = {IF_ct.rdata[i][assocCnt].addr, ld.addr[`VIRT_IDX_LEN-1:0]};
                miss[i].missAddr = ld.addr;
                miss[i].assoc = assocCnt;

                if (miss[i].mtype == TRANS_IN_PROG ||
                    miss[i].mtype == REGULAR ||
                    miss[i].mtype == REGULAR_NO_EVICT
                ) begin
                    ldResUOp[i].valid = 1;
                    ldResUOp[i].dataAvail = 0;
                    ldResUOp[i].fwdMask = stFwd[i].mask;
                    ldResUOp[i].data = stFwd[i].data;
                end
            end
        end
    end
end

// Load Result Buffering
wire LRB_ready[NUM_AGUS-1:0];
LoadResUOp LRB_uop[NUM_AGUS-1:0];
LoadResultBuffer#(`LRB_SIZE) loadResBuf[NUM_AGUS-1:0]
(
    .clk(clk),
    .rst(rst),

    .IN_memc(IN_memc),
    .IN_branch(IN_branch),

    .IN_uop(LRB_uop),
    .OUT_ready(LRB_ready),

    .IN_ready(IN_ready),
    .OUT_uop(OUT_uopLd)
);

// Store Pipeline
always_ff@(posedge clk) begin
    if (rst) begin
        for (integer i = 0; i < 2; i=i+1)
            stOps[i].valid <= 0;
    end
    else begin
        stOps[0] <= 'x;
        stOps[0].valid <= 0;
        stOps[1] <= 'x;
        stOps[1].valid <= 0;

        // Progress the delay line
        if (uopSt.valid && !OUT_stStall) begin
            stOps[0] <= uopSt;
            stOpPort[0] <= uopStPort;
        end

        if (stOps[0].valid) begin
            stOps[1] <= stOps[0];
            stOpPort[1] <= stOpPort[0];
        end
    end
end

// Cache Transfer State Machine
enum logic[3:0]
{
    IDLE, FLUSH, FLUSH_READ0, FLUSH_READ1, FLUSH_WAIT
} state;

// Place load in LoadResultBuffer or reactivate back in LoadBuffer via negative ack
for (genvar i = 0; i < NUM_AGUS; i=i+1) begin
    always_comb begin
        OUT_ldAck[i] = LD_Ack'{valid: 0, default: 'x};
        LRB_uop[i] = LoadResUOp'{valid: 0, default: 'x};

        if (ldResUOp[i].valid && (LRB_ready[i]) && (!miss[i].valid || forwardMiss[i])) begin
            LRB_uop[i] = ldResUOp[i];
        end
        else if (curLd[i].valid) begin
            OUT_ldAck[i].valid = 1;
            OUT_ldAck[i].fail = 1;
            OUT_ldAck[i].external = curLd[i].external;
            OUT_ldAck[i].loadSqN = curLd[i].loadSqN;
            OUT_ldAck[i].addr = curLd[i].addr;

            OUT_ldAck[i].doNotReIssue = 0;
            if (miss[i].valid && (!stOps[1].valid || stOpPort[1] != i)) begin
                if (miss[i].mtype == TRANS_IN_PROG) begin
                    OUT_ldAck[i].doNotReIssue = 1;
                end
                else if (miss[i].mtype == REGULAR || miss[i].mtype == REGULAR_NO_EVICT) begin
                    OUT_ldAck[i].doNotReIssue = forwardMiss[i] && !missEvictConflict[i];
                end
            end
        end
    end
end


wire redoStore = stOps[1].valid &&
    (miss[stOpPort[1]].valid ?
        (miss[stOpPort[1]].mtype == REGULAR ||
         miss[stOpPort[1]].mtype == REGULAR_NO_EVICT ||
         miss[stOpPort[1]].mtype == IO_BUSY ||
         miss[stOpPort[1]].mtype == TRANS_IN_PROG ||
         ((miss[stOpPort[1]].mtype == MGMT_CLEAN ||
           miss[stOpPort[1]].mtype == MGMT_FLUSH ||
           miss[stOpPort[1]].mtype == MGMT_INVAL) &&
          (!forwardMiss[stOpPort[1]] || missEvictConflict[stOpPort[1]]))
    ) :
        (!stOps[1].isMMIO &&
         IF_cache.busy[stOpPort[1]] &&
         IF_cache.rbusyBank[stOpPort[1]] == stOps[1].addr[2 + $clog2(`CWIDTH) +: $clog2(`CBANKS)]));

wire fuseStoreMiss = !missEvictConflict[stOpPort[1]] && (miss[stOpPort[1]].mtype == REGULAR || miss[stOpPort[1]].mtype == REGULAR_NO_EVICT) && forwardMiss[stOpPort[1]] && miss[stOpPort[1]].valid;

assign OUT_stAck.addr = stOps[1].addr;
assign OUT_stAck.data = stOps[1].data;
assign OUT_stAck.wmask = stOps[1].wmask;
assign OUT_stAck.nonce = stOps[1].nonce;
assign OUT_stAck.idx = stOps[1].id;
assign OUT_stAck.valid = stOps[1].valid;
assign OUT_stAck.fail = redoStore && !fuseStoreMiss;


// Check for conflicts
logic[NUM_AGUS-1:0] missEvictConflict;
always_comb begin
    for (integer i = 0; i < NUM_AGUS; i=i+1) begin
        missEvictConflict[i] = 0;

        // read after write
        for (integer j = 0; j < `AXI_NUM_TRANS; j=j+1) begin
            if (miss[i].valid &&
                IN_memc.transfers[j].valid &&
                IN_memc.transfers[j].writeAddr[31:`CLSIZE_E] == miss[i].missAddr[31:`CLSIZE_E]
            ) begin
                missEvictConflict[i] = 1;
            end
        end
        if ((LSU_memc.cmd == MEMC_REPLACE || LSU_memc.cmd == MEMC_CP_CACHE_TO_EXT) &&
            miss[i].valid && LSU_memc.writeAddr[31:`CLSIZE_E] == miss[i].missAddr[31:`CLSIZE_E])
            missEvictConflict[i] = 1;

        // write after read
        for (integer j = 0; j < `AXI_NUM_TRANS; j=j+1) begin
            if (miss[i].valid &&
                IN_memc.transfers[j].valid &&
                IN_memc.transfers[j].readAddr[31:`CLSIZE_E] == miss[i].writeAddr[31:`CLSIZE_E]
            ) begin
                missEvictConflict[i] = 1;
            end
        end

        // transaction on this cache line is in progress
        for (integer j = 0; j < `AXI_NUM_TRANS; j=j+1) begin
            if (miss[i].valid &&
                IN_memc.transfers[j].valid &&
                IN_memc.transfers[j].cacheID == 0 &&
                IN_memc.transfers[j].cacheAddr[`CACHE_SIZE_E-3 : `CLSIZE_E-2] == {miss[i].assoc, miss[i].missAddr[`VIRT_IDX_LEN-1:`CLSIZE_E]}
            ) begin
                missEvictConflict[i] = 1;
            end
        end


        if ((LSU_memc.cmd == MEMC_REPLACE || LSU_memc.cmd == MEMC_CP_EXT_TO_CACHE) &&
            miss[i].valid && LSU_memc.readAddr[31:`CLSIZE_E] == miss[i].writeAddr[31:`CLSIZE_E])
            missEvictConflict[i] = 1;

        if ((LSU_memc.cmd == MEMC_REPLACE || LSU_memc.cmd == MEMC_CP_EXT_TO_CACHE || LSU_memc.cmd == MEMC_CP_CACHE_TO_EXT) &&
            miss[i].valid && LSU_memc.cacheAddr[`CACHE_SIZE_E-3 : `CLSIZE_E-2] == {miss[i].assoc, miss[i].missAddr[`VIRT_IDX_LEN-1:`CLSIZE_E]})
            missEvictConflict[i] = 1;

    end
end

// Cache Table Writes
reg cacheTableWrite;
reg newMiss;
always_comb begin;
    cacheTableWrite = 0;
    IF_ct.we = 0;
    IF_ct.waddr = 'x;
    IF_ct.wdata = 'x;
    IF_ct.wassoc = 'x;
    newMiss = 0;

    if (!rst && state == IDLE) begin
        for (integer i = 0; i < NUM_AGUS; i=i+1) begin
            if (forwardMiss[i]) begin
                newMiss = 1;
                // Immediately write the new cache table entry (about to be loaded)
                // on a miss. We still need to intercept and pass through or stop
                // loads at the new address until the cache line is entirely loaded.
                case (miss[i].mtype)
                    REGULAR_NO_EVICT,
                    REGULAR: begin
                        IF_ct.we = 1;
                        IF_ct.waddr = miss[i].missAddr[`VIRT_IDX_LEN-1:0];
                        IF_ct.wassoc = miss[i].assoc;
                        IF_ct.wdata.addr = miss[i].missAddr[31:`VIRT_IDX_LEN];
                        IF_ct.wdata.valid = 1;
                        cacheTableWrite = 1;
                    end

                    MGMT_INVAL,
                    MGMT_FLUSH: begin
                        IF_ct.we = 1;
                        IF_ct.waddr = miss[i].missAddr[`VIRT_IDX_LEN-1:0];
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
// (otherwise we would need a separate write port to cache table)
reg[SIZE-1:0] dirty;

reg flushQueued;
reg initialFlush;
reg busy;
always_comb begin
    busy = 0;
    for (integer i = 0; i < NUM_AGUS; i=i+1) begin
        if (uopLd[i].valid || uopSt.valid || uopLd_0[i].valid || curLd[i].valid || stOps[0].valid || stOps[1].valid || !IN_SQ_empty || (OUT_ldAck[i].valid && OUT_ldAck[i].fail) || (OUT_stAck.valid && OUT_stAck.fail)) busy = 1;
    end
end


wire flushReady = !busy;
wire flushActive = (
    state == FLUSH || state == FLUSH_WAIT ||
    state == FLUSH_READ0 || state == FLUSH_READ1);
assign OUT_busy = busy || flushQueued || flushActive;

reg flushDone;
reg[`CACHE_SIZE_E-`CLSIZE_E-$clog2(`CASSOC)-1:0] flushIdx;
reg[$clog2(`CASSOC)-1:0] flushAssocIdx;

reg[$clog2(`CASSOC)-1:0] assocCnt;

wire canOutputMiss = (LSU_memc.cmd == MEMC_NONE || !IN_memc.stall[1]);
reg[NUM_AGUS-1:0] forwardMiss;
always_comb begin
    reg temp = 0;
    forwardMiss = '0;
    for (integer i = 0; i < NUM_AGUS; i=i+1) begin
        if (!temp &&
            canOutputMiss &&
            miss[i].valid && !missEvictConflict[i] &&
            miss[i].mtype != IO_BUSY && miss[i].mtype != SQ_CONFLICT &&
            miss[i].mtype != TRANS_IN_PROG
        ) begin
            temp = 1;
            forwardMiss[i] = 1;
        end
    end
end


always_ff@(posedge clk) begin

    if (canOutputMiss) begin
        LSU_memc <= 'x;
        LSU_memc.cmd <= MEMC_NONE;
    end

    if (rst) begin
        state <= IDLE;
        flushQueued <= 1;
        initialFlush <= 1;
        LSU_memc <= 'x;
        LSU_memc.cmd <= MEMC_NONE;
        assocCnt <= 0;
    end
    else begin

        if (IN_flush) flushQueued <= 1;
        if (setDirty) dirty[setDirtyIdx] <= 1;

        case (state)
            IDLE: begin
                for (integer i = 0; i < NUM_AGUS; i=i+1) begin

                    reg[$clog2(SIZE)-1:0] missIdx = {miss[i].assoc, miss[i].missAddr[`VIRT_IDX_LEN-1:`CLSIZE_E]};
                    MissType missType = miss[i].mtype;

                    if (forwardMiss[i]) begin
                        assocCnt <= assocCnt + 1;

                        // if not dirty, do not copy back to main memory
                        if (missType == REGULAR && !dirty[missIdx] && (!setDirty || setDirtyIdx != missIdx))
                            missType = REGULAR_NO_EVICT;

                        case (missType)
                            REGULAR: begin
                                LSU_memc.cmd <= MEMC_REPLACE;
                                LSU_memc.cacheAddr <= {miss[i].assoc, miss[i].missAddr[`VIRT_IDX_LEN-1:2]};
                                LSU_memc.writeAddr <= {miss[i].writeAddr[31:`VIRT_IDX_LEN], miss[i].missAddr[`VIRT_IDX_LEN-1:2], 2'b0};
                                LSU_memc.readAddr <= {miss[i].missAddr[31:2], 2'b0};
                                LSU_memc.cacheID <= 0;
                                LSU_memc.mask <= 0;
                            end

                            REGULAR_NO_EVICT: begin
                                LSU_memc.cmd <= MEMC_CP_EXT_TO_CACHE;
                                LSU_memc.cacheAddr <= {miss[i].assoc, miss[i].missAddr[`VIRT_IDX_LEN-1:2]};
                                LSU_memc.writeAddr <= 'x;
                                LSU_memc.readAddr <= {miss[i].missAddr[31:2], 2'b0};
                                LSU_memc.cacheID <= 0;
                                LSU_memc.mask <= 0;
                            end

                            MGMT_CLEAN,
                            MGMT_FLUSH: begin
                                LSU_memc.cmd <= MEMC_CP_CACHE_TO_EXT;
                                LSU_memc.cacheAddr <= {miss[i].assoc, miss[i].missAddr[`VIRT_IDX_LEN-1:2]};
                                LSU_memc.writeAddr <= {miss[i].writeAddr[31:`VIRT_IDX_LEN], miss[i].missAddr[`VIRT_IDX_LEN-1:2], 2'b0};
                                LSU_memc.readAddr <= 'x;
                                LSU_memc.cacheID <= 0;
                                LSU_memc.mask <= 0;
                            end
                            default: ; // MGMT_INVAL does not evict the cache line
                        endcase

                        // We can forward a single store to the memory controller, which will then splice
                        // the store value into the data stream from external RAM.
                        if ((missType == REGULAR || missType == REGULAR_NO_EVICT) && stOps[1].valid && fuseStoreMiss) begin
                            LSU_memc.mask <= stOps[1].wmask;
                            LSU_memc.data <= stOps[1].data;
                            dirty[missIdx] <= 1;
                        end
                        else begin
                            // new cache line is not dirty
                            dirty[missIdx] <= 0;
                        end
                    end
                end

                if (!(|forwardMiss) && flushQueued && flushReady) begin
                    state <= FLUSH_WAIT;
                    flushQueued <= 0;
                    flushIdx <= 0;
                    flushAssocIdx <= 0;
                    flushDone <= 0;
                end
            end

            FLUSH_WAIT: begin
                state <= FLUSH_READ0;
                if (LSU_memc.cmd != MEMC_NONE || BLSU_memc.cmd != MEMC_NONE)
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
                    state <= IDLE;
                    initialFlush <= 0;
                end
                else if (LSU_memc.cmd == MEMC_NONE || !IN_memc.stall[1]) begin
                    CTEntry entry = IF_ct.rdata[0][flushAssocIdx];

                    if (entry.valid && dirty[{flushAssocIdx, flushIdx}] && !initialFlush) begin
                        LSU_memc.cmd <= MEMC_CP_CACHE_TO_EXT;
                        LSU_memc.cacheAddr <= {flushAssocIdx, flushIdx, {(`CLSIZE_E-2){1'b0}}};
                        LSU_memc.writeAddr <= {entry.addr, flushIdx, {(`CLSIZE_E){1'b0}}};
                        LSU_memc.readAddr <= 'x;
                        LSU_memc.cacheID <= 0;
                        LSU_memc.mask <= 0;
                    end

                    {flushDone, flushIdx, flushAssocIdx} <= {flushIdx, flushAssocIdx} + 1;
                    if (flushAssocIdx == $clog2(`CASSOC)'(`CASSOC-1)) state <= FLUSH_READ0;
                end
            end
            default: state <= IDLE;
        endcase
    end
end

endmodule
