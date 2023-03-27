module ReturnStack
#(
    parameter NUM_ENTRIES=8
)
(
    input wire clk,
    input wire rst,
    
    input wire IN_valid,
    input wire[30:0] IN_data,
    
    output reg OUT_valid,
    input wire IN_pop,
    output reg[30:0] OUT_data
);

reg[30:0] stack[NUM_ENTRIES-1:0];

reg[$clog2(NUM_ENTRIES)-1:0] index;
reg[$clog2(NUM_ENTRIES):0] numFilled;

always_comb begin
    OUT_valid = (numFilled != 0);
    OUT_data = stack[index-1];
end

always@(posedge clk) begin
    
    if (rst) begin
        index = 0;
        numFilled = 0;
    end
    else begin
        
        if (IN_valid) begin
            stack[index] <= IN_data;
            index = index + 1;
            if (numFilled != NUM_ENTRIES)
                numFilled = numFilled + 1;
        end
        
        if (OUT_valid && IN_pop) begin
            index = index - 1;
            numFilled = numFilled - 1;
        end
    end
end


endmodule
