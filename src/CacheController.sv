

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
    parameter NUM_UOPS=2,
    parameter QUEUE_SIZE=4
)
(
    input wire clk,
    input wire rst,
    
    input BranchProv IN_branch,
    input wire IN_SQ_empty,
    
    output wire OUT_stall[NUM_UOPS-1:0],
    
    input AGU_UOp IN_uopLd,
    output AGU_UOp OUT_uopLd,
    
    input ST_UOp IN_uopSt,
    output ST_UOp OUT_uopSt,
    
    output reg OUT_MC_ce,
    output reg OUT_MC_we,
    output reg[9:0] OUT_MC_sramAddr,
    output reg[31:0] OUT_MC_extAddr,
    input wire[9:0] IN_MC_progress,
    input wire IN_MC_busy
);

integer i;
integer j;


CacheTableEntry ctable[SIZE-1:0];
reg freeEntryAvail;
reg evicting;
reg loading;
reg[$clog2(SIZE)-1:0] freeEntryID;
reg[$clog2(SIZE)-1:0] lruPointer;

assign OUT_stall[0] = cmissUOpLd.valid || waitCycle;
assign OUT_stall[1] = cmissUOpSt.valid || loading || evicting || waitCycle;

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

AGU_UOp cmissUOpLd;
ST_UOp cmissUOpSt;
reg waitCycle;
reg setDirty;

always_comb begin
    reg duplicate = 0;
    for (i = 0; i < SIZE; i=i+1)
        for (j = 0; j < SIZE; j=j+1)
            if (i != j)
                if (ctable[i].valid && ctable[j].valid && ctable[i].addr == ctable[j].addr)
                    duplicate = 1;
    assert(!duplicate);
