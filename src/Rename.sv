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
    parameter WIDTH_WR = 2
)
(
    input wire clk,
    input wire en,
    input wire rst,

    // Tag lookup for just decoded instrs
    input D_UOp IN_uop[WIDTH_UOPS-1:0],

    // Committed changes from ROB
    input wire comValid[WIDTH_WR-1:0],
    input wire[4:0] comRegNm[WIDTH_WR-1:0],
    input wire[5:0] comRegTag[WIDTH_WR-1:0],

    // WB for uncommitted but speculatively available values
    input wire IN_wbValid[WIDTH_WR-1:0],
    input wire[5:0] IN_wbTag[WIDTH_WR-1:0],
    input wire[4:0] IN_wbNm[WIDTH_WR-1:0],

    // Taken branch
    input wire IN_branchTaken,
    input wire[5:0] IN_branchSqN,
    input wire IN_mispredFlush,
    
    output reg OUT_uopValid[WIDTH_UOPS-1:0],
    output R_UOp OUT_uop[WIDTH_UOPS-1:0],
    output wire[5:0] OUT_nextSqN
);

//reg[4:0] freeTagInsertIndex;
//reg[4:0] freeTagOutputIndex;
//reg[5:0] freeTags[FREE_TAG_FIFO_SIZE-1:0];

TagBufEntry tags[63:0];

RATEntry rat[31:0];
integer i;
integer j;

bit[5:0] counterSqN;
assign OUT_nextSqN = counterSqN;

reg temp;

// Could also check this ROB-side and simply not commit older ops with same DstRegNm.
reg isNewestCommit[WIDTH_UOPS-1:0];
always_comb begin
    for (i = 0; i < WIDTH_UOPS; i=i+1) begin
        
        isNewestCommit[i] = comValid[i];
        if (comValid[i])
            for (j = i + 1; j < WIDTH_UOPS; j=j+1)
                if (comValid[j] && (comRegNm[j] == comRegNm[i]))
                    isNewestCommit[i] = 0;
    end
end


reg[5:0] newTags[WIDTH_UOPS-1:0];
reg newTagsAvail[WIDTH_UOPS-1:0];
always_comb begin
    for (i = 0; i < WIDTH_UOPS; i=i+1) begin
        newTagsAvail[i] = 0;
        newTags[i] = 6'bx;
        for (j = 0; j < 64; j=j+1) begin
            // TODO kind of hacky...
            if (!tags[j].used && (i == 0 || newTags[0] != j[5:0])) begin
                newTags[i] = j[5:0];
                newTagsAvail[i] = 1;
            end
        end
    end
end

// note: ROB has to consider order when multiple instructions
// that write to the same register are committed. Later wbs have prio.
always_ff@(posedge clk) begin

    if (rst) begin
        
        for (i = 0; i < 32; i=i+1) begin
            tags[i].used <= 1;
            tags[i].committed <= 1;
            tags[i].sqN <= 6'bxxxxxx;
        end
        for (i = 32; i < 64; i=i+1) begin
            tags[i].used <= 0;
            tags[i].committed <= 1'bx;
            tags[i].sqN <= 6'bxxxxxx;
        end
        
        counterSqN <= 0;
        
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
        
        counterSqN <= IN_branchSqN + 1;
        for (i = 0; i < 32; i=i+1) begin
            if (rat[i].comTag != rat[i].specTag && $signed(rat[i].newSqN - IN_branchSqN) > 0) begin
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

    else if (en) begin
        // Look up tags and availability of operands for new instructions
        for (i = 0; i < WIDTH_UOPS; i=i+1) begin
            OUT_uop[i].imm <= IN_uop[i].imm;
            OUT_uop[i].opcode <= IN_uop[i].opcode;
            OUT_uop[i].fu <= IN_uop[i].fu;
            OUT_uop[i].nmDst <= IN_uop[i].rd;
            OUT_uop[i].pc <= IN_uop[i].pc;
            OUT_uop[i].immB <= IN_uop[i].immB;
            OUT_uop[i].pcA <= IN_uop[i].pcA;

            OUT_uopValid[i] <= 1;
        end

        // Set seqnum/tags for next instruction(s)
        for (i = 0; i < WIDTH_UOPS; i=i+1) begin
            
            OUT_uop[i].sqN <= (counterSqN + i[5:0]);
            // These are affected by previous instrs
            OUT_uop[i].tagA <= rat[IN_uop[i].rs0].specTag;
            OUT_uop[i].availA <= rat[IN_uop[i].rs0].avail;
            OUT_uop[i].tagB <= rat[IN_uop[i].rs1].specTag;
            OUT_uop[i].availB <= rat[IN_uop[i].rs1].avail;
            
            if (IN_uop[i].rd != 0) begin
                OUT_uop[i].tagDst <= newTags[i];
                
                assert(newTagsAvail[i]);

                // Mark regs written to by newly issued instructions as unavailable/pending.
                // These are blocking to make sure they are forwarded to the next iters of this for-loop.
                rat[IN_uop[i].rd].avail = 0;
                rat[IN_uop[i].rd].specTag = newTags[i];
                rat[IN_uop[i].rd].newSqN = counterSqN + i[5:0];

                tags[newTags[i]].used <= 1;
            end
        end
        counterSqN <= counterSqN + WIDTH_WR[5:0];
    end
    else begin
        for (i = 0; i < WIDTH_UOPS; i=i+1)
            OUT_uopValid[i] <= 0;
    end
    
    if (!rst) begin
        // Commit results from ROB.
        for (i = 0; i < WIDTH_WR; i=i+1) begin
            // commit at higher index is newer op, takes precedence in case of collision
            if (comValid[i] && (comRegNm[i] != 0) && isNewestCommit[i]) begin
            
                tags[rat[comRegNm[i]].comTag].committed <= 0;
                tags[rat[comRegNm[i]].comTag].used <= 0;
                
                
                rat[comRegNm[i]].comTag <= comRegTag[i];
                
                
                tags[comRegTag[i]].committed <= 1;
                tags[comRegTag[i]].used <= 1;
                

                if (IN_mispredFlush) 
                    rat[comRegNm[i]].specTag <= comRegTag[i];
            end
        end

        // Written back values are speculatively available
        for (i = 0; i < WIDTH_WR; i=i+1) begin
            if (IN_wbValid[i] && rat[IN_wbNm[i]].specTag == IN_wbTag[i]) begin
                rat[IN_wbNm[i]].avail = 1;
            end
        end
    end

    
end
endmodule
