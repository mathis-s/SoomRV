module Rename
#(
    parameter WIDTH_ISSUE = `DEC_WIDTH,
    parameter WIDTH_COMMIT = 4,
    parameter WIDTH_WR = 4
)
(
    input wire clk,
    input wire frontEn,
    input wire rst,

    input wire[NUM_PORTS_TOTAL-1:0][WIDTH_ISSUE-1:0] IN_stalls,
    output reg OUT_stall,

    // Tag lookup for just decoded instrs
    input D_UOp IN_uop[WIDTH_ISSUE-1:0],

    // Committed changes from ROB
    input CommitUOp IN_comUOp[WIDTH_COMMIT-1:0],

    // WB for uncommitted but speculatively available values
    input wire IN_wbHasResult[WIDTH_WR-1:0],
    input RES_UOp IN_wbUOp[WIDTH_WR-1:0],

    // Taken branch
    input BranchProv IN_branch,
    input wire IN_mispredFlush,

    output R_UOp OUT_uop[WIDTH_ISSUE-1:0],
    // This is just an alternating bit that switches with each regular int op,
    // for assignment to issue queues.
    output IntUOpOrder_t OUT_uopOrdering[WIDTH_ISSUE-1:0],
    output SqN OUT_nextSqN,
    output SqN OUT_nextLoadSqN,
    output SqN OUT_nextStoreSqN
);

typedef struct packed
{
    SqN sqN;
    logic valid;
} LrScRsv;

reg[3:0] portStall;
always_comb begin
    for (integer i = 0; i < WIDTH_ISSUE; i=i+1) begin
        portStall[i] = 0;
        for (integer j = 0; j < NUM_PORTS_TOTAL; j=j+1)
            portStall[i] |= IN_stalls[j][i];
    end
end

wire RAT_lookupAvail[2*WIDTH_ISSUE-1:0];
Tag RAT_lookupSpecTag[2*WIDTH_ISSUE-1:0];
reg[4:0] RAT_lookupIDs[2*WIDTH_ISSUE-1:0];

reg[4:0] RAT_issueIDs[WIDTH_ISSUE-1:0];
reg RAT_issueValid[WIDTH_ISSUE-1:0];
reg RAT_issueAvail[WIDTH_ISSUE-1:0];
SqN RAT_issueSqNs[WIDTH_ISSUE-1:0];
reg TB_issueValid[WIDTH_ISSUE-1:0];
reg TB_tagNeeded[WIDTH_ISSUE-1:0];

reg RAT_commitValid[WIDTH_COMMIT-1:0];
reg TB_commitValid[WIDTH_COMMIT-1:0];

reg[4:0] RAT_commitIDs[WIDTH_COMMIT-1:0];
Tag RAT_commitTags[WIDTH_COMMIT-1:0];
Tag RAT_commitPrevTags[WIDTH_COMMIT-1:0];

Tag RAT_wbTags[WIDTH_WR-1:0];

SqN nextCounterSqN;

reg isSc[3:0];
reg scSuccessful[3:0];

always_comb begin

    OUT_stall = |portStall;
    nextCounterSqN = counterSqN;

    // Stall
    for (integer i = 0; i < WIDTH_ISSUE; i=i+1) begin

        if (IN_mispredFlush && IN_uop[i].valid)
            OUT_stall = 1;

        isSc[i] = IN_uop[i].fu == FU_AGU && IN_uop[i].opcode == LSU_SC_W;
        scSuccessful[i] = !(i == 0 && failSc);

        // Only need new tag if instruction writes to a register.
        // FU_ATOMIC always gets a register (even when rd is x0) as it is used for storing the intermediate result.
        TB_tagNeeded[i] = (IN_uop[i].rd != 0 || IN_uop[i].fu == FU_ATOMIC) &&
            // these don't write or writes are eliminated
            IN_uop[i].fu != FU_RN && IN_uop[i].fu != FU_TRAP && !isSc[i];

        if ((!TB_tagsValid[i]) && IN_uop[i].valid && frontEn && TB_tagNeeded[i])
            OUT_stall = 1;
    end

    // Issue/Lookup
    for (integer i = 0; i < WIDTH_ISSUE; i=i+1) begin

        RAT_lookupIDs[2*i+0] = IN_uop[i].rs1;
        RAT_lookupIDs[2*i+1] = IN_uop[i].rs2;

        RAT_issueIDs[i] = IN_uop[i].rd;
        RAT_issueSqNs[i] = nextCounterSqN;
        RAT_issueValid[i] = !rst && !IN_branch.taken && frontEn && !OUT_stall && IN_uop[i].valid;
        RAT_issueAvail[i] = IN_uop[i].fu == FU_RN || isSc[i];

        TB_issueValid[i] = RAT_issueValid[i] && TB_tagNeeded[i];

        if (RAT_issueValid[i])
            nextCounterSqN = nextCounterSqN + 1;
    end

    // Writeback
    for (integer i = 0; i < WIDTH_WR; i=i+1) begin
        RAT_wbTags[i] = IN_wbUOp[i].tagDst;
    end

    // Commit
    for (integer i = 0; i < WIDTH_COMMIT; i=i+1) begin
        RAT_commitValid[i] = (IN_comUOp[i].valid && (IN_comUOp[i].rd != 0));
        TB_commitValid[i] = IN_comUOp[i].valid;

        RAT_commitIDs[i] = IN_comUOp[i].rd;
        RAT_commitTags[i] = IN_comUOp[i].tagDst;
    end

end

RenameTable
#(
    .NUM_LOOKUP(WIDTH_ISSUE*2),
    .NUM_ISSUE(WIDTH_ISSUE),
    .NUM_COMMIT(WIDTH_COMMIT),
    .NUM_WB(WIDTH_WR)
)
rt
(
    .clk(clk),
    .rst(rst),
    .IN_mispred(IN_branch.taken),
    .IN_mispredFlush(IN_mispredFlush),

    .IN_lookupIDs(RAT_lookupIDs),
    .OUT_lookupAvail(RAT_lookupAvail),
    .OUT_lookupSpecTag(RAT_lookupSpecTag),

    .IN_issueValid(RAT_issueValid),
    .IN_issueIDs(RAT_issueIDs),
    .IN_issueTags(newTags),
    .IN_issueAvail(RAT_issueAvail),

    .IN_commitValid(RAT_commitValid),
    .IN_commitIDs(RAT_commitIDs),
    .IN_commitTags(RAT_commitTags),
    .OUT_commitPrevTags(RAT_commitPrevTags),

    .IN_wbValid(IN_wbHasResult),
    .IN_wbTag(RAT_wbTags)
);

reg failSc;
RFTag TB_tags[WIDTH_ISSUE-1:0];
Tag newTags[WIDTH_ISSUE-1:0];
reg TB_tagsValid[WIDTH_ISSUE-1:0];
always_comb begin
    for (integer i = 0; i < WIDTH_ISSUE; i=i+1) begin
        if (TB_issueValid[i]) newTags[i] = {1'b0, TB_tags[i]};
        else if (IN_uop[i].fu == FU_RN) newTags[i] = {1'b1, RFTag'(IN_uop[i].imm)};
        else if (isSc[i]) newTags[i] = {1'b1, {($bits(Tag)-2){1'b0}}, !scSuccessful[i]};
        else newTags[i] = TAG_ZERO;
    end
end
TagBuffer#(.NUM_ISSUE(WIDTH_ISSUE), .NUM_COMMIT(WIDTH_COMMIT)) tb
(
    .clk(clk),
    .rst(rst),
    .IN_mispr(IN_branch.taken),
    .IN_mispredFlush(IN_mispredFlush),

    .IN_issueValid(TB_issueValid),
    .OUT_issueTags(TB_tags),
    .OUT_issueTagsValid(TB_tagsValid),

    .IN_commitValid(TB_commitValid),
    .IN_commitNewest(isNewestCommit),
    .IN_RAT_commitPrevTags(RAT_commitPrevTags),
    .IN_commitTagDst(RAT_commitTags)
);

reg isNewestCommit[WIDTH_COMMIT-1:0];
always_comb begin
    for (integer i = 0; i < WIDTH_COMMIT; i=i+1) begin

        // When rd == 0, the register is (also) discarded immediately instead of being committed.
        // This is currently only used for rmw atomics with rd=x0.
        isNewestCommit[i] = IN_comUOp[i].valid && IN_comUOp[i].rd != 0;
        if (IN_comUOp[i].valid)
            for (integer j = i + 1; j < WIDTH_COMMIT; j=j+1)
                if (IN_comUOp[j].valid && (IN_comUOp[j].rd == IN_comUOp[i].rd))
                    isNewestCommit[i] = 0;
    end
end

wire cycleValid = !IN_branch.taken && frontEn && !OUT_stall;

// Generate SqNs
SqN counterSqN;
SqN counterStoreSqN;
SqN counterLoadSqN;
assign OUT_nextSqN = counterSqN;

SqN loadSqNs[WIDTH_ISSUE:0];
SqN storeSqNs[WIDTH_ISSUE:0];
always_comb begin

    loadSqNs[0] = counterLoadSqN;
    storeSqNs[0] = counterStoreSqN;

    for (integer i = 0; i < WIDTH_ISSUE; i=i+1) begin

        loadSqNs[i+1] = loadSqNs[i];
        storeSqNs[i+1] = storeSqNs[i];

        if (cycleValid && IN_uop[i].valid && !(isSc[i] && !scSuccessful[i])) begin
            if (IN_uop[i].fu == FU_ATOMIC || (IN_uop[i].fu == FU_AGU && IN_uop[i].opcode <  LSU_SC_W))
                loadSqNs[i+1] = loadSqNs[i] + 1;
            if (IN_uop[i].fu == FU_ATOMIC || (IN_uop[i].fu == FU_AGU && IN_uop[i].opcode >= LSU_SC_W))
                storeSqNs[i+1] = storeSqNs[i] + 1;
        end
    end
end

// Assign UOps to Ports
IntUOpOrder_t SCHED_uopOrder[WIDTH_ISSUE-1:0];
Scheduler scheduler
(
    .clk(clk),
    .rst(rst),

    .IN_valid(cycleValid),
    .IN_uopSqN(RAT_issueSqNs),
    .IN_uopLoadSqN(loadSqNs[WIDTH_ISSUE:1]),
    .IN_uopStoreSqN(storeSqNs[WIDTH_ISSUE:1]),
    .IN_uop(IN_uop),
    .OUT_order(SCHED_uopOrder)
);


always_ff@(posedge clk) begin

    if (rst) begin
        counterSqN <= 0;
        counterStoreSqN <= -1;
        counterLoadSqN <= 0;

        OUT_nextStoreSqN <= 0;
        OUT_nextLoadSqN <= 0;
        failSc <= 0;

        for (integer i = 0; i < WIDTH_ISSUE; i=i+1) begin
            OUT_uop[i] <= 'x;
            OUT_uop[i].valid <= 0;
            OUT_uop[i].validIQ <= 0;
        end
    end
    else if (IN_branch.taken) begin

        counterSqN <= IN_branch.sqN + 1;

        counterLoadSqN <= IN_branch.loadSqN;
        counterStoreSqN <= IN_branch.storeSqN;

        OUT_nextLoadSqN <= IN_branch.loadSqN;
        OUT_nextStoreSqN <= IN_branch.storeSqN + 1;

        failSc <= IN_branch.isSCFail;

        for (integer i = 0; i < WIDTH_ISSUE; i=i+1) begin
            if ($signed(OUT_uop[i].sqN - IN_branch.sqN) > 0) begin
                OUT_uop[i] <= 'x;
                OUT_uop[i].valid <= 0;
                OUT_uop[i].validIQ <= 0;
            end
        end
    end
    else begin
        counterLoadSqN <= loadSqNs[WIDTH_ISSUE];
        counterStoreSqN <= storeSqNs[WIDTH_ISSUE];
        OUT_nextLoadSqN <= loadSqNs[WIDTH_ISSUE];
        OUT_nextStoreSqN <= storeSqNs[WIDTH_ISSUE] + 1;
    end

    if (!rst && |portStall) begin
        // If frontend is stalled right now we need to make sure
        // the ops we're stalled on are kept up-to-date, as they will be
        // read later.
        for (integer i = 0; i < WIDTH_WR; i=i+1) begin
            if (IN_wbHasResult[i]) begin
                for (integer j = 0; j < WIDTH_ISSUE; j=j+1) begin
                    if (|OUT_uop[j].validIQ) begin
                        if (OUT_uop[j].tagA == IN_wbUOp[i].tagDst)
                            OUT_uop[j].availA <= 1;
                        if (OUT_uop[j].tagB == IN_wbUOp[i].tagDst)
                            OUT_uop[j].availB <= 1;
                        if (OUT_uop[j].tagC == IN_wbUOp[i].tagDst)
                            OUT_uop[j].availC <= 1;
                    end
                end
            end
        end
    end

    if (rst) ;
    else if (cycleValid) begin
        // Set seqnum/tags for next instruction(s)
        for (integer i = 0; i < WIDTH_ISSUE; i=i+1) begin
            OUT_uop[i] <= R_UOp'{valid: 0, validIQ: 0, default: 'x};
            if (IN_uop[i].valid) begin

                failSc <= 0;

                OUT_uop[i] <= R_UOp'{
                    imm:        IN_uop[i].imm,
                    imm12:      IN_uop[i].imm12,

                    availA:     RAT_lookupAvail[2*i+0],
                    tagA:       RAT_lookupSpecTag[2*i+0],
                    availB:     RAT_lookupAvail[2*i+1],
                    tagB:       RAT_lookupSpecTag[2*i+1],

                    tagC:       TAG_ZERO,
                    availC:     1'b1,

                    sqN:        RAT_issueSqNs[i],
                    tagDst:     newTags[i],
                    rd:         IN_uop[i].rd,

                    opcode:     IN_uop[i].opcode,
                    fu:         IN_uop[i].fu,
                    fetchID:    IN_uop[i].fetchID,
                    fetchOffs:  IN_uop[i].fetchOffs,
                    storeSqN:   storeSqNs[i+1], // +1 here, store sqn pre-increments
                    loadSqN:    loadSqNs[i],    // +0 here, load sqn post-increments
                    immB:       IN_uop[i].immB,
                    compressed: IN_uop[i].compressed,

                    valid:      1'b1,
                    validIQ:    {NUM_PORTS_TOTAL{1'b1}},
                    default:    'x
                };

                // The cause for decode-time pure traps is encoded
                // in rd. This saves encoding space, as these instructions
                // have no result anyways.
                if (IN_uop[i].fu == FU_TRAP)
                    OUT_uop[i].rd <= IN_uop[i].opcode[4:0];

                // Don't execute unsuccessful SC, handle (ie eliminate) just like load-imm
                if (isSc[i] && !scSuccessful[i])
                    OUT_uop[i].fu <= FU_RN;

                // Atomics need a total of three source tags (addr, reg operand, mem operand).
                // The mem operand is the result tag of the LD uop, and thus the same as tagDst.
                if (IN_uop[i].fu == FU_ATOMIC) begin
                    OUT_uop[i].tagC <= newTags[i];
                    OUT_uop[i].availC <= 0;
                end

                OUT_uopOrdering[i] <= SCHED_uopOrder[i];
            end
        end

        counterSqN <= nextCounterSqN;
    end
    else begin
        // R_UOp carries two seperate valid signals. "valid" is the plain signal
        // used by ROB and SQ. This signal is only ever set for one cycle, ROB and SQ
        // do not stall.
        // "validIQ" contains an individual valid bit for each IQ, these bits may be set
        // for multiple cycles should IQs stall.
        for (integer i = 0; i < WIDTH_ISSUE; i++) begin
            OUT_uop[i].valid <= 0;

            for (integer j = 0; j < NUM_PORTS_TOTAL; j=j+1) begin
                if (!IN_stalls[j][i]) OUT_uop[i].validIQ[j] <= 0;
            end
        end
    end
end
endmodule
