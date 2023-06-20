module IssueQueue
#(
    parameter SIZE = 8,
    parameter NUM_OPERANDS = 2,
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
    input wire IN_issueValid[RESULT_BUS_COUNT-1:0],
    input IS_UOp IN_issueUOps[RESULT_BUS_COUNT-1:0],
    
    input SqN IN_maxStoreSqN,
    input SqN IN_maxLoadSqN,
    input SqN IN_commitSqN,
    
    output reg OUT_valid,
    output IS_UOp OUT_uop,
    
    output reg OUT_full
);

localparam ID_LEN = $clog2(SIZE);
localparam IMM_EXT = ((32 - IMM_BITS) > 0) ? (32 - IMM_BITS) : 0;
localparam REGULAR_IMM_BITS = (IMM_BITS < 32) ? IMM_BITS : 32;


typedef struct packed
{
    logic[IMM_BITS-1:0] imm;
    
    logic[NUM_OPERANDS-1:0] avail;
    Tag[NUM_OPERANDS-1:0] tags;

    logic immB;
    SqN sqN;
    Tag tagDst;
    logic[5:0] opcode;
    FetchID_t fetchID;
    FetchOff_t fetchOffs;
    SqN storeSqN;
    SqN loadSqN;
    FuncUnit fu;
    logic compressed;
} R_ST_UOp;

R_ST_UOp queue[SIZE-1:0];

reg[$clog2(SIZE):0] insertIndex;
reg[32:0] reservedWBs;

//assign OUT_full = insertIndex > (SIZE-NUM_UOPS);

reg[NUM_OPERANDS-1:0] newAvail[SIZE-1:0];
reg[NUM_OPERANDS-1:0] newAvail_dl[SIZE-1:0];


always_comb begin
    for (integer i = 0; i < SIZE; i=i+1) begin
        
        for (integer k = 0; k < NUM_OPERANDS; k=k+1) begin
            newAvail[i][k] = 0;
            newAvail_dl[i][k] = 0;
        end
        
        for (integer j = 0; j < RESULT_BUS_COUNT; j=j+1) begin
            for (integer k = 0; k < NUM_OPERANDS; k=k+1)
                if (IN_resultValid[j] && queue[i].tags[k] == IN_resultUOp[j].tagDst) newAvail[i][k] = 1;
        end
        
        for (integer j = 0; j < 2; j=j+1) begin
            if (IN_issueValid[j] && !IN_issueUOps[j].tagDst[$bits(Tag)-1]) begin
                if (IN_issueUOps[j].fu == FU_INT) begin
                    for (integer k = 0; k < NUM_OPERANDS; k=k+1)
                        if (queue[i].tags[k] == IN_issueUOps[j].tagDst) newAvail[i][k] = 1;
                end
                else if (IN_issueUOps[j].fu == FU_FPU || IN_issueUOps[j].fu == FU_FMUL) begin
                    for (integer k = 0; k < NUM_OPERANDS; k=k+1)
                        if (queue[i].tags[k] == IN_issueUOps[j].tagDst) newAvail_dl[i][k] = 1;
                end
            end
        end
        
        for (integer k = 0; k < NUM_OPERANDS; k=k+1)
            if (IN_loadForwardValid && queue[i].tags[k] == IN_loadForwardTag) newAvail[i][k] = 1;
    end
end

