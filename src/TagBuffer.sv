typedef struct packed
{
    bit used;
    bit committed;
} TagBufEntry;

module TagBuffer
#
(
    parameter NUM_ISSUE=4,
    parameter NUM_COMMIT=4
)
(
    input wire clk,
    input wire rst,
    input wire IN_mispr,
    input wire IN_mispredFlush,
    
    input wire IN_issueValid[NUM_ISSUE-1:0],
    output reg[5:0] OUT_issueTags[NUM_ISSUE-1:0],
    output reg OUT_issueTagsValid[NUM_ISSUE-1:0],
    
    
    input wire IN_commitValid[NUM_COMMIT-1:0],
    input wire IN_commitNewest[NUM_COMMIT-1:0],
    input wire[6:0] IN_RAT_commitPrevTags[NUM_COMMIT-1:0],
    input wire[6:0] IN_commitTagDst[NUM_COMMIT-1:0]
);

TagBufEntry tags[63:0];

reg mispredWait;

reg[5:0] issueTags[NUM_ISSUE-1:0];
reg issueTagsValid[NUM_ISSUE-1:0];

// Naive algorithm
/*always_comb begin
    for (integer i = 0; i < NUM_ISSUE; i=i+1) begin
        issueTagsValid[i] = 0;
        issueTags[i] = 6'bx;
        for (integer j = 0; j < 64; j=j+1) begin
            
            reg usedByPrev = 0;
            for (integer k = 0; k < i; k=k+1)
                if (issueTags[k] == j[5:0]) 
                    usedByPrev = 1;
        
            if (!tags[j].used && !usedByPrev) begin
                issueTags[i] = j[5:0];
                issueTagsValid[i] = 1;
            end
        end
    end
end*/

// Optimized Algorithm: Priority encode from alternating sides
always_comb begin
    for (integer i = 0; i < NUM_ISSUE; i=i+1) begin
        issueTagsValid[i] = 0;
        issueTags[i] = 6'bx;
        if (i % 2 == 0) begin
            for (integer j = 0; j < 64; j=j+1) begin
                reg usedByPrev = 0;
                for (integer k = 0; k < i; k=k+2)
                    if (issueTags[k] == j[5:0]) 
                        usedByPrev = 1;
            
                if (!tags[j].used && !usedByPrev) begin
                    issueTags[i] = j[5:0];
                    issueTagsValid[i] = 1;
                end
            end
        end 
        else begin
            for (integer j = 63; j >= 0; j=j-1) begin
                reg usedByPrev = 0;
                for (integer k = 1; k < i; k=k+2)
                    if (issueTags[k] == j[5:0]) 
                        usedByPrev = 1;
            
                if (!tags[j].used && !usedByPrev) begin
                    issueTags[i] = j[5:0];
                    issueTagsValid[i] = 1;
                end
            end
        end
    end
    
    // Check for collisions (for all tags except first)
    for (integer i = 1; i < NUM_ISSUE; i=i+1) begin
        
        // Collision is possible with all lower tags
        // that were read from the opposing side
        for (integer j = 0; j < i; j=j+1) begin
            if ((i % 2) != (j % 2)) begin
                if (issueTags[i] == issueTags[j]) begin
                    issueTags[i] = 'x;
                    issueTagsValid[i] = 0;
                end
            end
        end

    end
end

always_ff@(posedge clk) begin
    
    mispredWait <= 0;

    if (rst) begin
        for (integer i = 0; i < 64; i=i+1) begin
            tags[i].used <= 1'b0;
            tags[i].committed <= 1'b0;
        end
        for (integer i = 0; i < NUM_ISSUE; i=i+1)
            OUT_issueTagsValid[i] <= 0;
    end
    else begin
        if (IN_mispr) begin
            // Issue
            mispredWait <= 1;
            for (integer i = 0; i < 64; i=i+1) begin
                if (!tags[i].committed)
                    tags[i].used <= 0;
            end

            for (integer i = 0; i < NUM_ISSUE; i=i+1) begin
                OUT_issueTagsValid[i] <= 0;
                OUT_issueTags[i] <= 'x;
            end
        end
        else begin
            
            // Invalidate current tags if they're used
            for (integer i = 0; i < NUM_ISSUE; i=i+1) begin
                if (IN_issueValid[i]) begin
                    assert(OUT_issueTagsValid[i]);

                    OUT_issueTagsValid[i] <= 0;
                    OUT_issueTags[i] <= 'x;
                end
            end

            // Output Tags for next cycle
            for (integer i = 0; i < NUM_ISSUE; i=i+1) begin
                if ((!OUT_issueTagsValid[i] || IN_issueValid[i]) && issueTagsValid[i] && !(mispredWait || IN_mispredFlush)) begin

                    OUT_issueTagsValid[i] <= 1;
                    OUT_issueTags[i] <= issueTags[i];

                    tags[issueTags[i]].used <= 1;
                end
            end
        end
        
        // Commit
        for (integer i = 0; i < NUM_COMMIT; i=i+1) begin
            if (IN_commitValid[i]) begin
                
                if (IN_mispredFlush) begin
                    if (!IN_mispr && !IN_commitTagDst[i][6]) begin
                        tags[IN_commitTagDst[i][5:0]].used <= 1;
                    end
                end
                else begin
                    if (IN_commitNewest[i]) begin
                        if (!IN_RAT_commitPrevTags[i][6]) begin
                            tags[IN_RAT_commitPrevTags[i][5:0]].committed <= 0;
                            tags[IN_RAT_commitPrevTags[i][5:0]].used <= 0;
                        end
                        
                        if (!IN_commitTagDst[i][6]) begin
                            tags[IN_commitTagDst[i][5:0]].committed <= 1;
                            tags[IN_commitTagDst[i][5:0]].used <= 1;
                        end
                    end
                    else if (!IN_commitTagDst[i][6]) begin
                        tags[IN_commitTagDst[i][5:0]].committed <= 0;
                        tags[IN_commitTagDst[i][5:0]].used <= 0;
                    end
                end
            end
        end
    end
end

endmodule
