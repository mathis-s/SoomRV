
module ICacheTable#(parameter ASSOC=2, parameter NUM_ICACHE_LINES=(1<<(`CACHE_SIZE_E-`CLSIZE_E)))
(
    input wire clk,
    input wire rst,
    
    input wire IN_lookupValid,
    input wire[31:0] IN_lookupPC,
    
    output reg[27:0] OUT_lookupAddress,
    output wire OUT_stall,
    
    output MemController_Req OUT_memc,
    input MemController_Res IN_memc
);

localparam LEN = NUM_ICACHE_LINES / ASSOC;
localparam ENTRY_ADDR_LEN = 32 - `CLSIZE_E - $clog2(LEN);

typedef struct packed
{
    logic[ENTRY_ADDR_LEN-1:0] addr;
    logic valid;
} ICacheTableEntry;

ICacheTableEntry icacheTable[LEN-1:0][ASSOC-1:0];
reg[$clog2(ASSOC)-1:0] counters[LEN-1:0];

reg doCacheLoad;
reg cacheEntryFound;
reg[$clog2(LEN)-1:0] cacheIndex;
reg[$clog2(ASSOC)-1:0] cacheAssocIndex;
always_comb begin
    cacheIndex = IN_lookupPC[`CLSIZE_E+:$clog2(LEN)];
    cacheEntryFound = 0;
    cacheAssocIndex = 0;
    OUT_lookupAddress = 0;
    doCacheLoad = 1;

    for (integer i = 0; i < ASSOC; i=i+1) begin
        if (icacheTable[cacheIndex][i].valid && 
            icacheTable[cacheIndex][i].addr == IN_lookupPC[31:`CLSIZE_E+$clog2(LEN)]
        ) begin
            OUT_lookupAddress[`CLSIZE_E+$clog2(NUM_ICACHE_LINES)-5:0] = 
                {i[$clog2(ASSOC)-1:0], cacheIndex, IN_lookupPC[`CLSIZE_E-1:4]};
            cacheEntryFound = 1;
            doCacheLoad = 0;
            cacheAssocIndex = i[$clog2(ASSOC)-1:0];
        end
    end

    for (integer i = 0; i < 4; i=i+1) begin
        if (IN_memc.transfers[i].valid && IN_memc.transfers[i].cacheID == 1 &&
            IN_lookupPC[31:`CLSIZE_E] == IN_memc.transfers[i].newAddr[31:`CLSIZE_E]
        ) begin
            cacheEntryFound = 0;
            doCacheLoad = 0;
        end
    end

    if (OUT_memc.cmd != MEMC_NONE && IN_lookupPC[31:`CLSIZE_E] == OUT_memc.extAddr[31:`CLSIZE_E]) begin
        cacheEntryFound = 0;
        doCacheLoad = 0;
    end
end

assign OUT_stall = (!cacheEntryFound || (state != IDLE)) && IN_lookupValid;

reg[$clog2(ASSOC)-1:0] loadAssocIdx;
reg[$clog2(LEN)-1:0] loadIdx;
reg[$clog2(LEN)-1:0] cleanIdx;

enum logic[2:0]
{
    IDLE,
    CLEAN
} state;

always_ff@(posedge clk) begin
    
    if (!(OUT_memc.cmd != MEMC_NONE && IN_memc.stall[0])) begin
        OUT_memc <= '0;
        OUT_memc.cmd <= MEMC_NONE;
    end

    if (rst) begin
        state <= CLEAN;
`ifdef SYNC_RESET
    for (integer i = 0; i < LEN; i=i+1)
        for (integer j = 0; j < ASSOC; j=j+1)
            icacheTable[i][j].valid <= 0;
    state <= IDLE;
`endif
    end
    else begin
        if (IN_lookupValid && cacheEntryFound) begin
            if (counters[cacheIndex] == cacheAssocIndex)
                counters[cacheIndex] <= counters[cacheIndex] + 1;
        end

        case (state)
`ifndef SYNC_RESET
            CLEAN: begin
                for (integer i = 0; i < ASSOC; i=i+1) begin
                    icacheTable[cleanIdx][i] <= 'x;
                    icacheTable[cleanIdx][i].valid <= 0;
                end
                if (cleanIdx == LEN - 1) begin
                    state <= IDLE;
                    cleanIdx <= 'x;
                end
                else cleanIdx <= cleanIdx + 1;
            end
`endif
            default: begin
                state <= IDLE;
                if (doCacheLoad && OUT_memc.cmd == MEMC_NONE) begin
                    OUT_memc.cmd <= MEMC_CP_EXT_TO_CACHE;
                    OUT_memc.sramAddr <= {counters[cacheIndex], cacheIndex, IN_lookupPC[`CLSIZE_E-1:4], 2'b0};
                    OUT_memc.extAddr <= {IN_lookupPC[31:4], 4'b0};
                    OUT_memc.cacheID <= 1;

                    loadIdx <= cacheIndex;
                    loadAssocIdx <= counters[cacheIndex];

                    icacheTable[cacheIndex][counters[cacheIndex]].addr <= IN_lookupPC[31:`CLSIZE_E+$clog2(LEN)];
                    icacheTable[cacheIndex][counters[cacheIndex]].valid <= 1;
                end
            end
        endcase
    end
end

endmodule
