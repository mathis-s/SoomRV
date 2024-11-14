module CacheWriteInterface
#(
    parameter ADDR_BITS=10, parameter LEN_BITS=8, parameter IWIDTH=128, parameter CWIDTH=128, parameter ID_LEN=2,
    localparam WNUM = IWIDTH / CWIDTH,
    localparam CNUM = CWIDTH / IWIDTH,
    localparam WIDTH = CWIDTH > IWIDTH ? CWIDTH : IWIDTH,

    localparam CHUNK_END_I = (CWIDTH/IWIDTH),
    localparam CHUNK_END = $clog2((CHUNK_END_I+1))'(CHUNK_END_I),

    localparam WM_LEN = CNUM==0 ? 1 : CNUM,
    localparam CHUNK_LEN = $clog2(CWIDTH/IWIDTH)
)
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
    output reg[WM_LEN-1:0] OUT_CACHE_wm,
    output reg[ADDR_BITS-1:0] OUT_CACHE_addr,
    output reg[CWIDTH-1:0] OUT_CACHE_data
);



typedef struct packed
{
    logic[WIDTH-1:0] data;
    logic[ADDR_BITS-1:0] addr;
    logic[$clog2(IWIDTH/CWIDTH):0] idx;
    logic[ID_LEN-1:0] id;
    logic[WM_LEN-1:0] wm;
    logic valid;
} Transfer;


Transfer cur_r;
Transfer cur_c;

wire addrConflict;
wire[WM_LEN-1:0] wm_new;
wire[CHUNK_LEN==0 ? 0 : CHUNK_LEN-1:0] chunkInsertIdx;
if (IWIDTH >= CWIDTH) begin
    assign wm_new = '1;
    assign addrConflict = 0;
    assign chunkInsertIdx = 0;
    assign OUT_ready = !cur_r.valid;
end
else begin
    assign addrConflict = cur_r.valid && IN_valid &&
        ((cur_r.addr[ADDR_BITS-1:CHUNK_LEN] != IN_addr[ADDR_BITS-1:CHUNK_LEN]));

    assign wm_new = 1 << IN_addr[0+:$clog2(WM_LEN)];
    assign chunkInsertIdx = IN_addr[0+:$clog2(WM_LEN)];
    assign OUT_ready = !cur_r.valid || !&cur_r.addr[0+:CHUNK_LEN];
end

logic writeLast;
logic[ID_LEN-1:0] writeLastId;
always_comb begin
    writeLast = 0;
    writeLastId = 'x;

    OUT_CACHE_ce = 1;
    OUT_CACHE_we = 'x;
    OUT_CACHE_addr = 'x;
    OUT_CACHE_data = 'x;
    OUT_CACHE_wm = 'x;

    cur_c = cur_r;

    if (!cur_c.valid && OUT_ready && IN_valid) begin
        cur_c.valid = 1;
        cur_c.addr = IN_addr;
        cur_c.data[chunkInsertIdx*IWIDTH+:IWIDTH] = (IN_data);
        cur_c.id = IN_id;
        cur_c.idx = 0;
        cur_c.wm |= wm_new;

        if (IWIDTH < CWIDTH) begin
            writeLast = 1;
            writeLastId = cur_c.id;
        end
    end
    else if (cur_c.valid && OUT_ready && IN_valid && !addrConflict) begin
        // we are still accumulating data
        cur_c.data[chunkInsertIdx*IWIDTH+:IWIDTH] = IN_data;
        cur_c.addr = IN_addr;
        cur_c.wm |= wm_new;

        if (IWIDTH < CWIDTH) begin
            writeLast = 1;
            writeLastId = cur_c.id;
        end
    end

    if ((IWIDTH >= CWIDTH || &cur_c.addr[CHUNK_LEN==0 ? 0 : CHUNK_LEN-1:0] || addrConflict) && cur_c.valid && IN_CACHE_ready) begin
        OUT_CACHE_ce = 0;
        OUT_CACHE_we = 0;
        OUT_CACHE_addr = cur_c.addr + $bits(cur_c.addr)'(cur_c.idx);
        OUT_CACHE_data = cur_c.data[cur_c.idx * CWIDTH +: CWIDTH];
        OUT_CACHE_wm = cur_c.wm;
        cur_c.idx = cur_c.idx + 1;

        if (cur_c.idx[$clog2(IWIDTH/CWIDTH)]) begin
            if (IWIDTH >= CWIDTH) begin
                writeLast = 1;
                writeLastId = cur_c.id;
            end
            cur_c = 'x;
            cur_c.valid = 0;
        end
    end

    if (addrConflict && IN_valid) begin
        cur_c.valid = 1;
        cur_c.addr = IN_addr;
        cur_c.data = WIDTH'(IN_data);
        cur_c.id = IN_id;
        cur_c.idx = 0;
        cur_c.wm |= wm_new;

        if (IWIDTH < CWIDTH) begin
            writeLast = 1;
            writeLastId = cur_c.id;
        end
    end
end

always_ff@(posedge clk or posedge rst) begin

    OUT_ackValid <= 0;
    OUT_ackId <= 'x;

    if (rst) begin
        cur_r <= 'x;
        cur_r.valid <= 0;
    end
    else begin
        cur_r <= cur_c;

        if (writeLast) begin
            OUT_ackValid <= 1;
            OUT_ackId <= writeLastId;
        end
    end
end

endmodule
