
module BranchSelector
#(
    parameter NUM_BRANCHES=4
)
(
    input wire clk,
    input wire rst,
    
    input BranchProv IN_branches[NUM_BRANCHES-1:0],
    output BranchProv OUT_branch,
    
    output reg OUT_PERFC_branchMispr,
    
    input SqN IN_ROB_curSqN,
    input SqN IN_RN_nextSqN,
    input wire IN_mispredFlush
);


SqN mispredFlushSqN;
reg disableMispredFlush;

always_comb begin
    OUT_branch = 'x;
    OUT_branch.flush = 0;
    OUT_branch.taken = 0;
    OUT_PERFC_branchMispr = 0;
    
    for (integer i = 0; i < 3; i=i+1) begin
        if (IN_branches[i].taken && 
            (!OUT_branch.taken || $signed(IN_branches[i].sqN - OUT_branch.sqN) < 0) &&
            (!IN_mispredFlush || $signed(IN_branches[i].sqN - mispredFlushSqN) < 0)) begin
            OUT_branch.taken = 1;
            OUT_branch.dstPC = IN_branches[i].dstPC;
            OUT_branch.sqN = IN_branches[i].sqN;
            OUT_branch.loadSqN = IN_branches[i].loadSqN;
            OUT_branch.storeSqN = IN_branches[i].storeSqN;
            if (i == 3)
                OUT_branch.flush = IN_branches[i].flush;
            OUT_branch.fetchID = IN_branches[i].fetchID;
            OUT_branch.history = IN_branches[i].history;
            OUT_branch.rIdx = IN_branches[i].rIdx;
            
            if (i < 2 && !IN_mispredFlush) OUT_PERFC_branchMispr = 1;
        end
    end
    
    if (IN_branches[3].taken && 
        (!IN_mispredFlush || $signed(IN_branches[3].sqN - mispredFlushSqN) < 0)) begin
        OUT_branch.taken = 1;
        OUT_branch.dstPC = IN_branches[3].dstPC;
        OUT_branch.sqN = IN_branches[3].sqN;
        OUT_branch.loadSqN = IN_branches[3].loadSqN;
        OUT_branch.storeSqN = IN_branches[3].storeSqN;
        OUT_branch.flush = IN_branches[3].flush;
        OUT_branch.fetchID = IN_branches[3].fetchID;
        OUT_branch.history = IN_branches[3].history;
        OUT_branch.rIdx = IN_branches[3].rIdx;
        OUT_PERFC_branchMispr = 0;
    end
end

always_ff@(posedge clk) begin
    
    if (rst) begin
        mispredFlushSqN <= 0;
        disableMispredFlush <= 0;
    end
    else if (OUT_branch.taken) begin
        mispredFlushSqN <= OUT_branch.sqN;
    end
end

endmodule
