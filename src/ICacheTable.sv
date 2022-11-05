
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
    
    output reg[28:0] OUT_lookupAddress,
    output wire OUT_stall,
    
    output IF_MemoryController OUT_MC_if,
    input wire IN_MC_cacheID,
    input wire[9:0] IN_MC_progress,
    input wire IN_MC_busy
);
integer i;

ICacheTableEntry icacheTable[NUM_ICACHE_LINES-1:0];
reg cacheEntryFound;
reg[$clog2(NUM_ICACHE_LINES)-1:0] cacheEntryIndex;
always_comb begin
    cacheEntryFound = 0;
    cacheEntryIndex = 0;
    OUT_lookupAddress = 29'bx;
    for (i = 0; i < NUM_ICACHE_LINES; i=i+1) begin
        if (icacheTable[i].valid && icacheTable[i].addr == IN_lookupPC[30:8]) begin
            OUT_lookupAddress = {i[22:0], IN_lookupPC[7:2]};
            cacheEntryFound = 1;
            cacheEntryIndex = i[$clog2(NUM_ICACHE_LINES)-1:0];
        end
    end
end

assign OUT_stall = !cacheEntryFound;
reg[$clog2(NUM_ICACHE_LINES)-1:0] lruPointer;

reg[30:0] loadAddr;
reg loading;
reg waitCycle;

always_ff@(posedge clk) begin
    
    waitCycle <= 0;
    
    if (rst) begin
        for (i = 0; i < NUM_ICACHE_LINES; i=i+1)
            icacheTable[i].valid <= 0;
        lruPointer <= 0;
        loading <= 0;
        OUT_MC_if.ce <= 0;
        OUT_MC_if.we <= 0;
    end
    else begin
    
        OUT_MC_if.ce <= 0;
        OUT_MC_if.we <= 0;
        
        // Mark entries as used
        if (IN_lookupValid && cacheEntryFound)
            icacheTable[cacheEntryIndex].used <= 1;
        
        // Finish current load
        if (loading && waitCycle && IN_MC_cacheID != 1) begin
            loading <= 0;
        end
        else if (loading && !IN_MC_busy && !waitCycle) begin
            icacheTable[lruPointer].addr <= loadAddr[30:8];
            icacheTable[lruPointer].valid <= 1;
            icacheTable[lruPointer].used <= 1;
            lruPointer <= lruPointer + 1;
            loading <= 0;
        end
        // Cache Miss, start load
        else if (!loading && !IN_MC_busy && !cacheEntryFound) begin
            OUT_MC_if.ce <= 1;
            OUT_MC_if.we <= 0;
            OUT_MC_if.sramAddr <= {lruPointer, 7'b0};
            OUT_MC_if.extAddr <= {IN_lookupPC[30:8], 7'b0};
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
