module CacheWriteInterface
#(parameter ADDR_BITS=10, parameter LEN_BITS=8, parameter IWIDTH=128, parameter CWIDTH=128, parameter ID_LEN=2)
(
    input wire clk,
    input wire rst,

    output reg OUT_ready,
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


Transfer cur_r;
Transfer cur_c;

assign OUT_ready = !cur_r.valid;

logic writeLast;
logic[ID_LEN-1:0] writeLastId;
always_comb begin
    writeLast = 0;
    writeLastId = 'x;
    cur_c = cur_r;

    if (OUT_ready && IN_valid) begin
        cur_c.valid = 1;
        cur_c.addr = IN_addr;
        cur_c.data = IN_data;
        cur_c.id = IN_id;
        cur_c.idx = 0;
    end

    OUT_CACHE_ce = 1;
    OUT_CACHE_we = 'x;
    OUT_CACHE_addr = 'x;
    OUT_CACHE_data = 'x;

    if (cur_c.valid && IN_CACHE_ready) begin
        OUT_CACHE_ce = 0;
        OUT_CACHE_we = 0;
        OUT_CACHE_addr = cur_c.addr + $bits(cur_c.addr)'(cur_c.idx);
        OUT_CACHE_data = cur_c.data[cur_c.idx * CWIDTH +: CWIDTH];
        cur_c.idx = cur_c.idx + 1;
        if (cur_c.idx[$clog2(IWIDTH/CWIDTH)]) begin
            writeLast = 1;
            writeLastId = cur_c.id;
            cur_c = 'x;
            cur_c.valid = 0;
        end
    end
end

always_ff@(posedge clk) begin

    OUT_ackValid <= 0;
    OUT_ackId <= 'x;

    cur_r <= cur_c;

    if (writeLast) begin
        OUT_ackValid <= 1;
        OUT_ackId <= writeLastId;
    end

    if (rst) begin
        cur_r <= 'x;
        cur_r.valid <= 0;
    end
end

endmodule
