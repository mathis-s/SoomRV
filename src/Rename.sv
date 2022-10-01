

typedef struct packed
{
    bit used;
    bit committed;
    bit[5:0] sqN;
} TagBufEntry;

module Rename
#(
    parameter WIDTH_UOPS = 3,
    parameter WIDTH_WR = 3
)
(
    input wire clk,
    input wire en,
    input wire frontEn,
    input wire rst,

    // Tag lookup for just decoded instrs
    input D_UOp IN_uop[WIDTH_UOPS-1:0],

    // Committed changes from ROB
    input CommitUOp IN_comUOp[WIDTH_UOPS-1:0],

    // WB for uncommitted but speculatively available values
    input wire IN_wbHasResult[WIDTH_WR-1:0],
    input RES_UOp IN_wbUOp[WIDTH_WR-1:0],

    // Taken branch
    input wire IN_branchTaken,
    input wire IN_branchFlush,
    input wire[5:0] IN_branchSqN,
    input wire[5:0] IN_branchLoadSqN,
    input wire[5:0] IN_branchStoreSqN,
    input wire IN_mispredFlush,
    
    output reg OUT_uopValid[WIDTH_UOPS-1:0],
    output R_UOp OUT_uop[WIDTH_UOPS-1:0],
    output wire[5:0] OUT_nextSqN,
    output reg[5:0] OUT_nextLoadSqN,
    output reg[5:0] OUT_nextStoreSqN
);

integer i;
integer j;

TagBufEntry tags[63:0];

wire RAT_lookupAvail[2*WIDTH_UOPS-1:0];
wire[5:0] RAT_lookupSpecTag[2*WIDTH_UOPS-1:0];
reg[4:0] RAT_lookupIDs[2*WIDTH_UOPS-1:0];

reg[4:0] RAT_issueIDs[WIDTH_UOPS-1:0];
reg RAT_issueValid[WIDTH_UOPS-1:0];
reg[5:0] RAT_issueSqNs[WIDTH_UOPS-1:0];

reg commitValid[WIDTH_UOPS-1:0];
reg[4:0] RAT_commitIDs[WIDTH_UOPS-1:0];
reg[5:0] RAT_commitTags[WIDTH_UOPS-1:0];
wire[5:0] RAT_commitPrevTags[WIDTH_UOPS-1:0];

reg[4:0] RAT_wbIDs[WIDTH_UOPS-1:0];
reg[5:0] RAT_wbTags[WIDTH_UOPS-1:0];

reg[5:0] nextCounterSqN;
always_comb begin
    
    nextCounterSqN = counterSqN;
    
    for (i = 0; i < WIDTH_UOPS; i=i+1) begin
        RAT_lookupIDs[2*i+0] = IN_uop[i].rs0;
        RAT_lookupIDs[2*i+1] = IN_uop[i].rs1;
    end
    for (i = 0; i < WIDTH_UOPS; i=i+1) begin
        // Issue/Lookup
        RAT_issueIDs[i] = IN_uop[i].rd;
        RAT_issueSqNs[i] = nextCounterSqN;
        RAT_issueValid[i] = !rst && !IN_branchTaken && en && frontEn && IN_uop[i].valid;
        if (RAT_issueValid[i])
            nextCounterSqN = nextCounterSqN + 1;
        
        // Commit
        commitValid[i] = (IN_comUOp[i].valid && (IN_comUOp[i].nmDst != 0)
            && (!IN_branchTaken || $signed(IN_comUOp[i].sqN - IN_branchSqN) <= 0));
        RAT_commitIDs[i] = IN_comUOp[i].nmDst;
        RAT_commitTags[i] = IN_comUOp[i].tagDst;
        
        // Writeback
        RAT_wbIDs[i] = IN_wbUOp[i].nmDst;
        RAT_wbTags[i] = IN_wbUOp[i].tagDst;
    end
end

