typedef struct packed 
{
    bit[5:0] tag;
} BQEntry;

module BranchQueue
#(
    parameter NUM_ENTRIES = 8
)
(
    input wire clk,
    input wire rst,

    input wire IN_valid,
    input wire IN_isBranch,
    input wire[5:0] IN_tag,

    input wire IN_checkedValid,
    input wire[5:0] IN_checkedTag,
    input wire IN_checkedCorrect,
    
    output wire OUT_full,
    output wire OUT_commitLimitValid,
    output wire[5:0] OUT_commitLimitTag
);
integer i;
reg[2:0] index;
BQEntry entries[NUM_ENTRIES-1:0];

assign OUT_commitLimitValid = (index != 0);
assign OUT_commitLimitTag = entries[0].tag;
assign OUT_full = (index == (NUM_ENTRIES[2:0] - 1));

reg checkedIndexFound;
reg[2:0] checkedIndex;
always_comb begin
    checkedIndexFound = 0;
    checkedIndex = NUM_ENTRIES[2:0] - 1;
    for (i = 0; i < NUM_ENTRIES; i=i+1) begin
        // TODO: hint this to be one-hot
        if (!checkedIndexFound && IN_checkedTag == entries[i].tag) begin
            checkedIndex = i[2:0];
            checkedIndexFound = 1;
        end
    end
end 

always_ff@(posedge clk) begin

    if (rst) begin
        index = 0;
    end
    else begin
        if (IN_checkedValid) begin
            if (IN_checkedCorrect) begin
                for (i = {29'b0, checkedIndex}; i < NUM_ENTRIES-1; i=i+1)
                    entries[i] = entries[i+1];

                index = index - 1;
            end
            else begin
                // Branch incorrect, so it and all branches after it are invalid.
                index = checkedIndex;
            end
        end
        
        if (IN_valid && IN_isBranch) begin
            entries[index] = IN_tag;
            index = index + 1;
        end
    end
end


endmodule