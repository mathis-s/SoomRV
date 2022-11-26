module Rename
#(
    parameter WIDTH_UOPS = 4,
    parameter WIDTH_WR = 4
)
(
    input wire clk,
    input wire en,
    input wire frontEn,
    input wire rst,
    
    output reg OUT_stall,

    // Tag lookup for just decoded instrs
    input D_UOp IN_uop[WIDTH_UOPS-1:0],

    // Committed changes from ROB
    input CommitUOp IN_comUOp[WIDTH_UOPS-1:0],

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
    
    output reg OUT_uopValid[WIDTH_UOPS-1:0],
    output R_UOp OUT_uop[WIDTH_UOPS-1:0],
    // This is just an alternating bit that switches with each regular int op,
    // for assignment to issue queues.
    output reg OUT_uopOrdering[WIDTH_UOPS-1:0],
    output SqN OUT_nextSqN,
    output SqN OUT_nextLoadSqN,
    output SqN OUT_nextStoreSqN
);

integer i;
integer j;

wire RAT_lookupAvail[2*WIDTH_UOPS-1:0];
wire[6:0] RAT_lookupSpecTag[2*WIDTH_UOPS-1:0];
reg[4:0] RAT_lookupIDs[2*WIDTH_UOPS-1:0];

reg[4:0] RAT_issueIDs[WIDTH_UOPS-1:0];
reg RAT_issueValid[WIDTH_UOPS-1:0];
reg RAT_issueAvail[WIDTH_UOPS-1:0];
SqN RAT_issueSqNs[WIDTH_UOPS-1:0];

reg commitValid[WIDTH_UOPS-1:0];
reg commitValid_int[WIDTH_UOPS-1:0];
//reg commitValid_fp[WIDTH_UOPS-1:0];

reg[4:0] RAT_commitIDs[WIDTH_UOPS-1:0];
reg[6:0] RAT_commitTags[WIDTH_UOPS-1:0];
wire[6:0] RAT_commitPrevTags[WIDTH_UOPS-1:0];
reg RAT_commitAvail[WIDTH_UOPS-1:0];

reg[4:0] RAT_wbIDs[WIDTH_UOPS-1:0];
reg[6:0] RAT_wbTags[WIDTH_UOPS-1:0];

reg TB_issueValid[WIDTH_UOPS-1:0];
//reg TB_issueValid_fp[WIDTH_UOPS-1:0];

SqN nextCounterSqN;
always_comb begin
    
    nextCounterSqN = counterSqN;
    
    for (i = 0; i < WIDTH_UOPS; i=i+1) begin
        RAT_lookupIDs[2*i+0] = IN_uop[i].rs0;
        RAT_lookupIDs[2*i+1] = IN_uop[i].rs1;
    end
    for (i = 0; i < WIDTH_UOPS; i=i+1) begin
        // Issue/Lookup
        RAT_issueIDs[i] = IN_uop[i].rd;//{IN_uop[i].rd_fp, IN_uop[i].rd};
        RAT_issueSqNs[i] = nextCounterSqN;
        RAT_issueValid[i] = !rst && !IN_branchTaken && en && frontEn && !OUT_stall && IN_uop[i].valid;
        RAT_issueAvail[i] = IN_uop[i].fu == FU_RN;
        // Only need new tag if instruction writes to a register
        TB_issueValid[i] = RAT_issueValid[i] && IN_uop[i].rd != 0 && IN_uop[i].fu != FU_RN;
        //TB_issueValid_fp[i] = RAT_issueValid[i] && IN_uop[i].rd_fp;
        
        if (RAT_issueValid[i])
            nextCounterSqN = nextCounterSqN + 1;
        
        // Commit
        commitValid[i] = (IN_comUOp[i].valid && (IN_comUOp[i].nmDst != 0) && 
            (!IN_branchTaken || $signed(IN_comUOp[i].sqN - IN_branchSqN) <= 0));
        
        commitValid_int[i] = commitValid[i];// && !IN_comUOp[i].nmDst[5];
        //commitValid_fp[i] = (IN_comUOp[i].valid && IN_comUOp[i].nmDst[5] && 
        //    (!IN_branchTaken || $signed(IN_comUOp[i].sqN - IN_branchSqN) <= 0));
        
        RAT_commitIDs[i] = IN_comUOp[i].nmDst;
        RAT_commitTags[i] = IN_comUOp[i].tagDst;
        // Only using during mispredict replay
        RAT_commitAvail[i] = IN_comUOp[i].compressed;
        
        // Writeback
        RAT_wbIDs[i] = IN_wbUOp[i].nmDst;
        RAT_wbTags[i] = IN_wbUOp[i].tagDst;
    end
