
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

    input wire IN_enable,

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

    input logic IN_ctReadReady[NUM_CT_READS-1:0],
    output CacheTableRead OUT_ctRead[NUM_CT_READS-1:0],
    input CacheTableResult IN_ctResult[NUM_CT_READS-1:0],

    output CacheLineSetDirty OUT_setDirty,
    output CacheMiss OUT_miss,
    input logic IN_missReady,

    input StFwdResult IN_sqStFwd[NUM_AGUS-1:0],
    input StFwdResult IN_sqbStFwd[NUM_AGUS-1:0],
    output ST_Ack OUT_stAck,

    output MemController_Req OUT_BLSU_memc,
    input MemController_Req LSU_memc,
    input MemController_Res IN_memc,

    input wire[NUM_AGUS-1:0] IN_ready,
    output ResultUOp OUT_resultUOp[NUM_AGUS-1:0],
    output FlagsUOp OUT_flagsUOp[NUM_AGUS-1:0]
);

localparam PORT_IDX_BITS = NUM_AGUS == 1 ? 1 : $clog2(NUM_AGUS);
typedef logic[PORT_IDX_BITS-1:0] PortIdx;

LoadResUOp ldResUOp[NUM_AGUS-1:0];

MemController_Req BLSU_memc;
assign OUT_BLSU_memc = BLSU_memc;

logic[NUM_AGUS-1:0] isCacheBypassLdUOp;
always_comb begin
    for (integer i = 0; i < NUM_AGUS; i=i+1)
        isCacheBypassLdUOp[i] =
            `ENABLE_EXT_MMIO && ldOps_0[i].valid && ldOps_0[i].isMMIO &&
            ldOps_0[i].addr >= `EXT_MMIO_START_ADDR && ldOps_0[i].addr < `EXT_MMIO_END_ADDR;
end


wire isCacheBypassStUOp =
    `ENABLE_EXT_MMIO && IN_uopSt.valid && IN_uopSt.isMMIO &&
    IN_uopSt.addr >= `EXT_MMIO_START_ADDR && IN_uopSt.addr < `EXT_MMIO_END_ADDR;

PortIdx blsuLdIdx;
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
    .IN_uopLd(ldOps_0[blsuLdIdx]),

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
assign OUT_stStall = ((isCacheBypassStUOp ? BLSU_stStall : (!IN_enable || !IN_ctReadReady[STORE_PORT]))) && IN_uopSt.valid;

localparam STORE_PORT = NUM_CT_READS - 1;

always_comb
    for (integer i = 0; i < NUM_AGUS; i=i+1)
        OUT_uopLdSq[i] = ldOps_0[i];

ST_UOp uopSt;
assign uopSt = IN_uopSt;

// Both load and store read from cache table
always_comb begin
    for (integer i = 0; i < NUM_AGUS; i=i+1) begin
        OUT_ctRead[i].valid = selLd[i].valid && !selLd[i].isMMIO;
        OUT_ctRead[i].addr = selLd[i].addr[`VIRT_IDX_LEN-1:0];
    end

    OUT_ctRead[STORE_PORT].valid = uopSt.valid && !uopSt.isMMIO && !(isCacheBypassStUOp || OUT_stStall);
    OUT_ctRead[STORE_PORT].addr = uopSt.addr[`VIRT_IDX_LEN-1:0];
end

PortIdx[NUM_AGUS-1:0] idxs_c;
PortIdx[NUM_AGUS-1:0] idxs_r;
always_ff@(posedge clk) idxs_r <= idxs_c;

if (NUM_AGUS > 1) begin
    PortIdx startIdx;
    always_ff@(posedge clk /*or posedge rst*/)
        if (rst) startIdx <= 0;
        else startIdx <= (startIdx + 1);

    // Stores only go through port 0. To still make port
    // pressure even we shuffle incoming loads.
    always_comb begin
        for (integer i = 0; i < NUM_AGUS; i=i+1)
            idxs_c[i] = startIdx + PortIdx'(i);
    end
end
else assign idxs_c[0] = 0;

typedef enum logic[0:0]
{
    SRC_AGU,
    SRC_LB
} LoadSource;
LoadSource selLdSrc_c[NUM_AGUS-1:0];
LoadSource selLdSrc_r[NUM_AGUS-1:0];
always_ff@(posedge clk) selLdSrc_r <= selLdSrc_c;