RenameTable rt
(
    .clk(clk),
    .rst(rst),
    .IN_mispred(IN_branchTaken),
    .IN_mispredSqN(IN_branchSqN),
    .IN_mispredFlush(IN_mispredFlush),
    
    .IN_lookupIDs(RAT_lookupIDs),
    .OUT_lookupAvail(RAT_lookupAvail),
    .OUT_lookupSpecTag(RAT_lookupSpecTag),
    
    .IN_issueValid(RAT_issueValid),
    .IN_issueIDs(RAT_issueIDs),
    .IN_issueSqNs(RAT_issueSqNs),
    .IN_issueTags(newTags),
    
    .IN_commitValid(commitValid),
    .IN_commitIDs(RAT_commitIDs),
    .IN_commitTags(RAT_commitTags),
    .OUT_commitPrevTags(RAT_commitPrevTags),
    
    .IN_wbValid(IN_wbHasResult),
    .IN_wbID(RAT_wbIDs),
    .IN_wbTag(RAT_wbTags)
);


bit[5:0] counterSqN;
bit[5:0] counterStoreSqN;
bit[5:0] counterLoadSqN;
assign OUT_nextSqN = counterSqN;

reg temp;

// Could also check this ROB-side and simply not commit older ops with same DstRegNm.
reg isNewestCommit[WIDTH_UOPS-1:0];
always_comb begin
    for (i = 0; i < WIDTH_UOPS; i=i+1) begin
        
        isNewestCommit[i] = IN_comUOp[i].valid;
        if (IN_comUOp[i].valid)
            for (j = i + 1; j < WIDTH_UOPS; j=j+1)
                if (IN_comUOp[j].valid && (IN_comUOp[j].nmDst == IN_comUOp[i].nmDst))
                    isNewestCommit[i] = 0;
    end
end


reg[5:0] newTags[WIDTH_UOPS-1:0];
reg newTagsAvail[WIDTH_UOPS-1:0];
always_comb begin
    for (i = 0; i < WIDTH_UOPS; i=i+1) begin
        newTagsAvail[i] = 1'b0;
        newTags[i] = 6'bx;
        for (j = 0; j < 64; j=j+1) begin
            // TODO kind of hacky...
            if (!tags[j].used && (i == 0 || newTags[0] != j[5:0]) && (i <= 1 || newTags[1] != j[5:0])) begin
                newTags[i] = j[5:0];
                newTagsAvail[i] = 1'b1;
            end
        end
    end
end

int usedTags;
always_comb begin
    usedTags = 0;
    for (i = 0; i < 64; i=i+1)
        if(tags[i].used)
            usedTags = usedTags + 1;
end



