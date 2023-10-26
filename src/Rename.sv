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
    
    input wire[3:0][WIDTH_ISSUE-1:0] IN_stalls,
    output reg OUT_stall,

    // Tag lookup for just decoded instrs
    input D_UOp IN_uop[WIDTH_ISSUE-1:0],

    // Committed changes from ROB
    input CommitUOp IN_comUOp[WIDTH_COMMIT-1:0],

    // WB for uncommitted but speculatively available values
    input wire IN_wbHasResult[WIDTH_WR-1:0],
    input RES_UOp IN_wbUOp[WIDTH_WR-1:0],

    // Taken branch
    input wire IN_branchTaken,
    input wire IN_branchFlush,
    input SqN IN_branchSqN,
    input SqN IN_branchLoadSqN,
    input SqN IN_branchStoreSqN,
    input wire IN_mispredFlush,
    
    output R_UOp OUT_uop[WIDTH_ISSUE-1:0],
    // This is just an alternating bit that switches with each regular int op,
    // for assignment to issue queues.
    output reg OUT_uopOrdering[WIDTH_ISSUE-1:0],
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
        for (integer j = 0; j < 4; j=j+1)
            portStall[i] |= IN_stalls[j][i];
    end
end

wire RAT_lookupAvail[2*WIDTH_ISSUE-1:0];
wire[6:0] RAT_lookupSpecTag[2*WIDTH_ISSUE-1:0];
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
reg[6:0] RAT_commitTags[WIDTH_COMMIT-1:0];
wire[6:0] RAT_commitPrevTags[WIDTH_COMMIT-1:0];
reg RAT_commitAvail[WIDTH_COMMIT-1:0];

reg[6:0] RAT_wbTags[WIDTH_WR-1:0];

SqN nextCounterSqN;


reg isSc[3:0];
reg scSuccessful[3:0];
LrScRsv lrScRsv;
LrScRsv nextLrScRsv;

always_comb begin

    OUT_stall = |portStall;

    nextCounterSqN = counterSqN;
    nextLrScRsv = lrScRsv;
    
    if ($signed(lrScRsv.sqN - counterSqN) >= 0)
        nextLrScRsv.valid = 0;
        
    // Stall
    for (integer i = 0; i < WIDTH_ISSUE; i=i+1) begin

        if (IN_mispredFlush && IN_uop[i].valid)
            OUT_stall = 1;
        
        isSc[i] = IN_uop[i].fu == FU_ST && IN_uop[i].opcode == LSU_SC_W;
        
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
        RAT_issueValid[i] = !rst && !IN_branchTaken && frontEn && !OUT_stall && IN_uop[i].valid;
        RAT_issueAvail[i] = IN_uop[i].fu == FU_RN || isSc[i];
        
        // LR/SC Handling
        scSuccessful[i] = 0;
        if (RAT_issueValid[i]) begin
            // Reserve if LR
            if (IN_uop[i].fu == FU_LD && IN_uop[i].opcode == LSU_LR_W) begin
                nextLrScRsv.sqN = RAT_issueSqNs[i];
                nextLrScRsv.valid = 1;
            end
            // Use reservation if SC
            else if (isSc[i]) begin
                scSuccessful[i] = nextLrScRsv.valid;
                nextLrScRsv.valid = 0;
            end
            // All other stores, cmo or amo ops clear reservation
            else if (IN_uop[i].fu == FU_ST || IN_uop[i].fu == FU_ATOMIC) begin
                nextLrScRsv.valid = 0;
            end
        end
            
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
            //&& (!IN_branchTaken || $signed(IN_comUOp[i].sqN - IN_branchSqN) <= 0));
        TB_commitValid[i] = IN_comUOp[i].valid;
        
        RAT_commitIDs[i] = IN_comUOp[i].rd;
        RAT_commitTags[i] = IN_comUOp[i].tagDst;
        // Only using during mispredict replay
        RAT_commitAvail[i] = IN_comUOp[i].compressed;

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
    .IN_mispred(IN_branchTaken),
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
    .IN_commitAvail(RAT_commitAvail),
    .OUT_commitPrevTags(RAT_commitPrevTags),
    
    .IN_wbValid(IN_wbHasResult),
    .IN_wbTag(RAT_wbTags)
);

