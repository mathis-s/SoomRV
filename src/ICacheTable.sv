
module ICacheTable#(parameter NUM_ICACHE_LINES=32, parameter ASSOC=2, parameter CLSIZE_E=7)
(
    input wire clk,
    input wire rst,
    
    input wire IN_lookupValid,
    input wire[31:0] IN_lookupPC,
    
    output reg[27:0] OUT_lookupAddress,
    output wire OUT_stall,
    
    output CTRL_MemC OUT_memc,
    input STAT_MemC IN_memc
);

localparam LEN = NUM_ICACHE_LINES / ASSOC;
localparam ENTRY_ADDR_LEN = 32 - CLSIZE_E - $clog2(LEN);

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
    cacheIndex = IN_lookupPC[CLSIZE_E+:$clog2(LEN)];
    cacheEntryFound = 0;
    cacheAssocIndex = 0;
    OUT_lookupAddress = 0;

    for (integer i = 0; i < ASSOC; i=i+1) begin
        if (icacheTable[cacheIndex][i].valid && 
            icacheTable[cacheIndex][i].addr == IN_lookupPC[31:CLSIZE_E+$clog2(LEN)]
        ) begin
            OUT_lookupAddress[CLSIZE_E+$clog2(NUM_ICACHE_LINES)-5:0] = 
                {i[$clog2(ASSOC)-1:0], cacheIndex, IN_lookupPC[CLSIZE_E-1:4]};
            cacheEntryFound = 1;
            cacheAssocIndex = i[$clog2(ASSOC)-1:0];
        end
    end
end

assign OUT_stall = (!cacheEntryFound || state != IDLE) && IN_lookupValid;

reg[$clog2(ASSOC)-1:0] loadAssocIdx;
reg[$clog2(LEN)-1:0] loadIdx;

enum logic[1:0]
{
    IDLE,
    LOAD_RQ,
    LOAD_ACTIVE,
    FLUSH_WAIT
} state;

always_ff@(posedge clk) begin
    OUT_memc.data <= 'x;
    if (rst) begin
        for (integer i = 0; i < LEN; i=i+1)
            for (integer j = 0; j < ASSOC; j=j+1)
                icacheTable[i][j].valid <= 0;
        state <= FLUSH_WAIT;
        OUT_memc.cmd <= MEMC_NONE;
    end
    else begin
        if (IN_lookupValid && cacheEntryFound) begin
            if (counters[cacheIndex] == cacheAssocIndex)
                counters[cacheIndex] <= counters[cacheIndex] + 1;
        end

        case (state)
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
                    OUT_memc.sramAddr <= {counters[cacheIndex], cacheIndex, {(CLSIZE_E-2){1'b0}}};
                    OUT_memc.extAddr <= {IN_lookupPC[31:CLSIZE_E], {(CLSIZE_E-2){1'b0}}};
                    OUT_memc.cacheID <= 1;
                    OUT_memc.rqID <= 1;

                    loadIdx <= cacheIndex;
                    loadAssocIdx <= counters[cacheIndex];

                    icacheTable[cacheIndex][counters[cacheIndex]].addr <= IN_lookupPC[31:CLSIZE_E+$clog2(LEN)];
                    icacheTable[cacheIndex][counters[cacheIndex]].valid <= 0;

                    state <= LOAD_RQ;
                end
            end
        endcase
    end
end

endmodule
