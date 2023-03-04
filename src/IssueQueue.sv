module IssueQueue
#(
    parameter SIZE = 8,
    parameter NUM_UOPS = 4,
    parameter RESULT_BUS_COUNT = 4,
    parameter IMM_BITS=32,
    parameter FU0 = FU_ST,
    parameter FU1 = FU_ST,
    parameter FU2 = FU_ST,
    parameter FU3 = FU_ST,
    parameter FU0_SPLIT=0,
    parameter FU0_ORDER=0,
    parameter FU1_DLY=0
    
)
(
    input wire clk,
    input wire rst,
    input wire frontEn,
    
    input wire IN_stall,
    input wire IN_doNotIssueFU1,
    input wire IN_doNotIssueFU2,
    
    input wire IN_uopValid[NUM_UOPS-1:0],
    input R_UOp IN_uop[NUM_UOPS-1:0],
    input wire IN_uopOrdering[NUM_UOPS-1:0],
    
    input wire IN_resultValid[RESULT_BUS_COUNT-1:0],
    input RES_UOp IN_resultUOp[RESULT_BUS_COUNT-1:0],
    
    input wire IN_loadForwardValid,
    input Tag IN_loadForwardTag,
    
    input BranchProv IN_branch,
    
    // All ops that are being issued (including OUT_uop)
    // For operand forwarding
    input wire IN_issueValid[NUM_UOPS-1:0],
    input R_UOp IN_issueUOps[NUM_UOPS-1:0],
    
    input SqN IN_maxStoreSqN,
    input SqN IN_maxLoadSqN,
    
    output reg OUT_valid,
    output R_UOp OUT_uop,
    
    output reg OUT_full
);

localparam ID_LEN = $clog2(SIZE);

integer i;
integer j;

typedef struct packed
{
    logic[IMM_BITS-1:0] imm;
    logic availA;
    Tag tagA;
    logic availB;
    Tag tagB;
    logic immB;
    SqN sqN;
    Tag tagDst;
    RegNm nmDst;
    logic[5:0] opcode;
    FetchID_t fetchID;
    FetchOff_t fetchOffs;
    SqN storeSqN;
    SqN loadSqN;
    FuncUnit fu;
    logic compressed;
} R_ST_UOp;

R_ST_UOp queue[SIZE-1:0];
reg valid[SIZE-1:0];

reg[$clog2(SIZE):0] insertIndex;
reg[32:0] reservedWBs;

//assign OUT_full = insertIndex > (SIZE-NUM_UOPS);

reg newAvailA[SIZE-1:0];
reg newAvailB[SIZE-1:0];

reg newAvailA_dl[SIZE-1:0];
reg newAvailB_dl[SIZE-1:0];

always_comb begin
    for (i = 0; i < SIZE; i=i+1) begin
        
        newAvailA[i] = 0;
        newAvailB[i] = 0;
        newAvailA_dl[i] = 0;
        newAvailB_dl[i] = 0;
        
        for (j = 0; j < RESULT_BUS_COUNT; j=j+1) begin
            if (IN_resultValid[j] && queue[i].tagA == IN_resultUOp[j].tagDst) newAvailA[i] = 1;
            if (IN_resultValid[j] && queue[i].tagB == IN_resultUOp[j].tagDst) newAvailB[i] = 1;
        end
        
        for (j = 0; j < 2; j=j+1) begin
            if (IN_issueValid[j] && IN_issueUOps[j].nmDst != 0) begin
                if (IN_issueUOps[j].fu == FU_INT) begin
                    if (queue[i].tagA == IN_issueUOps[j].tagDst) newAvailA[i] = 1;
                    if (queue[i].tagB == IN_issueUOps[j].tagDst) newAvailB[i] = 1;
                end
                else if (IN_issueUOps[j].fu == FU_FPU || IN_issueUOps[j].fu == FU_FMUL) begin
                    if (queue[i].tagA == IN_issueUOps[j].tagDst) newAvailA_dl[i] = 1;
                    if (queue[i].tagB == IN_issueUOps[j].tagDst) newAvailB_dl[i] = 1;
                end
            end
        end
        
        if (IN_loadForwardValid && queue[i].tagA == IN_loadForwardTag) newAvailA[i] = 1;
        if (IN_loadForwardValid && queue[i].tagB == IN_loadForwardTag) newAvailB[i] = 1;
    end
