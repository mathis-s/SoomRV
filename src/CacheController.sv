module CacheController
#(
    parameter SIZE=32,
    parameter ASSOC=4,
    parameter CLSIZE_E=7,
    localparam TOTAL_UOPS = 2
)
(
    input wire clk,
    input wire rst,
    
    input BranchProv IN_branch,
    input wire IN_SQ_empty,
    
    input wire IN_stall[TOTAL_UOPS-1:0],
    output reg OUT_stall[TOTAL_UOPS-1:0],

    input LD_UOp IN_uopLd,
    output LD_UOp OUT_uopLdSq,
    output LD_UOp OUT_uopLd,
    
    input ST_UOp IN_uopSt,
    output ST_UOp OUT_uopSt,
    
    output CTRL_MemC OUT_memc,
    input STAT_MemC IN_memc,
    
    input wire IN_fence,
    output wire OUT_fenceBusy
);


localparam LEN = SIZE / ASSOC;
localparam TAG_LEN = 32 - CLSIZE_E - $clog2(LEN);

wire LMQ_full;
LD_UOp LMQ_ld;
LD_UOp uopLd;
assign uopLd = LMQ_ld.valid ? LMQ_ld : IN_uopLd;
assign OUT_uopLdSq = uopLd;
LoadMissQueue#(2, CLSIZE_E) loadMissQueue
(
    .clk(clk),
    .rst(rst),
    
    .IN_ready(state == IDLE),
    .IN_branch(IN_branch),
    
    .OUT_full(LMQ_full),

    .IN_cacheLoadActive(state == LOAD_ACTIVE),
    .IN_cacheLoadProgress(IN_memc.progress[CLSIZE_E-2:0]),
    .IN_cacheLoadAddr(OUT_memc.extAddr[29:CLSIZE_E-2]),

    .IN_ld(uopLd),
    .IN_enqueue(isCacheMiss[0]),

    .OUT_ld(LMQ_ld),
    .IN_dequeue(!stall[0] && LMQ_ld.valid)
);

typedef struct packed
{
    logic[TAG_LEN-1:0] addr;
    logic valid;
    logic dirty;
    logic used;
} CacheTableEntry;

typedef struct packed
{
    logic[31:0] addr;
    logic isMgmt;
    logic[1:0] mgmtOp;
    logic isMMIO;
    logic isLoad;
    logic external;
    AGU_Exception exception;
    logic valid;
} CommonUOp;

CommonUOp uops[TOTAL_UOPS-1:0];
always_comb begin
    uops[0].valid = uopLd.valid && (uopLd.external || !IN_branch.taken || $signed(uopLd.sqN - IN_branch.sqN) <= 0);
    uops[0].exception = uopLd.exception;
    uops[0].isLoad = 1;
    uops[0].isMgmt = 0;
    uops[0].external = uopLd.external;
    uops[0].mgmtOp = 'x;
    uops[0].addr = uopLd.addr;

    uops[1].valid = IN_uopSt.valid;
    uops[1].exception = AGU_NO_EXCEPTION;
    uops[1].isLoad = 0;
    uops[1].isMgmt = IN_uopSt.wmask == 0;
    uops[1].external = 0;
    uops[1].mgmtOp = IN_uopSt.data[1:0];
    uops[1].addr = IN_uopSt.addr;
end

assign OUT_fenceBusy = flushActive || IN_fence;
reg flushActive;
reg flushWaiting;
reg[$clog2(SIZE):0] flushIter;
wire[$clog2(LEN)-1:0] flushIdx = flushIter[$clog2(SIZE)-1:$clog2(ASSOC)];
wire[$clog2(ASSOC)-1:0] flushAssocIdx = flushIter[$clog2(ASSOC)-1:0];

