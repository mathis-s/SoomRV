typedef struct packed 
{
    bit[5:0] tag;
} BQEntry;

module BranchQueue
#(
    parameter NUM_IN = 2,
    parameter NUM_ENTRIES = 8
)
(
    input wire clk,
    input wire rst,

    input wire IN_valid[NUM_IN-1:0],
    input wire IN_isBranch[NUM_IN-1:0],
    input wire[5:0] IN_tag[NUM_IN-1:0],
    
    input wire IN_invalidate,
    input wire[5:0] IN_invalidateSqN,
    
    input wire IN_checkedValid,
    input wire[5:0] IN_checkedTag,
    input wire IN_checkedCorrect,
    
    output wire OUT_full,
    output wire OUT_commitLimitValid,
    output wire[5:0] OUT_commitLimitTag
);
integer i;
reg[2:0] indexIn;
reg[2:0] indexOut;
BQEntry entries[NUM_ENTRIES-1:0];

assign OUT_commitLimitValid = (indexIn == indexOut);
assign OUT_commitLimitTag = entries[indexOut].tag;
assign OUT_full = (0); // placeholder

reg checkedIndexFound;
reg[2:0] checkedIndex;

always_comb begin
    checkedIndexFound = 0;
    checkedIndex = NUM_ENTRIES[2:0] - 1;
    for (i = {29'b0, indexOut}; i[2:0] != indexIn; i=i+1) begin
        // TODO: hint this to be one-hot
        if (!checkedIndexFound && IN_checkedTag == entries[i].tag) begin
            checkedIndex = i[2:0];
            checkedIndexFound = 1;
        end
    end
end 

always_ff@(posedge clk) begin

    if (!rst && IN_invalidate) begin
        while (indexIn != indexOut && $signed(entries[indexIn] - IN_invalidateSqN) > 0)
            indexIn = indexIn - 1;
    end
    
    if (rst) begin
        indexIn = 0;
        indexOut = 0;
    end
    else begin
        if (IN_checkedValid) begin
            if (IN_checkedCorrect) begin
                indexOut = indexOut + 1;
            end
            else begin
                // Branch incorrect, so it and all branches after it are invalid.
                indexIn = checkedIndex;
            end
        end
        
        for (i = 0; i < NUM_IN; i=i+1) begin
            if (IN_valid[i] && IN_isBranch[i]) begin
                entries[indexIn] = IN_tag[i];
                indexIn = indexIn + 1;
            end
        end
    end
    
end


endmodule
