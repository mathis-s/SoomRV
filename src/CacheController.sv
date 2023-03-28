

typedef struct packed
{
    logic[23:0] addr;
    logic valid;
    logic dirty;
    logic used;
} CacheTableEntry;

module CacheController
#(
    parameter SIZE=16,
    localparam NUM_UOPS = 2
)
(
    input wire clk,
    input wire rst,
    
    input BranchProv IN_branch,
    input wire IN_SQ_empty,
    
    input wire IN_stall[NUM_UOPS-1:0],
    output wire OUT_stall[NUM_UOPS-1:0],
    
    input AGU_UOp IN_uopLd,
    output AGU_UOp OUT_uopLd,
    
    input ST_UOp IN_uopSt,
    output ST_UOp OUT_uopSt,
    
    output CTRL_MemC OUT_memc,
    input STAT_MemC IN_memc,
    
    input wire IN_fence,
    output wire OUT_fenceBusy
);

integer i;
integer j;


CacheTableEntry ctable[SIZE-1:0];

reg freeEntryAvail;

reg evictReq;
reg evictActive;

reg loadReq;
reg loadActive;

reg[$clog2(SIZE)-1:0] freeEntryID;
reg[$clog2(SIZE)-1:0] lruPointer;
reg[$clog2(SIZE)-1:0] evictingID;

assign OUT_stall[0] = IN_stall[0] || cmissUOpLd.valid;
assign OUT_stall[1] = IN_stall[1] || cmissUOpSt.valid || evictionRq != EV_RQ_NONE;

// Cache Table Lookups
reg cacheTableEntryFound[NUM_UOPS-1:0];
reg[$clog2(SIZE)-1:0] cacheTableEntry[NUM_UOPS-1:0];
always_comb begin
    cacheTableEntryFound[0] = 0;
    cacheTableEntry[0] = 4'bx;
    for (j = 0; j < SIZE; j=j+1) begin
        if (ctable[j].valid && ctable[j].addr == IN_uopLd.addr[31:8]) begin
            cacheTableEntryFound[0] = 1;
            cacheTableEntry[0] = j[$clog2(SIZE)-1:0];
        end
    end
    
    cacheTableEntryFound[1] = 0;
    cacheTableEntry[1] = 4'bx;
    for (j = 0; j < SIZE; j=j+1) begin
        if (ctable[j].valid && ctable[j].addr == IN_uopSt.addr[31:8]) begin
            cacheTableEntryFound[1] = 1;
            cacheTableEntry[1] = j[$clog2(SIZE)-1:0];
        end
    end
end

reg fenceScheduled;
reg fenceActive;
assign OUT_fenceBusy = fenceScheduled || fenceActive || evictReq;

reg empty;
always_comb begin
    empty = 1;
    for (i = 0; i < SIZE; i=i+1)
        if (ctable[i].valid) empty = 0;
end

AGU_UOp cmissUOpLd;
ST_UOp cmissUOpSt;
reg setDirty;

enum logic[1:0] {EV_RQ_NONE, EV_RQ_CLEAN, EV_RQ_FLUSH, EV_RQ_INVAL} evictionRq;
reg[$clog2(SIZE)-1:0] evictionRqID;
reg evictionRqActive;
reg outHistory;