CacheTableEntry ctable[LEN-1:0][ASSOC-1:0];
reg cacheHit[1:0];
reg[$clog2(ASSOC)-1:0] cacheHitIdx[1:0];
reg cacheFreeAvail[1:0];
reg[$clog2(ASSOC)-1:0] cacheFreeIdx[1:0];
reg[$clog2(ASSOC)-1:0] cacheEvictIdx[1:0];
reg[$clog2(LEN)-1:0] cacheIdx[1:0];
always_comb begin
    
    /* verilator lint_off VARHIDDEN */
    for (integer i = 0; i < TOTAL_UOPS; i=i+1) begin
        cacheHit[i] = 0;
        cacheFreeAvail[i] = 0;
        cacheHitIdx[i] = 'x;
        cacheFreeIdx[i] = 'x;
        cacheEvictIdx[i] = 0;

        cacheIdx[i] = uops[i].addr[CLSIZE_E+$clog2(LEN)-1:CLSIZE_E];

        for (integer j = 0; j < ASSOC; j=j+1)
            if (ctable[cacheIdx[i]][j].valid &&
                ctable[cacheIdx[i]][j].addr == uops[i].addr[31:CLSIZE_E+$clog2(LEN)]) begin
                
                cacheHit[i] = 1;
                cacheHitIdx[i] = j[$clog2(ASSOC)-1:0];
            end

        for (integer j = 0; j < ASSOC; j=j+1)
            if (!ctable[cacheIdx[i]][j].valid) begin
                cacheFreeIdx[i] = j[$clog2(ASSOC)-1:0];
                cacheFreeAvail[i] = 1;
            end

        for (integer j = 0; j < ASSOC; j=j+1)
            if (!ctable[cacheIdx[i]][j].used)
                cacheEvictIdx[i] = j[$clog2(ASSOC)-1:0];
    end
end

