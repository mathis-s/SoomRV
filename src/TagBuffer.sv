

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
    output RFTag OUT_issueTags[NUM_ISSUE-1:0],
    output reg OUT_issueTagsValid[NUM_ISSUE-1:0],


    input wire IN_commitValid[NUM_COMMIT-1:0],
    input wire IN_commitNewest[NUM_COMMIT-1:0],
    input Tag IN_RAT_commitPrevTags[NUM_COMMIT-1:0],
    input Tag IN_commitTagDst[NUM_COMMIT-1:0]
);
// half of tag space is for eliminating immediates
localparam PTAG_LEN = $bits(Tag) - 1;
localparam NUM_TAGS = 1 << PTAG_LEN;

logic[NUM_TAGS-1:0] free /*verilator public*/;
logic[NUM_TAGS-1:0] freeCom /*verilator public*/;

reg mispredWait;

reg issueTagsValid[NUM_ISSUE-1:0];
RFTag issueTags[NUM_ISSUE-1:0];

PriorityEncoder#(NUM_TAGS, NUM_ISSUE) penc
(
    .IN_data(free),
    .OUT_idx(issueTags),
    .OUT_idxValid(issueTagsValid)
);

always_ff@(posedge clk or posedge rst) begin

    mispredWait <= 0;

    if (rst) begin
        for (integer i = 0; i < NUM_TAGS; i=i+1) begin
            free[i] <= 1'b1;
            freeCom[i] <= 1'b1;
        end
        for (integer i = 0; i < NUM_ISSUE; i=i+1)
            OUT_issueTagsValid[i] <= 0;
    end
    else begin
        if (IN_mispr) begin
            // Issue
            mispredWait <= 1;
            for (integer i = 0; i < NUM_TAGS; i=i+1) begin
                if (freeCom[i])
                    free[i] <= 1;
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

                    free[issueTags[i]] <= 0;
                end
            end
        end

        // Commit
        for (integer i = 0; i < NUM_COMMIT; i=i+1) begin
            if (IN_commitValid[i]) begin

                if (IN_mispredFlush) begin
                    if (!IN_mispr && !IN_commitTagDst[i][$bits(Tag)-1]) begin
                        free[RFTag'(IN_commitTagDst[i])] <= 0;
                    end
                end
                else begin
                    if (IN_commitNewest[i]) begin
                        if (!IN_RAT_commitPrevTags[i][$bits(Tag)-1]) begin
                            freeCom[RFTag'(IN_RAT_commitPrevTags[i])] <= 1;
                            free[RFTag'(IN_RAT_commitPrevTags[i])] <= 1;
                        end

                        if (!IN_commitTagDst[i][$bits(Tag)-1]) begin
                            freeCom[RFTag'(IN_commitTagDst[i])] <= 0;
                            free[RFTag'(IN_commitTagDst[i])] <= 0;
                        end
                    end
                    else if (!IN_commitTagDst[i][$bits(Tag)-1]) begin
                        freeCom[RFTag'(IN_commitTagDst[i])] <= 1;
                        free[RFTag'(IN_commitTagDst[i])] <= 1;
                    end
                end
            end
        end
    end
end

endmodule
