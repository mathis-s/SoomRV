module BranchPredictor
#(
    parameter NUM_IN=2,
    parameter NUM_ENTRIES=32,
    parameter ID_BITS=12
)
(
    input wire clk,
    input wire rst,
    input wire IN_mispredFlush,
    input BranchProv IN_branch,
    
    // IF interface
    input wire IN_pcValid,
    input wire[31:0] IN_pc,
    output wire OUT_branchTaken,
    output wire OUT_isJump,
    output wire[31:0] OUT_branchSrc,
    output wire[31:0] OUT_branchDst,
    output wire[ID_BITS-1:0] OUT_branchID,
    output wire OUT_multipleBranches,
    output wire OUT_branchFound,
    output wire OUT_branchCompr,
    
    // Branch XU interface
    input BTUpdate IN_btUpdates[NUM_IN-1:0],
    
    
    // Branch ROB Interface
    input CommitUOp IN_comUOp,
    
    output reg OUT_CSR_branchCommitted
);

integer i;

reg[ID_BITS-1:0] gHistory;
reg[ID_BITS-1:0] gHistoryCom;

// Try to find valid branch target update
BTUpdate btUpdate;
always_comb begin
    btUpdate = 67'bx;
    btUpdate.valid = 0;
    for (i = 0; i < NUM_IN; i=i+1) begin
        if (IN_btUpdates[i].valid)
            btUpdate = IN_btUpdates[i];
    end
end

wire[ID_BITS-1:0] hash = (OUT_branchCompr ? OUT_branchSrc[ID_BITS:1] : OUT_branchSrc[ID_BITS:1] - 1) ^ gHistory;

assign OUT_branchID = gHistory;

assign OUT_branchDst[0] = 1'b0;
assign OUT_branchSrc[0] = 1'b0;
BranchTargetBuffer btb
(
    .clk(clk),
    .rst(rst),
    .IN_pcValid(IN_pcValid),
    .IN_pc(IN_pc[31:1]),
    .OUT_branchFound(OUT_branchFound),
    .OUT_branchDst(OUT_branchDst[31:1]),
    .OUT_branchSrc(OUT_branchSrc[31:1]),
    .OUT_branchIsJump(OUT_isJump),
    .OUT_branchCompr(OUT_branchCompr),
    .OUT_multipleBranches(OUT_multipleBranches),
    .IN_BPT_branchTaken(OUT_branchTaken),
    .IN_btUpdate(btUpdate)
);

BranchPredictionTable bpt
(
    .clk(clk),
    .rst(rst),
    .IN_readAddr(hash),
    .OUT_taken(OUT_branchTaken),
    .IN_writeEn(IN_comUOp.valid && IN_comUOp.isBranch && IN_comUOp.predicted && !IN_mispredFlush),
    .IN_writeAddr(IN_comUOp.branchID ^ IN_comUOp.pc[ID_BITS-1:0]),
    .IN_writeTaken(IN_comUOp.branchTaken)
);

always@(posedge clk) begin

    if (rst) begin
        gHistory <= 0;
        gHistoryCom <= 0;
        OUT_CSR_branchCommitted <= 0;
    end
    else begin
        if (OUT_branchFound && !OUT_isJump)
            gHistory <= {gHistory[ID_BITS-2:0], OUT_branchTaken};
        
        if (IN_comUOp.valid && IN_comUOp.isBranch && !IN_mispredFlush) begin
            gHistoryCom <= {gHistoryCom[ID_BITS-2:0], IN_comUOp.branchTaken};
            OUT_CSR_branchCommitted <= 1;
        end
        else OUT_CSR_branchCommitted <= 0;
    end
    
    if (!rst && IN_branch.taken) begin
        if (IN_branch.predicted)
            gHistory <= {IN_branch.branchID[ID_BITS-2:0], IN_branch.branchTaken};
        else
            gHistory <= IN_branch.branchID;
    end
end

endmodule
