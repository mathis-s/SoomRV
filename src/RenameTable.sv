typedef struct packed
{
    bit avail;
    bit[6:0] comTag;
    bit[6:0] specTag;
} RATEntry;

module RenameTable
#(
    parameter NUM_LOOKUP=6,
    parameter NUM_ISSUE=3,
    parameter NUM_COMMIT=3,
    parameter NUM_WB=3,
    parameter NUM_REGS=64,
    parameter ID_SIZE=$clog2(NUM_REGS),
    parameter TAG_SIZE=7
)
(
    input wire clk,
    input wire rst,
    input wire IN_mispred,
    input wire IN_mispredFlush,

    input wire[ID_SIZE-1:0] IN_lookupIDs[NUM_LOOKUP-1:0],
    output reg OUT_lookupAvail[NUM_LOOKUP-1:0],
    output reg[TAG_SIZE-1:0] OUT_lookupSpecTag[NUM_LOOKUP-1:0],
    
    input wire IN_issueValid[NUM_ISSUE-1:0],
    input wire[ID_SIZE-1:0] IN_issueIDs[NUM_ISSUE-1:0],
    input wire[TAG_SIZE-1:0] IN_issueTags[NUM_ISSUE-1:0],
    
    input wire IN_commitValid[NUM_COMMIT-1:0],
    input wire[ID_SIZE-1:0] IN_commitIDs[NUM_COMMIT-1:0],
    input wire[TAG_SIZE-1:0] IN_commitTags[NUM_COMMIT-1:0],
    output reg[TAG_SIZE-1:0] OUT_commitPrevTags[NUM_COMMIT-1:0],

    input wire IN_wbValid[NUM_WB-1:0],
    input wire[ID_SIZE-1:0] IN_wbID[NUM_WB-1:0],
    input wire[TAG_SIZE-1:0] IN_wbTag[NUM_WB-1:0]
);
integer i;
integer j;

RATEntry rat[NUM_REGS-1:0];

always_comb begin
    for (i = 0; i < NUM_LOOKUP; i=i+1) begin
        OUT_lookupAvail[i] = rat[IN_lookupIDs[i]].avail;
        OUT_lookupSpecTag[i] = rat[IN_lookupIDs[i]].specTag;
        
        // Results that are written back in the current cycle also need to be marked as available
        for (j = 0; j < NUM_WB; j=j+1) begin
            if (IN_wbValid[j] && IN_wbTag[j] == OUT_lookupSpecTag[i])
                OUT_lookupAvail[i] = 1;
        end
        // Later lookups are affected by previous ops, even in the same cycle
        for (j = 0; j < (i / 2); j=j+1) begin
            if (IN_issueValid[j] && IN_issueIDs[j] == IN_lookupIDs[i] && IN_issueIDs[j] != 0) begin
                OUT_lookupAvail[i] = 0;
                OUT_lookupSpecTag[i] = IN_issueTags[j];
            end
        end
    end
    
    for (i = 0; i < NUM_COMMIT; i=i+1) begin
        OUT_commitPrevTags[i] = rat[IN_commitIDs[i]].comTag;
    end
end

always_ff@(posedge clk) begin
    
    if (rst) begin
        // Registers initialized with tags 0..31
        for (i = 0; i < NUM_REGS; i=i+1) begin
            rat[i].avail <= 1;
            rat[i].comTag <= i[TAG_SIZE-1:0];
            rat[i].specTag <= i[TAG_SIZE-1:0];
        end
    end
    else begin
        
        // Written back values are speculatively available
        for (i = 0; i < NUM_WB; i=i+1) begin
            if (IN_wbValid[i] && rat[IN_wbID[i]].specTag == IN_wbTag[i]) begin
                rat[IN_wbID[i]].avail <= 1;
            end
        end
        
        if (IN_mispred) begin
            for (i = 0; i < NUM_REGS; i=i+1) begin
                rat[i].avail <= 1;
                // Ideally we would set specTag to the last specTag that isn't post incoming branch.
                // We can't keep such a history for every register though. As such, we flush the pipeline
                // after a mispredict. After flush, all results are committed, and rename can continue again.
                rat[i].specTag <= rat[i].comTag;
            end
        end
        else begin
            for (i = 0; i < NUM_ISSUE; i=i+1) begin
                if (IN_issueValid[i] && IN_issueIDs[i] != 0) begin
                    rat[IN_issueIDs[i]].avail <= 0;
                    rat[IN_issueIDs[i]].specTag <= IN_issueTags[i];
                end
            end
        end
        
        for (i = 0; i < NUM_COMMIT; i=i+1) begin
            if (IN_commitValid[i]) begin
                rat[IN_commitIDs[i]].comTag <= IN_commitTags[i];
                if (IN_mispredFlush || IN_mispred) begin
                    rat[IN_commitIDs[i]].specTag <= IN_commitTags[i];
                    //rat[IN_commitIDs[i]].avail <= 1;
                end
            end
        end
    end
end

endmodule
