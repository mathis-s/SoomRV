

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
    
    output wire OUT_stall,
    
    input AGU_UOp IN_uop[NUM_UOPS-1:0],
    output AGU_UOp OUT_uop[NUM_UOPS-1:0],
    
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

//reg cacheMiss;
assign OUT_stall = cmissUOp[0].valid || cmissUOp[1].valid || loading || evicting || waitCycle;

// Cache Table Lookups
reg cacheTableEntryFound[NUM_UOPS-1:0];
reg[$clog2(SIZE)-1:0] cacheTableEntry[NUM_UOPS-1:0];
always_comb begin
    for (i = 0; i < NUM_UOPS; i=i+1) begin
        cacheTableEntryFound[i] = 0;
        cacheTableEntry[i] = 4'bx;
        
        for (j = 0; j < SIZE; j=j+1) begin
            if (ctable[j].valid && ctable[j].addr == IN_uop[i].addr[31:8]) begin
                cacheTableEntryFound[i] = 1;
                cacheTableEntry[i] = j[$clog2(SIZE)-1:0];
            end
        end
    end
end

AGU_UOp cmissUOp[NUM_UOPS-1:0];
reg[0:0] loadID;
reg waitCycle;

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
        
        cmissUOp[0].valid <= 0;
        cmissUOp[1].valid <= 0;
        
        waitCycle <= 0;
        
        for (i = 0; i < NUM_UOPS; i=i+1)
            OUT_uop[i].valid <= 0;
    end
    else begin
        waitCycle <= 0;
        outHistory <= OUT_uop[0].valid;
        
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
                /*else if (!ctable[lruPointer].dirty) begin
                    freeEntryAvail <= 1;
                    freeEntryID <= lruPointer;
                    ctable[lruPointer].
                end*/
                else if (!ctable[lruPointer].used && IN_SQ_empty && ((!IN_uop[0].valid && !OUT_uop[0].valid && !outHistory) || OUT_stall)) begin
                    OUT_MC_ce <= 1;
                    OUT_MC_we <= 1;
                    
                    OUT_MC_sramAddr <= {lruPointer, 6'b0};
                    OUT_MC_extAddr <= {2'b0, ctable[lruPointer].addr, 6'b0};
                    
                    ctable[lruPointer].valid <= 0;
                    ctable[lruPointer].used <= 0;
                    freeEntryID <= lruPointer;
                    
                    evicting <= 1;
                    waitCycle <= 1;
                end
            end
        end
        
        // Invalidate queued entry
        if (IN_branch.taken) begin
            for (i = 0; i < NUM_UOPS; i=i+1)
                if ($signed(cmissUOp[i].sqN - IN_branch.sqN) > 0)
                    cmissUOp[i].valid <= 0;
        end
        
        // Pass through uops that hit cache, enqueue uops that don't
        if (!cmissUOp[0].valid && !cmissUOp[1].valid) begin
            for (i = 0; i < NUM_UOPS; i=i+1) begin
                if (IN_uop[i].valid && (!IN_branch.taken || $signed(IN_uop[i].sqN - IN_branch.sqN) <= 0)) begin
                
                    // Cache hit
                    if (IN_uop[i].exception || cacheTableEntryFound[i] || IN_uop[i].addr[31:24] >= 8'hfe) begin
                        OUT_uop[i] <= IN_uop[i];
                        if (IN_uop[i].addr[31:24] < 8'hfe)
                            OUT_uop[i].addr <= {20'b0, cacheTableEntry[i], IN_uop[i].addr[7:0]};
                        ctable[cacheTableEntry[i]].used <= 1;
                    end
                    // Cache miss
                    else begin
                        cmissUOp[i] <= IN_uop[i];
                        OUT_uop[i].valid <= 0;
                        //cacheMiss <= 1;
                    end
                end
                else OUT_uop[i].valid <= 0;
            end
        end
        
        // Handle cache misses
        if (loading && !waitCycle) begin
            OUT_MC_ce <= 0;
            if (!IN_MC_busy) begin
                
                for (i = 0; i < NUM_UOPS; i=i+1)
                    if (cmissUOp[i].valid && 
                        cmissUOp[i].addr[31:8] == OUT_MC_extAddr[29:6] && 
                        (!IN_branch.taken || $signed(cmissUOp[i].sqN - IN_branch.sqN) <= 0)) begin
                        OUT_uop[i] <= cmissUOp[i];
                        OUT_uop[i].addr <= {20'b0, freeEntryID, cmissUOp[i].addr[7:0]};
                        cmissUOp[i].valid <= 0;
                    end
                    
                loading <= 0;
                ctable[freeEntryID].valid <= 1;
                ctable[freeEntryID].used <= 1;
            end
        end
        else if (freeEntryAvail && !IN_branch.taken) begin
            reg temp = 0;
            for (i = 0; i < NUM_UOPS; i=i+1) begin
                if (!temp && cmissUOp[i].valid) begin
                    OUT_MC_ce <= 1;
                    OUT_MC_we <= 0;
                    OUT_MC_sramAddr <= {freeEntryID, 6'b0};
                    OUT_MC_extAddr <= {2'b0, cmissUOp[i].addr[31:8], 6'b0};
                    
                    ctable[freeEntryID].used <= 1;
                    ctable[freeEntryID].addr <= cmissUOp[i].addr[31:8];
                    loading <= 1;
                    loadID <= i[0:0];
                    freeEntryAvail <= 0;
                    waitCycle <= 1;
                    temp = 1;
                end
            end
        end
    end

end


endmodule