end

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
        
        OUT_MC_ce <= 0;
        OUT_MC_we <= 0;
        
        evicting <= 0;
        loading <= 0;
        
        cmissUOpLd.valid <= 0;
        cmissUOpSt.valid <= 0;
        
        waitCycle <= 0;
        
        OUT_uopLd.valid <= 0;
        OUT_uopSt.valid <= 0;
    end
    else begin
        waitCycle <= 0;
        
        if (ctable[lruPointer].valid && ctable[lruPointer].used) begin
            if (ctable[lruPointer].valid)
                ctable[lruPointer].used <= 0;
            lruPointer <= lruPointer + 1;
        end
        
        // Entry Eviction logic
        if (!loading) begin
            if (evicting && !waitCycle) begin
                OUT_MC_ce <= 0;
                OUT_MC_we <= 0;
                
                if (!IN_MC_busy) begin
                    freeEntryAvail <= 1;
                    evicting <= 0;
                end
            end
            else if (!freeEntryAvail && !evicting) begin
            
                if (!ctable[lruPointer].valid) begin
                    freeEntryAvail <= 1;
                    freeEntryID <= lruPointer;
                end

                else if (!ctable[lruPointer].used && (!IN_uopLd.valid || OUT_stall[0]) && !OUT_uopLd.valid
                && (!IN_uopSt.valid || OUT_stall[1]) && !OUT_uopSt.valid) begin
                    
                    ctable[lruPointer].valid <= 0;
                    ctable[lruPointer].used <= 0;
                    freeEntryID <= lruPointer;
                        
                    if (ctable[lruPointer].dirty) begin
                        OUT_MC_ce <= 1;
                        OUT_MC_we <= 1;
                        
                        OUT_MC_sramAddr <= {lruPointer, 6'b0};
                        OUT_MC_extAddr <= {2'b0, ctable[lruPointer].addr, 6'b0};
                        
                        evicting <= 1;
                        waitCycle <= 1;
                    end
                    else freeEntryAvail <= 1;
                end
            end
        end
        
        // Invalidate cache miss uops
        if (IN_branch.taken && $signed(cmissUOpLd.sqN - IN_branch.sqN) > 0)
            cmissUOpLd.valid <= 0;
        
        // Load Pipeline
        if (!OUT_stall[0] && IN_uopLd.valid && (!IN_branch.taken || $signed(IN_uopLd.sqN - IN_branch.sqN) <= 0)) begin
            // Cache hit
            if (IN_uopLd.exception || cacheTableEntryFound[0] || IN_uopLd.addr[31:24] >= 8'hfe) begin
                OUT_uopLd <= IN_uopLd;
                if (IN_uopLd.addr[31:24] < 8'hfe && !IN_uopLd.exception)
                    OUT_uopLd.addr <= {20'b0, cacheTableEntry[0], IN_uopLd.addr[7:0]};
                ctable[cacheTableEntry[0]].used <= 1;
            end
            // Cache hit, section currently being loaded
            else if (loading && (!waitCycle) && IN_uopLd.addr[31:8] == OUT_MC_extAddr[29:6] &&
                (!IN_MC_busy || IN_MC_progress[5:0] > IN_uopLd.addr[7:2])) begin
                
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
            loading && !waitCycle && 
            cmissUOpLd.addr[31:8] == OUT_MC_extAddr[29:6] &&
            (!IN_MC_busy || IN_MC_progress[5:0] > cmissUOpLd.addr[7:2])) begin

                // Issue the op as soon as the relevant address is available
                OUT_uopLd <= cmissUOpLd;
                OUT_uopLd.addr <= {20'b0, freeEntryID, cmissUOpLd.addr[7:0]};
                cmissUOpLd.valid <= 0;
        end
        else OUT_uopLd.valid <= 0;
        
        
        // Store Pipeline
        if (!OUT_stall[1] && IN_uopSt.valid) begin
            // Cache hit
            if (cacheTableEntryFound[1] || IN_uopSt.addr[31:24] >= 8'hfe) begin
                OUT_uopSt <= IN_uopSt;
                if (IN_uopSt.addr[31:24] < 8'hfe)
                    OUT_uopSt.addr <= {20'b0, cacheTableEntry[1], IN_uopSt.addr[7:0]};
                ctable[cacheTableEntry[1]].used <= 1;
                ctable[cacheTableEntry[1]].dirty <= 1;
            end
            // Cache miss
            else begin
                cmissUOpSt <= IN_uopSt;
                OUT_uopSt.valid <= 0;
            end
        end
        else if (cmissUOpSt.valid &&
            loading && !waitCycle && 
            cmissUOpSt.addr[31:8] == OUT_MC_extAddr[29:6] && !IN_MC_busy) begin

                // Issue the op as soon as the relevant address is available
                OUT_uopSt <= cmissUOpSt;
                OUT_uopSt.addr <= {20'b0, freeEntryID, cmissUOpSt.addr[7:0]};
                cmissUOpSt.valid <= 0;
                setDirty = 1;
        end
        else OUT_uopSt.valid <= 0;
        
        
        // Handle cache misses
        if (loading && !waitCycle) begin
            OUT_MC_ce <= 0;
            if (!IN_MC_busy) begin
                    
                loading <= 0;
                ctable[freeEntryID].valid <= 1;
                ctable[freeEntryID].used <= 1;
                ctable[freeEntryID].dirty <= setDirty;
            end
        end
        else if (!loading && freeEntryAvail && !IN_branch.taken) begin
            if (cmissUOpLd.valid) begin
                OUT_MC_ce <= 1;
                OUT_MC_we <= 0;
                OUT_MC_sramAddr <= {freeEntryID, 6'b0};
                OUT_MC_extAddr <= {2'b0, cmissUOpLd.addr[31:8], 6'b0};
                
                ctable[freeEntryID].used <= 1;
                ctable[freeEntryID].addr <= cmissUOpLd.addr[31:8];
                loading <= 1;
                freeEntryAvail <= 0;
                waitCycle <= 1;
                setDirty = 0;
            end
            else if (cmissUOpSt.valid) begin
                OUT_MC_ce <= 1;
                OUT_MC_we <= 0;
                OUT_MC_sramAddr <= {freeEntryID, 6'b0};
                OUT_MC_extAddr <= {2'b0, cmissUOpSt.addr[31:8], 6'b0};
                
                ctable[freeEntryID].used <= 1;
                ctable[freeEntryID].addr <= cmissUOpSt.addr[31:8];
                loading <= 1;
                freeEntryAvail <= 0;
                waitCycle <= 1;
                setDirty = 0;
            end
        end
    end

end


endmodule
