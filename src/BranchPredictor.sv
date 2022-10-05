
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
    parameter ID_BITS=6
)
(
    input wire clk,
    input wire rst,
    
    // IF interface
    input wire IN_pcValid,
    input wire[31:0] IN_pc,
    output reg OUT_branchTaken,
    output reg OUT_isJump,
    output reg[31:0] OUT_branchSrc,
    output reg[31:0] OUT_branchDst,
    output reg[ID_BITS-1:0] OUT_branchID,
    output reg OUT_multipleBranches,
    output reg OUT_branchFound,
    output reg OUT_branchCompr,
    
    // Branch XU interface
    input BTUpdate IN_btUpdates[NUM_IN-1:0],
    
    // Branch ROB Interface
    input CommitUOp IN_comUOp,
    
    output reg OUT_CSR_branchCommitted
);

integer i;

reg[ID_BITS-1:0] insertIndex;
BTEntry entries[NUM_ENTRIES-1:0];

// Primes 135037 cycles
// Dhrys 58573 cycles
// BTB lookup for iFetch
always_comb begin
    OUT_branchFound = 0;
    // default not taken
    OUT_branchTaken = 0;
    OUT_multipleBranches = 0;
    OUT_isJump = 1'bx;
    OUT_branchSrc = 32'bx;
    OUT_branchDst = 32'bx;
    OUT_branchID = 6'bx;
    OUT_branchCompr = 1'bx;
    
    // TODO: Compare: Could also have the mux 2x (4x for final design) to extract 0,1,2,3 at the same time.
    // that would allow one-hot encoding and much faster readout.
    if (IN_pcValid)
        for (i = 0; i < NUM_ENTRIES; i=i+1) begin
            if (entries[i].valid && 
                entries[i].srcAddr[31:3] == IN_pc[31:3] && entries[i].srcAddr[2:1] >= IN_pc[2:1] &&
                (!OUT_branchFound || (entries[i].srcAddr[2:1] < OUT_branchSrc[2:1]))) begin
                
                if (OUT_branchFound) OUT_multipleBranches = 1;
                    
                OUT_branchFound = 1;
                OUT_branchTaken = entries[i].taken || entries[i].counters[entries[i].history][1];
                OUT_isJump = entries[i].taken;
                OUT_branchSrc = entries[i].srcAddr;
                OUT_branchDst = entries[i].dstAddr;
                OUT_branchID = i[ID_BITS-1:0];
                OUT_branchCompr = entries[i].compressed;
            end
        end
end

// Try to find valid branch target update
BTUpdate btUpdate;
always_comb begin
    btUpdate = 73'bx;
    btUpdate.valid = 0;
    for (i = 0; i < NUM_IN; i=i+1) begin
        if (IN_btUpdates[i].valid)
            btUpdate = IN_btUpdates[i];
    end
end

always@(posedge clk) begin
    
    OUT_CSR_branchCommitted <= 0;
    
    if (rst) begin
        for (i = 0; i < NUM_ENTRIES; i=i+1) begin
            entries[i].valid <= 0;
        end
        
        insertIndex <= 0;
    end
    
    else if (btUpdate.valid) begin
    
        entries[insertIndex[4:0]].valid <= 1;
        entries[insertIndex[4:0]].used <= 1;
        entries[insertIndex[4:0]].srcAddr <= btUpdate.src;
        entries[insertIndex[4:0]].dstAddr <= btUpdate.dst;
        // only jumps always taken
        entries[insertIndex[4:0]].taken <= btUpdate.isJump;
        entries[insertIndex[4:0]].counters[0] <= 2'b00;
        entries[insertIndex[4:0]].counters[1] <= 2'b10;
        entries[insertIndex[4:0]].counters[2] <= 2'b01;
        entries[insertIndex[4:0]].counters[3] <= 2'b11;
        entries[insertIndex[4:0]].history <= 2'b01;
        entries[insertIndex[4:0]].compressed <= btUpdate.compressed;
        insertIndex <= insertIndex + 1;
    end
    else begin
        // If not valid or not used recently, keep this entry as first to replace
        if (entries[insertIndex[4:0]].valid && entries[insertIndex[4:0]].used) begin
            insertIndex[4:0] <= insertIndex[4:0] + 1;
            entries[insertIndex[4:0]].used <= 0;
        end
    end
    
    // TODO: Currently address check is problematic, as address of uncompressed branches is incremented and might not match anymore.
    // This means there might (rarely) be a branch prediction update coming from the wrong branch.
    if (IN_comUOp.valid && IN_comUOp.isBranch && IN_comUOp.branchID != ((1 << ID_BITS) - 1)/* && {IN_comUOp.pc, 2'b00} == entries[IN_comUOp.branchID[4:0]].srcAddr*/) begin
        
        reg[1:0] hist = entries[IN_comUOp.branchID[4:0]].history;
        
        entries[IN_comUOp.branchID[4:0]].history <= {hist[0], IN_comUOp.branchTaken};
        
        OUT_CSR_branchCommitted <= !entries[IN_comUOp.branchID[4:0]].taken;
        
        if (IN_comUOp.branchTaken) begin
            if (entries[IN_comUOp.branchID[4:0]].counters[hist] != 2'b11)
                entries[IN_comUOp.branchID[4:0]].counters[hist] <= entries[IN_comUOp.branchID[4:0]].counters[hist] + 1;
        end
        else if (entries[IN_comUOp.branchID[4:0]].counters[hist] != 2'b00)
            entries[IN_comUOp.branchID[4:0]].counters[hist] <= entries[IN_comUOp.branchID[4:0]].counters[hist] - 1;
            
    end
    
    if (!rst && IN_pcValid && OUT_branchTaken) begin
        entries[OUT_branchID[4:0]].used <= 1;
    end
end


endmodule