always_comb begin
    reg[$clog2(SIZE):0] count = 0;
    for (integer i = 0; i < NUM_UOPS; i=i+1) begin
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
    for (integer i = 0; i < SIZE; i=i+1) begin
        queue[i].avail <= queue[i].avail | newAvail[i] | newAvail_dl[i];
    end
    reservedWBs <= {1'b0, reservedWBs[32:1]};
    
    if (rst) begin
        insertIndex = 0;
        reservedWBs <= 0;
        OUT_uop <= 'x;
        OUT_valid <= 0;
    end
    else if (IN_branch.taken) begin
        
        reg[ID_LEN:0] newInsertIndex = 0;
        // Set insert index to first invalid entry
        for (integer i = 0; i < SIZE; i=i+1) begin
            if (i < insertIndex && $signed(queue[i].sqN - IN_branch.sqN) <= 0) begin
                newInsertIndex = i[$clog2(SIZE):0] + 1;
            end
        end
        insertIndex = newInsertIndex;
        if (!IN_stall || $signed(OUT_uop.sqN - IN_branch.sqN) > 0) begin
            OUT_uop <= 'x;
            OUT_valid <= 0;
        end
    end
    else begin
        reg issued = 0;
        
        // Issue
        if (!IN_stall) begin
            OUT_uop <= 'x;
            OUT_valid <= 0;
            
            for (integer i = 0; i < SIZE; i=i+1) begin
                if (i < insertIndex && !issued) begin
                    if (&(queue[i].avail | newAvail[i]) &&
                        (queue[i].fu != FU1 || !IN_doNotIssueFU1) && 
                        (queue[i].fu != FU2 || !IN_doNotIssueFU2) && 
                        !((queue[i].fu == FU_INT || queue[i].fu == FU_FPU || queue[i].fu == FU_FMUL) && reservedWBs[0]) && 
                        
                        // Issue CSR accesses in order
                        ((FU0 != FU_CSR && FU1 != FU_CSR && FU2 != FU_CSR && FU3 != FU_CSR) ||
                            queue[i].fu != FU_CSR || (i == 0 && queue[i].sqN == IN_commitSqN)) &&
                        
                        // Only issue stores that fit into store queue
                        ((FU0 != FU_ST && FU1 != FU_ST && FU2 != FU_ST && FU3 != FU_ST) || 
                            queue[i].fu != FU_ST || $signed(queue[i].storeSqN - IN_maxStoreSqN) <= 0) &&
                        
                        // Only issue loads that fit into load order buffer
                        ((FU0 != FU_LD && FU1 != FU_LD && FU2 != FU_LD && FU3 != FU_LD) || 
                            queue[i].fu != FU_LD || $signed(queue[i].loadSqN - IN_maxLoadSqN) <= 0)) begin
                        
                        issued = 1;
                        OUT_valid <= 1;
                        
                        OUT_uop.imm <= {{(IMM_EXT){1'b0}}, queue[i].imm[REGULAR_IMM_BITS-1:0]};
                        
                        OUT_uop.tagA <= queue[i].tags[0];
                        
                        if (NUM_OPERANDS >= 2) begin
                            // verilator lint_off SELRANGE
                            OUT_uop.tagB <= queue[i].tags[1];
                            // verilator lint_on SELRANGE
                        end
                        else
                            OUT_uop.tagB <= 7'h40;
                    
                        
                        if (NUM_OPERANDS >= 3) begin
                            // verilator lint_off SELRANGE
                            OUT_uop.tagC <= queue[i].tags[2];
                            // verilator lint_on SELRANGE
                        end
                        else
                            OUT_uop.tagC <= 7'h40;
                        
                        
                        OUT_uop.immB <= queue[i].immB;
                        OUT_uop.sqN <= queue[i].sqN;
                        OUT_uop.tagDst <= queue[i].tagDst;
                        OUT_uop.opcode <= queue[i].opcode;
                        OUT_uop.fetchID <= queue[i].fetchID;
                        OUT_uop.fetchOffs <= queue[i].fetchOffs;
                        OUT_uop.storeSqN <= queue[i].storeSqN;
                        OUT_uop.loadSqN <= queue[i].loadSqN;
                        OUT_uop.fu <= queue[i].fu;
                        OUT_uop.compressed <= queue[i].compressed;

                        if (IMM_BITS == 36 && FU0 == FU_INT) begin
                            // verilator lint_off SELRANGE
                            OUT_uop.imm12 <= {queue[i].imm[35:32], queue[i].imm[0], queue[i].tags[1]};
                            // verilator lint_on SELRANGE
                        end
                        else OUT_uop.imm12 <= 'x;
                        
                        // Shift other ops forward
                        for (integer j = i; j < SIZE-1; j=j+1) begin
                            queue[j] <= queue[j+1];
                            queue[j].avail <= queue[j+1].avail | newAvail[j+1] | newAvail_dl[j+1];
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
        if (frontEn && !IN_branch.taken) begin
            for (integer i = 0; i < NUM_UOPS; i=i+1) begin
                if (IN_uopValid[i] && 
                    ((IN_uop[i].fu == FU0 && (!FU0_SPLIT || IN_uopOrdering[i] == FU0_ORDER)) || 
                        IN_uop[i].fu == FU1 || IN_uop[i].fu == FU2 || IN_uop[i].fu == FU3)) begin
                    
                    R_ST_UOp temp;
                    
                    temp.imm = 0;
                    temp.imm[REGULAR_IMM_BITS-1:0] = IN_uop[i].imm[REGULAR_IMM_BITS-1:0];
                    
                    temp.avail[0] = IN_uop[i].availA;
                    temp.tags[0] = IN_uop[i].tagA;
                    
                    if (NUM_OPERANDS >= 2) begin
                        // verilator lint_off SELRANGE
                        temp.avail[1] = IN_uop[i].availB;
                        temp.tags[1] = IN_uop[i].tagB;
                        // verilator lint_on SELRANGE
                    end
                    
                    temp.immB = IN_uop[i].immB;
                    temp.sqN = IN_uop[i].sqN;
                    temp.tagDst = IN_uop[i].tagDst;
                    temp.opcode = IN_uop[i].opcode;
                    temp.fetchID = IN_uop[i].fetchID;
                    temp.fetchOffs = IN_uop[i].fetchOffs;
                    temp.storeSqN = IN_uop[i].storeSqN;
                    temp.loadSqN = IN_uop[i].loadSqN;
                    temp.fu = IN_uop[i].fu;
                    temp.compressed = IN_uop[i].compressed;
                    
                    
                    // Check if the result for this op is being broadcasted in the current cycle
                    for (integer j = 0; j < RESULT_BUS_COUNT; j=j+1) begin
                        if (IN_resultValid[j]) begin
                            for (integer k = 0; k < NUM_OPERANDS; k=k+1)
                                if (k < 2 && temp.tags[k] == IN_resultUOp[j].tagDst) temp.avail[k] = 1;
                        end
                    end
                    
                    // Special handling for multi-uop instructions
                    if (FU0 == FU_ST) begin
                        // verilator lint_off SELRANGE
                        if (IN_uop[i].fu == FU_ATOMIC) begin
                            // Second uop goes into store FU
                            // Data operand is result of op
                            temp.tags[2] = IN_uop[i].tagDst;
                            temp.avail[2] = 0;
                            // Result was already written
                            temp.tagDst = 7'h40;
                        end
                        else temp.avail[2] = 1;
                        // verilator lint_on SELRANGE
                    end
                    if (FU0 == FU_ST || FU0 == FU_LD)
                        if (temp.fu == FU_ATOMIC) begin
                            temp.fu = FuncUnit'(FU0);
                        end
                    
                    // Special handling for jalr
                    if (IN_uop[i].fu == FU_INT && (IN_uop[i].opcode == INT_V_JALR || IN_uop[i].opcode == INT_V_JR)) begin
                        assert(IMM_BITS == 36);
                        // verilator lint_off SELRANGE
                        
                        // Use {imm[0], tags[1]} to encode 8 bits of imm12
                        temp.tags[1] = IN_uop[i].imm12[6:0];
                        temp.imm[0] = IN_uop[i].imm12[7];

                        // rest goes into upper 4 bits of 36 (!) immediate bits
                        temp.imm[35:32] = IN_uop[i].imm12[11:8];

                        // tags[1] is not used for register encoding, thus is always valid
                        temp.avail[1] = 1;
                        // verilator lint_on SELRANGE
                    end

                    queue[insertIndex[ID_LEN-1:0]] <= temp;
                    insertIndex = insertIndex + 1;
                end
            end
        end
    end
end

endmodule
