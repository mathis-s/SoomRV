module CacheWriteInterface
#(parameter ADDR_BITS=10, parameter LEN_BITS=8, parameter IWIDTH=128, parameter CWIDTH=128)
(
    input wire clk,
    input wire rst,
    
    output wire OUT_ready,
    // Set at start of transaction
    input wire IN_valid,
    input wire[ADDR_BITS-1:0] IN_addr,
    input wire[IWIDTH-1:0] IN_data,

    // Cache Interface
    input wire IN_CACHE_ready,
    output reg OUT_CACHE_ce,
    output reg OUT_CACHE_we,
    output reg[ADDR_BITS-1:0] OUT_CACHE_addr,
    output reg[CWIDTH-1:0] OUT_CACHE_data
);

localparam WNUM = IWIDTH / CWIDTH;

typedef struct packed
{
    reg[IWIDTH-1:0] data;
    reg[ADDR_BITS-1:0] addr;
    reg[$clog2(IWIDTH/CWIDTH):0] idx;
    reg valid;
} Transfer;

Transfer cur;

assign OUT_ready = !cur.valid || (writeValid && cur.idx == 1'((IWIDTH/CWIDTH) - 1));

wire writeValid = !OUT_CACHE_ce && IN_CACHE_ready;
always_comb begin
    
    OUT_CACHE_ce = 1;
    OUT_CACHE_we = 'x;
    OUT_CACHE_addr = 'x;
    OUT_CACHE_data = 'x;
    
    // TODO: forwarding from IN_data
    if (cur.valid) begin
        OUT_CACHE_ce = 0;
        OUT_CACHE_we = 0;
        OUT_CACHE_addr = cur.addr + {{`CACHE_SIZE_E-3{1'b0}}, cur.idx};
        OUT_CACHE_data = cur.data[cur.idx * CWIDTH +: CWIDTH];
    end
end

always_ff@(posedge clk) begin
    if (rst) begin
        cur <= 'x;
        cur.valid <= 0;
    end
    else begin
        reg[$clog2(IWIDTH/CWIDTH):0] nextIdx = cur.idx;

        if (writeValid) begin
            nextIdx = nextIdx + 1;
        end
        
        cur.idx <= nextIdx;
        if (nextIdx[$clog2(IWIDTH/CWIDTH)]) begin
            cur <= 'x;
            cur.valid <= 0;
        end

        if (OUT_ready && IN_valid) begin
            cur.valid <= 1;
            cur.addr <= IN_addr;
            cur.data <= IN_data;
            cur.idx <= 0;
        end
    end
end

endmodule
