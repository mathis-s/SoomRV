module Aligner
#(
    parameter WIDTH=32,
    parameter CHUNK=8,
    parameter ADDR_LEN=8,
    parameter OUTPUT_PARTIAL=1,
    localparam NUM_CHUNKS = WIDTH / CHUNK,
    localparam OFFS_LEN = $clog2(NUM_CHUNKS),
    localparam IDX_LEN = ADDR_LEN - OFFS_LEN
)
(
    input logic clk,
    input logic rst,

    input logic IN_clear,

    input logic[NUM_CHUNKS-1:0] IN_valid,
    input logic[NUM_CHUNKS-1:0][CHUNK-1:0] IN_data,
    input logic[ADDR_LEN-1:0] IN_addr,

    output logic[NUM_CHUNKS-1:0] OUT_valid,
    output logic[NUM_CHUNKS-1:0][CHUNK-1:0] OUT_data,
    output logic[ADDR_LEN-1:0] OUT_addr
);

function automatic logic[ADDR_LEN-1:0] AlignAddr(logic[ADDR_LEN-1:0] addr);
    logic[ADDR_LEN-1:0] rv = {addr[OFFS_LEN+:IDX_LEN], OFFS_LEN'(0)};
    return rv;
endfunction

localparam STORAGE_CHUNKS = NUM_CHUNKS - 1;
localparam WINDOW_CHUNKS = NUM_CHUNKS + STORAGE_CHUNKS;

logic[STORAGE_CHUNKS-1:0][CHUNK-1:0] data_r;
logic[ADDR_LEN-1:0] addr_r;
logic[STORAGE_CHUNKS-1:0] valid_r;

logic[WINDOW_CHUNKS-1:0][CHUNK-1:0] data_c;
logic[ADDR_LEN-1:0] addr_c;
logic[WINDOW_CHUNKS-1:0] valid_c;

always_ff@(posedge clk) begin
    if (rst || IN_clear) begin
        data_r <= 'x;
        addr_r <= 'x;
        valid_r <= 0;
    end
    else begin

        if (overflow_c) begin
            data_r <= data_c[NUM_CHUNKS+:STORAGE_CHUNKS];
            valid_r <= valid_c[NUM_CHUNKS+:STORAGE_CHUNKS];
        end
        else if (!OUTPUT_PARTIAL) begin
            data_r <= data_c[0+:STORAGE_CHUNKS];
            valid_r <= valid_c[0+:STORAGE_CHUNKS];
        end
        else if (OUTPUT_PARTIAL) begin
            data_r <= 'x;
            valid_r <= 0;
        end

        addr_r <= addr_c;
    end
end

logic overflow_c;
always_comb begin
    overflow_c = 0;
    OUT_valid = 0;
    OUT_data = 'x;
    OUT_addr = 'x;

    data_c = {{NUM_CHUNKS{ CHUNK'(0) }}, data_r};
    valid_c = {{NUM_CHUNKS{ 1'b0 }}, valid_r};
    addr_c = addr_r;

    if (valid_c == 0)
        addr_c = AlignAddr(IN_addr);

    // insert all input data into data_c
    for (integer i = 0; i < NUM_CHUNKS; i=i+1) begin
        logic[ADDR_LEN-1:0] curAddr = (IN_addr + i[ADDR_LEN-1:0]) - addr_c;
        if (IN_valid[i]) begin
            data_c[curAddr[0+:$clog2(WINDOW_CHUNKS)]] = IN_data[i];
            valid_c[curAddr[0+:$clog2(WINDOW_CHUNKS)]] = 1;

            overflow_c = curAddr >= NUM_CHUNKS-1;
        end
    end

    if (overflow_c || OUTPUT_PARTIAL) begin
        OUT_valid = valid_c[0+:NUM_CHUNKS];
        OUT_data = data_c[0+:NUM_CHUNKS];
        OUT_addr = addr_c;

        if (overflow_c) begin
            addr_c = addr_c + NUM_CHUNKS;
        end
    end
end

endmodule
