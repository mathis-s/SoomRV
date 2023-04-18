module BranchTargetBuffer
(
    input wire clk,
    input wire rst,
    
    input wire IN_pcValid,
    input wire[30:0] IN_pc,
    
    output reg OUT_branchFound,
    output reg[30:0] OUT_branchDst,
    output FetchOff_t OUT_branchSrcOffs,
    output reg OUT_branchIsJump,
    output reg OUT_branchIsCall,
    output reg OUT_branchCompr,
    output reg OUT_multipleBranches,
    input wire IN_BPT_branchTaken,
    
    input BTUpdate IN_btUpdate
);

typedef struct packed
{
    bit isJump;
    bit isCall; // TODO unify fields
    bit compr;
    bit used;
    bit valid;
    bit[30:0] dst;
    bit[`BTB_TAG_SIZE-1:0] src;
} BTBEntry;

localparam LENGTH = `BTB_ENTRIES / `BTB_ASSOC;

BTBEntry[`BTB_ASSOC-1:0] entries[LENGTH-1:0];

reg[$clog2(`BTB_ASSOC)-1:0] usedID;

always_comb begin
    
    BTBEntry[`BTB_ASSOC-1:0] fetched = entries[IN_pc[$clog2(LENGTH)+2:3]];
    
    OUT_branchFound = 0;
    OUT_multipleBranches = 0;
    OUT_branchDst = 'x;
    OUT_branchIsJump = 0;
    OUT_branchIsCall = 0;
    OUT_branchCompr = 0;
    OUT_branchSrcOffs = 'x;
    usedID = 0;
    
    if (IN_pcValid) begin
        
        for (integer i = 0; i < `BTB_ASSOC; i=i+1) begin
            
            if (fetched[i].valid && fetched[i].src[`BTB_TAG_SIZE-1:3] == IN_pc[`BTB_TAG_SIZE-1:3] && fetched[i].src[2:0] >= IN_pc[2:0] &&
                (!OUT_branchFound || fetched[i].src[2:0] < OUT_branchSrcOffs)) begin
                
                if (OUT_branchFound)
                    OUT_multipleBranches = 1;
                OUT_branchFound = 1;
                OUT_branchIsJump = fetched[i].isJump;
                OUT_branchIsCall = fetched[i].isCall;
                OUT_branchDst = fetched[i].dst;
                OUT_branchSrcOffs = fetched[i].src[$bits(FetchOff_t)-1:0];
                OUT_branchCompr = fetched[i].compr;
                usedID = i[$clog2(`BTB_ASSOC)-1:0];
            end
        end
    end
end

always_ff@(posedge clk) begin
    
    if (rst) begin
        for (integer i = 0; i < LENGTH; i=i+1)
            for (integer j = 0; j < `BTB_ASSOC; j=j+1)
                entries[i][j].valid <= 0;
    end
    else begin
    
        if (IN_btUpdate.valid) begin
            
            reg inserted = 0;
            
            if (!IN_btUpdate.clean) begin
                // Try to find invalid fields
                for (integer i = 0; i < `BTB_ASSOC; i=i+1) begin
                    if (!inserted && (!entries[IN_btUpdate.src[$clog2(LENGTH)+3:4]][i].valid)) begin
                        
                        inserted = 1;
                        entries[IN_btUpdate.src[$clog2(LENGTH)+3:4]][i].valid <= 1;
                        entries[IN_btUpdate.src[$clog2(LENGTH)+3:4]][i].used <= 0;
                        entries[IN_btUpdate.src[$clog2(LENGTH)+3:4]][i].compr <= IN_btUpdate.compressed;
                        entries[IN_btUpdate.src[$clog2(LENGTH)+3:4]][i].isJump <= IN_btUpdate.isJump;
                        entries[IN_btUpdate.src[$clog2(LENGTH)+3:4]][i].isCall <= IN_btUpdate.isCall;
                        entries[IN_btUpdate.src[$clog2(LENGTH)+3:4]][i].dst <= IN_btUpdate.dst[31:1];
                        entries[IN_btUpdate.src[$clog2(LENGTH)+3:4]][i].src <= IN_btUpdate.src[`BTB_TAG_SIZE:1];
                    end
                    else if (!inserted) entries[IN_btUpdate.src[$clog2(LENGTH)+3:4]][i].used <= 0;
                end
                
                // Try to find unused fields
                for (integer i = 0; i < `BTB_ASSOC; i=i+1) begin
                    if (!inserted && (!entries[IN_btUpdate.src[$clog2(LENGTH)+3:4]][i].used)) begin
                        
                        inserted = 1;
                        entries[IN_btUpdate.src[$clog2(LENGTH)+3:4]][i].valid <= 1;
                        entries[IN_btUpdate.src[$clog2(LENGTH)+3:4]][i].used <= 0;
                        entries[IN_btUpdate.src[$clog2(LENGTH)+3:4]][i].compr <= IN_btUpdate.compressed;
                        entries[IN_btUpdate.src[$clog2(LENGTH)+3:4]][i].isJump <= IN_btUpdate.isJump;
                        entries[IN_btUpdate.src[$clog2(LENGTH)+3:4]][i].isCall <= IN_btUpdate.isCall;
                        entries[IN_btUpdate.src[$clog2(LENGTH)+3:4]][i].dst <= IN_btUpdate.dst[31:1];
                        entries[IN_btUpdate.src[$clog2(LENGTH)+3:4]][i].src <= IN_btUpdate.src[`BTB_TAG_SIZE:1];
                    end
                    else if (!inserted) entries[IN_btUpdate.src[$clog2(LENGTH)+3:4]][i].used <= 0;
                end
            end
            else begin
                // Delete all entries in block on branch target mispredict for now.
                for (integer i = 0; i < `BTB_ASSOC; i=i+1)
                    entries[IN_btUpdate.src[$clog2(LENGTH)+3:4]][i].valid <= 0;
            end
        end
        
        // maybe else if (for port sharing?)
        if (IN_pcValid && OUT_branchFound && (IN_BPT_branchTaken || OUT_branchIsJump)) begin
            entries[IN_pc[$clog2(LENGTH)+2:3]][usedID].used <= 1;
        end
    end

end


endmodule