reg[5:0] TB_tags[WIDTH_ISSUE-1:0];
reg[6:0] newTags[WIDTH_ISSUE-1:0];
reg TB_tagsValid[WIDTH_ISSUE-1:0];
always_comb begin
    for (integer i = 0; i < WIDTH_ISSUE; i=i+1) begin
        if (TB_issueValid[i]) newTags[i] = {1'b0, TB_tags[i]};
        else if (IN_uop[i].fu == FU_RN) newTags[i] = {1'b1, IN_uop[i].imm[5:0]};
        else if (isSc[i]) newTags[i] = {1'b1, 5'b0, !scSuccessful[i]};
        else newTags[i] = 7'h40;
    end
end
TagBuffer#(.NUM_ISSUE(WIDTH_ISSUE), .NUM_COMMIT(WIDTH_COMMIT)) tb
(
    .clk(clk),
    .rst(rst),
    .IN_mispr(IN_branchTaken),
    .IN_mispredFlush(IN_mispredFlush),
    
    .IN_issueValid(TB_issueValid),
    .OUT_issueTags(TB_tags),
    .OUT_issueTagsValid(TB_tagsValid),
    
    .IN_commitValid(TB_commitValid),
    .IN_commitNewest(isNewestCommit),
    .IN_RAT_commitPrevTags(RAT_commitPrevTags),
    .IN_commitTagDst(RAT_commitTags)
);

reg intOrder;
SqN counterSqN;
SqN counterStoreSqN;
SqN counterLoadSqN;
assign OUT_nextSqN = counterSqN;

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

always_ff@(posedge clk) begin

    if (rst) begin
        counterSqN <= 0;
        counterStoreSqN = -1;
        counterLoadSqN = 0;
        OUT_nextLoadSqN <= counterLoadSqN;
        OUT_nextStoreSqN <= counterStoreSqN + 1;
        intOrder = 0;
        lrScRsv.valid <= 0;
    
        for (integer i = 0; i < WIDTH_ISSUE; i=i+1) begin
            OUT_uop[i] <= 'x;
            OUT_uop[i].valid <= 0;
            OUT_uop[i].validIQ <= 0;
        end
    end
    else if (IN_branchTaken) begin
        
        counterSqN <= IN_branchSqN + 1;
        
        counterLoadSqN = IN_branchLoadSqN;
        counterStoreSqN = IN_branchStoreSqN;
        
        for (integer i = 0; i < WIDTH_ISSUE; i=i+1) begin
            if ($signed(OUT_uop[i].sqN - IN_branchSqN) > 0) begin
                OUT_uop[i] <= 'x;
                OUT_uop[i].valid <= 0;
                OUT_uop[i].validIQ <= 0;
            end
        end
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
                    end
                end
            end
        end
    end

    if (rst) ;
    else if (!IN_branchTaken && frontEn && !OUT_stall) begin

        // Look up tags and availability of operands for new instructions
        for (integer i = 0; i < WIDTH_ISSUE; i=i+1) begin
            OUT_uop[i].imm <= IN_uop[i].imm;
            OUT_uop[i].imm12 <= IN_uop[i].imm12;
            OUT_uop[i].opcode <= IN_uop[i].opcode;
            OUT_uop[i].fu <= IN_uop[i].fu;
            
            // The cause for decode-time pure traps is encoded
            // in rd. This saves encoding space, as these instructions
            // have no result anyways.
            if (IN_uop[i].fu == FU_TRAP)
                OUT_uop[i].rd <= IN_uop[i].opcode[4:0];
            else
                OUT_uop[i].rd <= IN_uop[i].rd;
                
            // Don't execute unsuccessful SC, handle (ie eliminate) just like load-imm
            if (isSc[i] && !scSuccessful[i])
                OUT_uop[i].fu <= FU_RN;
            
            OUT_uop[i].fetchID <= IN_uop[i].fetchID;
            OUT_uop[i].fetchOffs <= IN_uop[i].fetchOffs;
            OUT_uop[i].immB <= IN_uop[i].immB;
            OUT_uop[i].compressed <= IN_uop[i].compressed;
        end
        
        // Set seqnum/tags for next instruction(s)
        for (integer i = 0; i < WIDTH_ISSUE; i=i+1) begin
            if (IN_uop[i].valid) begin
                
                OUT_uop[i].valid <= 1;
                OUT_uop[i].validIQ <= '1;
                
                OUT_uop[i].loadSqN <= counterLoadSqN;
                OUT_uopOrdering[i] <= intOrder;
                
                if (!(isSc[i] && !scSuccessful[i]))
                    case (IN_uop[i].fu)
                        FU_INT: intOrder = !intOrder;
                        FU_DIV, FU_FPU:  intOrder = 1;
                        FU_FDIV, FU_FMUL, FU_MUL: intOrder = 0;
                        
                        FU_ST: counterStoreSqN = counterStoreSqN + 1;
                        FU_LD: counterLoadSqN = counterLoadSqN + 1;
                        
                        FU_ATOMIC: begin
                            counterStoreSqN = counterStoreSqN + 1;
                            counterLoadSqN = counterLoadSqN + 1;
                            intOrder = 1;
                        end
                        default: begin end
                    endcase
                
                OUT_uop[i].sqN <= RAT_issueSqNs[i];
                OUT_uop[i].storeSqN <= counterStoreSqN;
                // These are affected by previous instrs
                OUT_uop[i].tagA <= RAT_lookupSpecTag[2*i+0];
                OUT_uop[i].tagB <= RAT_lookupSpecTag[2*i+1];
                OUT_uop[i].availA <= RAT_lookupAvail[2*i+0];
                OUT_uop[i].availB <= RAT_lookupAvail[2*i+1];
                
                OUT_uop[i].tagDst <= newTags[i];
            end
            else begin
                OUT_uop[i] <= R_UOp'{valid: 0, validIQ: 0, default: 'x};
            end
        end
        counterSqN <= nextCounterSqN;
        lrScRsv <= nextLrScRsv;
    end
    else begin
        // R_UOp carries two seperate valid signals. "valid" is the plain signal
        // used by ROB and SQ. This signal is only ever set for one cycle, ROB and SQ
        // do not stall.
        // "validIQ" contains an individual valid bit for each IQ, these bits may be set
        // for multiple cycles should IQs stall.
        for (integer i = 0; i < WIDTH_ISSUE; i++) begin
            OUT_uop[i].valid <= 0;

            for (integer j = 0; j < 4; j=j+1) begin
                if (!IN_stalls[j][i]) OUT_uop[i].validIQ[j] <= 0;
            end
        end
    end
    
    OUT_nextLoadSqN <= counterLoadSqN;
    OUT_nextStoreSqN <= counterStoreSqN + 1;

    
end
endmodule
