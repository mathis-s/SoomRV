
typedef struct packed
{
    bit valid;
    bit used; // for pseudo-LRU
    bit[31:0] srcAddr;
    bit[31:0] dstAddr;
    bit taken;  // always taken or dynamic bp?
    bit[1:0] counter; // dynamic bp counter
} BTEntry;

module BranchPredictor
#(
    parameter NUM_IN=2,
    parameter NUM_ENTRIES=8,
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
    
    
    // Branch XU interface
    input wire IN_branchValid,
    input wire[ID_BITS-1:0] IN_branchID,
    input wire[31:0] IN_branchAddr,
    input wire[31:0] IN_branchDest,
    input wire IN_branchTaken,
    input wire IN_branchIsJump
);

integer i;

reg[ID_BITS-1:0] insertIndex;
BTEntry entries[NUM_ENTRIES-1:0];

always_comb begin
    OUT_branchFound = 0;
    // default not taken
    OUT_branchTaken = 0;
    OUT_multipleBranches = 0;
    OUT_isJump = 1'bx;
    OUT_branchSrc = 32'bx;
    OUT_branchDst = 32'bx;
    OUT_branchID = 6'bx;
    
    // TODO: Compare: Could also have the mux 2x (4x for final design) to extract 0,1,2,3 at the same time.
    // that would allow one-hot encoding and much faster readout.
    if (IN_pcValid)
        for (i = 0; i < NUM_ENTRIES; i=i+1) begin
            if (entries[i].valid && 
                entries[i].srcAddr[31:3] == IN_pc[31:3] && entries[i].srcAddr[2:0] >= IN_pc[2:0] &&
                (!OUT_branchFound || (entries[i].srcAddr[2:0] < OUT_branchSrc[2:0]))) begin
                
                if (OUT_branchFound) OUT_multipleBranches = 1;
                    
                OUT_branchFound = 1;
                OUT_branchTaken = entries[i].taken || entries[i].counter[1];
                OUT_isJump = entries[i].taken;
                OUT_branchSrc = entries[i].srcAddr;
                OUT_branchDst = entries[i].dstAddr;
                OUT_branchID = i[ID_BITS-1:0];
            end
        end
end

always@(posedge clk) begin

    if (rst) begin
        for (i = 0; i < NUM_ENTRIES; i=i+1) begin
            entries[i].valid <= 0;
        end
        
        insertIndex <= 0;
    end
    
    else if (IN_branchValid) begin
        
        // No entry yet, create entry
        if (IN_branchTaken && IN_branchID == ((1 << ID_BITS) - 1)) begin
            entries[insertIndex[2:0]].valid <= 1;
            entries[insertIndex[2:0]].used <= 1;
            entries[insertIndex[2:0]].srcAddr <= IN_branchAddr;
            entries[insertIndex[2:0]].dstAddr <= IN_branchDest;
            // only jumps always taken
            entries[insertIndex[2:0]].taken <= IN_branchIsJump;
            entries[insertIndex[2:0]].counter <= {IN_branchTaken, 1'b0};
            insertIndex <= insertIndex + 1;
        end
        
        // Entry exists (and was not replaced)
        else if (IN_branchAddr == entries[IN_branchID[2:0]].srcAddr) begin
        
            //entries[IN_branchID].used <= 1;
            
            // Update saturating counter
            if (IN_branchTaken) begin
                if (entries[IN_branchID[2:0]].counter != 2'b11)
                    entries[IN_branchID[2:0]].counter <= entries[IN_branchID[2:0]].counter + 1;
            end
            else if (entries[IN_branchID[2:0]].counter != 2'b00)
                entries[IN_branchID[2:0]].counter <= entries[IN_branchID[2:0]].counter - 1;
        end
        
    end
    else begin
        // If not valid or not used recently, keep this entry as first to replace
        if (entries[insertIndex[2:0]].valid && entries[insertIndex[2:0]].used) begin
            insertIndex[2:0] <= insertIndex[2:0] + 1;
            entries[insertIndex[2:0]].used <= 0;
        end
    end
    
    if (!rst && IN_pcValid && OUT_branchTaken) begin
        entries[OUT_branchID[2:0]].used <= 1;
    end
end


endmodule