// Select load to execute
// 1. special load (page walk, non-speculative or external)
// 2. regular load
LD_UOp selLd[NUM_AGUS-1:0];
always_comb begin

    for (integer i = NUM_AGUS-1; i >= 0; i=i-1) begin
        PortIdx idx = idxs_c[i];

        selLdSrc_c[i] = 'x;
        selLd[i] = LD_UOp'{valid: 0, default: 'x};

        // Only addr[11:0] is well defined, the rest is
        // still being calculated (for regular loads at least) and will
        // only be available in the next cycle.
        if (!IN_enable) begin
            // do not issue load
        end
        else if (!IN_ctReadReady[i]) begin
            // cache table port is being used to handle cache miss
        end
        else if (IN_uopLd[idx].valid &&
            (!IN_branch.taken || IN_uopLd[idx].external || $signed(IN_uopLd[idx].sqN - IN_branch.sqN) <= 0)
        ) begin
            selLd[i] = IN_uopLd[idx];
            selLdSrc_c[i] = SRC_LB;
        end
        else if (IN_uopELd[idx].valid) begin
            selLd[i].valid = 1;
            selLd[i].external = 0;
            selLd[i].addr[11:0] = IN_uopELd[idx].addr;

            selLd[i].isMMIO = 0; // assume that this is not MMIO such that cache is read
            selLdSrc_c[i] = SRC_AGU;
        end
    end
end

// Generate Stalls
LD_UOp uopLd[NUM_AGUS-1:0];
always_comb begin

    for (integer i = 0; i < NUM_AGUS; i=i+1) begin
        OUT_ldStall[i] = 1;
        OUT_ldAGUStall[i] = 1;
    end

    for (integer i = 0; i < NUM_AGUS; i=i+1) begin
        uopLd[i] = LD_UOp'{valid: 0, default: 'x};

        if (selLd[i].valid && (!IF_cache.busy[i] || selLd[i].isMMIO)) begin
            case (selLdSrc_c[i])
                SRC_AGU: OUT_ldAGUStall[idxs_c[i]] = 0;
                SRC_LB: OUT_ldStall[idxs_c[i]] = 0;
            endcase
            // todo: stall or continue? right now we always stall, but we could instead
            // try to handle following ops.
            uopLd[i] = selLd[i];
        end
    end
end

LD_UOp ldOps_0[NUM_AGUS-1:0];
always_comb begin
    for (integer i = 0; i < NUM_AGUS; i=i+1) begin
        PortIdx idx = idxs_r[i];
        ldOps_0[i] = ldOps[i][0];

        // For regular loads, we only get the full address and other
        // info now.
        if (ldOps_0[i].valid && selLdSrc_r[i] == SRC_AGU) begin
            assert(rst || !IN_aguLd[idx].valid || IN_aguLd[idx].addr[11:0] == ldOps_0[i].addr[11:0]);

            ldOps_0[i] = 'x;
            ldOps_0[i].valid = 0;
            if (IN_aguLd[idx].valid)
                ldOps_0[i] = IN_aguLd[idx];
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
        if (ldOps_0[i].valid && ldOps_0[i].isMMIO && !isCacheBypassLdUOp[i]) begin
            IF_mmio.re = 0;
            IF_mmio.raddr = ldOps_0[i].addr;
            IF_mmio.rsize = ldOps_0[i].size;
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

reg loadWasExtIOBusy[NUM_AGUS-1:0];
reg[1:0] loadCacheAccessFailed[NUM_AGUS-1:0];

// Load Pipeline
always_ff@(posedge clk /*or posedge rst*/) begin

    for (integer i = 0; i < NUM_AGUS; i=i+1) begin
        for (integer j = 0; j < 2; j=j+1) begin
            ldOps[i][j] <= 'x;
            ldOps[i][j].valid <= 0;
        end
        loadWasExtIOBusy[i] <= 'x;
        loadCacheAccessFailed[i] <= 'x;
    end

    if (rst) ;
    else begin
        for (integer i = 0; i < NUM_AGUS; i=i+1) begin
            // Progress the delay line
            if (uopLd[i].valid) begin
                ldOps[i][0] <= uopLd[i];
                loadCacheAccessFailed[i][0] <= IF_cache.busy[i];
            end

            if (ldOps_0[i].valid && (!IN_branch.taken || ldOps_0[i].external || $signed(ldOps_0[i].sqN - IN_branch.sqN) <= 0) &&
                // if the BLSU is busy, we place the OP in the Load Miss Queue.
                (!isCacheBypassLdUOp[i] || BLSU_ldStall)
            ) begin
                ldOps[i][1] <= ldOps_0[i];
                loadWasExtIOBusy[i] <= isCacheBypassLdUOp[i];
                loadCacheAccessFailed[i][1] <= loadCacheAccessFailed[i][0];
            end
        end
    end
end

