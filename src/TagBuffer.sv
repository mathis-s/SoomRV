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
integer i;
integer j;
integer k;

TagBufEntry tags[63:0];

always_comb begin
    for (i = 0; i < NUM_ISSUE; i=i+1) begin
        OUT_issueTags[i] = 6'bx;
        for (j = 0; j < 64; j=j+1) begin
            
            reg usedByPrev = 0;
            for (k = 0; k < i; k=k+1)
                if (OUT_issueTags[k] == j[5:0]) 
                    usedByPrev = 1;
        
            if (!tags[j].used && !usedByPrev) begin
                OUT_issueTags[i] = j[5:0];
            end
        end
    end
end

reg[63:0] dbgUsed;
always_comb begin
    for (i = 0; i < 64; i=i+1)
        dbgUsed[i] = tags[i].used;
end

reg[6:0] free;
reg[6:0] freeCom;
//reg[1:0] resStage0[31:0];
//reg[2:0] resStage1[15:0];
//reg[2:0] resStage2[7:0];
//reg[2:0] resStage3[3:0];
//reg[2:0] resStage4[1:0];
always_comb begin
    /*free = 0;
    
    for (i = 0; i < 32; i=i+1) resStage0[i] = (!tags[2*i].used) + (!tags[2*i+1].used);
    for (i = 0; i < 16; i=i+1) resStage1[i] = resStage0[2*i] + resStage0[2*i+1];
    for (i = 0; i < 8; i=i+1) begin
        reg[3:0] temp = resStage1[2*i] + resStage1[2*i+1];
        resStage2[i] = temp[3] ? 3'b100 : temp[2:0];
    end 
    for (i = 0; i < 4; i=i+1) begin
        reg[3:0] temp = resStage2[2*i] + resStage2[2*i+1];
        resStage3[i] = temp[3] ? 3'b100 : temp[2:0];
    end 
    for (i = 0; i < 2; i=i+1) begin
        reg[3:0] temp = resStage3[2*i] + resStage3[2*i+1];
        resStage4[i] = temp[3] ? 3'b100 : temp[2:0];
    end
    for (i = 0; i < 1; i=i+1) begin
        reg[3:0] temp = resStage4[2*i] + resStage4[2*i+1];
        free = temp[3] ? 3'b100 : temp[2:0];
    end*/
    
    for (i = 0; i < NUM_ISSUE; i=i+1)
        OUT_issueTagsValid[i] = free > i[6:0];
end

reg[6:0] cnt;
always_comb begin
    
    cnt = 0;
    if (!rst) begin
        for (i = 0; i < 64; i=i+1)
            if (!tags[i].used) cnt = cnt + 1;
        
        if (cnt != free)
            $display("%d %d", cnt, free);
        //assert(cnt == free);
    end
end

always_ff@(posedge clk) begin
    if (rst) begin
        for (i = 0; i < 64; i=i+1) begin
            tags[i].used <= 1'b0;
            tags[i].committed <= 1'b0;
        end
        
        free = 64;
        freeCom = 64;
    end
    else begin
        if (IN_mispr) begin
            // Issue
            for (i = 0; i < 64; i=i+1) begin
                if (!tags[i].committed)
                    tags[i].used <= 0;
            end
        end
        else begin
            for (i = 0; i < NUM_ISSUE; i=i+1) begin
                if (IN_issueValid[i]) begin
                    assert(OUT_issueTagsValid[i]);
                    tags[OUT_issueTags[i]].used <= 1;
                    free = free - 1;
                end
            end
        end
        
        // Commit
        for (i = 0; i < NUM_COMMIT; i=i+1) begin
            if (IN_commitValid[i]) begin
                
                if (IN_mispredFlush) begin
                    if (!IN_mispr && !IN_commitTagDst[i][6]) begin
                        tags[IN_commitTagDst[i][5:0]].used <= 1;
                        free = free - 1;
                    end
                end
                else begin
                    if (IN_commitNewest[i]) begin
                        if (!IN_RAT_commitPrevTags[i][6]) begin
                            tags[IN_RAT_commitPrevTags[i][5:0]].committed <= 0;
                            tags[IN_RAT_commitPrevTags[i][5:0]].used <= 0;
                            
                            /*if (tags[IN_RAT_commitPrevTags[i][5:0]].committed)*/ freeCom = freeCom + 1;
                            /*if (tags[IN_RAT_commitPrevTags[i][5:0]].used)*/ free = free + 1;
                            
                        end
                        
                        if (!IN_commitTagDst[i][6]) begin
                            tags[IN_commitTagDst[i][5:0]].committed <= 1;
                            tags[IN_commitTagDst[i][5:0]].used <= 1;
                            
                            /*if (!tags[IN_commitTagDst[i][5:0]].committed)*/ freeCom = freeCom - 1;
                            // if (!tags[IN_commitTagDst[i][5:0]].used) free = free - 1;
                        end
                    end
                    else if (!IN_commitTagDst[i][6]) begin
                        tags[IN_commitTagDst[i][5:0]].committed <= 0;
                        tags[IN_commitTagDst[i][5:0]].used <= 0;
                        
                        //if (tags[IN_commitTagDst[i][5:0]].committed) freeCom = freeCom + 1;
                        /*if (tags[IN_commitTagDst[i][5:0]].used)*/ free = free + 1;
                    end
                end
            end
        end
            
        if (IN_mispr)
            free = freeCom;
    end
end

endmodule
