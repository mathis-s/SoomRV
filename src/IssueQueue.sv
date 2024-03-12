module IssueQueue
#(
    parameter SIZE = 8,
    parameter NUM_ENQUEUE=4,
    parameter PORT_IDX=0,
    parameter NUM_OPERANDS = 2,
    parameter NUM_UOPS = 4,
    parameter RESULT_BUS_COUNT = 4,
    parameter IMM_BITS=32,
    parameter FU0 = FU_AGU,
    parameter FU1 = FU_AGU,
    parameter FU2 = FU_AGU,
    parameter FU3 = FU_AGU,
    parameter FU0_SPLIT=0,
    parameter FU0_ORDER=0,
    parameter FU1_DLY=0
    
)
(
    input wire clk,
    input wire rst,
    output reg[NUM_UOPS-1:0] OUT_stall,
    
    input wire IN_stall,
    input wire IN_doNotIssueFU1,
    input wire IN_doNotIssueFU2,

    input R_UOp IN_uop[NUM_UOPS-1:0],
    input wire IN_uopOrdering[NUM_UOPS-1:0],
    
    input wire IN_resultValid[RESULT_BUS_COUNT-1:0],
    input RES_UOp IN_resultUOp[RESULT_BUS_COUNT-1:0],
    
    input wire IN_loadForwardValid,
    input Tag IN_loadForwardTag,
    
    input BranchProv IN_branch,
    
    // All ops that are being issued (including OUT_uop)
    // For operand forwarding
    input IS_UOp IN_issueUOps[NUM_UOPS-1:0],
    
    input SqN IN_maxStoreSqN,
    input SqN IN_maxLoadSqN,
    input SqN IN_commitSqN,
    
    output IS_UOp OUT_uop
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
            if (IN_issueUOps[j].valid && !IN_issueUOps[j].tagDst[$bits(Tag)-1]) begin
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

R_UOp enqCandidates[NUM_ENQUEUE-1:0];
always_comb begin
    logic[$clog2(NUM_ENQUEUE)-1:0] idx = 0;
    logic[$clog2(SIZE):0] qIdx = insertIndex;
    logic limit = 0;

    for (integer i = 0; i < NUM_ENQUEUE; i=i+1)
        enqCandidates[i] = R_UOp'{valid: 0, validIQ: 0, default: 'x};

    for (integer i = 0; i < NUM_UOPS; i=i+1) begin
        OUT_stall[i] = 0;
        // check if this is a candidate to enqueue
        if (IN_uop[i].validIQ[PORT_IDX] &&
            
            (!(IN_uop[i].fu == FU_AGU && IN_uop[i].opcode <  LSU_SC_W) || (IN_uop[i].loadSqN[0]  == PORT_IDX[0])) &&
            (!(IN_uop[i].fu == FU_AGU && IN_uop[i].opcode >= LSU_SC_W) || (IN_uop[i].storeSqN[0] == PORT_IDX[0])) &&
            (!(IN_uop[i].fu == FU_ATOMIC) || (IN_uop[i].storeSqN[0] == PORT_IDX[0]) || PORT_IDX == 0) &&

            ((IN_uop[i].fu == FU0 && (!FU0_SPLIT || IN_uopOrdering[i] == FU0_ORDER)) || 
                IN_uop[i].fu == FU1 || IN_uop[i].fu == FU2 || IN_uop[i].fu == FU3 || 
                    (PORT_IDX == 0 && IN_uop[i].fu == FU_ATOMIC)) &&
            // Edge Case: INT port does not enqueue AMOSWAP (no int uop needed)
            (PORT_IDX != 0 || IN_uop[i].fu != FU_ATOMIC || IN_uop[i].opcode != ATOMIC_AMOSWAP_W)
        ) begin
            // check if we have capacity to enqueue this op now
            if (!limit && qIdx != SIZE && !IN_branch.taken) begin
                
                if (NUM_ENQUEUE == NUM_UOPS)
                    enqCandidates[i] = IN_uop[i];
                else begin
                    enqCandidates[idx] = IN_uop[i];
                    {limit, idx} = idx + 1;
                end
                
                OUT_stall[i] = 0;
                qIdx = qIdx + 1;
            end
            else OUT_stall[i] = 1;
        end
    end
