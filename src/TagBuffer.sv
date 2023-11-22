

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
// half of tag space is for eliminating immediates
localparam PTAG_LEN = $bits(Tag) - 1;
localparam NUM_TAGS = 1 << ($bits(Tag) - 1);

logic free[NUM_TAGS-1:0] /*verilator public*/;
logic freeCom[NUM_TAGS-1:0] /*verilator public*/;

reg mispredWait;

reg issueTagsValid[NUM_ISSUE-1:0];
reg[5:0] issueTags[NUM_ISSUE-1:0];

// Search Tree for getting index of NUM_ISSUE unused entries.
// This essentially is the classic count-leading-zeros type
// search tree, but instead of tracking one index, we track
// NUM_ISSUE indices. 
localparam NUM_STAGES = $clog2(NUM_TAGS); // excl base case
generate
for (genvar g = 0; g < NUM_STAGES+1; g=g+1) begin : gen
    logic[NUM_ISSUE-1:0][g:0] s[(NUM_TAGS>>g)-1:0];

    // Base
    if (g == 0) begin
        always_comb begin
            for (integer i = 0; i < NUM_TAGS; i=i+1) begin
                for (integer j = 0; j < NUM_ISSUE; j=j+1)
                    s[i][j] = 1; // LSBit represents undefined
                s[i][0] = !free[i];
            end
        end
    end
    // Step
    else begin
        for (genvar i = 0; i < (NUM_TAGS>>g); i=i+1) begin
            wire[NUM_ISSUE-1:0][g-1:0] a = gen[g-1].s[2*i+0];
            wire[NUM_ISSUE-1:0][g-1:0] b = gen[g-1].s[2*i+1];
            
            for (genvar j = 0; j < NUM_ISSUE; j=j+1) begin : gen2
                
                // manually build mux to avoid non-const index arithmetic
                wire[g-1:0] mux[j+1:0];
                for (genvar k = 0; k <= j; k=k+1)
                    assign mux[k] = b[j - k];
                assign mux[j+1] = a[j];
                
                // verilator lint_off WIDTHEXPAND
                wire[j == 0 ? 0 : ($clog2(j+2)-1):0] redSum;
                if (j == 0) assign redSum = !a[j][0];
                else        assign redSum = !a[j][0] + gen2[j-1].redSum;
                // verilator lint_on WIDTHEXPAND

                assign s[i][j] = {a[j][0], mux[redSum]};
            end
        end
    end
end
endgenerate

always_comb begin
    logic[NUM_ISSUE-1:0][PTAG_LEN:0] packedTags = gen[NUM_STAGES].s[0];
    for (integer i = 0; i < NUM_ISSUE; i=i+1) begin
        issueTags[i] = packedTags[i][PTAG_LEN:1];
        issueTagsValid[i] = !packedTags[i][0];
    end
end

always_ff@(posedge clk) begin
    
    mispredWait <= 0;

    if (rst) begin
        for (integer i = 0; i < 64; i=i+1) begin
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
            for (integer i = 0; i < 64; i=i+1) begin
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
                    if (!IN_mispr && !IN_commitTagDst[i][6]) begin
                        free[IN_commitTagDst[i][5:0]] <= 0;
                    end
                end
                else begin
                    if (IN_commitNewest[i]) begin
                        if (!IN_RAT_commitPrevTags[i][6]) begin
                            freeCom[IN_RAT_commitPrevTags[i][5:0]] <= 1;
                            free[IN_RAT_commitPrevTags[i][5:0]] <= 1;
                        end
                        
                        if (!IN_commitTagDst[i][6]) begin
                            freeCom[IN_commitTagDst[i][5:0]] <= 0;
                            free[IN_commitTagDst[i][5:0]] <= 0;
                        end
                    end
                    else if (!IN_commitTagDst[i][6]) begin
                        freeCom[IN_commitTagDst[i][5:0]] <= 1;
                        free[IN_commitTagDst[i][5:0]] <= 1;
                    end
                end
            end
        end
    end
end

endmodule
