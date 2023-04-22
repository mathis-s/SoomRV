module TageTable
#(
    parameter SIZE=64,
    parameter TAG_SIZE=9,
    parameter USF_SIZE=2,
    parameter CNT_SIZE=2,
    parameter INTERVAL=20
)
(
    input wire clk,
    input wire rst,
    
    input wire[$clog2(SIZE)-1:0] IN_readAddr,
    input wire[TAG_SIZE-1:0] IN_readTag,
    output reg OUT_readValid,
    output reg OUT_readTaken,
    
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

typedef struct packed
{
    bit[TAG_SIZE-1:0] tag;
    bit[USF_SIZE-1:0] useful;
    bit[CNT_SIZE-1:0] counter;
} TageEntry;

TageEntry entries[SIZE-1:0];

// Prediction: Read from entry, check tag
always_comb begin
    OUT_readValid = entries[IN_readAddr].tag == IN_readTag;
    OUT_readTaken = entries[IN_readAddr].counter[CNT_SIZE-1];
end

always_comb begin
    OUT_allocAvail = entries[IN_writeAddr].useful == 0;
end

reg[INTERVAL-1:0] decrCnt;
reg decrBit;
always_ff@(posedge clk) begin
         
    if (rst) begin
        decrCnt <= 0;
`ifdef __ICARUS__
        for (integer i = 0; i < SIZE; i=i+1)
            entries[i] <= '0;
`endif
    end
    else if (IN_writeValid) begin
        if (IN_writeUpdate) begin

            // Update prediction counter
            if (IN_writeTaken && entries[IN_writeAddr].counter != {CNT_SIZE{1'b1}})
                entries[IN_writeAddr].counter <= entries[IN_writeAddr].counter + 1;
            else if (!IN_writeTaken && entries[IN_writeAddr].counter != {CNT_SIZE{1'b0}})
                entries[IN_writeAddr].counter <= entries[IN_writeAddr].counter - 1;
            
            // Update useful counter

            // Update when altpred different from final pred
            if (IN_writeUseful) begin
                // Increment if correct, decrement if not.
                if (IN_writeCorrect && entries[IN_writeAddr].useful != {USF_SIZE{1'b1}})
                    entries[IN_writeAddr].useful <= entries[IN_writeAddr].useful + 1;
                else if (!IN_writeCorrect && entries[IN_writeAddr].useful != {USF_SIZE{1'b0}})
                    entries[IN_writeAddr].useful <= entries[IN_writeAddr].useful - 1;
            end
        end
        else if (IN_doAlloc) begin
            if (entries[IN_writeAddr].useful == 0) begin
                entries[IN_writeAddr].tag <= IN_writeTag;
                entries[IN_writeAddr].counter <= {IN_writeTaken, {(CNT_SIZE-1){1'b0}}};
                entries[IN_writeAddr].useful <= 0;
            end
        end
        else if (IN_allocFailed) begin
            assert(entries[IN_writeAddr].useful != 0);
            entries[IN_writeAddr].useful <= entries[IN_writeAddr].useful - 1;
        end
    end
    
    // Clear low or high bit of useful counters alternatingly periodically
    if (decrCnt == 0) begin
        for (integer i = 0; i < SIZE; i=i+1)
            entries[i].useful[decrBit] <= 0;
        decrBit <= !decrBit;
    end
    decrCnt <= decrCnt - 1;
end

endmodule
