
typedef struct packed
{
    logic[22:0] addr;
    logic valid;
    logic used;
} ICacheTableEntry;


module ICacheTable#(parameter NUM_ICACHE_LINES=8)
(
    input wire clk,
    input wire rst,
    
    input wire IN_lookupValid,
    input wire[30:0] IN_lookupPC,
    
    output reg[27:0] OUT_lookupAddress,
    output wire OUT_stall,
    
    output CTRL_MemC OUT_memc,
    input STAT_MemC IN_memc
);
integer i;

ICacheTableEntry icacheTable[NUM_ICACHE_LINES-1:0];
reg cacheEntryFound;
reg[$clog2(NUM_ICACHE_LINES)-1:0] cacheEntryIndex;
always_comb begin
    cacheEntryFound = 0;
    cacheEntryIndex = 0;
    OUT_lookupAddress = 28'bx;
    for (i = 0; i < NUM_ICACHE_LINES; i=i+1) begin
        if (icacheTable[i].valid && icacheTable[i].addr == IN_lookupPC[30:8]) begin
            OUT_lookupAddress = {i[22:0], IN_lookupPC[7:3]};
            cacheEntryFound = 1;
            cacheEntryIndex = i[$clog2(NUM_ICACHE_LINES)-1:0];
        end
    end
    
    if (0 && loading && !waitCycle && IN_lookupPC[30:8] == loadAddr[30:8] && {lastProgress, 1'b0} > {IN_lookupPC[7:2], 2'b11}) begin
        cacheEntryFound = 1;
        cacheEntryIndex = lruPointer;
    end
end

assign OUT_stall = !cacheEntryFound || loading;
reg[$clog2(NUM_ICACHE_LINES)-1:0] lruPointer;

reg[30:0] loadAddr;
reg loading;
reg waitCycle;
reg[6:0] lastProgress;

always_ff@(posedge clk) begin
    
    waitCycle <= 0;
    lastProgress <= IN_memc.progress[6:0];
    OUT_memc.cmd <= MEMC_NONE;
    
    if (rst) begin
        for (i = 0; i < NUM_ICACHE_LINES; i=i+1)
            icacheTable[i].valid <= 0;
        lruPointer <= 0;
        loading <= 0;
    end
    else begin
        // Mark entries as used
        if (IN_lookupValid && cacheEntryFound)
            icacheTable[cacheEntryIndex].used <= 1;
        
        if (loading && IN_memc.cacheID != 1 && IN_memc.busy) begin
            loading <= 0;
        end
        // Finish current load
        else if (loading && !IN_memc.busy && !waitCycle) begin
            icacheTable[lruPointer].addr <= loadAddr[30:8];
            icacheTable[lruPointer].valid <= 1;
            icacheTable[lruPointer].used <= 1;
            lruPointer <= lruPointer + 1;
            loading <= 0;
        end
        // Cache Miss, start load
        else if (!loading && !IN_memc.busy && !cacheEntryFound) begin
            OUT_memc.cmd <= MEMC_CP_EXT_TO_CACHE;
            OUT_memc.sramAddr <= {lruPointer, 7'b0};
            OUT_memc.extAddr <= {IN_lookupPC[30:8], 7'b0};
            OUT_memc.cacheID <= 1;
            icacheTable[lruPointer].valid <= 0;
            loadAddr <= IN_lookupPC;
            loading <= 1;
            waitCycle <= 1;
        end
        else begin
            if (icacheTable[lruPointer].valid && icacheTable[lruPointer].used)
                lruPointer <= lruPointer + 1;
        end
    end
end


endmodule