// Cache Access
always_comb begin
    for (integer i = 0; i < NUM_CT_READS; i=i+1) begin
        IF_cache.addr[i] = 'x;
        IF_cache.wdata[i] = 'x;
        IF_cache.wmask[i] = 'x;
        IF_cache.wassoc[i] = 'x;
        IF_cache.we[i] = 1;
        IF_cache.re[i] = 1;
    end

    // Loads speculatively load from all possible locations
    for (integer i = 0; i < NUM_AGUS; i=i+1) begin
        IF_cache.re[i] = !(selLd[i].valid && !selLd[i].isMMIO);
        IF_cache.addr[i] = selLd[i].addr[`VIRT_IDX_LEN-1:0];
    end

    if (storeWriteToCache) begin
        IF_cache.we[STORE_PORT] = 0;
        IF_cache.re[STORE_PORT] = 0;
        IF_cache.addr[STORE_PORT] = stOps[1].addr[`VIRT_IDX_LEN-1:0];
        IF_cache.wassoc[STORE_PORT] = storeWriteAssoc;
        IF_cache.wdata[STORE_PORT] = stOps[1].data;
        IF_cache.wmask[STORE_PORT] = stOps[1].wmask;
    end
end

typedef struct packed
{
    logic[$clog2(`CASSOC)-1:0] idx;
    logic valid;
} IdxN;

IdxN ldAssocHit_c[NUM_AGUS-1:0];
IdxN stAssocHit_c;

// OHEncoder for checking load tags
generate for (genvar i = 0; i < NUM_AGUS; i=i+1) begin
logic[`CASSOC-1:0] ldAssocHitUnary_c;
always_comb begin
    for(integer j = 0; j < `CASSOC; j=j+1)
        ldAssocHitUnary_c[j] = IN_ctResult[i].data[j].valid && IN_ctResult[i].data[j].addr == ldOps[i][1].addr[31:`VIRT_IDX_LEN];
end
OHEncoder#(`CASSOC, 1) ohEncLd(ldAssocHitUnary_c, ldAssocHit_c[i].idx, ldAssocHit_c[i].valid);
end endgenerate

// OHEncoder for checking store tags
logic[`CASSOC-1:0] stAssocHitUnary_c;
always_comb begin
    for(integer j = 0; j < `CASSOC; j=j+1)
        stAssocHitUnary_c[j] = IN_ctResult[STORE_PORT].data[j].valid && IN_ctResult[STORE_PORT].data[j].addr == stOps[1].addr[31:`VIRT_IDX_LEN];
end
OHEncoder#(`CASSOC, 1) ohEncSt(stAssocHitUnary_c, stAssocHit_c.idx, stAssocHit_c.valid);

CacheMiss miss[NUM_CT_READS-1:0];

reg storeWriteToCache;
reg[$clog2(`CASSOC)-1:0] storeWriteAssoc;

// Process Cache Table Read Responses
LD_UOp curLd[NUM_AGUS-1:0];
reg blsuLoadHandled;
always_comb begin

    blsuLoadHandled = 0;

    OUT_setDirty = CacheLineSetDirty'{valid: 0, default: 'x};

    storeWriteToCache = 0;
    storeWriteAssoc = 'x;

    for (integer i = 0; i < NUM_AGUS; i=i+1)
        ldResUOp[i] = LoadResUOp'{valid: 0, default: 'x};

    for (integer i = 0; i < NUM_CT_READS; i=i+1) begin
        miss[i] = 'x;
        miss[i].valid = 0;
    end

    // Handle Loads
    for (integer i = 0; i < NUM_AGUS; i=i+1) begin
        // only one of these is valid
        LD_UOp ld = ldOps[i][1];

        if (!ld.valid && !blsuLoadHandled)
            ld = BLSU_uopLd;
        curLd[i] = ld;

        if (ld.valid) begin
            reg isExtMMIO = !ldOps[i][1].valid;
            reg isIntMMIO = ld.valid && ld.isMMIO;
            reg isMMIO = isExtMMIO || isIntMMIO;
            reg isCache = !isExtMMIO && !isIntMMIO;
            reg noEvict = !IN_ctResult[i].data[assocCnt].valid;
            reg doCacheLoad = 1;

            reg cacheHit = 0;
            reg[31:0] readData = 'x;

            if (ld.dataValid) begin
                readData = ld.data;
                doCacheLoad = 0;
            end
            else if (isExtMMIO) begin
                readData = BLSU_ldResult;
                blsuLoadHandled = 1;
                doCacheLoad = 0;
            end
            else if (isIntMMIO) begin
                readData = IF_mmio.rdata;
                doCacheLoad = 0;
            end
            else begin
                if (ldAssocHit_c[i].valid) begin
                    cacheHit = 1;
                    doCacheLoad = 0;
                    readData = IF_cache.rdata[i][ldAssocHit_c[i].idx];
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
            ldResUOp[i].sext = ld.signExtend;
            ldResUOp[i].size = ld.size;
            ldResUOp[i].addr = ld.addr;


            miss[i].writeAddr = {IN_ctResult[i].data[assocCnt].addr, ld.addr[`VIRT_IDX_LEN-1:0]};
            miss[i].missAddr = ld.addr;
            miss[i].assoc = assocCnt;

            // Go through all possible miss or hit cases
            if (!isExtMMIO && loadWasExtIOBusy[i]) begin
                miss[i].mtype = CONFLICT;
                miss[i].valid = 1;
            end
            else if (!isMMIO && stFwd[i].conflict) begin
                miss[i].mtype = CONFLICT;
                miss[i].valid = 1;
            end
            else if (!isMMIO && !ld.dataValid && loadCacheAccessFailed[i][1]) begin
                miss[i].mtype = CONFLICT;
                miss[i].valid = 1;
            end
            else if (doCacheLoad) begin
                miss[i].mtype = noEvict ? REGULAR_NO_EVICT : REGULAR;
                miss[i].valid = 1;

                ldResUOp[i].valid = 1;
                ldResUOp[i].dataAvail = 0;
                ldResUOp[i].fwdMask = stFwd[i].mask;
                ldResUOp[i].data = stFwd[i].data;
            end
            else if (!isMMIO) begin

                if (cacheHit || ld.dataValid) begin
                    for (integer j = 0; j < 4; j=j+1) begin
                        if (stFwd[i].mask[j]) readData[j*8+:8] = stFwd[i].data[j*8+:8];
                    end

                    ldResUOp[i].valid = 1;
                    ldResUOp[i].dataAvail = 1;
                    ldResUOp[i].fwdMask = 4'b1111;
                    ldResUOp[i].data = readData;
                end
                else begin
                    miss[i].mtype = TRANS_IN_PROG;
                    miss[i].valid = 1;

                    ldResUOp[i].valid = 1;
                    ldResUOp[i].dataAvail = 0;
                    ldResUOp[i].fwdMask = stFwd[i].mask;
                    ldResUOp[i].data = stFwd[i].data;
                end

            end
            else if (isMMIO) begin
                ldResUOp[i].valid = 1;
                ldResUOp[i].dataAvail = 1;
                ldResUOp[i].fwdMask = 4'b1111;
                ldResUOp[i].data = readData;
            end
        end
    end
    begin
        ST_UOp st = stOps[1];
        if (st.valid) begin
            reg cacheHit = 0;
            reg cacheTableHit = 1;
            reg doCacheLoad = 1;
            reg[$clog2(`CASSOC)-1:0] cacheHitAssoc = 'x;
            reg noEvict = !IN_ctResult[STORE_PORT].data[assocCnt].valid;

            // check for hit in cache table
            if (stAssocHit_c.valid) begin
                doCacheLoad = 0;
                cacheHit = 1;
                cacheHitAssoc = stAssocHit_c.idx;
                cacheTableHit = 1;
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
            else if (st.isMgmt) begin
                // Management Ops
                if (cacheTableHit) begin
                    miss[STORE_PORT].valid = 1;
                    miss[STORE_PORT].writeAddr = st.addr;
                    miss[STORE_PORT].missAddr = st.addr;
                    miss[STORE_PORT].assoc = cacheHitAssoc;
                    case (st.data[1:0])
                        0: miss[STORE_PORT].mtype = MGMT_CLEAN;
                        1: miss[STORE_PORT].mtype = MGMT_INVAL;
                        2: miss[STORE_PORT].mtype = MGMT_FLUSH;
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
                    OUT_setDirty.valid = 1;
                    OUT_setDirty.idx = {cacheHitAssoc, st.addr[`VIRT_IDX_LEN-1:`CLSIZE_E]};
                end
                else begin
                    miss[STORE_PORT].valid = 1;
                    miss[STORE_PORT].mtype = doCacheLoad ? (noEvict ? REGULAR_NO_EVICT : REGULAR) : TRANS_IN_PROG;
                    miss[STORE_PORT].writeAddr = {IN_ctResult[STORE_PORT].data[assocCnt].addr, st.addr[`VIRT_IDX_LEN-1:0]};
                    miss[STORE_PORT].missAddr = st.addr;
                    miss[STORE_PORT].assoc = assocCnt;
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
    .OUT_resultUOp(OUT_resultUOp),
    .OUT_flagsUOp(OUT_flagsUOp)
);

// Store Pipeline
always_ff@(posedge clk /*or posedge rst*/) begin
    if (rst) begin
        for (integer i = 0; i < 2; i=i+1)
            stOps[i] <= ST_UOp'{valid: 0, default: 'x};
    end
    else begin
        stOps[0] <= 'x;
        stOps[0].valid <= 0;
        stOps[1] <= 'x;
        stOps[1].valid <= 0;

        // Progress the delay line
        if (uopSt.valid && !OUT_stStall) begin
            stOps[0] <= uopSt;
        end

        if (stOps[0].valid) begin
            stOps[1] <= stOps[0];
        end
    end
