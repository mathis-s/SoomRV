module LoadResultBuffer#(parameter SIZE=8)
(
    input wire clk,
    input wire rst,

    input BranchProv IN_branch,
    input MemController_Res IN_memc,

    input LoadResUOp IN_uop,
    output wire OUT_ready,

    input wire IN_ready,
    output ResultUOp OUT_resultUOp,
    output FlagsUOp OUT_flagsUOp
);

typedef struct packed
{
    logic[$clog2(SIZE)-1:0] idx;
    logic valid;
} IdxN;

LoadResUOp entries[SIZE-1:0];

// Select load to write back
LoadResUOp outLMQ_c;
LoadResUOp enqLMQ_c;

IdxN deq_c;
logic[SIZE-1:0] entryReady;
always_comb
    for (integer i = 0; i < SIZE; i=i+1)
        entryReady[i] = entries[i].valid && entries[i].dataAvail;
PriorityEncoder#(SIZE, 1) deqEnc(entryReady, '{deq_c.idx}, '{deq_c.valid});

always_comb begin
    outLMQ_c = LoadResUOp'{valid: 0, default: 'x};
    enqLMQ_c = IN_uop;

    // Select load result op to output
    if (IN_ready) begin

        if (deq_c.valid) begin
            outLMQ_c = entries[deq_c.idx];
            end
        else if (IN_uop.valid && IN_uop.dataAvail) begin
            outLMQ_c = IN_uop;
            // do not enqueue, we're forwarding
            enqLMQ_c = LoadResUOp'{valid: 0, default: 'x};
        end
    end
end

// Get enqueue index
IdxN enq;
assign OUT_ready = enq.valid;
logic[SIZE-1:0] entryFree;
always_comb
    for (integer i = 0; i < SIZE; i=i+1)
        entryFree[i] = !entries[i].valid;
PriorityEncoder#(SIZE, 1) freeEnc(entryFree, '{enq.idx}, '{enq.valid});

always_ff@(posedge clk or posedge rst) begin
    if (rst) begin
        for (integer i = 0; i < SIZE; i=i+1) begin
            entries[i] <= LoadResUOp'{valid: 0, default: 'x};
        end
    end
    else begin

        // Snoop Results
        for (integer i = 0; i < SIZE; i=i+1) begin
            if (entries[i].valid && !entries[i].dataAvail && IN_memc.ldDataFwd.valid &&
                entries[i].addr[31:$clog2(`AXI_WIDTH/8)] == IN_memc.ldDataFwd.addr[31:$clog2(`AXI_WIDTH/8)]
            ) begin
                entries[i].dataAvail <= 1;
                for (integer j = 0; j < 4; j=j+1)
                    if (!entries[i].fwdMask[j])
                        entries[i].data[8*j+:8] <=
                            IN_memc.ldDataFwd.data[{j[1:0]}*8+:8];
            end
        end

        // Dequeue
        if (deq_c.valid)
            entries[deq_c.idx] <= LoadResUOp'{valid: 0, default: 'x};

        // Enqueue
        if (enqLMQ_c.valid && enq.valid &&
            (!IN_branch.taken || enqLMQ_c.external || $signed(enqLMQ_c.sqN - IN_branch.sqN) <= 0)) begin
            entries[enq.idx] <= enqLMQ_c;
        end

        // Invalidate
        if (IN_branch.taken)
            for (integer i = 0; i < SIZE; i=i+1) begin
                if (entries[i].valid && !entries[i].external &&
                    $signed(entries[i].sqN - IN_branch.sqN) > 0
                ) begin
                    entries[i] <= LoadResUOp'{valid: 0, default: 'x};
                end
            end
    end
end

// Shift/Mask raw loaded data to produce final result/flag uops
ResultUOp resultUOp_c;
always_comb begin
    resultUOp_c = ResultUOp'{valid: 0, default: 'x};
    OUT_flagsUOp = FlagsUOp'{valid: 0, default: 'x};

    if (outLMQ_c.valid) begin
        OUT_flagsUOp.valid = 1;
        OUT_flagsUOp.flags = FLAGS_NONE;
        OUT_flagsUOp.doNotCommit = outLMQ_c.doNotCommit;
        OUT_flagsUOp.tagDst = outLMQ_c.tagDst;
        OUT_flagsUOp.sqN = outLMQ_c.sqN;

        resultUOp_c.valid = 1;
        resultUOp_c.doNotCommit = outLMQ_c.doNotCommit;
        resultUOp_c.tagDst = outLMQ_c.tagDst;

        case (outLMQ_c.size)
            0: resultUOp_c.result =
                {{24{outLMQ_c.sext ? outLMQ_c.data[8*(outLMQ_c.addr[1:0])+7] : 1'b0}},
                outLMQ_c.data[8*(outLMQ_c.addr[1:0])+:8]};

            1: resultUOp_c.result =
                {{16{outLMQ_c.sext ? outLMQ_c.data[16*(outLMQ_c.addr[1])+15] : 1'b0}},
                outLMQ_c.data[16*(outLMQ_c.addr[1])+:16]};

            2: resultUOp_c.result = outLMQ_c.data;
            default: assert(0);
        endcase
    end
end

always_ff@(posedge clk)
    OUT_resultUOp <= resultUOp_c;

endmodule
