typedef struct packed
{
    bit avail;
    bit[5:0] comTag;
    bit[5:0] specTag;
    bit[5:0] newSqN;
} RATEntry;

typedef struct packed
{
    bit used;
    bit committed;
    bit[5:0] sqN;
} TagBufEntry;

module Rename
#(
    parameter WIDTH_UOPS = 2,
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

TagBufEntry tags[63:0];

RATEntry rat[31:0];
integer i;
integer j;

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
wire[5:0] newTagsDbg0 = newTags[0];
wire[5:0] newTagsDbg1 = newTags[1];
always_comb begin
    for (i = 0; i < WIDTH_UOPS; i=i+1) begin
        newTagsAvail[i] = 1'b0;
        newTags[i] = 6'bx;
        for (j = 0; j < 64; j=j+1) begin
            // TODO kind of hacky...
            if (!tags[j].used && (i == 0 || newTags[0] != j[5:0])) begin
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
        
        counterSqN = 0;
        counterStoreSqN = 63;
        // TODO: check if load sqn is correctly handled
        counterLoadSqN = 0;
        OUT_nextLoadSqN <= counterLoadSqN;
        OUT_nextStoreSqN <= counterStoreSqN + 1;
        
        // Registers initialized with tags 0..31
        for (i = 0; i < 32; i=i+1) begin
            rat[i].avail <= 1;
            rat[i].comTag <= i[5:0];
            rat[i].specTag <= i[5:0];
        end
        for (i = 0; i < WIDTH_UOPS; i=i+1) begin
            OUT_uop[i].sqN <= i[5:0];
            OUT_uopValid[i] <= 0;
        end
    end
    else if (IN_branchTaken) begin
        
        counterSqN = IN_branchSqN + 1;
        
        counterLoadSqN = IN_branchLoadSqN;
        counterStoreSqN = IN_branchStoreSqN;
        
        for (i = 0; i < 32; i=i+1) begin
            if (rat[i].comTag != rat[i].specTag && ($signed(rat[i].newSqN - IN_branchSqN) > 0 || IN_branchFlush)) begin
                rat[i].avail <= 1;
                // This might not be valid, but the pipeline is flushed after branch.
                // During the flush, the valid tag is committed and written.
                rat[i].specTag <= rat[i].comTag;
            end
        end
        
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
                
                OUT_uop[i].sqN <= counterSqN;
                OUT_uop[i].storeSqN <= counterStoreSqN;
                // These are affected by previous instrs
                OUT_uop[i].tagA <= rat[IN_uop[i].rs0].specTag;
                OUT_uop[i].tagB <= rat[IN_uop[i].rs1].specTag;

                // TODO: Do this parametric
                // Forward from WB
                if ((IN_wbHasResult[0] && IN_wbUOp[0].tagDst == rat[IN_uop[i].rs0].specTag) ||
                    (IN_wbHasResult[1] && IN_wbUOp[1].tagDst == rat[IN_uop[i].rs0].specTag) ||
                    (IN_wbHasResult[2] && IN_wbUOp[2].tagDst == rat[IN_uop[i].rs0].specTag))
                    OUT_uop[i].availA <= 1;
                else
                    OUT_uop[i].availA <= rat[IN_uop[i].rs0].avail;

                if ((IN_wbHasResult[0] && IN_wbUOp[0].tagDst == rat[IN_uop[i].rs1].specTag) ||
                    (IN_wbHasResult[1] && IN_wbUOp[1].tagDst == rat[IN_uop[i].rs1].specTag) ||
                    (IN_wbHasResult[2] && IN_wbUOp[2].tagDst == rat[IN_uop[i].rs1].specTag))
                    OUT_uop[i].availB <= 1;
                else
                    OUT_uop[i].availB <= rat[IN_uop[i].rs1].avail;


                if (IN_uop[i].rd != 0) begin
                    OUT_uop[i].tagDst <= newTags[i];

                    assert(newTagsAvail[i]);

                    // Mark regs written to by newly issued instructions as unavailable/pending.
                    // These are blocking to make sure they are forwarded to the next iters of this for-loop.
                    rat[IN_uop[i].rd].avail = 0;
                    rat[IN_uop[i].rd].specTag = newTags[i];
                    rat[IN_uop[i].rd].newSqN = counterSqN;

                    tags[newTags[i]].used <= 1;
                    tags[newTags[i]].sqN <= counterSqN;
                end
                counterSqN = counterSqN + 1;
                
                
            end
            else
                OUT_uopValid[i] <= 0;
        end
    end
    else if (!en) begin
        for (i = 0; i < WIDTH_UOPS; i=i+1)
            OUT_uopValid[i] <= 0;
    end
    
    if (!rst) begin
        // Commit results from ROB.
        for (i = 0; i < WIDTH_UOPS; i=i+1) begin
            // commit at higher index is newer op, takes precedence in case of collision
            if (IN_comUOp[i].valid && (IN_comUOp[i].nmDst != 0)
                && (!IN_branchTaken || $signed(IN_comUOp[i].sqN - IN_branchSqN) <= 0)) begin
                
                if (isNewestCommit[i]) begin
                    tags[rat[IN_comUOp[i].nmDst].comTag].committed <= 0;
                    tags[rat[IN_comUOp[i].nmDst].comTag].used <= 0;
                    
                    
                    rat[IN_comUOp[i].nmDst].comTag <= IN_comUOp[i].tagDst;
                    
                    
                    tags[IN_comUOp[i].tagDst].committed <= 1;
                    tags[IN_comUOp[i].tagDst].used <= 1;
                    

                    if (IN_mispredFlush || IN_branchTaken) begin 
                        rat[IN_comUOp[i].nmDst].specTag <= IN_comUOp[i].tagDst;
                        rat[IN_comUOp[i].nmDst].avail <= 1;
                    end
                end
                else begin
                    tags[IN_comUOp[i].tagDst].committed <= 0;
                    tags[IN_comUOp[i].tagDst].used <= 0;
                end
            end
        end

        // Written back values are speculatively available
        for (i = 0; i < WIDTH_WR; i=i+1) begin
            if (IN_wbHasResult[i] && rat[IN_wbUOp[i].nmDst].specTag == IN_wbUOp[i].tagDst) begin
                rat[IN_wbUOp[i].nmDst].avail = 1;
            end
            
            // If frontend is stalled right now we need to make sure 
            // the op we're stalled on is kept up-to-date, as it will be
            // read later.
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
