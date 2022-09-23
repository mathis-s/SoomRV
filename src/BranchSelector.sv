
module BranchSelector
#(
    parameter NUM_BRANCHES=4
)
(
    input wire clk,
    input wire rst,
    
    input BranchProv IN_branches[NUM_BRANCHES-1:0],
    output BranchProv OUT_branch,
    
    input wire[5:0] IN_ROB_curSqN,
    input wire[5:0] IN_RN_nextSqN,
    output reg OUT_mispredFlush
);

integer i;

reg[5:0] mispredFlushSqN;
reg disableMispredFlush;

always_comb begin
    OUT_branch.taken = 0;
    OUT_branch = 0;
    for (i = 0; i < 4; i=i+1) begin
        if (IN_branches[i].taken && 
            (!OUT_branch.taken || $signed(IN_branches[i].sqN - OUT_branch.sqN) < 0) &&
            (!OUT_mispredFlush || $signed(IN_branches[i].sqN - mispredFlushSqN) < 0)) begin
            OUT_branch.taken = 1;
            OUT_branch.dstPC = IN_branches[i].dstPC;
            OUT_branch.sqN = IN_branches[i].sqN;
            OUT_branch.loadSqN = IN_branches[i].loadSqN;
            OUT_branch.storeSqN = IN_branches[i].storeSqN;
            OUT_branch.flush = IN_branches[i].flush;
        end
    end
end

always_ff@(posedge clk) begin
    
    if (rst) begin
        mispredFlushSqN <= 0;
        disableMispredFlush <= 0;
        OUT_mispredFlush <= 0;
    end
    else if (OUT_branch.taken) begin
        mispredFlushSqN <= OUT_branch.sqN;
        OUT_mispredFlush <= (IN_ROB_curSqN != IN_RN_nextSqN);
        disableMispredFlush <= 0;
    end
    else if (OUT_mispredFlush) begin
        disableMispredFlush <= (IN_ROB_curSqN == IN_RN_nextSqN);
        if (disableMispredFlush)
            OUT_mispredFlush <= 0;
    end

end

endmodule
