
module PrefetchIssuer#(parameter NUM_ACCESS=2, parameter NUM_STREAMS=4)
(
    input logic clk,
    input logic rst,

    input PrefetchAccess IN_access[NUM_ACCESS-1:0],
    input PrefetchPattern IN_pattern,

    output Prefetch OUT_prefetch,
    input logic IN_prefetchReady,
    input Prefetch_ACK IN_prefetchAck
);

localparam USEFUL_LEN = 2;
localparam PREFETCH_DEPTH = 2;
localparam USEFUL_DEC = 10;

typedef logic[USEFUL_LEN-1:0] UsefulCnt_t;
typedef logic[$clog2(PREFETCH_DEPTH+1)-1:0] DepthCnt_t;

typedef struct packed
{
    DepthCnt_t depth;
    PFStride_t stride;
    PFAddr_t addr;
    UsefulCnt_t useful;
    logic valid;
} PrefetchStream;

typedef struct packed
{
    logic[$clog2(NUM_STREAMS)-1:0] idx;
    logic valid;
} IdxN;

PrefetchStream streams[NUM_STREAMS-1:0];

// Get index of free entry
logic[NUM_STREAMS-1:0] freeUnary_c;
always_comb begin
    for (integer i = 0; i < NUM_STREAMS; i=i+1) begin
        freeUnary_c[i] = !streams[i].valid || !|streams[i].useful;
    end
end
IdxN free_c;
PriorityEncoder#(NUM_STREAMS, 1) freeEnc(freeUnary_c, '{free_c.idx}, '{free_c.valid});
IdxN free_r;
always_ff@(posedge clk) free_r <= free_c;

// Get index of next stream to prefetch for
logic[NUM_STREAMS-1:0] issueUnary_c;
always_comb begin
    for (int i = 0; i < NUM_STREAMS; i++) begin
        issueUnary_c[i] = streams[i].valid && (streams[i].depth != PREFETCH_DEPTH);
    end
end
IdxN issue_c;
PriorityEncoder#(NUM_STREAMS, 1) issueEnc(issueUnary_c, '{issue_c.idx}, '{issue_c.valid});
IdxN issue_r;
always_ff@(posedge clk) issue_r <= issue_c;


// Get Prefetch
wire PrefetchStream issueStream_c = streams[issue_c.idx];
logic[`VIRT_IDX_LEN-`CLSIZE_E-1:0] streamStride_c[NUM_STREAMS-1:0];
always_comb begin
    for (int i = 0; i < NUM_STREAMS; i++) begin
        streamStride_c[i] = 'x;
        case(streams[i].stride)
            STRIDE_M_TWO: streamStride_c[i] = -2;
            STRIDE_M_ONE: streamStride_c[i] = -1;
            STRIDE_ONE: streamStride_c[i] = 1;
            STRIDE_TWO: streamStride_c[i] = 2;
        endcase
    end
end

Prefetch prefetch_c;
always_comb begin
    prefetch_c = Prefetch'{valid: 0, default: 'x};
    if (issue_c.valid) begin
        // verilator lint_off WIDTHEXPAND
        prefetch_c = Prefetch'{
            addr: (issueStream_c.addr + (issueStream_c.depth * streamStride_c[issue_c.idx])) << `CLSIZE_E,
            valid: 1
        };
        // verilator lint_on WIDTHEXPAND
    end
end

always_ff@(posedge clk /*or posedge rst*/) begin
    if (rst)
        OUT_prefetch <= Prefetch'{valid: 0, default: 'x};
    else if (issueReady)
        OUT_prefetch <= prefetch_c;
end

typedef struct packed
{
    logic[1:0] depth;
    PFAddr_t newAddr;
    logic[$clog2(NUM_STREAMS)-1:0] idx;
    logic valid;
} Advance;
Advance advance_c[NUM_ACCESS-1:0];
always_comb begin
    for (int i = 0; i < NUM_ACCESS; i=i+1) begin
        logic kill = 0;
        advance_c[i] = Advance'{valid: 0, default: 'x};
        for (int j = 0; j < NUM_STREAMS; j=j+1) begin
            // verilator lint_off WIDTHTRUNC
            PFAddr_t diff = IN_access[i].addr - streams[j].addr;
            PFAddr_t mod = IN_access[i].addr % (^streams[j].stride ? 1 : 2);
            if (diff > 0 && diff < 4 && mod == 0 && !kill) begin
                advance_c[i] = Advance'{
                    depth: (diff > PREFETCH_DEPTH ? ((1 << $clog2(PREFETCH_DEPTH+1))-1) : diff),
                    newAddr: IN_access[i].addr,
                    idx: j,
                    valid: 1
                };
                kill = 1;
            end
            else if (diff == 0) kill = 1;
            // verilator lint_on WIDTHTRUNC
        end
    end
end

// todo: downsample to 1x
//Advance advance_r[NUM_ACCESS-1:0];
//always_ff@(posedge clk) advance_r <= advance_c;

typedef struct packed
{
    logic[USEFUL_DEC-1:0] cnt;
    logic activeBit;
    logic overflow;
} UsefulDecProc;

UsefulDecProc usefulDec;
always_ff@(posedge clk) begin
    if (rst) begin
        usefulDec <= UsefulDecProc'{default: '0};
    end
    else begin
        {usefulDec.overflow, usefulDec.cnt} <= usefulDec.cnt + 1'b1;
        if (usefulDec.overflow)
            usefulDec.activeBit <= !usefulDec.activeBit;
    end
end

wire issueReady = !OUT_prefetch.valid || IN_prefetchReady;

always_ff@(posedge clk /*or posedge rst*/) begin
    if (rst) begin
        for (integer i = 0; i < NUM_STREAMS; i++) begin
            streams[i] <= PrefetchStream'{valid: 0, default: 'x};
        end
    end
    else begin
        // Enqueue
        if (free_c.valid) begin
            streams[free_c.idx] <= PrefetchStream'{valid: 0, default: 'x};
            if (IN_pattern.valid) begin
                streams[free_c.idx] <= PrefetchStream'{
                    depth: 0,
                    stride: IN_pattern.stride,
                    addr: IN_pattern.addr,
                    useful: 1,
                    valid: 1
                };
            end
        end

        // Issue
        if (issue_c.valid && issueReady) begin
            streams[issue_c.idx].depth <= streams[issue_c.idx].depth + 1;
        end

        // Advance
        for (integer i = 0; i < NUM_ACCESS; i++) begin
            if (advance_c[i].valid) begin
                // verilator lint_off WIDTHEXPAND
                streams[advance_c[i].idx].addr <= advance_c[i].newAddr;

                if (advance_c[i].depth > streams[advance_c[i].idx].depth)
                    streams[advance_c[i].idx].depth <= 0;
                else
                    streams[advance_c[i].idx].depth <= streams[advance_c[i].idx].depth - advance_c[i].depth +
                        1'(issue_c.valid && issueReady && issue_c.idx == advance_c[i].idx);

                // verilator lint_on WIDTHEXPAND

                if (!&streams[advance_c[i].idx].useful)
                    streams[advance_c[i].idx].useful <= streams[advance_c[i].idx].useful + 1;
            end
        end

        // Decrement Useful
        if (usefulDec.overflow) begin
            for (integer i = 0; i < NUM_STREAMS; i++) begin
                streams[i].useful[usefulDec.activeBit] <= 0;
            end
        end

    end
end


endmodule
