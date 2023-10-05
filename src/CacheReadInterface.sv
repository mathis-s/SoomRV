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
    input wire IN_mmio,
    input wire[31:0] IN_mmioData,

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
    input wire[CWIDTH-1:0] IN_CACHE_data,

    // Cache Read Info
    output reg OUT_cacheReadValid,
    output reg[ID_LEN-1:0] OUT_cacheReadId
);

localparam WNUM = IWIDTH / CWIDTH;
localparam CWIDTH_W_ = CWIDTH / 32;
localparam CWIDTH_W = LEN_BITS'(CWIDTH_W_);

logic[$clog2(BUF_LEN):0] FIFO_free;

logic FIFO_valid;
logic[IWIDTH-1:0] FIFO_data;
logic[ID_LEN-1:0] FIFO_id;
logic FIFO_last;
logic FIFO_ready;

FIFO#(IWIDTH + ID_LEN + 1, BUF_LEN, 1, 0) fifo
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
    logic[31:0] mmioData;
    logic mmio;

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

    if (readMetaSR[1].valid) begin
        accIdx_c = accIdx_c + 1;

        if (readMetaSR[1].mmio) begin
            FIFO_valid = 1;
            FIFO_data = '0;
            FIFO_data[31:0] = readMetaSR[1].mmioData;
            FIFO_id = readMetaSR[1].id;
            FIFO_last = readMetaSR[1].last;
            assert(accIdx_c == 1);
            accIdx_c = 0;
        end
        else if (accIdx_c[$clog2(WNUM)]) begin
            FIFO_valid = 1;
            FIFO_data = acc;
            FIFO_data[(WNUM-1) * CWIDTH +: CWIDTH] = IN_CACHE_data;
            FIFO_id = readMetaSR[1].id;
            FIFO_last = readMetaSR[1].last;
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
            assert(!readMetaSR[1].last);
        end
    end
end

logic allowNewRead;
always_comb begin
    logic[$clog2(BUF_LEN):0] inFlight = $clog2(BUF_LEN)'(readMetaSR[1].valid) + $clog2(BUF_LEN)'(readMetaSR[1].valid);
    allowNewRead = ((FIFO_free * WNUM) > inFlight);
end

typedef struct packed
{
    logic[31:0] mmioData;
    logic[ID_LEN-1:0] id;
    logic mmio;
    logic last;
    logic valid;
} ReadMeta;

// Issue new read
ReadMeta readMeta;
always_comb begin
    OUT_CACHE_ce = 1;
    OUT_CACHE_we = 1;
    OUT_CACHE_addr = 'x;

    readMeta = ReadMeta'{default: 'x, valid: 0};

    if (cur.valid && allowNewRead) begin

        OUT_CACHE_ce = 0;
        OUT_CACHE_we = 1;
        OUT_CACHE_addr = {cur.addr[ADDR_BITS-1:`CLSIZE_E-2], cur.addr[`CLSIZE_E-3:0] + cur.progress[`CLSIZE_E-3:0]};
        
        readMeta.valid = 1;
        readMeta.id = cur.id;
        readMeta.last = (cur.progress[LEN_BITS-1:$clog2(CWIDTH_W)] == cur.len[LEN_BITS-1:$clog2(CWIDTH_W)]) || cur.mmio;
        readMeta.mmio = cur.mmio;
        readMeta.mmioData = cur.mmioData;
    end
end

wire readSucc = readMeta.valid && (IN_CACHE_ready || readMeta.mmio);
assign OUT_ready = !next.valid || (readSucc && readMeta.last);

// Output read info to inform MemC that
// this location may now be overwritten
always_comb begin
    OUT_cacheReadValid = 0;
    OUT_cacheReadId = 'x;
    if (readSucc) begin
        OUT_cacheReadValid = 1;
        OUT_cacheReadId = readMeta.id;
    end
end

ReadMeta[1:0] readMetaSR;
always_ff@(posedge clk) begin
    
    if (rst) begin
        cur <= 'x;
        cur.valid <= 0;
        next <= 'x;
        next.valid <= 0;
        readMetaSR <= '0;
    end
    else begin
        Transfer incoming = Transfer'{default: 'x, valid: 0};

        if (IN_valid && OUT_ready) begin
            incoming.valid = 1;
            incoming.id = IN_id;
            incoming.addr = IN_addr;
            incoming.progress = 0;
            incoming.len = IN_len;
            
            incoming.mmio = IN_mmio;
            incoming.mmioData = IN_mmioData;
        end
        
        readMetaSR <= {readMetaSR[0], readSucc ? readMeta : '0};
        
        if (readSucc) begin
            if (readMeta.last) begin
                if (next.valid) begin
                    cur <= next;
                    next <= Transfer'{default: 'x, valid: 0};
                end
                else begin
                    cur <= incoming;
                    incoming = Transfer'{default: 'x, valid: 0};
                end
            end
            else cur.progress <= cur.progress + CWIDTH_W;
        end
        
        if (incoming.valid) begin
            if (!cur.valid) cur <= incoming;
            else next <= incoming;
        end
    end
end


endmodule