reg isMgmt[TOTAL_UOPS-1:0];
reg isMMIO[TOTAL_UOPS-1:0];
reg isCacheHit[TOTAL_UOPS-1:0];
reg isCachePassthru[TOTAL_UOPS-1:0];
reg isCacheMiss[TOTAL_UOPS-1:0];
reg stall[TOTAL_UOPS-1:0];
always_comb begin
    for (integer i = 0; i < TOTAL_UOPS; i=i+1) begin
        
        isMgmt[i] = uops[i].valid && uops[i].isMgmt;

        isMMIO[i] = uops[i].valid && !uops[i].isMgmt &&
            (`IS_MMIO_PMA(uops[i].addr) || uops[i].exception != AGU_NO_EXCEPTION);

        isCacheHit[i] = uops[i].valid && !uops[i].isMgmt && !`IS_MMIO_PMA(uops[i].addr) && cacheHit[i];

        isCachePassthru[i] = uops[i].valid && !uops[i].isMgmt && !`IS_MMIO_PMA(uops[i].addr) &&
            state == LOAD_ACTIVE &&
            OUT_memc.extAddr[29:CLSIZE_E-2] == uops[i].addr[31:CLSIZE_E] &&
            IN_memc.progress[CLSIZE_E-2:0] > {1'b0, uops[i].addr[CLSIZE_E-1:2]};

        isCacheMiss[i] = uops[i].valid && 
            !uops[i].isMgmt &&
            !isMMIO[i] &&
            !isCacheHit[i] &&
            !isCachePassthru[i] &&
            uops[i].exception == AGU_NO_EXCEPTION;

        if (i == 1) begin
            stall[i] = (uops[i].valid && !(isMgmt[i] && state == IDLE && !uops[0].valid /* HACK */) &&
                !isMMIO[i] && !isCacheHit[i] && !isCachePassthru[i]) || IN_stall[i] || flushActive;

            OUT_stall[i] = stall[i];
        end
        else begin
            stall[i] = IN_stall[i] || flushActive;
            OUT_stall[i] = stall[i] || (LMQ_full && isCacheMiss[i]) || LMQ_ld.valid;
        end
    end
end

CommonUOp outUops[TOTAL_UOPS-1:0];
ST_UOp outStUOp_r;
LD_UOp outLdUOp_r;
always_comb begin

    OUT_uopLd = outLdUOp_r;
    OUT_uopLd.valid = outUops[0].valid;
    OUT_uopLd.addr = outUops[0].addr;
    OUT_uopLd.isMMIO = outUops[0].isMMIO;
    OUT_uopLd.external = outUops[0].external;

    OUT_uopSt = outStUOp_r;
    OUT_uopSt.valid = outUops[1].valid;
    OUT_uopSt.addr = outUops[1].addr;
    OUT_uopSt.isMMIO = outUops[1].isMMIO;
    //OUT_uopSt.external = outUops[1].external;
end

enum logic[2:0]
{
    IDLE, EVICT_RQ, EVICT_ACTIVE, LOAD_RQ, LOAD_ACTIVE, REPLACE_RQ, REPLACE_ACTIVE
} state;

reg[29:0] replaceOpNewAddr;
wire[$clog2(LEN)-1:0] curOpIdx = OUT_memc.sramAddr[CLSIZE_E-2+:$clog2(LEN)];
wire[$clog2(ASSOC)-1:0] curOpAssocIdx = OUT_memc.sramAddr[CLSIZE_E+$clog2(LEN)-2+:$clog2(ASSOC)];

always_ff@(posedge clk) begin
    reg temp = 0;
    OUT_memc.data <= 'x;

    if (rst) begin
        OUT_memc.cmd <= MEMC_NONE;
        state <= IDLE;
        flushActive <= 0;
        for (integer i = 0; i < TOTAL_UOPS; i=i+1) begin
            outUops[i] <= 'x;
            outUops[i].valid <= 0;
        end
    end
    else begin
        
        // Evict/Load State Machine
        case (state)
            default: state <= IDLE;
            LOAD_RQ: begin
                if (IN_memc.busy && IN_memc.rqID == 0) begin
                    OUT_memc.cmd <= MEMC_NONE;
                    state <= LOAD_ACTIVE;
                end
            end
            LOAD_ACTIVE: begin
                if (!IN_memc.busy || IN_memc.progress == (1 << (CLSIZE_E - 2))) begin
                    state <= IDLE;
                    ctable[curOpIdx][curOpAssocIdx].valid <= 1;
                    ctable[curOpIdx][curOpAssocIdx].addr <= OUT_memc.extAddr[29:$clog2(LEN)+CLSIZE_E-2];
                end
            end
            EVICT_RQ: begin
                if (IN_memc.busy && IN_memc.rqID == 0) begin
                    OUT_memc.cmd <= MEMC_NONE;
                    state <= EVICT_ACTIVE;
                end
            end
            EVICT_ACTIVE: begin
                if (!IN_memc.busy || IN_memc.progress == (1 << (CLSIZE_E - 2))) begin
                    state <= IDLE;
                end
            end
            REPLACE_RQ: begin
                if (IN_memc.busy && IN_memc.rqID == 0) begin
                    OUT_memc.cmd <= MEMC_NONE;
                    state <= REPLACE_ACTIVE;
                end
            end
            REPLACE_ACTIVE: begin
                if (!IN_memc.busy || IN_memc.progress == (1 << (CLSIZE_E - 2))) begin
                    state <= LOAD_RQ;
                    // sramAddr stays the same
                    OUT_memc.cmd <= MEMC_CP_EXT_TO_CACHE;
                    OUT_memc.extAddr <= replaceOpNewAddr;
                    OUT_memc.cacheID <= 0;
                    OUT_memc.rqID <= 0;
                    replaceOpNewAddr <= 'x;
                end
            end
        endcase
        
        // Flushing Logic
        if (IN_fence) begin
            flushActive <= 0;
            flushWaiting <= 1;
        end
        else if (flushWaiting && IN_SQ_empty && !uops[0].valid && !uops[1].valid && !OUT_uopLd.valid && !OUT_uopSt.valid && state == IDLE) begin
            flushWaiting <= 0;
            flushActive <= 1;
            flushIter <= 0;
        end
        
        // Flush: Iterate through all cache lines and evict them if dirty and invalidate them.
        if (flushActive) begin
            if (flushIter[$bits(flushIter)-1]) begin
                if (state == IDLE) begin
                    flushActive <= 0;
                end
            end
            else if (ctable[flushIdx][flushAssocIdx].valid) begin
                if (ctable[flushIdx][flushAssocIdx].dirty) begin
                    if (state == IDLE) begin
                        
                        state <= EVICT_RQ;
                        OUT_memc.cmd <= MEMC_CP_CACHE_TO_EXT;
                        OUT_memc.sramAddr <= {flushAssocIdx, flushIdx, {(CLSIZE_E-2){1'b0}}};
                        OUT_memc.extAddr <= {ctable[flushIdx][flushAssocIdx].addr, flushIdx, {(CLSIZE_E-2){1'b0}}};
                        OUT_memc.cacheID <= 0;
                        OUT_memc.rqID <= 0;
                        temp = 1;

                        ctable[flushIdx][flushAssocIdx].valid <= 0;
                        ctable[flushIdx][flushAssocIdx].dirty <= 0;
                        ctable[flushIdx][flushAssocIdx].used <= 0;
                        flushIter <= flushIter + 1;
                    end
                end
                else begin
                    ctable[flushIdx][flushAssocIdx].valid <= 0;
                    ctable[flushIdx][flushAssocIdx].dirty <= 0;
                    ctable[flushIdx][flushAssocIdx].used <= 0;
                    flushIter <= flushIter + 1;
                end
            end
            else flushIter <= flushIter + 1;
        end

        // Incoming UOps handling
        for (integer i = 0; i < TOTAL_UOPS; i=i+1) begin
            
            if (!IN_stall[i]) begin
                outUops[i] <= 'x;
                outUops[i].valid <= 0;
            end
            
            if (uops[i].valid && !flushActive) begin

                // Cache Management Ops
                if (isMgmt[i] && state == IDLE && !stall[i]) begin

                    reg dirty = ctable[cacheIdx[i]][cacheHitIdx[i]].dirty;
                    for (integer j = 0; j < TOTAL_UOPS; j=j+1)
                        if (j != i && isCacheHit[j] && 
                            cacheIdx[j] == cacheIdx[i] &&
                            cacheHitIdx[j] == cacheHitIdx[i] &&
                            !uops[j].isLoad) 
                            dirty = 1;

                    assert(!temp);
                    
                    if (uops[i].mgmtOp == 0 || uops[i].mgmtOp == 3) begin // cbo.clean
                        if (cacheHit[i] && dirty) begin
                            state <= EVICT_RQ;
                            OUT_memc.cmd <= MEMC_CP_CACHE_TO_EXT;
                            OUT_memc.sramAddr <= {cacheHitIdx[i], cacheIdx[i], {(CLSIZE_E-2){1'b0}}};
                            OUT_memc.extAddr <= {ctable[cacheIdx[i]][cacheHitIdx[i]].addr, cacheIdx[i], {(CLSIZE_E-2){1'b0}}};
                            OUT_memc.cacheID <= 0;
                            OUT_memc.rqID <= 0;
                            temp = 1;
                        end
                    end

                    if (uops[i].mgmtOp == 1 || uops[i].mgmtOp == 3) begin // cbo.inval
                        if (cacheHit[i]) begin
                            ctable[cacheIdx[i]][cacheHitIdx[i]].valid <= 0;
                            ctable[cacheIdx[i]][cacheHitIdx[i]].dirty <= 0;
                            ctable[cacheIdx[i]][cacheHitIdx[i]].used <= 0;
                            temp = 1;
                        end
                    end
                end

                // MMIO
                else if (isMMIO[i] && !stall[i]) begin
                    outUops[i] <= uops[i];
                    outUops[i].isMMIO <= 1;
                    outUops[i].valid <= 1;
                    if (i == 0) outLdUOp_r <= uopLd;
                    if (i == 1) outStUOp_r <= IN_uopSt;
                end

                // Regular load/store, cache hit
                else if ((isCacheHit[i] || isCachePassthru[i]) && !stall[i]) begin
                    outUops[i] <= uops[i];
                    outUops[i].isMMIO <= 0;
                    outUops[i].valid <= 1;

                    if (isCacheHit[i]) begin
                        outUops[i].addr <= {{{32-CLSIZE_E-$clog2(SIZE)}{1'b0}}, cacheHitIdx[i], cacheIdx[i], uops[i].addr[CLSIZE_E-1:0]};
                        if (!uops[i].isLoad) ctable[cacheIdx[i]][cacheHitIdx[i]].dirty <= 1;
                        // maybe manage used in separate array?
                        for (integer j = 0; j < ASSOC; j=j+1) 
                            ctable[cacheIdx[i]][j].used <= 0;
                        ctable[cacheIdx[i]][cacheHitIdx[i]].used <= 1;
                    end
                    else begin // if (isCachePassthru[i])
                        outUops[i].addr <= {{{32-CLSIZE_E-$clog2(SIZE)}{1'b0}}, curOpAssocIdx, curOpIdx, uops[i].addr[CLSIZE_E-1:0]};

                        if (!uops[i].isLoad) ctable[curOpIdx][curOpAssocIdx].dirty <= 1;
                        ctable[curOpIdx][curOpAssocIdx].used <= 1;
                    end

                    if (i == 0) outLdUOp_r <= uopLd;
                    if (i == 1) outStUOp_r <= IN_uopSt;
                end
                // Evict/Clean/Load cache line
                else if (isCacheMiss[i] && state == IDLE && !temp) begin
                    
                    reg dirty = ctable[cacheIdx[i]][cacheEvictIdx[i]].dirty;
                    for (integer j = 0; j < TOTAL_UOPS; j=j+1)
                        if (j != i && isCacheHit[j] && 
                            cacheIdx[j] == cacheIdx[i] &&
                            cacheHitIdx[j] == cacheEvictIdx[i] &&
                            !uops[j].isLoad) 
                            dirty = 1;
                    
                    if (!cacheFreeAvail[i]) begin
                        ctable[cacheIdx[i]][cacheEvictIdx[i]].valid <= 0;
                        ctable[cacheIdx[i]][cacheEvictIdx[i]].dirty <= 0;
                        ctable[cacheIdx[i]][cacheEvictIdx[i]].used <= 0;
                    end
                    
                    // Evict if dirty
                    if (dirty && !cacheFreeAvail[i]) begin
                        state <= REPLACE_RQ;
                        OUT_memc.cmd <= MEMC_CP_CACHE_TO_EXT;
                        OUT_memc.sramAddr <= {cacheEvictIdx[i], cacheIdx[i], {(CLSIZE_E-2){1'b0}}};
                        OUT_memc.extAddr <= {ctable[cacheIdx[i]][cacheEvictIdx[i]].addr, cacheIdx[i], {(CLSIZE_E-2){1'b0}}};
                        OUT_memc.cacheID <= 0;
                        OUT_memc.rqID <= 0;
                        replaceOpNewAddr <= {uops[i].addr[31:CLSIZE_E], {(CLSIZE_E-2){1'b0}}};
                        temp = 1;
                    end
                    // Load immediately if clean or free avail
                    else begin
                        state <= LOAD_RQ;
                        OUT_memc.cmd <= MEMC_CP_EXT_TO_CACHE;

                        if (cacheFreeAvail[i])
                            OUT_memc.sramAddr <= {cacheFreeIdx[i], cacheIdx[i], {(CLSIZE_E-2){1'b0}}};
                        else
                            OUT_memc.sramAddr <= {cacheEvictIdx[i], cacheIdx[i], {(CLSIZE_E-2){1'b0}}};

                        OUT_memc.extAddr <= {uops[i].addr[31:CLSIZE_E], {(CLSIZE_E-2){1'b0}}};
                        OUT_memc.cacheID <= 0;
                        OUT_memc.rqID <= 0;
                        temp = 1;
                    end
                end
                
            end
        end
    end
end

endmodule
