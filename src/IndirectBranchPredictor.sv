module IndirectBranchPredictor#(parameter NUM_UPDATES=2)
(
    input wire clk,
    input wire rst,
    input wire IN_clearICache,
    
    input IndirBranchInfo IN_ibUpdates[NUM_UPDATES-1:0],
    
    output reg[30:0] OUT_predDst
);

always_ff@(posedge clk) begin

    if (rst || IN_clearICache) begin
        OUT_predDst <= 0;
    end
    else begin
        for (integer i = 0; i < NUM_UPDATES; i=i+1) begin
            if (IN_ibUpdates[i].valid)
                OUT_predDst <= IN_ibUpdates[i].dst;
        end
    end
end

endmodule
