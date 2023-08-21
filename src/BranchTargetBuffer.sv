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
    logic isJump;
    logic isCall; // TODO unify fields
    logic compr;
    logic used;
    logic valid;
    logic[30:0] dst;
    logic[`BTB_TAG_SIZE-1:0] src;
    FetchOff_t offs;
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
            if (fetched[i].valid &
                fetched[i].src == IN_pc[$clog2(LENGTH)+3 +: `BTB_TAG_SIZE] &&
                fetched[i].offs >= IN_pc[2:0] &&
                (!OUT_branchFound || fetched[i].offs < OUT_branchSrcOffs)
            ) begin
                
                if (OUT_branchFound)
                    OUT_multipleBranches = 1;
                OUT_branchFound = 1;
                OUT_branchIsJump = fetched[i].isJump;
                OUT_branchIsCall = fetched[i].isCall;
                OUT_branchDst = fetched[i].dst;
                OUT_branchSrcOffs = fetched[i].offs;
                OUT_branchCompr = fetched[i].compr;
                usedID = i[$clog2(`BTB_ASSOC)-1:0];
            end
        end
    end
end

// Shift the index at which we begin searching for unused
// entries in a line for improved distribution of entries
reg[$clog2(`BTB_ASSOC)-1:0] searchIdx;
always_ff@(posedge clk) begin
    searchIdx <= searchIdx + 1;
end

reg[$clog2(`BTB_ASSOC)-1:0] insertAssocIdx;
reg insertAssocIdxValid;
always_comb begin
    insertAssocIdxValid = 0;
    insertAssocIdx = 'x;

    for (integer i = 0; i < `BTB_ASSOC; i=i+1) begin
        reg[$clog2(`BTB_ASSOC)-1:0] assocIdx = searchIdx + i[$clog2(`BTB_ASSOC)-1:0];
        if (!entries[IN_btUpdate.src[$clog2(LENGTH)+3:4]][assocIdx].used) begin
            insertAssocIdx = assocIdx;
            insertAssocIdxValid = 1;
        end
    end

    for (integer i = 0; i < `BTB_ASSOC; i=i+1) begin
        
        reg[$clog2(`BTB_ASSOC)-1:0] assocIdx = searchIdx + i[$clog2(`BTB_ASSOC)-1:0];
        reg[$clog2(LENGTH)-1:0] idx = IN_btUpdate.src[$clog2(LENGTH)+3:4];

        if (entries[idx][assocIdx].src == IN_btUpdate.src[$clog2(LENGTH)+4 +: `BTB_TAG_SIZE] &&
            entries[idx][assocIdx].offs == IN_btUpdate.src[1 +: $bits(FetchOff_t)]
        ) begin
            insertAssocIdx = assocIdx;
            insertAssocIdxValid = 1;
        end
    end
end

always_ff@(posedge clk) begin
    
    if (rst) begin
        `ifdef SYNC_RESET
        for (integer i = 0; i < LENGTH; i=i+1)
            for (integer j = 0; j < `BTB_ASSOC; j=j+1) begin
                entries[i][j].valid <= 0;
                entries[i][j].used <= 0;
            end
        `endif
    end
    else begin
        if (IN_btUpdate.valid) begin
            reg[$clog2(LENGTH)-1:0] idx = IN_btUpdate.src[$clog2(LENGTH)+3:4];
            if (!IN_btUpdate.clean) begin
                if (insertAssocIdxValid) begin
                    entries[idx][insertAssocIdx].valid <= 1;
                    entries[idx][insertAssocIdx].used <= 0;
                    entries[idx][insertAssocIdx].compr <= IN_btUpdate.compressed;
                    entries[idx][insertAssocIdx].isJump <= IN_btUpdate.isJump;
                    entries[idx][insertAssocIdx].isCall <= IN_btUpdate.isCall;
                    entries[idx][insertAssocIdx].dst <= IN_btUpdate.dst[31:1];
                    entries[idx][insertAssocIdx].src <= IN_btUpdate.src[$clog2(LENGTH)+4 +: `BTB_TAG_SIZE];
                    entries[idx][insertAssocIdx].offs <= IN_btUpdate.src[1 +: $bits(FetchOff_t)];
                end
                else begin
                    for (integer i = 0; i < `BTB_ASSOC; i=i+1)
                        entries[idx][i].used <= 0;
                end
            end
            else begin
                entries[idx][insertAssocIdx].valid <= 0;
                entries[idx][insertAssocIdx].used <= 0;
            end
        end
        else if (IN_pcValid && OUT_branchFound && (IN_BPT_branchTaken || OUT_branchIsJump)) begin
            entries[IN_pc[$clog2(LENGTH)+2:3]][usedID].used <= 1;
        end
    end
end
endmodule
