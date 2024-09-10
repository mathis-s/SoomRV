
module BranchSelector
#(
    parameter NUM_BRANCHES=4
)
(
    input wire clk,
    input wire rst,

    input IS_UOp IN_isUOps[3:0],

    input BranchProv IN_branches[NUM_BRANCHES-1:0],
    output BranchProv OUT_branch,

    output reg OUT_PERFC_branchMispr,

    input SqN IN_ROB_curSqN,
    input SqN IN_RN_nextSqN,
    input wire IN_mispredFlush
);

logic OUT_PERFC_branchMispr_c;
BranchProv branch_c;
always_ff@(posedge clk) OUT_branch <= branch_c;
always_ff@(posedge clk) OUT_PERFC_branchMispr <= OUT_PERFC_branchMispr_c;

logic[0:0] priorityPort;

always_ff@(posedge clk) begin
    priorityPort <= $signed(IN_isUOps[1].sqN - IN_isUOps[0].sqN) > 0;
end

BranchProv intPortBranch;
always_comb begin
    if (IN_branches[0].taken && (!IN_branches[1].taken || priorityPort))
        intPortBranch = IN_branches[0];
    else
        intPortBranch = IN_branches[1];
end

wire BranchProv[1:0] compBranches = {IN_branches[2], intPortBranch};

always_comb begin

    branch_c = 'x;
    branch_c.flush = 0;
    branch_c.taken = 0;
    OUT_PERFC_branchMispr_c = 0;

    if (compBranches[0].taken && (!compBranches[1].taken || ($signed(compBranches[0].sqN - compBranches[1].sqN) < 0))) begin
        branch_c = compBranches[0];
        if (!IN_mispredFlush)
            OUT_PERFC_branchMispr_c = 1;
    end
    else
        branch_c = compBranches[1];

    if (IN_branches[3].taken) begin
        branch_c = IN_branches[3];
        OUT_PERFC_branchMispr_c = 0;
    end
end

endmodule