end

always_comb begin
    reg[$clog2(SIZE):0] count = 0;
    for (i = 0; i < NUM_UOPS; i=i+1) begin
        if (IN_uopValid[i] && 
            ((IN_uop[i].fu == FU0 && (!FU0_SPLIT || IN_uopOrdering[i] == FU0_ORDER)) || 
                IN_uop[i].fu == FU1 || IN_uop[i].fu == FU2 || IN_uop[i].fu == FU3)) begin
            count = count + 1;
        end
    end
    OUT_full = insertIndex > (SIZE[$clog2(SIZE):0] - count);
end

always_ff@(posedge clk) begin
    
    // Update availability
    for (i = 0; i < SIZE; i=i+1) begin
        queue[i].availA <= queue[i].availA | newAvailA[i] | newAvailA_dl[i];
        queue[i].availB <= queue[i].availB | newAvailB[i] | newAvailB_dl[i];
    end
    reservedWBs <= {1'b0, reservedWBs[32:1]};
    
    if (rst) begin
        insertIndex = 0;
        reservedWBs <= 0;
        OUT_valid <= 0;
    end
    else if (IN_branch.taken) begin
        
        reg[ID_LEN:0] newInsertIndex = 0;
        // Set insert index to first invalid entry
        for (i = 0; i < SIZE; i=i+1) begin
            if (i < insertIndex && $signed(queue[i].sqN - IN_branch.sqN) <= 0) begin
                newInsertIndex = i[$clog2(SIZE):0] + 1;
            end
        end
        insertIndex = newInsertIndex;
        if (!IN_stall || $signed(OUT_uop.sqN - IN_branch.sqN) > 0)
            OUT_valid <= 0;
    end
    else begin
        reg issued = 0;
        
        // Issue
        if (!IN_stall) begin
            OUT_valid <= 0;
            
            for (i = 0; i < SIZE; i=i+1) begin
                if (i < insertIndex && !issued) begin
                    if ((queue[i].availA || newAvailA[i]) && (queue[i].availB || newAvailB[i]) && 
                        (queue[i].fu != FU1 || !IN_doNotIssueFU1) && 
                        (queue[i].fu != FU2 || !IN_doNotIssueFU2) && 
                        !((queue[i].fu == FU_INT || queue[i].fu == FU_FPU || queue[i].fu == FU_FMUL) && reservedWBs[0]) && 
                        
                        // Only issue stores that fit into store queue
                        ((FU0 != FU_ST && FU1 != FU_ST && FU2 != FU_ST && FU3 != FU_ST) || 
                            queue[i].fu != FU_ST || $signed(queue[i].storeSqN - IN_maxStoreSqN) <= 0) &&
                        
                        // Only issue loads that fit into load order buffer
                        ((FU0 != FU_LD && FU1 != FU_LD && FU2 != FU_LD && FU3 != FU_LD) || 
                            queue[i].fu != FU_LD || $signed(queue[i].loadSqN - IN_maxLoadSqN) <= 0)) begin
                        
                        issued = 1;
                        OUT_valid <= 1;
                        //OUT_uop <= queue[i];
                        
                        OUT_uop.imm <= {{(32 - IMM_BITS){1'b0}}, queue[i].imm};
                        OUT_uop.availA <= queue[i].availA;
                        OUT_uop.tagA <= queue[i].tagA;
                        OUT_uop.availB <= queue[i].availB;
                        OUT_uop.tagB <= queue[i].tagB;
                        OUT_uop.immB <= queue[i].immB;
                        OUT_uop.sqN <= queue[i].sqN;
                        OUT_uop.tagDst <= queue[i].tagDst;
                        OUT_uop.nmDst <= queue[i].nmDst;
                        OUT_uop.opcode <= queue[i].opcode;
                        OUT_uop.fetchID <= queue[i].fetchID;
                        OUT_uop.fetchOffs <= queue[i].fetchOffs;
                        OUT_uop.storeSqN <= queue[i].storeSqN;
                        OUT_uop.loadSqN <= queue[i].loadSqN;
                        OUT_uop.fu <= queue[i].fu;
                        OUT_uop.compressed <= queue[i].compressed;
                        
                        // Shift other ops forward
                        for (j = i; j < SIZE-1; j=j+1) begin
                            queue[j] <= queue[j+1];
                            queue[j].availA <= queue[j+1].availA | newAvailA[j+1] | newAvailA_dl[j+1];
                            queue[j].availB <= queue[j+1].availB | newAvailB[j+1] | newAvailB_dl[j+1];
                        end
                        insertIndex = insertIndex - 1;
                        
                        // Reserve WB if this is a slow operation
                        if (queue[i].fu == FU1 && FU1_DLY > 0)
                            reservedWBs <= {1'b0, reservedWBs[32:1]} | (1 << (FU1_DLY - 1));
                    end
                end
            end
        end
        
        // Enqueue
        if (frontEn) begin
            for (i = 0; i < NUM_UOPS; i=i+1) begin
                if (IN_uopValid[i] && 
                    ((IN_uop[i].fu == FU0 && (!FU0_SPLIT || IN_uopOrdering[i] == FU0_ORDER)) || 
                        IN_uop[i].fu == FU1 || IN_uop[i].fu == FU2 || IN_uop[i].fu == FU3)) begin
                    
                    R_ST_UOp temp;// = IN_uop[i];
                    
                    temp.imm = IN_uop[i].imm[IMM_BITS-1:0];
                    temp.availA = IN_uop[i].availA;
                    temp.tagA = IN_uop[i].tagA;
                    temp.availB = IN_uop[i].availB;
                    temp.tagB = IN_uop[i].tagB;
                    temp.immB = IN_uop[i].immB;
                    temp.sqN = IN_uop[i].sqN;
                    temp.tagDst = IN_uop[i].tagDst;
                    temp.nmDst = IN_uop[i].nmDst;
                    temp.opcode = IN_uop[i].opcode;
                    temp.fetchID = IN_uop[i].fetchID;
                    temp.fetchOffs = IN_uop[i].fetchOffs;
                    temp.storeSqN = IN_uop[i].storeSqN;
                    temp.loadSqN = IN_uop[i].loadSqN;
                    temp.fu = IN_uop[i].fu;
                    temp.compressed = IN_uop[i].compressed;
                    
                    
                    // Check if the result for this op is being broadcasted in the current cycle
                    for (j = 0; j < RESULT_BUS_COUNT; j=j+1) begin
                        if (IN_resultValid[j]) begin
                            if (temp.tagA == IN_resultUOp[j].tagDst) temp.availA = 1;
                            if (temp.tagB == IN_resultUOp[j].tagDst) temp.availB = 1;
                        end
                    end
                    
                    // Special handling for multi-uop instructions
                    if (IN_uop[i].fu == FU_ATOMIC) begin
                    
                        // First uop goes into load FU
                        if (FU0 == FU_LD) begin
                            // Operand is not required
                            temp.tagB = 0;
                            temp.availB = 1;
                        end
                        
                        // Second uop goes into first int FU
                        /*else if (FU0 == FU_INT) begin
                            // First operand is loaded value
                            temp.tagA = IN_uop[i].tagDst;
                        end*/
                        
                        // Third uop goes into store FU
                        else if (FU0 == FU_ST) begin
                            // Data operand is result of op
                            //temp.tagB = IN_uop[i].tagDst;
                            //temp.availB = 0;
                            // Result was already written by second uop
                            temp.nmDst = 0;
                        end
                    end
                    
                    queue[insertIndex[ID_LEN-1:0]] <= temp;
                    
                    insertIndex = insertIndex + 1;
                end
            end
        end
    end
end

endmodule