end

RenameTable rt
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
    
    .IN_commitValid(commitValid),
    .IN_commitIDs(RAT_commitIDs),
    .IN_commitTags(RAT_commitTags),
    .IN_commitAvail(RAT_commitAvail),
    .OUT_commitPrevTags(RAT_commitPrevTags),
    
    .IN_wbValid(IN_wbHasResult),
    .IN_wbID(RAT_wbIDs),
    .IN_wbTag(RAT_wbTags)
);

reg[5:0] TB_tags[WIDTH_UOPS-1:0];
reg[6:0] newTags[WIDTH_UOPS-1:0];
//reg[5:0] TB_FP_tags[WIDTH_UOPS-1:0];
reg TB_tagsValid[WIDTH_UOPS-1:0];
//reg TB_FP_tagsValid[WIDTH_UOPS-1:0];
always_comb begin
    for (i = 0; i < WIDTH_UOPS; i=i+1) begin
        if (TB_issueValid[i])
            newTags[i] = {1'b0, TB_tags[i]};
        //else if (TB_issueValid_fp[i])
        //    newTags[i] = {1'b1, TB_FP_tags[i]};
        else if (IN_uop[i].fu == FU_RN) newTags[i] = {1'b1, IN_uop[i].imm[5:0]};
        else newTags[i] = 7'h40;
    end
end
TagBuffer tb
(
    .clk(clk),
    .rst(rst),
    .IN_mispr(IN_branchTaken),
    .IN_mispredFlush(IN_mispredFlush),
    
    .IN_issueValid(TB_issueValid),
    .OUT_issueTags(TB_tags),
    .OUT_issueTagsValid(TB_tagsValid),
    
    .IN_commitValid(commitValid_int),
    .IN_commitNewest(isNewestCommit),
    .IN_RAT_commitPrevTags(RAT_commitPrevTags),
    .IN_commitTagDst(RAT_commitTags)
);
/*TagBuffer tb_fp
(
    .clk(clk),
    .rst(rst),
    .IN_mispr(IN_branchTaken),
    .IN_mispredFlush(IN_mispredFlush),
    
    .IN_issueValid(TB_issueValid_fp),
    .OUT_issueTags(TB_FP_tags),
    .OUT_issueTagsValid(TB_FP_tagsValid),
    
    .IN_commitValid(commitValid_fp),
    .IN_commitNewest(isNewestCommit),
    .IN_RAT_commitPrevTags(TB_RAT_commitPrevTags),
    .IN_commitTagDst(TB_RAT_commitTags)
);*/

always_comb begin
    OUT_stall = 0;
    for (i = 0; i < WIDTH_UOPS; i=i+1) begin
        if ((!TB_tagsValid[i]/* || !TB_FP_tagsValid[i]*/) && IN_uop[i].valid && IN_uop[i].rd != 0 && IN_uop[i].fu != FU_RN)
            OUT_stall = 1;
    end
        
end

reg intOrder;
SqN counterSqN;
SqN counterStoreSqN;
SqN counterLoadSqN;
assign OUT_nextSqN = counterSqN;

reg isNewestCommit[WIDTH_UOPS-1:0];
always_comb begin
    for (i = 0; i < WIDTH_UOPS; i=i+1) begin
        
        isNewestCommit[i] = IN_comUOp[i].valid && IN_comUOp[i].nmDst != 0;
        if (IN_comUOp[i].valid)
            for (j = i + 1; j < WIDTH_UOPS; j=j+1)
                if (IN_comUOp[j].valid && (IN_comUOp[j].nmDst == IN_comUOp[i].nmDst))
                    isNewestCommit[i] = 0;
    end
end

always_ff@(posedge clk) begin

    if (rst) begin
        
        counterSqN <= 0;
        counterStoreSqN = -1;
        // TODO: check if load sqn is correctly handled
        counterLoadSqN = 0;
        OUT_nextLoadSqN <= counterLoadSqN;
        OUT_nextStoreSqN <= counterStoreSqN + 1;
        intOrder = 0;
    
        for (i = 0; i < WIDTH_UOPS; i=i+1) begin
            OUT_uop[i].sqN <= i[$bits(SqN)-1:0];
            OUT_uopValid[i] <= 0;
        end
    end
    else if (IN_branchTaken) begin
        
        counterSqN <= IN_branchSqN + 1;
        
        counterLoadSqN = IN_branchLoadSqN;
        counterStoreSqN = IN_branchStoreSqN;
        
        for (i = 0; i < WIDTH_UOPS; i=i+1)
            OUT_uopValid[i] <= 0;
    end

    else if (en && frontEn && !OUT_stall) begin
        // Look up tags and availability of operands for new instructions
        for (i = 0; i < WIDTH_UOPS; i=i+1) begin
            //OUT_uop[i].pc <= IN_uop[i].pc;
            OUT_uop[i].imm <= IN_uop[i].imm;
            OUT_uop[i].opcode <= IN_uop[i].opcode;
            OUT_uop[i].fu <= IN_uop[i].fu;
            OUT_uop[i].nmDst <= IN_uop[i].rd;//{IN_uop[i].rd_fp, IN_uop[i].rd};
            OUT_uop[i].fetchID <= IN_uop[i].fetchID;
            OUT_uop[i].fetchOffs <= IN_uop[i].fetchOffs;
            OUT_uop[i].immB <= IN_uop[i].immB;
            OUT_uop[i].compressed <= IN_uop[i].compressed;
        end
        
        // Set seqnum/tags for next instruction(s)
        for (i = 0; i < WIDTH_UOPS; i=i+1) begin
            if (IN_uop[i].valid) begin
                
                OUT_uopValid[i] <= 1;
                
                OUT_uop[i].loadSqN <= counterLoadSqN;
                OUT_uopOrdering[i] <= intOrder;
                
                case (IN_uop[i].fu)
                    FU_INT: intOrder = !intOrder;
                    FU_DIV, FU_FPU:  intOrder = 1;
                    FU_FDIV, FU_FMUL, FU_MUL: intOrder = 0;
                    
                    FU_ST: counterStoreSqN = counterStoreSqN + 1;
                    FU_LSU: counterLoadSqN = counterLoadSqN + 1;
                    default: begin end
                endcase
                
                OUT_uop[i].sqN <= RAT_issueSqNs[i];
                OUT_uop[i].storeSqN <= counterStoreSqN;
                // These are affected by previous instrs
                OUT_uop[i].tagA <= RAT_lookupSpecTag[2*i+0];
                OUT_uop[i].tagB <= RAT_lookupSpecTag[2*i+1];
                OUT_uop[i].availA <= RAT_lookupAvail[2*i+0];
                OUT_uop[i].availB <= RAT_lookupAvail[2*i+1];

                if (IN_uop[i].rd != 0) begin
                    OUT_uop[i].tagDst <= newTags[i];
                end
            end
            else
                OUT_uopValid[i] <= 0;
        end
        counterSqN <= nextCounterSqN;
         
    end
    else if (!en) begin
        for (i = 0; i < WIDTH_UOPS; i=i+1)
            OUT_uopValid[i] <= 0;
    end
    
    if (!rst) begin
        // If frontend is stalled right now we need to make sure 
        // the ops we're stalled on are kept up-to-date, as they will be
        // read later.
        for (i = 0; i < WIDTH_WR; i=i+1) begin
            if (en && (!frontEn || OUT_stall) && IN_wbHasResult[i]) begin
                for (j = 0; j < WIDTH_UOPS; j=j+1) begin
                    if (OUT_uopValid[j]) begin
                        if (OUT_uop[j].tagA == IN_wbUOp[i].tagDst)
                            OUT_uop[j].availA <= 1;
                        if (OUT_uop[j].tagB == IN_wbUOp[i].tagDst)
                            OUT_uop[j].availB <= 1;
                    end
                end
            end
        end
    end
    
    OUT_nextLoadSqN <= counterLoadSqN;
    OUT_nextStoreSqN <= counterStoreSqN + 1;

    
end
endmodule
