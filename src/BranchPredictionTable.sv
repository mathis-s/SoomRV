module BranchPredictionTable
#(
    parameter INDEX_LEN = 8,
    parameter NUM_COUNTERS = (1 << INDEX_LEN)
)
(
    input wire clk,
    input wire rst,
    
    input wire[INDEX_LEN-1:0] IN_readAddr,
    output wire OUT_taken,
    
    input wire IN_writeEn,
    input wire[INDEX_LEN-1:0] IN_writeAddr,
    input wire IN_writeTaken
);
integer i;

reg[1:0] counters[NUM_COUNTERS-1:0];

assign OUT_taken = counters[IN_readAddr][1];

always@(posedge clk) begin
    
    if (rst) begin
        // NOTE: Reset state for easier debugging + perf analysis, remove this before synthesis.
        for (i = 0; i < NUM_COUNTERS; i=i+1) begin
            counters[i] <= 2'b10;
        end
    end
    else begin
        if (IN_writeEn) begin
            if (IN_writeTaken) 
                counters[IN_writeAddr] <= (counters[IN_writeAddr] == 2'b11) ? (2'b11) : (counters[IN_writeAddr] + 1);
            else
                counters[IN_writeAddr] <= (counters[IN_writeAddr] == 2'b00) ? (2'b00) : (counters[IN_writeAddr] - 1);
        end
    end
end

endmodule
