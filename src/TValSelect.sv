module TValSelect#(parameter NUM_TVAL_PROVS=2)
(
    input wire clk,
    input wire rst,
    
    input BranchProv IN_branch,
    input SqN IN_commitSqN,
    input TValProv IN_tvalProvs[NUM_TVAL_PROVS-1:0],
    output TValState OUT_tvalState
);

wire invalidateCurTVal = curTVal.live && (
    $signed(IN_commitSqN - curTVal.sqN) > 0 ||
    (IN_branch.taken && $signed(curTVal.sqN - IN_branch.sqN) > 0));

struct packed
{
    logic[31:0] tval;
    SqN sqN;
    logic live;
} curTVal;
assign OUT_tvalState.tval = curTVal.tval;

TValProv earliest;
always_comb begin
    earliest = 'x;
    earliest.valid = 0;
    for (integer i = 0; i < NUM_TVAL_PROVS; i++) begin
        if (IN_tvalProvs[i].valid && 
            (!earliest.valid || $signed(earliest.sqN - IN_tvalProvs[i].sqN) > 0)
        ) begin
            earliest = IN_tvalProvs[i];
        end
    end
end

always_ff@(posedge clk) begin
    if (rst) begin
        curTVal <= 'x;
        curTVal.live <= 0;
    end
    else begin
        if (invalidateCurTVal) begin
            // keep tval in the register
            curTVal.sqN <= 'x;
            curTVal.live <= 0;
        end
        
        if (earliest.valid && (!curTVal.live || invalidateCurTVal || $signed(curTVal.sqN - earliest.sqN) >= 0)) begin
            curTVal.tval <= earliest.tval;
            curTVal.sqN <= earliest.sqN;
            curTVal.live <= 1;
        end
    end
end

endmodule