end

// Place load in LoadResultBuffer or reactivate back in LoadBuffer via negative ack
for (genvar i = 0; i < NUM_AGUS; i=i+1) begin
    always_comb begin
        OUT_ldAck[i] = LD_Ack'{valid: 0, default: 'x};
        LRB_uop[i] = LoadResUOp'{valid: 0, default: 'x};

        if (ldResUOp[i].valid && (LRB_ready[i]) && (!miss[i].valid || (forwardMiss[i] && IN_missReady))) begin
            LRB_uop[i] = ldResUOp[i];
        end
        else if (curLd[i].valid) begin
            OUT_ldAck[i].valid = 1;
            OUT_ldAck[i].fail = 1;
            OUT_ldAck[i].external = curLd[i].external;
            OUT_ldAck[i].loadSqN = curLd[i].loadSqN;
            OUT_ldAck[i].addr = curLd[i].addr;

            OUT_ldAck[i].doNotReIssue = 0;
            //if (miss[i].valid && (!stOps[1].valid || STORE_PORT != i)) begin
            //    if (miss[i].mtype == TRANS_IN_PROG) begin
            //        OUT_ldAck[i].doNotReIssue = 1;
            //    end
            //    else if (miss[i].mtype == REGULAR || miss[i].mtype == REGULAR_NO_EVICT) begin
            //        OUT_ldAck[i].doNotReIssue = forwardMiss[i] && !missEvictConflict[i];
            //    end
            //end
        end
    end
