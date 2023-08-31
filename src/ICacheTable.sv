
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

reg cacheEntryFound;

reg[$clog2(LEN)-1:0] cacheIndex;
reg[$clog2(ASSOC)-1:0] cacheAssocIndex;
always_comb begin
    cacheIndex = IN_lookupPC[`CLSIZE_E+:$clog2(LEN)];
    cacheEntryFound = 0;
    cacheAssocIndex = 0;
    OUT_lookupAddress = 0;

    for (integer i = 0; i < ASSOC; i=i+1) begin
        if (icacheTable[cacheIndex][i].valid && 
            icacheTable[cacheIndex][i].addr == IN_lookupPC[31:`CLSIZE_E+$clog2(LEN)]
        ) begin
            OUT_lookupAddress[`CLSIZE_E+$clog2(NUM_ICACHE_LINES)-5:0] = 
                {i[$clog2(ASSOC)-1:0], cacheIndex, IN_lookupPC[`CLSIZE_E-1:4]};
            cacheEntryFound = 1;
            cacheAssocIndex = i[$clog2(ASSOC)-1:0];
        end
    end

    if (state == LOAD_ACTIVE && 
        IN_lookupPC[31:`CLSIZE_E] == cacheMissPC[31:`CLSIZE_E] &&
        (IN_memc.progress[`CLSIZE_E-2:2] > (IN_lookupPC[4 +: `CLSIZE_E-4] - cacheMissPC[4 +: `CLSIZE_E-4]))
    ) begin
        cacheEntryFound = 1;
        cacheAssocIndex = loadAssocIdx;
        OUT_lookupAddress[`CLSIZE_E+$clog2(NUM_ICACHE_LINES)-5:0] = 
            {loadAssocIdx, loadIdx, IN_lookupPC[`CLSIZE_E-1:4]};
    end
end

assign OUT_stall = (!cacheEntryFound || (state != IDLE && state != LOAD_ACTIVE)) && IN_lookupValid;

reg[$clog2(ASSOC)-1:0] loadAssocIdx;
reg[$clog2(LEN)-1:0] loadIdx;
reg[$clog2(LEN)-1:0] cleanIdx;
reg[31:0] cacheMissPC;

enum logic[2:0]
{
    IDLE,
    LOAD_RQ,
    LOAD_ACTIVE,
    FLUSH_WAIT,
    CLEAN
} state;

always_ff@(posedge clk) begin
    OUT_memc.data <= 'x;
    if (rst) begin
        state <= CLEAN;
        OUT_memc.cmd <= MEMC_NONE;
`ifdef SYNC_RESET
    for (integer i = 0; i < LEN; i=i+1)
        for (integer j = 0; j < ASSOC; j=j+1)
            icacheTable[i][j].valid <= 0;
    state <= FLUSH_WAIT;
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
                    state <= FLUSH_WAIT;
                    cleanIdx <= 'x;
                end
                else cleanIdx <= cleanIdx + 1;
            end
`endif
            FLUSH_WAIT: begin
                if (!IN_memc.busy || IN_memc.rqID != 1)
                    state <= IDLE;
            end
            LOAD_RQ: begin
                if (IN_memc.busy && IN_memc.rqID == 1) begin
                    OUT_memc.cmd <= MEMC_NONE;
                    state <= LOAD_ACTIVE;
                end
            end
            LOAD_ACTIVE: begin
                if (!IN_memc.busy) begin
                    state <= IDLE;
                    icacheTable[loadIdx][loadAssocIdx].valid <= 1;
                end
            end
            default: begin
                state <= IDLE;
                if (!cacheEntryFound) begin
                    OUT_memc.cmd <= MEMC_CP_EXT_TO_CACHE;
                    OUT_memc.sramAddr <= {counters[cacheIndex], cacheIndex, IN_lookupPC[`CLSIZE_E-1:4], 2'b0};
                    OUT_memc.extAddr <= {IN_lookupPC[31:4], 2'b0};
                    OUT_memc.cacheID <= 1;
                    OUT_memc.rqID <= 1;

                    loadIdx <= cacheIndex;
                    loadAssocIdx <= counters[cacheIndex];

                    icacheTable[cacheIndex][counters[cacheIndex]].addr <= IN_lookupPC[31:`CLSIZE_E+$clog2(LEN)];
                    icacheTable[cacheIndex][counters[cacheIndex]].valid <= 0;
                    
                    cacheMissPC <= IN_lookupPC;
                    state <= LOAD_RQ;
                end
            end
        endcase
    end
end

endmodule
