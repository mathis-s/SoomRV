module BranchPredictionTable
(
    input wire clk,
    input wire rst,
    
    input wire IN_readValid,
    input wire[`BP_BASEP_ID_LEN-1:0] IN_readAddr,
    output reg OUT_taken,
    
    input wire IN_writeEn,
    input wire[`BP_BASEP_ID_LEN-1:0] IN_writeAddr,
    input wire IN_writeTaken
);

localparam NUM_COUNTERS = (1 << `BP_BASEP_ID_LEN);
reg[1:0] counters[NUM_COUNTERS-1:0];

always_ff@(posedge clk) begin
    if (IN_readValid)
        OUT_taken <= counters[IN_readAddr][1];
end

always_ff@(posedge clk) begin
    
    if (rst) begin
        // NOTE: Reset state for easier debugging + perf analysis, remove this before synthesis.
        `ifdef __ICARUS__
        for (integer i = 0; i < NUM_COUNTERS; i=i+1) begin
            counters[i] <= 2'b10;
        end
        `endif
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
