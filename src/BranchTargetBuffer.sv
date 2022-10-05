typedef struct packed
{
    bit isJump;
    bit compr;
    bit used;
    bit valid;
    bit[30:0] dst;
    bit[30:0] src;
} BTBEntry;

module BranchTargetBuffer
#(
    parameter NUM_ENTRIES=64
)
(
    input wire clk,
    input wire rst,
    
    input wire IN_pcValid,
    input wire[30:0] IN_pc,
    
    output reg OUT_branchFound,
    output reg[30:0] OUT_branchDst,
    output reg[30:0] OUT_branchSrc,
    output reg OUT_branchIsJump,
    output reg OUT_branchCompr,
    output reg OUT_multipleBranches,
    input wire IN_BPT_branchTaken,
    
    input BTUpdate IN_btUpdate
);
integer i;

reg[$clog2(NUM_ENTRIES)-1:0] lruPointer;
BTBEntry entries[NUM_ENTRIES-1:0];

reg[$clog2(NUM_ENTRIES)-1:0] outBranchID;
always_comb begin
    OUT_branchFound = 0;
    OUT_multipleBranches = 0;
    OUT_branchDst = 31'bx;
    OUT_branchIsJump = 0;
    OUT_branchCompr = 0;
    OUT_branchSrc = 31'bx;
    outBranchID = 0;
    
    if (IN_pcValid)
        for (i = 0; i < NUM_ENTRIES; i=i+1) begin
            if (entries[i].valid && entries[i].src[30:2] == IN_pc[30:2] && entries[i].src[1:0] >= IN_pc[1:0] &&
                (!OUT_branchFound || entries[i].src[1:0] < OUT_branchSrc[1:0])) begin
                
                if (OUT_branchFound)
                    OUT_multipleBranches = 1;
                OUT_branchFound = 1;
                OUT_branchIsJump = entries[i].isJump;
                OUT_branchDst = entries[i].dst;
                OUT_branchSrc = entries[i].src;
                OUT_branchCompr = entries[i].compr;
                outBranchID = i[$clog2(NUM_ENTRIES)-1:0];
            end
        end
end


always@(posedge clk) begin

    if (rst) begin
        for (i = 0; i < NUM_ENTRIES; i=i+1)
            entries[i].valid <= 0;
        lruPointer <= 0;
    end
    else begin
        // Store this regardless of mispredict, information is still useful
        if (IN_btUpdate.valid) begin
            entries[lruPointer].valid <= 1;
            entries[lruPointer].used <= 1;
            entries[lruPointer].compr <= IN_btUpdate.compressed;
            entries[lruPointer].isJump <= IN_btUpdate.isJump;
            entries[lruPointer].dst <= IN_btUpdate.dst[31:1];
            entries[lruPointer].src <= IN_btUpdate.src[31:1];
        end
        
        // Update pseudo-lru pointer
        if ((entries[lruPointer].used && entries[lruPointer].valid) || IN_btUpdate.valid)
            lruPointer <= lruPointer + 1;
        
        // Mark used entries as used (only if taken, as untaken branches don't need to be stored)
        if (IN_pcValid && OUT_branchFound && (IN_BPT_branchTaken || OUT_branchIsJump)) begin
            entries[outBranchID].used <= 1;
        end
            
    end
end


endmodule
