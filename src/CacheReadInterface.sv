module CacheReadInterface
#(parameter ADDR_BITS=10, parameter LEN_BITS=8, parameter IWIDTH=128, parameter CWIDTH=32, parameter BUF_LEN=4, parameter ID_LEN = 2)
(
    input wire clk,
    input wire rst,
    
    // Set at start of transaction
    output wire OUT_ready,
    input wire IN_valid,
    input wire[ID_LEN-1:0] IN_id,
    input wire[LEN_BITS-1:0] IN_len,
    input wire[ADDR_BITS-1:0] IN_addr,

    // Streaming
    input wire IN_ready,
    output logic OUT_valid,
    output logic[ID_LEN-1:0] OUT_id,
    output logic[IWIDTH-1:0] OUT_data,
    output logic OUT_last,
    
    // Cache Interface
    input reg IN_CACHE_ready,
    output reg OUT_CACHE_ce,
    output reg OUT_CACHE_we,
    output reg[ADDR_BITS-1:0] OUT_CACHE_addr,
    input wire[31:0] IN_CACHE_data
);

localparam WNUM = IWIDTH / CWIDTH;

logic[$clog2(BUF_LEN):0] FIFO_free;

logic FIFO_valid;
logic[IWIDTH-1:0] FIFO_data;
logic[ID_LEN-1:0] FIFO_id;
logic FIFO_last;
logic FIFO_ready;

FIFO#(IWIDTH + ID_LEN + 1, BUF_LEN) fifo
(
    .clk(clk),
    .rst(rst),

    .free(FIFO_free),
    .IN_valid(FIFO_valid),
    .IN_data({FIFO_last, FIFO_id, FIFO_data}),
    .OUT_ready(FIFO_ready),

    .OUT_valid(OUT_valid),
    .IN_ready(IN_ready),
    .OUT_data({OUT_last, OUT_id, OUT_data})
);

typedef struct packed
{
    logic[LEN_BITS-1:0] progress;
    logic[LEN_BITS-1:0] len;
    logic[ADDR_BITS-1:0] addr;
    logic[ID_LEN-1:0] id;
    logic valid;
} Transfer;

Transfer cur;
Transfer next;

// Accumulate or pass thru read data
logic[IWIDTH-1:0] acc;
logic[$clog2(WNUM):0] accIdx_r;
logic[$clog2(WNUM):0] accIdx_c;
logic doAcc;
always_comb begin
    accIdx_c = accIdx_r;
    FIFO_valid = 0;
    FIFO_data = 'x;
    FIFO_id = 'x;
    FIFO_last = 'x;
    doAcc = 0;

    if (readSuccSR[1]) begin
        accIdx_c = accIdx_c + 1;
        if (accIdx_c[$clog2(WNUM)]) begin
            FIFO_valid = 1;
            FIFO_data = acc;
            FIFO_data[(WNUM-1) * CWIDTH +: CWIDTH] = IN_CACHE_data;
            FIFO_last = readLastSR[1];
            accIdx_c = 0;
        end
        else doAcc = 1;
    end
end
always_ff@(posedge clk) begin
    if (rst) begin
        accIdx_r <= 0;
    end
    else begin
        accIdx_r <= accIdx_c;
        if (doAcc) begin
            acc[accIdx_r * CWIDTH +: CWIDTH] <= IN_CACHE_data;
            assert(!readLastSR[1]);
        end
    end
end

logic allowNewRead;
always_comb begin
    logic[$clog2(BUF_LEN):0] inFlight = $clog2(BUF_LEN)'(readSuccSR[1]) + $clog2(BUF_LEN)'(readSuccSR[0]);
    allowNewRead = ((FIFO_free * WNUM) > inFlight);
end


// Issue new read
logic readValid;
logic readLast;
logic[ID_LEN-1:0] readId;
always_comb begin
    OUT_CACHE_ce = 1;
    OUT_CACHE_we = 1;
    OUT_CACHE_addr = 'x;
    
    readId = 'x;
    readLast = 'x;
    readValid = 0;

    if (cur.valid && allowNewRead) begin
        OUT_CACHE_ce = 0;
        OUT_CACHE_we = 1;
        OUT_CACHE_addr = {cur.addr[ADDR_BITS-1:`CLSIZE_E-2], cur.addr[`CLSIZE_E-3:0] + cur.progress[`CLSIZE_E-3:0]};
        readId = cur.id;
        readValid = 1;
        readLast = (cur.progress == cur.len);
    end
end

wire readSucc = readValid && IN_CACHE_ready;

logic[1:0] readSuccSR;
logic[1:0] readLastSR;
logic[1:0][ID_LEN-1:0] readIdSR;

assign OUT_ready = !next.valid || (readSucc && readLast);

always_ff@(posedge clk) begin
    
    if (rst) begin
        cur <= 'x;
        cur.valid <= 0;
        next <= 'x;
        next.valid <= 0;
        readSuccSR <= 0;
        readLastSR <= 'x;
        readIdSR <= 'x;
    end
    else begin
        Transfer incoming = Transfer'{default: 'x, valid: 0};

        if (IN_valid && OUT_ready) begin
            incoming.valid = 1;
            incoming.id = IN_id;
            incoming.addr = IN_addr;
            incoming.progress = 0;
            incoming.len = IN_len;
        end

        readSuccSR <= {readSuccSR[0], readSucc};
        readLastSR <= {readLastSR[0], readLast};
        readIdSR <= {readIdSR[0], readId};
        
        if (readSucc) begin
            if (readLast) begin
                if (next.valid) begin
                    cur <= next;
                    next <= Transfer'{default: 'x, valid: 0};
                end
                else begin
                    cur <= incoming;
                    incoming = Transfer'{default: 'x, valid: 0};
                end
            end
            else cur.progress <= cur.progress + 1;
        end
        
        if (incoming.valid) begin
            if (!cur.valid) cur <= incoming;
            else next <= incoming;
        end
    end
end


endmodule