end


wire redoStore = stOps[1].valid &&
    (miss[STORE_PORT].valid ?
        (miss[STORE_PORT].mtype == REGULAR ||
         miss[STORE_PORT].mtype == REGULAR_NO_EVICT ||
         miss[STORE_PORT].mtype == CONFLICT ||
         miss[STORE_PORT].mtype == TRANS_IN_PROG ||
         ((miss[STORE_PORT].mtype == MGMT_CLEAN ||
           miss[STORE_PORT].mtype == MGMT_FLUSH ||
           miss[STORE_PORT].mtype == MGMT_INVAL) &&
          (!forwardMiss[STORE_PORT] || !IN_missReady))
    ) :
        (!stOps[1].isMMIO &&
         IF_cache.busy[STORE_PORT]));

wire fuseStoreMiss = 0;//!missEvictConflict[STORE_PORT] && (miss[STORE_PORT].mtype == REGULAR || miss[STORE_PORT].mtype == REGULAR_NO_EVICT) && forwardMiss[STORE_PORT] && miss[STORE_PORT].valid;

assign OUT_stAck.addr = stOps[1].addr;
assign OUT_stAck.data = stOps[1].data;
assign OUT_stAck.wmask = stOps[1].wmask;
assign OUT_stAck.nonce = stOps[1].nonce;
assign OUT_stAck.idx = stOps[1].id;
assign OUT_stAck.valid = stOps[1].valid;
assign OUT_stAck.fail = redoStore && !fuseStoreMiss;

logic[NUM_CT_READS-1:0] forwardMiss;
always_comb begin
    forwardMiss = 0;
    OUT_miss = CacheMiss'{valid: 0, default: 'x};

    for (integer i = 0; i < NUM_CT_READS; i=i+1) begin
        if (!OUT_miss.valid) begin
            if (miss[i].valid &&
                miss[i].mtype != CONFLICT && miss[i].mtype != TRANS_IN_PROG
            ) begin
                forwardMiss[i] = 1;
                OUT_miss = miss[i];
            end
        end
    end
end


logic[$clog2(`CASSOC)-1:0] assocCnt;
always_ff@(posedge clk /*or posedge rst*/) begin
    if (rst) begin
        assocCnt <= 0;
    end
    else begin
        if (OUT_miss.valid && IN_missReady)
            assocCnt <= assocCnt + 1;
    end
end

endmodule