end

always_ff@(posedge clk) begin
    
    reg[ID_LEN:0] newInsertIndex = 'x;

    // Update availability
    for (integer i = 0; i < SIZE; i=i+1) begin
        queue[i].avail <= queue[i].avail | newAvail[i] | newAvail_dl[i];
    end
    reservedWBs <= {1'b0, reservedWBs[32:1]};

    if (rst) begin
        insertIndex <= 0;
        reservedWBs <= 0;
        OUT_uop <= 'x;
        OUT_uop.valid <= 0;
    end
    else if (IN_branch.taken) begin
        
        newInsertIndex = 0;
        // Set insert index to first invalid entry
        for (integer i = 0; i < SIZE; i=i+1) begin
            if (i < insertIndex && $signed(queue[i].sqN - IN_branch.sqN) <= 0) begin
                newInsertIndex = i[$clog2(SIZE):0] + 1;
            end
        end
        insertIndex <= newInsertIndex;
        if (!IN_stall || $signed(OUT_uop.sqN - IN_branch.sqN) > 0) begin
            OUT_uop <= 'x;
            OUT_uop.valid <= 0;
        end
    end
    else begin
        reg issued = 0;
        newInsertIndex = insertIndex;
        
        // Issue
        if (!IN_stall) begin
            OUT_uop <= 'x;
            OUT_uop.valid <= 0;
            
            for (integer i = 0; i < SIZE; i=i+1) begin
                if (i < newInsertIndex && !issued) begin
                    if (&(queue[i].avail | newAvail[i]) &&
                        (queue[i].fu != FU1 || !IN_doNotIssueFU1) && 
                        (queue[i].fu != FU2 || !IN_doNotIssueFU2) && 
                        !((queue[i].fu == FU_INT || queue[i].fu == FU_FPU || queue[i].fu == FU_FMUL) && reservedWBs[0]) && 
                        
                        // Issue CSR accesses in order
                        ((FU0 != FU_CSR && FU1 != FU_CSR && FU2 != FU_CSR && FU3 != FU_CSR) ||
                            queue[i].fu != FU_CSR || (i == 0 && queue[i].sqN == IN_commitSqN)) &&
                        
                        // Only issue loads that fit into load order buffer
                        ((FU0 != FU_AGU && FU1 != FU_AGU && FU2 != FU_AGU && FU3 != FU_AGU) || 
                            (queue[i].fu != FU_AGU && queue[i].fu != FU_ATOMIC) || 
                            (queue[i].opcode >= LSU_SC_W && queue[i].opcode < ATOMIC_AMOSWAP_W) || $signed(queue[i].loadSqN - IN_maxLoadSqN) <= 0) &&

                        // Issue SCs in order (currently we don't have a recovery mechanism for reservations)
                        ((FU0 != FU_AGU && FU1 != FU_AGU && FU2 != FU_AGU && FU3 != FU_AGU) ||
                            queue[i].fu != FU_AGU || queue[i].opcode != LSU_SC_W || 
                                (i == 0 && queue[i].sqN == IN_commitSqN))
                    ) begin
                        
                        issued = 1;
                        OUT_uop.valid <= 1;
                        
                        OUT_uop.imm <= {{(IMM_EXT){queue[i].imm[REGULAR_IMM_BITS-1]}}, queue[i].imm[REGULAR_IMM_BITS-1:0]};
                        
                        OUT_uop.tagA <= queue[i].tags[0];
                        
                        if (NUM_OPERANDS >= 2) begin
                            // verilator lint_off SELRANGE
                            OUT_uop.tagB <= queue[i].tags[1];
                            // verilator lint_on SELRANGE
                        end
                        else
                            OUT_uop.tagB <= 7'h40;
                        
                        
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
                        newInsertIndex = newInsertIndex - 1;
                        
                        // Reserve WB if this is a slow operation
                        if (queue[i].fu == FU1 && FU1_DLY > 0)
                            reservedWBs <= {1'b0, reservedWBs[32:1]} | (1 << (FU1_DLY - 1));
                    end
                end
            end
        end
        
        // Enqueue
        for (integer i = 0; i < NUM_ENQUEUE; i=i+1) begin
            if (enqCandidates[i].validIQ[PORT_IDX]) begin
                R_ST_UOp temp;
                
                temp.imm = 0;
                temp.imm[REGULAR_IMM_BITS-1:0] = enqCandidates[i].imm[REGULAR_IMM_BITS-1:0];
                
                temp.avail[0] = enqCandidates[i].availA;
                temp.tags[0] = enqCandidates[i].tagA;
                
                if (NUM_OPERANDS >= 2) begin
                    // verilator lint_off SELRANGE
                    temp.avail[1] = enqCandidates[i].availB;
                    temp.tags[1] = enqCandidates[i].tagB;
                    // verilator lint_on SELRANGE
                end
                temp.tagDst = enqCandidates[i].tagDst;
                temp.fu = enqCandidates[i].fu;
                temp.immB = enqCandidates[i].immB;
                temp.sqN = enqCandidates[i].sqN;
                temp.opcode = enqCandidates[i].opcode;
                temp.fetchID = enqCandidates[i].fetchID;
                temp.fetchOffs = enqCandidates[i].fetchOffs;
                temp.storeSqN = enqCandidates[i].storeSqN;
                temp.loadSqN = enqCandidates[i].loadSqN;
                temp.compressed = enqCandidates[i].compressed;

                // verilator lint_off SELRANGE
                // Ports 0, 2, 3 are used for atomics
                if (PORT_IDX == 0 || PORT_IDX == 2 || PORT_IDX == 3) begin
                    if (temp.fu == FU_ATOMIC) begin
                        temp.fu = FuncUnit'(FU0);
                        // No changes for LD uop
                        // INT port uses value loaded by LD uop as operand
                        if (PORT_IDX == 0) begin
                            temp.avail[0] = enqCandidates[i].availC;
                            temp.tags[0] = enqCandidates[i].tagC;
                            temp.tagDst = 7'h40;
                        end
                    end
                end
                // verilator lint_on SELRANGE
                
                
                // Check if the result for this op is being broadcasted in the current cycle
                for (integer j = 0; j < RESULT_BUS_COUNT; j=j+1) begin
                    if (IN_resultValid[j]) begin
                        for (integer k = 0; k < NUM_OPERANDS; k=k+1)
                            if (temp.tags[k] == IN_resultUOp[j].tagDst) temp.avail[k] = 1;
                    end
                end
                
                // Special handling for jalr
                // verilator lint_off SELRANGE
                if (enqCandidates[i].fu == FU_INT && (enqCandidates[i].opcode == INT_V_JALR || enqCandidates[i].opcode == INT_V_JR)) begin
                    assert(IMM_BITS == 36);
                    
                    // Use {imm[0], tags[1]} to encode 8 bits of imm12
                    temp.tags[1] = enqCandidates[i].imm12[6:0];
                    temp.imm[0] = enqCandidates[i].imm12[7];

                    // rest goes into upper 4 bits of 36 (!) immediate bits
                    temp.imm[35:32] = enqCandidates[i].imm12[11:8];

                    // tags[1] is not used for register encoding, thus is always valid
                    temp.avail[1] = 1;
                end
                // verilator lint_on SELRANGE
                
                queue[newInsertIndex[ID_LEN-1:0]] <= temp;
                newInsertIndex = newInsertIndex + 1;
            end
        end
        insertIndex <= newInsertIndex;
    end
end

endmodule
