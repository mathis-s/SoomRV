module TageTable
#(
    parameter SIZE=64,
    parameter TAG_SIZE=9,
    parameter USF_SIZE=2,
    parameter CNT_SIZE=2,
    parameter INTERVAL=`TAGE_CLEAR_INTERVAL
)
(
    input wire clk,
    input wire rst,

    input wire IN_readValid,
    input wire[$clog2(SIZE)-1:0] IN_readAddr,
    input wire[TAG_SIZE-1:0] IN_readTag,
    output reg OUT_readValid,
    output wire OUT_readTaken,

    input wire IN_writeValid,
    input wire[$clog2(SIZE)-1:0] IN_writeAddr,
    input wire[TAG_SIZE-1:0] IN_writeTag,
    input wire IN_writeTaken,

    input wire IN_writeUpdate,
    input wire IN_writeUseful,
    input wire IN_writeCorrect,

    output reg OUT_allocAvail,
    input wire IN_doAlloc,
    input wire IN_allocFailed
);

BranchPredictionTable#($clog2(SIZE)) counters
(
    .clk(clk),
    .rst(rst),

    .IN_readValid(IN_readValid),
    .IN_readAddr(IN_readAddr),
    .OUT_taken(OUT_readTaken),

    .IN_writeEn(IN_writeValid && (IN_writeUpdate || (IN_doAlloc && useful[IN_writeAddr] == 0))),
    .IN_writeAddr(IN_writeAddr),
    .IN_writeInit(!IN_writeUpdate),
    .IN_writeTaken(IN_writeTaken)
);

logic[TAG_SIZE-1:0] tag[SIZE-1:0];
logic[USF_SIZE-1:0] useful[SIZE-1:0];

// Prediction: Read from entry, check tag

reg[TAG_SIZE-1:0] tagRegA;
reg[TAG_SIZE-1:0] tagRegB;
always_ff@(posedge clk) begin
    if (IN_readValid) begin
        tagRegA <= tag[IN_readAddr];
        tagRegB <= IN_readTag;
    end
end
always_comb begin
    OUT_readValid = (tagRegA == tagRegB);
end

always_comb begin
    OUT_allocAvail = useful[IN_writeAddr] == 0;
end

reg[INTERVAL-1:0] decrCnt;
reg decrBit;
reg[$clog2(SIZE):0] resetIdx;

always_ff@(posedge clk or posedge rst) begin

    if (rst) begin
        decrCnt <= 0;
        resetIdx <= 0;
    end
    else begin
        if (!resetIdx[$clog2(SIZE)]) begin
            tag[resetIdx[$clog2(SIZE)-1:0]] <= 0;
            useful[resetIdx[$clog2(SIZE)-1:0]] <= 0;
            resetIdx <= resetIdx + 1;
        end
        else if (IN_writeValid) begin
            if (IN_writeUpdate) begin
                // Update when altpred different from final pred
                if (IN_writeUseful) begin
                    // Increment if correct, decrement if not.
                    if (IN_writeCorrect && useful[IN_writeAddr] != {USF_SIZE{1'b1}})
                        useful[IN_writeAddr] <= useful[IN_writeAddr] + 1;
                    else if (!IN_writeCorrect && useful[IN_writeAddr] != {USF_SIZE{1'b0}})
                        useful[IN_writeAddr] <= useful[IN_writeAddr] - 1;
                end
            end
            else if (IN_doAlloc) begin
                if (useful[IN_writeAddr] == 0) begin
                    tag[IN_writeAddr] <= IN_writeTag;
                end
            end
            else if (IN_allocFailed) begin
                assert(useful[IN_writeAddr] != 0);
                useful[IN_writeAddr] <= useful[IN_writeAddr] - 1;
            end
        end

`ifdef TAGE_CLEAR_ENABLE
        // Clear low or high bit of useful counters alternatingly periodically
        if (decrCnt == 0) begin
            for (integer i = 0; i < SIZE; i=i+1)
                useful[i][decrBit] <= 0;
            decrBit <= !decrBit;
        end
        decrCnt <= decrCnt - 1;
`endif
    end
end

endmodule
