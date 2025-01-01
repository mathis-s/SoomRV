

module PrefetchPatternDetector
#(
    parameter SR_SIZE = 5,
    parameter FIFO_SIZE = 4
)
(
    input wire clk,
    input wire rst,

    input PrefetchMiss IN_miss,
    output PrefetchPattern OUT_pattern
);

typedef logic[0:0] Len_t;

PrefetchMiss miss;
// verilator lint_off WIDTHEXPAND
wire missAck = !iter.valid || iter.idx == (SR_SIZE - 1);
// verilator lint_on WIDTHEXPAND
FIFO#($bits(IN_miss)-1, FIFO_SIZE, 0, 0) fifo
(
    .clk(clk),
    .rst(rst),
    .free(),

    .IN_valid(IN_miss[0]),
    .IN_data(IN_miss[1+:$bits(IN_miss)-1]),
    .OUT_ready(), // ignore, drop on overflow

    .OUT_valid(miss[0]),
    .IN_ready(missAck),
    .OUT_data(miss[1+:$bits(IN_miss)-1])
);

PrefetchMiss missSR[SR_SIZE-1:0];
PrefetchMiss baseMiss;

// Miss shift register
always_ff@(posedge clk) begin
    if (rst) begin
        for (int i = 0; i < SR_SIZE; i++) begin
            missSR[i] <= PrefetchMiss'{valid: 0, default: 'x};
        end
        baseMiss <= PrefetchMiss'{valid: 0, default: 'x};
    end
    else begin
        if (miss.valid && missAck) begin
            missSR[0] <= miss;
            for (int i = 1; i < SR_SIZE; i++)
                missSR[i] <= missSR[i-1];
            baseMiss <= missSR[SR_SIZE-1];
        end
    end
end


typedef struct packed
{
    logic[$clog2(SR_SIZE)-1:0] idx;
    logic valid;
} IdxN;


logic[SR_SIZE-1:0] hit_oh_c;
always_comb begin
    for (integer i = 0; i < SR_SIZE; i=i+1) begin
        hit_oh_c[i] = missSR[i].addr == predAddr;
    end
end
IdxN hit_c;
PriorityEncoder#(SR_SIZE, 1) penc(hit_oh_c, '{hit_c.idx}, '{hit_c.valid});

wire PFAddr_t predAddr_c = missSR[iter.idx + 1].addr * 2 - baseMiss.addr;

wire[`VIRT_IDX_LEN-`CLSIZE_E-1:0] stride = (`VIRT_IDX_LEN - `CLSIZE_E)'((predAddr - baseMiss.addr) >> 1);
PFStride_t strideEnc;
logic strideEncValid;
always_comb begin
    strideEncValid = 1;
    case (stride)
        //-2: strideEnc = STRIDE_M_TWO;
        -1: strideEnc = STRIDE_M_ONE;
        1: strideEnc = STRIDE_ONE;
        //2: strideEnc = STRIDE_TWO;
        default: begin
            strideEncValid = 0;
            strideEnc = 'x;
        end
    endcase
end


PFAddr_t predAddr;
IdxN iter;
always_ff@(posedge clk) begin
    OUT_pattern <= PrefetchPattern'{valid: 0, default: 'x};
    if (rst) begin
        iter <= IdxN'{valid: 0, default: '1};
    end
    else begin

        if (iter.valid) begin
            iter.idx <= iter.idx + 1;
            predAddr <= predAddr_c;

            if (hit_c.valid && strideEncValid) begin
                iter <= IdxN'{valid: 0, default: '1};
                missSR[iter.idx] <= PrefetchMiss'{valid: 0, default: 'x};
                missSR[hit_c.idx] <= PrefetchMiss'{valid: 0, default: 'x};
                OUT_pattern <= PrefetchPattern'{
                    stride: strideEnc,
                    addr: predAddr + ($signed(predAddr - baseMiss.addr) >>> 1),
                    valid: 1
                };
            end

            if (iter.idx == $clog2(SR_SIZE)'(SR_SIZE-1))
                iter <= IdxN'{valid: 0, default: '1};
        end

        if (miss.valid && missAck) begin
            iter <= IdxN'{valid: 1, idx: 0};
            predAddr <= predAddr_c;
        end
    end
end

endmodule
