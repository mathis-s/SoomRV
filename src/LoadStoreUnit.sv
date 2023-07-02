module LoadStoreUnit
#(
    parameter ASSOC=4,
    parameter CLSIZE_E=7,
    parameter SIZE=(1<<(`CACHE_SIZE_E - CLSIZE_E)),
    localparam TOTAL_UOPS = 2
)
(
    input wire clk,
    input wire rst,

    input BranchProv IN_branch,
    output wire OUT_ldStall,
    output wire OUT_stStall,

    input LD_UOp IN_uopLd,
    output LD_UOp OUT_uopLdSq,

    input ST_UOp IN_uopSt,

    IF_Cache.HOST IF_cache,
    IF_MMIO.HOST IF_mmio,
    IF_CTable.HOST IF_ct,
    
    input StFwdResult IN_stFwd,

    output MemController_Req OUT_memc,
    input MemController_Res IN_memc,

    output RES_UOp OUT_uopLd
);

MemController_Req BLSU_memc;
MemController_Req LSU_memc;
assign OUT_memc = (LSU_memc.cmd != MEMC_NONE) ? LSU_memc : BLSU_memc;

wire isCacheBypassLdUOp = 
    `ENABLE_EXT_MMIO && IN_uopLd.valid && IN_uopLd.isMMIO && IN_uopLd.exception == AGU_NO_EXCEPTION &&
    IN_uopLd.addr >= `EXT_MMIO_START_ADDR && IN_uopLd.addr < `EXT_MMIO_END_ADDR;
wire isCacheBypassStUOp = 
    `ENABLE_EXT_MMIO && IN_uopSt.valid && IN_uopSt.isMMIO && 
    IN_uopSt.addr >= `EXT_MMIO_START_ADDR && IN_uopSt.addr < `EXT_MMIO_END_ADDR;

wire ignoreLd = isCacheBypassLdUOp && !LMQ_ld.valid;
wire ignoreSt = isCacheBypassLdUOp && !SMQ_st.valid;

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
    .IN_uopLd(IN_uopLd),

    .IN_uopStEn(isCacheBypassStUOp),
    .OUT_stStall(BLSU_stStall),
    .IN_uopSt(IN_uopSt),

    .IN_ldStall(ldOps[1].valid),
    .OUT_uopLd(BLSU_uopLd),
    .OUT_ldData(BLSU_ldResult),

    .OUT_memc(BLSU_memc),
    .IN_memc(IN_memc)
);

always_comb begin
    IF_mmio.re = 1;
    IF_mmio.raddr = 0;
    IF_mmio.rsize = 0;
end

// stall only affects start of ld/st pipelines.
wire[1:0] stall;
assign stall[0] = (OUT_ldStall && !LMQ_ld.valid) || cacheTableWrite;
assign stall[1] = (OUT_stStall && !SMQ_st.valid) || cacheTableWrite;
assign OUT_ldStall = (isCacheBypassLdUOp ? BLSU_ldStall : (LMQ_full || LMQ_ld.valid || cacheTableWrite)) && IN_uopLd.valid;
assign OUT_stStall = (isCacheBypassStUOp ? BLSU_stStall : (SMQ_full || SMQ_st.valid || cacheTableWrite)) && IN_uopSt.valid;

LD_UOp LMQ_ld;
LD_UOp uopLd;
assign uopLd = LMQ_ld.valid ? LMQ_ld : IN_uopLd;
assign OUT_uopLdSq = uopLd;

ST_UOp SMQ_st;
ST_UOp uopSt;
assign uopSt = SMQ_st.valid ? SMQ_st : IN_uopSt;


wire loadValid = uopLd.valid && (!IN_branch.taken || $signed(uopLd.sqN - IN_branch.sqN) <= 0);

// Both load and store read from cache table
always_comb begin
    IF_ct.re[0] = loadValid && !uopLd.isMMIO && uopLd.exception == AGU_NO_EXCEPTION && !stall[0] && !ignoreLd;
    IF_ct.raddr[0] = uopLd.addr[11:0];
    
    IF_ct.re[1] = uopSt.valid && !uopSt.isMMIO && !stall[1] && !ignoreSt;
    IF_ct.raddr[1] = uopSt.addr[11:0];
end

// Loads also speculatively load from all possible locations
always_comb begin
    IF_cache.re = !(loadValid && !stall[0] && !uopLd.isMMIO && uopLd.exception == AGU_NO_EXCEPTION && !ignoreLd);
    IF_cache.raddr = uopLd.addr[11:0];
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

// Load Pipeline
always_ff@(posedge clk) begin
    if (rst) begin
        for (integer i = 0; i < 2; i=i+1)
            ldOps[i].valid <= 0;
    end
    else begin
        ldOps[0] <= 'x;
        ldOps[0].valid <= 0;
        ldOps[1] <= 'x;
        ldOps[1].valid <= 0;
        
        // Progress the delay line
        if (loadValid && !stall[0] && !ignoreLd)
            ldOps[0] <= uopLd;
        
        if (ldOps[0].valid && (!IN_branch.taken || $signed(ldOps[0].sqN - IN_branch.sqN) <= 0))
            ldOps[1] <= ldOps[0];
    end
end

reg[$clog2(`CASSOC)-1:0] assocCnt;