// note: ROB has to consider order when multiple instructions
// that write to the same register are committed. Later wbs have prio.
always_ff@(posedge clk) begin

    if (rst) begin
        
        for (i = 0; i < 32; i=i+1) begin
            tags[i].used <= 1'b1;
            tags[i].committed <= 1'b1;
            tags[i].sqN <= 6'bxxxxxx;
        end
        for (i = 32; i < 64; i=i+1) begin
            tags[i].used <= 1'b0;
            tags[i].committed <= 1'b0;
            tags[i].sqN <= 6'bxxxxxx;
        end
        
        counterSqN <= 0;
        counterStoreSqN = 63;
        // TODO: check if load sqn is correctly handled
        counterLoadSqN = 0;
        OUT_nextLoadSqN <= counterLoadSqN;
        OUT_nextStoreSqN <= counterStoreSqN + 1;
    
        for (i = 0; i < WIDTH_UOPS; i=i+1) begin
            OUT_uop[i].sqN <= i[5:0];
            OUT_uopValid[i] <= 0;
        end
    end
    else if (IN_branchTaken) begin
        
        counterSqN <= IN_branchSqN + 1;
        
        counterLoadSqN = IN_branchLoadSqN;
        counterStoreSqN = IN_branchStoreSqN;
        
        for (i = 0; i < 64; i=i+1) begin
            if (!tags[i].committed && $signed(tags[i].sqN - IN_branchSqN) > 0)
                tags[i].used <= 0;
        end
        
        for (i = 0; i < WIDTH_UOPS; i=i+1)
            OUT_uopValid[i] <= 0;
    end

    else if (en && frontEn) begin
        // Look up tags and availability of operands for new instructions
        for (i = 0; i < WIDTH_UOPS; i=i+1) begin
            OUT_uop[i].imm <= IN_uop[i].imm;
            OUT_uop[i].opcode <= IN_uop[i].opcode;
            OUT_uop[i].fu <= IN_uop[i].fu;
            OUT_uop[i].nmDst <= IN_uop[i].rd;
            OUT_uop[i].pc <= IN_uop[i].pc;
            OUT_uop[i].immB <= IN_uop[i].immB;
            OUT_uop[i].branchID <= IN_uop[i].branchID;
            OUT_uop[i].branchPred <= IN_uop[i].branchPred;
            OUT_uop[i].compressed <= IN_uop[i].compressed;
        end
        
        // Set seqnum/tags for next instruction(s)
        for (i = 0; i < WIDTH_UOPS; i=i+1) begin
            if (IN_uop[i].valid) begin
                
                OUT_uopValid[i] <= 1;
                
                OUT_uop[i].loadSqN <= counterLoadSqN;
                
                if (IN_uop[i].fu == FU_LSU) begin
                    if (IN_uop[i].opcode == LSU_SB ||
                        IN_uop[i].opcode == LSU_SH ||
                        IN_uop[i].opcode == LSU_SW)
                        counterStoreSqN = counterStoreSqN + 1;
                    else
                        counterLoadSqN = counterLoadSqN + 1;
                end
                
                OUT_uop[i].sqN <= RAT_issueSqNs[i];
                OUT_uop[i].storeSqN <= counterStoreSqN;
                // These are affected by previous instrs
                OUT_uop[i].tagA <= RAT_lookupSpecTag[2*i+0];
                OUT_uop[i].tagB <= RAT_lookupSpecTag[2*i+1];
                OUT_uop[i].availA <= RAT_lookupAvail[2*i+0];
                OUT_uop[i].availB <= RAT_lookupAvail[2*i+1];

                if (IN_uop[i].rd != 0) begin
                    OUT_uop[i].tagDst <= newTags[i];

                    assert(newTagsAvail[i]);
                    tags[newTags[i]].used <= 1;
                    tags[newTags[i]].sqN <= RAT_issueSqNs[i];
                end
            end
            else
                OUT_uopValid[i] <= 0;
        end
        counterSqN <= nextCounterSqN;
         
    end
    else if (!en) begin
        for (i = 0; i < WIDTH_UOPS; i=i+1)
            OUT_uopValid[i] <= 0;
    end
    
    if (!rst) begin
        // Commit results from ROB.
        for (i = 0; i < WIDTH_UOPS; i=i+1) begin
            // commit at higher index is newer op, takes precedence in case of collision
            if (commitValid[i]) begin
                if (isNewestCommit[i]) begin
                    // Free tag that previously held the committed value of this reg
                    tags[RAT_commitPrevTags[i]].committed <= 0;
                    tags[RAT_commitPrevTags[i]].used <= 0;
                    
                    // Set new tag as used
                    tags[IN_comUOp[i].tagDst].committed <= 1;
                    tags[IN_comUOp[i].tagDst].used <= 1;
                end
                else begin
                    tags[IN_comUOp[i].tagDst].committed <= 0;
                    tags[IN_comUOp[i].tagDst].used <= 0;
                end
            end
        end
        
        // If frontend is stalled right now we need to make sure 
        // the ops we're stalled on are kept up-to-date, as they will be
        // read later.
        for (i = 0; i < WIDTH_WR; i=i+1) begin
            if (en && !frontEn && IN_wbHasResult[i]) begin
                for (j = 0; j < WIDTH_UOPS; j=j+1) begin
                    if (OUT_uopValid[j]) begin
                        if (OUT_uop[j].tagA == IN_wbUOp[i].tagDst)
                            OUT_uop[j].availA <= 1;
                        if (OUT_uop[j].tagB == IN_wbUOp[i].tagDst)
                            OUT_uop[j].availB <= 1;
                    end
                end
            end
        end
    end
    
    OUT_nextLoadSqN <= counterLoadSqN;
    OUT_nextStoreSqN <= counterStoreSqN + 1;

    
end
endmodule
