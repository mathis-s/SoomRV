typedef struct packed
{
    bit used;
    bit committed;
} TagBufEntry;

module TagBuffer
#
(
    parameter NUM_UOPS=3
)
(
    input wire clk,
    input wire rst,
    input wire IN_mispr,
    input wire IN_mispredFlush,
    
    input wire IN_issueValid[NUM_UOPS-1:0],
    output reg[5:0] OUT_issueTags[NUM_UOPS-1:0],
    output reg OUT_issueTagsValid[NUM_UOPS-1:0],
    
    
    input wire IN_commitValid[NUM_UOPS-1:0],
    input wire IN_commitNewest[NUM_UOPS-1:0],
    input wire[5:0] IN_RAT_commitPrevTags[NUM_UOPS-1:0],
    input wire[5:0] IN_commitTagDst[NUM_UOPS-1:0]
);
integer i;
integer j;

TagBufEntry tags[63:0];

always_comb begin
    for (i = 0; i < NUM_UOPS; i=i+1) begin
        OUT_issueTags[i] = 6'bx;
        OUT_issueTagsValid[i] = 0;
        for (j = 0; j < 64; j=j+1) begin
            if (!tags[j].used && 
                (i <= 0 || OUT_issueTags[0] != j[5:0]) &&
                (i <= 1 || OUT_issueTags[1] != j[5:0])) begin
                OUT_issueTags[i] = j[5:0];
                OUT_issueTagsValid[i] = 1;
            end
        end
    end
end

always_ff@(posedge clk) begin
    if (rst) begin
        for (i = 0; i < 32; i=i+1) begin
            tags[i].used <= 1'b1;
            tags[i].committed <= 1'b1;
        end
        for (i = 32; i < 64; i=i+1) begin
            tags[i].used <= 1'b0;
            tags[i].committed <= 1'b0;
        end
    end
    else begin
        if (IN_mispr) begin
            // Issue
            for (i = 0; i < 64; i=i+1) begin
                if (!tags[i].committed/* && $signed(tags[i].sqN - IN_misprSqN) > 0*/)
                    tags[i].used <= 0;
            end
        end
        else begin
            for (i = 0; i < NUM_UOPS; i=i+1) begin
                if (IN_issueValid[i]) begin
                    assert(OUT_issueTagsValid[i]);
                    tags[OUT_issueTags[i]].used <= 1;
                    //tags[OUT_issueTags[i]].sqN <= IN_issueSqNs[i];
                end
            end
        end
        
        // Commit
        for (i = 0; i < NUM_UOPS; i=i+1) begin
            if (IN_commitValid[i]) begin
                
                if (IN_mispredFlush) begin
                    if (!IN_mispr) tags[IN_commitTagDst[i]].used <= 1;
                end
                else begin
                    if (IN_commitNewest[i]) begin
                        tags[IN_RAT_commitPrevTags[i]].committed <= 0;
                        tags[IN_RAT_commitPrevTags[i]].used <= 0;
                        
                        tags[IN_commitTagDst[i]].committed <= 1;
                        tags[IN_commitTagDst[i]].used <= 1;
                    end
                    else begin
                        tags[IN_commitTagDst[i]].committed <= 0;
                        tags[IN_commitTagDst[i]].used <= 0;
                    end
                end
            end
        end
    end
end

endmodule
