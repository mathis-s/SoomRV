

typedef struct packed
{
    logic[25:0] addr;
    logic valid;
    logic dirty;
    logic used;
} CacheTableEntry;

module CacheController
#(
    parameter SIZE=64,
    parameter NUM_UOPS=1,
    parameter QUEUE_SIZE=4
)
(
    input wire clk,
    input wire rst,
    
    input BranchProv IN_branch,
    
    output wire OUT_stall,
    
    input AGU_UOp IN_uop[NUM_UOPS-1:0],
    output AGU_UOp OUT_uop[NUM_UOPS-1:0],
    
    output reg OUT_MC_ce,
    output reg OUT_MC_we,
    output reg[9:0] OUT_MC_sramAddr,
    output reg[31:0] OUT_MC_extAddr,
    input wire[7:0] IN_MC_progress,
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

reg cacheMiss;
assign OUT_stall = cacheMiss;

// Cache Table Lookups
reg cacheTableEntryFound[NUM_UOPS-1:0];
reg[$clog2(SIZE)-1:0] cacheTableEntry[NUM_UOPS-1:0];
always_comb begin
    for (i = 0; i < NUM_UOPS; i=i+1) begin
        cacheTableEntryFound[i] = 0;
        cacheTableEntry[i] = 6'bx;
        
        for (j = 0; j < SIZE; j=j+1) begin
            if (ctable[j].valid && ctable[j].addr == IN_uop[i].addr[31:6]) begin
                cacheTableEntryFound[i] = 1;
                cacheTableEntry[i] = j[$clog2(SIZE)-1:0];
            end
        end
    end
end

AGU_UOp cmissUOp;

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
        
        cacheMiss <= 0;
        cmissUOp.valid <= 0;
    end
    else begin
        if (ctable[lruPointer].valid && ctable[lruPointer].used) begin
            if (ctable[lruPointer].valid)
                ctable[lruPointer].used <= 0;
            lruPointer <= lruPointer + 1;
        end
        
        // Entry Eviction logic
        if (!loading) begin
            if (evicting) begin
                OUT_MC_ce <= 0;
                OUT_MC_we <= 0;
                
                if (!IN_MC_busy) begin
                    freeEntryAvail <= 1;
                    evicting <= 0;
                end
            end
            else if (!freeEntryAvail) begin
            
                if (!ctable[lruPointer].valid) begin
                    freeEntryAvail <= 1;
                    freeEntryID <= lruPointer;
                end
                else begin
                    OUT_MC_ce <= 1;
                    OUT_MC_we <= 1;
                    
                    OUT_MC_sramAddr <= {lruPointer, 4'b0};
                    OUT_MC_extAddr <= {ctable[lruPointer].addr, 6'b0};
                    
                    ctable[lruPointer].valid <= 0;
                    ctable[lruPointer].used <= 0;
                    freeEntryID <= lruPointer;
                    
                    evicting <= 1;
                end
            end
        end
        
        // Invalidate queued entry
        if (IN_branch.taken) begin
            if ($signed(cmissUOp.sqN - IN_branch.sqN) > 0)
                cmissUOp.valid <= 0;
        end
        
        // Pass through uops that hit cache, enqueue uops that don't
        if (!cacheMiss) begin
            for (i = 0; i < NUM_UOPS; i=i+1) begin
                if (IN_uop[i].valid && (!IN_branch.taken || $signed(IN_uop[i].sqN - IN_branch.sqN) <= 0)) begin
                
                    // Cache hit
                    if (IN_uop[i].exception || cacheTableEntryFound[i]) begin
                        OUT_uop[i] <= IN_uop[i];
                        //OUT_uop[i].addr <= {20'b0, cacheTableEntry[i], IN_uop[i].addr[5:0]};
                        ctable[cacheTableEntry[i]].used <= 1;
                    end
                    // Cache miss
                    else begin
                        cmissUOp <= IN_uop[i];
                        OUT_uop[i].valid <= 0;
                        cacheMiss <= 1;
                    end
                end
                else OUT_uop[i].valid <= 0;
            end
        end
        
        // Handle cache misses
        if (loading) begin
            OUT_MC_ce <= 0;
            if (!IN_MC_busy) begin
                if (cmissUOp.valid && (!IN_branch.taken || $signed(cmissUOp.sqN - IN_branch.sqN) <= 0)) begin
                    OUT_uop[0] <= cmissUOp;
                    //OUT_uop[0].addr <= {20'b0, freeEntryID, cmissUOp.addr[5:0]};
                end
                    
                loading <= 0;
                cacheMiss <= 0;
                cmissUOp.valid <= 0;
                ctable[freeEntryID].valid <= 1;
            end
        end
        else if (cacheMiss && freeEntryAvail && !IN_branch.taken) begin
            OUT_MC_ce <= 1;
            OUT_MC_we <= 0;
            OUT_MC_sramAddr <= {freeEntryID, 4'b0};
            OUT_MC_extAddr <= cmissUOp.addr;
            
            ctable[freeEntryID].used <= 1;
            ctable[freeEntryID].addr <= cmissUOp.addr[31:6];
            loading <= 1;
            freeEntryAvail <= 0;
        end
    end

end


endmodule