always_ff@(posedge clk) begin
    
    if (rst) begin
        for (i = 0; i < SIZE; i=i+1) begin
            ctable[i].valid <= 0;
            ctable[i].used <= 0;
        end
        lruPointer <= 0;
        
        freeEntryAvail <= 1;
        freeEntryID <= 0;
        
        evictReq <= 0;
        evictActive <= 0;
        
        loadReq <= 0;
        loadActive <= 0;
        
        cmissUOpLd.valid <= 0;
        cmissUOpSt.valid <= 0;
        
        OUT_uopLd.valid <= 0;
        OUT_uopSt.valid <= 0;
        
        OUT_memc.cmd <= MEMC_NONE;
        evictionRq <= EV_RQ_NONE;
    end
    else begin
        reg temp = 0;

        if (fenceActive) begin
            // During fence, we search for used entries using lruPointer to evict them
            if (!ctable[lruPointer].valid)
                lruPointer <= lruPointer + 1;
        end
        else begin
            if (ctable[lruPointer].valid && ctable[lruPointer].used) begin
                if (ctable[lruPointer].valid)
                    ctable[lruPointer].used <= 0;
                lruPointer <= lruPointer + 1;
            end
        end
        
        // Entry Eviction logic
        if (!loadReq) begin
            if (evictReq) begin
                if (!evictActive) begin
                    if (IN_memc.busy && IN_memc.rqID == 0) begin
                        evictActive <= 1;
                        OUT_memc.cmd <= MEMC_NONE;
                    end
                end
                else begin
                    if (!IN_memc.busy) begin
                        if (evictionRqActive)
                            evictionRq <= EV_RQ_NONE;
                        else
                            freeEntryAvail <= 1;
                            
                        evictReq <= 0;
                        evictActive <= 0;
                    end
                end
            end
            else begin
                // Requested eviction
                if (!IN_memc.busy && evictionRq != EV_RQ_NONE) begin
                    
                    if (!ctable[evictionRqID].valid) begin
                        evictionRq <= EV_RQ_NONE;
                    end
                    else if ((!IN_uopLd.valid || OUT_stall[0]) && !OUT_uopLd.valid && 
                        (!IN_uopSt.valid || OUT_stall[1]) && !OUT_uopSt.valid) begin
                        
                        // Clean only pushes new contents of entry back to memory
                        if (evictionRq != EV_RQ_CLEAN) begin
                            ctable[evictionRqID].valid <= 0;
                            ctable[evictionRqID].used <= 0;
                        end
                        else ctable[evictionRqID].dirty <= 0;
                        
                        if (ctable[evictionRqID].dirty && evictionRq != EV_RQ_INVAL) begin
                            OUT_memc.cmd <= MEMC_CP_CACHE_TO_EXT;
                            OUT_memc.sramAddr <= {evictionRqID, 6'b0};
                            OUT_memc.extAddr <= {ctable[evictionRqID].addr, 6'b0};
                            OUT_memc.cacheID <= 0;
                            OUT_memc.rqID <= 0;
                            
                            evictReq <= 1;
                            evictActive <= 0;
                            evictionRqActive <= 1;
                            evictingID <= evictionRqID;
                        end
                        // If not dirty, we're already done
                        else begin
                            evictionRq <= EV_RQ_NONE;
                        end
                    end
                    temp = 1;
                end
                // Regular eviction or fence
                else if ((!freeEntryAvail || fenceActive) && !IN_memc.busy) begin
                
                    if (!ctable[lruPointer].valid) begin
                        freeEntryAvail <= 1;
                        freeEntryID <= lruPointer;
                    end

                    else if ((!ctable[lruPointer].used || fenceActive) && (!IN_uopLd.valid || OUT_stall[0]) && !OUT_uopLd.valid
                    && (!IN_uopSt.valid || OUT_stall[1]) && !OUT_uopSt.valid) begin
                        
                        ctable[lruPointer].valid <= 0;
                        ctable[lruPointer].used <= 0;
                        freeEntryID <= lruPointer;
                            
                        if (ctable[lruPointer].dirty) begin
                            OUT_memc.cmd <= MEMC_CP_CACHE_TO_EXT;
                            OUT_memc.sramAddr <= {lruPointer, 6'b0};
                            OUT_memc.extAddr <= {ctable[lruPointer].addr, 6'b0};
                            OUT_memc.cacheID <= 0;
                            OUT_memc.rqID <= 0;
                            
                            evictReq <= 1;
                            evictActive <= 0;
                            evictionRqActive <= 0;
                            evictingID <= lruPointer;
                        end
                        else freeEntryAvail <= 1;
                    end
                    temp = 1;
                end
            end
        end
        
        // Invalidate cache miss uops
        if (IN_branch.taken && $signed(cmissUOpLd.sqN - IN_branch.sqN) > 0)
            cmissUOpLd.valid <= 0;
        
        // Load Pipeline
        if (!OUT_stall[0] && IN_uopLd.valid && (!IN_branch.taken || $signed(IN_uopLd.sqN - IN_branch.sqN) <= 0)) begin
            // Cache hit
            if (IN_uopLd.exception != AGU_NO_EXCEPTION || cacheTableEntryFound[0] || `IS_MMIO_PMA(IN_uopLd.addr)) begin
                OUT_uopLd <= IN_uopLd;
                if (!`IS_MMIO_PMA(IN_uopLd.addr) && IN_uopLd.exception == AGU_NO_EXCEPTION) begin
                    OUT_uopLd.addr <= {20'b0, cacheTableEntry[0], IN_uopLd.addr[7:0]};
                    ctable[cacheTableEntry[0]].used <= 1;
                end
            end
            // Cache hit, section currently being loaded
            else if (loadActive && IN_uopLd.addr[31:8] == OUT_memc.extAddr[29:6] &&
                (!IN_memc.busy || IN_memc.progress[5:0] > IN_uopLd.addr[7:2])) begin
                
                OUT_uopLd <= IN_uopLd;
                OUT_uopLd.addr[31:0] <= {20'b0, freeEntryID, IN_uopLd.addr[7:0]};
            end
            // Cache miss
            else begin
                cmissUOpLd <= IN_uopLd;
                OUT_uopLd.valid <= 0;
            end
        end
        else if (cmissUOpLd.valid && (!IN_branch.taken || $signed(cmissUOpLd.sqN - IN_branch.sqN) <= 0) &&
            loadActive && 
            cmissUOpLd.addr[31:8] == OUT_memc.extAddr[29:6] &&
            (!IN_memc.busy || IN_memc.progress[5:0] > cmissUOpLd.addr[7:2])) begin

                // Issue the op as soon as the relevant address is available
                OUT_uopLd <= cmissUOpLd;
                OUT_uopLd.addr <= {20'b0, freeEntryID, cmissUOpLd.addr[7:0]};
                cmissUOpLd.valid <= 0;
        end
        else if (!IN_stall[0]) OUT_uopLd.valid <= 0;
        
        
        // Store Pipeline
        if (!OUT_stall[1] && IN_uopSt.valid) begin
            
            // Cache management operations
            if (IN_uopSt.wmask == 0) begin
                assert(evictionRq == EV_RQ_NONE);
                if (cacheTableEntryFound[1]) begin
                    evictionRqID <= cacheTableEntry[1];
                    case (IN_uopSt.data[1:0])
                        0: evictionRq <= EV_RQ_CLEAN;
                        1: evictionRq <= EV_RQ_INVAL;
                        default: evictionRq <= EV_RQ_FLUSH;
                    endcase
                end
                
                OUT_uopSt.valid <= 0;
            end
            // Cache hit
            else if (cacheTableEntryFound[1] || `IS_MMIO_PMA(IN_uopSt.addr)) begin
                OUT_uopSt <= IN_uopSt;
                if (!`IS_MMIO_PMA(IN_uopSt.addr)) begin
                    OUT_uopSt.addr <= {20'b0, cacheTableEntry[1], IN_uopSt.addr[7:0]};
                    ctable[cacheTableEntry[1]].used <= 1;
                    ctable[cacheTableEntry[1]].dirty <= 1;
                end
            end
            // Cache hit, section currently being loaded
            else if (loadActive && IN_uopSt.addr[31:8] == OUT_memc.extAddr[29:6] &&
                (!IN_memc.busy || IN_memc.progress[5:0] > IN_uopSt.addr[7:2])) begin
                OUT_uopSt <= IN_uopSt;
                OUT_uopSt.addr[31:0] <= {20'b0, freeEntryID, IN_uopSt.addr[7:0]};
                setDirty = 1;
            end
            // Cache miss
            else begin
                cmissUOpSt <= IN_uopSt;
                OUT_uopSt.valid <= 0;
            end
        end
        else if (cmissUOpSt.valid &&
            loadActive && 
            cmissUOpSt.addr[31:8] == OUT_memc.extAddr[29:6] &&
            (!IN_memc.busy || IN_memc.progress[5:0] > cmissUOpSt.addr[7:2])) begin

                OUT_uopSt <= cmissUOpSt;
                OUT_uopSt.addr <= {20'b0, freeEntryID, cmissUOpSt.addr[7:0]};
                cmissUOpSt.valid <= 0;
                setDirty = 1;
        end
        else if (!IN_stall[1]) OUT_uopSt.valid <= 0;
        
        // Handle cache misses
        if (loadReq) begin
            if (!loadActive) begin
                if (IN_memc.busy && IN_memc.rqID == 0) begin
                    loadActive <= 1;
                    OUT_memc.cmd <= MEMC_NONE;
                end
            end
            else begin
                if (!IN_memc.busy) begin
                    ctable[freeEntryID].valid <= 1;
                    ctable[freeEntryID].used <= 1;
                    ctable[freeEntryID].dirty <= setDirty;
                    
                    loadReq <= 0;
                    loadActive <= 0;
                end
            end
        end
        else if (!temp && freeEntryAvail && !evictReq && !IN_branch.taken && evictionRq == EV_RQ_NONE) begin
            if (cmissUOpLd.valid) begin
                OUT_memc.cmd <= MEMC_CP_EXT_TO_CACHE;
                OUT_memc.sramAddr <= {freeEntryID, 6'b0};
                OUT_memc.extAddr <= {cmissUOpLd.addr[31:8], 6'b0};
                OUT_memc.cacheID <= 0;
                OUT_memc.rqID <= 0;
                
                ctable[freeEntryID].used <= 1;
                ctable[freeEntryID].addr <= cmissUOpLd.addr[31:8];
                loadReq <= 1;
                loadActive <= 0;
                freeEntryAvail <= 0;
                setDirty = 0;
            end
            else if (cmissUOpSt.valid) begin
                OUT_memc.cmd <= MEMC_CP_EXT_TO_CACHE;
                OUT_memc.sramAddr <= {freeEntryID, 6'b0};
                OUT_memc.extAddr <= {cmissUOpSt.addr[31:8], 6'b0};
                OUT_memc.cacheID <= 0;
                OUT_memc.rqID <= 0;
                
                ctable[freeEntryID].used <= 1;
                ctable[freeEntryID].addr <= cmissUOpSt.addr[31:8];
                loadReq <= 1;
                loadActive <= 0;
                freeEntryAvail <= 0;
                setDirty = 0;
            end
        end
        
        
        if (fenceActive && empty) begin
            fenceActive <= 0;
        end
        else if (fenceScheduled && IN_SQ_empty && 
            (!IN_uopLd.valid && !IN_uopSt.valid && !OUT_uopLd.valid && !OUT_uopSt.valid) && 
            !loadReq && !evictReq && evictionRq == EV_RQ_NONE) begin
            fenceActive <= 1;
            fenceScheduled <= 0;
        end
        else if (IN_fence) begin
            fenceScheduled <= 1;
        end
    end

end


endmodule
