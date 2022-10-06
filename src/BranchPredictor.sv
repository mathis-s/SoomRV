
typedef struct packed
{
    bit valid;
    bit used; // for pseudo-LRU
    bit[31:0] srcAddr;
    bit[31:0] dstAddr;
    bit compressed;
    bit taken;  // always taken or dynamic bp?
    bit[1:0] history;
    bit[3:0][1:0] counters;
} BTEntry;

module BranchPredictor
#(
    parameter NUM_IN=2,
    parameter NUM_ENTRIES=32,
    parameter ID_BITS=8
)
(
    input wire clk,
    input wire rst,
    input wire IN_mispredFlush,
    
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
    
    output wire OUT_CSR_branchCommitted
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

wire[ID_BITS-1:0] hash = IN_pc[8:1] ^ gHistory;
// Non-branches (including jumps) get 0 as their ID.
assign OUT_branchID = (OUT_branchFound && !OUT_isJump) ? hash : 0;

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
    .IN_writeEn(IN_comUOp.valid && IN_comUOp.isBranch),
    .IN_writeAddr(IN_comUOp.branchID),
    .IN_writeTaken(IN_comUOp.branchTaken)
);

assign OUT_CSR_branchCommitted = 0;

always@(posedge clk) begin
    
    if (rst) begin
        gHistory <= 0;
        gHistoryCom <= 0;
    end
    else begin
        if (OUT_branchFound && !OUT_isJump)
            gHistory <= {gHistory[6:0], OUT_branchTaken};
        
        if (IN_comUOp.valid && IN_comUOp.isBranch)
            gHistoryCom <= {gHistoryCom[6:0], IN_comUOp.branchTaken};
            
        if (IN_mispredFlush)
            gHistory <= gHistoryCom;
    end
end

endmodule