typedef enum logic[2:0]
{
    REGULAR, REGULAR_NO_EVICT, MGMT_CLEAN, MGMT_INVAL, MGMT_FLUSH
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
always_comb begin
    // Load output is combination of ldOps[1] (the op that accessed cache 2 cycles ago)
    // and the loaded result OR an MMIO load.
    LD_UOp ld = ldOps[1].valid ? ldOps[1] : BLSU_uopLd;
    reg isMMIO = !ldOps[1].valid;
    reg noEvict = !IF_ct.rdata[0][assocCnt].valid;
    
    OUT_uopLd = 'x;
    OUT_uopLd.valid = 0;
    miss[0] = 'x;
    miss[0].valid = 0;

    if (ld.valid) begin
        reg cacheHit = 0;
        reg[31:0] cacheData = 'x;
        if (!isMMIO) begin
            for (integer i = 0; i < `CASSOC; i=i+1) begin
                if (IF_ct.rdata[0][i].valid && IF_ct.rdata[0][i].addr == ld.addr[31:12]) begin
                    assert(!cacheHit); // multiple hits are invalid
                    cacheHit = 1;
                    cacheData = IF_cache.rdata[i];
                end
            end
            
            if (cacheTransfer && cacheLoadAddr == ld.addr[31:CLSIZE_E]) begin
                cacheHit = cacheLoadActive && (cacheLoadProgress > {1'b0, ld.addr[CLSIZE_E-1:2]});
                cacheData = cacheHit ? IF_cache.rdata[cacheLoadAssoc] : 'x;
            end
            
            // trying to access an address that is being evicted
            if (cacheTransfer && cacheEvictAddr == ld.addr[31:CLSIZE_E]) begin
                cacheHit = 0;
                cacheData = 'x;
            end
        end

        if (cacheHit || ld.exception != AGU_NO_EXCEPTION || isMMIO) begin
            // Use forwarded store data if available
            if (!isMMIO) begin
                for (integer i = 0; i < `CASSOC; i=i+1) begin
                    if (IN_stFwd.mask[i]) cacheData[i*8+:8] = IN_stFwd.data[i*8+:8];
                end
            end
            
            OUT_uopLd.valid = 1;
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
                    {{24{ld.signExtend ? cacheData[8*(ld.addr[1:0])+7] : 1'b0}},
                    cacheData[8*(ld.addr[1:0])+:8]};

                1: OUT_uopLd.result = 
                    {{16{ld.signExtend ? cacheData[16*(ld.addr[1])+15] : 1'b0}},
                    cacheData[16*(ld.addr[1])+:16]};

                2: OUT_uopLd.result = cacheData;
                default: ;//assert(0);
            endcase
        end
        else begin
            miss[0].valid = 1;
            miss[0].mtype = noEvict ? REGULAR_NO_EVICT : REGULAR;
            miss[0].oldAddr = {IF_ct.rdata[0][assocCnt].addr, 12'b0};
            miss[0].missAddr = ld.addr;
            miss[0].assoc = assocCnt;
        end
    end
end

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
        if (uopSt.valid && !uopSt.isMMIO && !stall[1] && !ignoreSt)
            stOps[0] <= uopSt;
        
        if (stOps[0].valid)
            stOps[1] <= stOps[0];
    end
end

// Store
always_comb begin
    ST_UOp st = stOps[1];
    reg cacheHit = 0;
    reg[$clog2(`CASSOC)-1:0] cacheHitAssoc = 'x;
    reg noEvict = !IF_ct.rdata[1][assocCnt].valid;

    IF_cache.waddr = 'x;
    IF_cache.wassoc = 'x;
    IF_cache.wdata = 'x;
    IF_cache.wmask = 'x;
    IF_cache.we = 1;
    miss[1] = 'x;
    miss[1].valid = 0;

    if (stOps[1].valid) begin
        
        for (integer i = 0; i < `CASSOC; i=i+1) begin
            if (IF_ct.rdata[1][i].valid && IF_ct.rdata[1][i].addr == stOps[1].addr[31:12]) begin
                assert(!cacheHit); // multiple hits are invalid
                cacheHit = 1;
                cacheHitAssoc = i[$clog2(`CASSOC)-1:0];
            end
        end

        if (cacheTransfer && cacheLoadAddr == st.addr[31:CLSIZE_E]) begin
            cacheHit = cacheLoadActive && (cacheLoadProgress > {1'b0, st.addr[CLSIZE_E-1:2]});
            cacheHitAssoc = cacheLoadAssoc;
        end
        
        // trying to access an address that is being evicted
        if (cacheTransfer && cacheEvictAddr == st.addr[31:CLSIZE_E]) begin
            cacheHit = 0;
        end
        
        if (st.wmask == 0) begin
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
                IF_cache.waddr = stOps[1].addr[11:0];
                IF_cache.wassoc = cacheHitAssoc;
                IF_cache.wdata = stOps[1].data;
                IF_cache.wmask = stOps[1].wmask;
            end
            else begin
                miss[1].valid = 1;
                miss[1].mtype = noEvict ? REGULAR_NO_EVICT : REGULAR;
                miss[1].oldAddr = {IF_ct.rdata[1][assocCnt].addr, 12'b0};
                miss[1].missAddr = stOps[1].addr;
                miss[1].assoc = assocCnt;
            end
        end
    end
end


// Cache Transfer State Machine
enum logic[2:0]
{
    IDLE, EVICT_RQ, EVICT_ACTIVE, LOAD_RQ, LOAD_ACTIVE, REPLACE_RQ, REPLACE_ACTIVE
} state;

reg cacheTransfer;
wire cacheLoadActive = (state == LOAD_ACTIVE);
wire[CLSIZE_E-2:0] cacheLoadProgress = IN_memc.progress[CLSIZE_E-2:0];
wire[31-CLSIZE_E:0] cacheLoadAddr = curCacheMiss.missAddr[31:CLSIZE_E];
wire[31-CLSIZE_E:0] cacheEvictAddr = curCacheMiss.oldAddr[31:CLSIZE_E];
reg[$clog2(ASSOC)-1:0] cacheLoadAssoc;

wire LMQ_full;
LoadMissQueue#(4, CLSIZE_E) loadMissQueue
(
    .clk(clk),
    .rst(rst),
    
    .IN_ready(state == IDLE),
    .IN_branch(IN_branch),
    
    .OUT_full(LMQ_full),

    .IN_cacheLoadActive(cacheLoadActive),
    .IN_cacheLoadProgress(cacheLoadProgress),
    .IN_cacheLoadAddr(cacheLoadAddr),

    .IN_ld(ldOps[1]),
    .IN_enqueue(miss[0].valid),

    .OUT_ld(LMQ_ld),
    .IN_dequeue(!stall[0] && LMQ_ld.valid)
);

wire SMQ_full;
StoreMissQueue#(4, CLSIZE_E) storeMissQueue
(
    .clk(clk),
    .rst(rst),
    
    .IN_ready(state == IDLE),
    
    .OUT_full(SMQ_full),

    .IN_cacheLoadActive(cacheLoadActive),
    .IN_cacheLoadProgress(cacheLoadProgress),
    .IN_cacheLoadAddr(cacheLoadAddr),

    .IN_st(stOps[1]),
    // do not enqueue mgmt ops
    .IN_enqueue((miss[1].valid || IF_cache.wbusy) && (miss[1].mtype == REGULAR || miss[1].mtype == REGULAR_NO_EVICT)),

    .OUT_st(SMQ_st),
    .IN_dequeue(!stall[1] && SMQ_st.valid)
);

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
            if (miss[i].valid && !temp) begin
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
end

// Cache<->Memory Transfer State Machine
CacheMiss curCacheMiss;
reg[$clog2(`CASSOC)-1:0] replaceAssoc;
always_ff@(posedge clk) begin

    if (rst) begin
        state <= IDLE;
        replaceAssoc <= 0;
        LSU_memc <= 'x;
        LSU_memc.cmd <= MEMC_NONE;
        cacheTransfer <= 0;
        cacheLoadAssoc <= 0;
    end
    else begin
        case (state)
            IDLE: begin
                reg temp = 0;
                cacheTransfer <= 0;
                for (integer i = 0; i < 2; i=i+1) begin
                    if (miss[i].valid && !temp) begin
                        temp = 1;
                        curCacheMiss <= miss[i];
                        assocCnt <= assocCnt + 1;
                        cacheTransfer <= 1;
                        
                        case (miss[i].mtype)
                            REGULAR: begin
                                state <= REPLACE_RQ;
                                LSU_memc.cmd <= MEMC_CP_CACHE_TO_EXT;
                                LSU_memc.sramAddr <= {miss[i].assoc, miss[i].missAddr[11:CLSIZE_E], {(CLSIZE_E-2){1'b0}}};
                                LSU_memc.extAddr <= {miss[i].oldAddr[31:12], miss[i].missAddr[11:CLSIZE_E], {(CLSIZE_E-2){1'b0}}};
                                LSU_memc.cacheID <= 0;
                                LSU_memc.rqID <= 0;
                                cacheLoadAssoc <= miss[i].assoc;
                            end

                            REGULAR_NO_EVICT: begin
                                state <= LOAD_RQ;
                                LSU_memc.cmd <= MEMC_CP_EXT_TO_CACHE;
                                LSU_memc.sramAddr <= {miss[i].assoc, miss[i].missAddr[11:CLSIZE_E], {(CLSIZE_E-2){1'b0}}};
                                LSU_memc.extAddr <= {miss[i].missAddr[31:CLSIZE_E], {(CLSIZE_E-2){1'b0}}};
                                LSU_memc.cacheID <= 0;
                                LSU_memc.rqID <= 0;
                                cacheLoadAssoc <= miss[i].assoc;
                            end

                            MGMT_CLEAN,
                            MGMT_FLUSH: begin
                                state <= EVICT_RQ;
                                LSU_memc.cmd <= MEMC_CP_CACHE_TO_EXT;
                                LSU_memc.sramAddr <= {miss[i].assoc, miss[i].missAddr[11:CLSIZE_E], {(CLSIZE_E-2){1'b0}}};
                                LSU_memc.extAddr <= {miss[i].oldAddr[31:12], miss[i].missAddr[11:CLSIZE_E], {(CLSIZE_E-2){1'b0}}};
                                LSU_memc.cacheID <= 0;
                                LSU_memc.rqID <= 0;
                                cacheLoadAssoc <= miss[i].assoc;
                            end
                            
                            default: ; // MGMT_INVAL does not evict the cache line
                        endcase
                    end
                end
            end
            LOAD_RQ: begin
                if (IN_memc.busy && IN_memc.rqID == 0) begin
                    LSU_memc.cmd <= MEMC_NONE;
                    state <= LOAD_ACTIVE;
                end
            end
            LOAD_ACTIVE: begin
                if (!IN_memc.busy || IN_memc.progress == (1 << (CLSIZE_E - 2))) begin
                    state <= IDLE;
                    cacheTransfer <= 0;
                end
            end
            EVICT_RQ: begin
                if (IN_memc.busy && IN_memc.rqID == 0) begin
                    LSU_memc.cmd <= MEMC_NONE;
                    state <= EVICT_ACTIVE;
                end
            end
            EVICT_ACTIVE: begin
                if (!IN_memc.busy || IN_memc.progress == (1 << (CLSIZE_E - 2))) begin
                    state <= IDLE;
                    cacheTransfer <= 0;
                end
            end
            REPLACE_RQ: begin
                if (IN_memc.busy && IN_memc.rqID == 0) begin
                    LSU_memc.cmd <= MEMC_NONE;
                    state <= REPLACE_ACTIVE;
                end
            end
            REPLACE_ACTIVE: begin
                if (!IN_memc.busy || IN_memc.progress == (1 << (CLSIZE_E - 2))) begin
                    state <= LOAD_RQ;
                    // sramAddr stays the same
                    LSU_memc.cmd <= MEMC_CP_EXT_TO_CACHE;
                    LSU_memc.extAddr <= {curCacheMiss.missAddr[31:CLSIZE_E], {(CLSIZE_E-2){1'b0}}};
                    LSU_memc.cacheID <= 0;
                    LSU_memc.rqID <= 0;
                end
            end
            default: state <= IDLE;
        endcase
    end
end

endmodule
