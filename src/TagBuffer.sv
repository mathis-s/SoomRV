typedef struct packed
{
    bit used;
    bit committed;
} TagBufEntry;

module TagBuffer
#
(
    parameter NUM_UOPS=4
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
    input wire[6:0] IN_RAT_commitPrevTags[NUM_UOPS-1:0],
    input wire[6:0] IN_commitTagDst[NUM_UOPS-1:0]
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
                (i <= 1 || OUT_issueTags[1] != j[5:0]) &&
                (i <= 2 || OUT_issueTags[2] != j[5:0])
                ) begin
                OUT_issueTags[i] = j[5:0];
                OUT_issueTagsValid[i] = 1;
            end
        end
    end
end

reg[63:0] dbgUsed;
always_comb begin
    for (i = 0; i < 64; i=i+1)
        dbgUsed[i] = tags[i].used;
end

/*
RESULTS
Runtime (cycles) 24008
Executed (instrs) 38427
Decoded (instrs) 38895
mIPC 1600
mDMIPS/MHz 4761
36648 cycles
*/
always_ff@(posedge clk) begin
    if (rst) begin
    
        /*tags[0].used <= 1'b0;
        tags[0].committed <= 1'b0;
        
        for (i = 1; i < 32; i=i+1) begin
            tags[i].used <= 1'b1;
            tags[i].committed <= 1'b1;
        end*/
        for (i = 0; i < 64; i=i+1) begin
            tags[i].used <= 1'b0;
            tags[i].committed <= 1'b0;
        end
        
        /*for (i = 1; i < 32; i=i+1) begin
            tags[i].used <= 1'b1;
            tags[i].committed <= 1'b1;
        end*/
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
                    if (!IN_mispr && !IN_commitTagDst[i][6]) tags[IN_commitTagDst[i][5:0]].used <= 1;
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
