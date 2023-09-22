module CacheWriteInterface
#(parameter ADDR_BITS=10, parameter LEN_BITS=8, parameter IWIDTH=128, parameter CWIDTH=128, parameter ID_LEN=2)
(
    input wire clk,
    input wire rst,
    
    output wire OUT_ready,
    input wire IN_valid,
    input wire[ADDR_BITS-1:0] IN_addr,
    input wire[IWIDTH-1:0] IN_data,
    input wire[ID_LEN-1:0] IN_id,

    output reg OUT_ackValid,
    output reg[ID_LEN-1:0] OUT_ackId, 

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
    logic[IWIDTH-1:0] data;
    logic[ADDR_BITS-1:0] addr;
    logic[$clog2(IWIDTH/CWIDTH):0] idx;
    logic[ID_LEN-1:0] id;
    logic valid;
} Transfer;

Transfer cur;

assign OUT_ready = !cur.valid || (writeValid && cur.idx == ($bits(cur.idx))'((IWIDTH/CWIDTH) - 1));

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
        OUT_CACHE_addr = cur.addr + $bits(cur.addr)'(cur.idx);
        OUT_CACHE_data = cur.data[cur.idx * CWIDTH +: CWIDTH];
    end
end

always_ff@(posedge clk) begin
    
    OUT_ackValid <= 0;
    OUT_ackId <= 'x;

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
            
            OUT_ackValid <= 1;
            OUT_ackId <= cur.id;

            cur <= 'x;
            cur.valid <= 0;
        end

        if (OUT_ready && IN_valid) begin
            cur.valid <= 1;
            cur.addr <= IN_addr;
            cur.data <= IN_data;
            cur.id <= IN_id;
            cur.idx <= 0;
        end
    end
end

endmodule
