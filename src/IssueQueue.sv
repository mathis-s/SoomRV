module IssueQueue
#(
    parameter SIZE = 8,
    parameter NUM_ENQUEUE=4,
    parameter PORT_IDX=0,
    parameter NUM_OPERANDS = 2,
    parameter NUM_UOPS = 4,
    parameter RESULT_BUS_COUNT = 4,
    parameter IMM_BITS=32,
    parameter FUS=0

)
(
    input wire clk,
    input wire rst,

    input wire[NUM_UOPS-1:0] IN_defer,
    output reg[NUM_UOPS-1:0] OUT_stall,

    input wire IN_stall,
    input wire IN_doNotIssueDiv,
    input wire IN_doNotIssueFDiv,

    input R_UOp IN_uop[NUM_UOPS-1:0],
    input IntUOpOrder_t IN_uopOrdering[NUM_UOPS-1:0],

    input FlagsUOp IN_flagUOp[RESULT_BUS_COUNT-1:0],

    input BranchProv IN_branch,

    // All ops that are being issued (including OUT_uop)
    // For operand forwarding
    input IS_UOp IN_issueUOps[RESULT_BUS_COUNT-1:0],

    input SqN IN_maxStoreSqN,
    input SqN IN_maxLoadSqN,
    input SqN IN_commitSqN,

    output IS_UOp OUT_uop
);

function automatic HasFU(FuncUnit fu);
    logic rv = (FUS & (1 << fu)) != 0;
    return rv;
endfunction

localparam ID_LEN = $clog2(SIZE);
localparam IMM_EXT = ((32 - IMM_BITS) > 0) ? (32 - IMM_BITS) : 0;
localparam REGULAR_IMM_BITS = (IMM_BITS < 32) ? IMM_BITS : 32;

localparam IDIV_DLY=33;
localparam IMUL_DLY=9-4-2;

localparam AGU_PORT_IDX = (PORT_IDX >= NUM_ALUS) ? (PORT_IDX - NUM_ALUS) : PORT_IDX;

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
                if (IN_flagUOp[j].valid && !IN_flagUOp[j].tagDst[$bits(Tag)-1] && queue[i].tags[k] == IN_flagUOp[j].tagDst)
                    newAvail[i][k] = 1;
        end

        for (integer j = 0; j < NUM_ALUS; j=j+1) begin
            if (IN_issueUOps[j].valid && !IN_issueUOps[j].tagDst[$bits(Tag)-1]) begin
                if (IN_issueUOps[j].fu == FU_INT || IN_issueUOps[j].fu == FU_BRANCH || IN_issueUOps[j].fu == FU_BITMANIP
                ) begin
                    for (integer k = 0; k < NUM_OPERANDS; k=k+1)
                        if (queue[i].tags[k] == IN_issueUOps[j].tagDst) newAvail[i][k] = 1;
                end
                else if (IN_issueUOps[j].fu == FU_FPU || IN_issueUOps[j].fu == FU_FMUL) begin
                    for (integer k = 0; k < NUM_OPERANDS; k=k+1)
                        if (queue[i].tags[k] == IN_issueUOps[j].tagDst) newAvail_dl[i][k] = 1;
                end
            end
        end
    end
end

// If store data queues wish to defer any op,
// we must defer all following ones as well to
// maintain ordering.
reg defer[NUM_UOPS-1:0];
always_comb begin
    defer[0] = IN_defer[0];
    for (integer i = 1; i < NUM_UOPS; i=i+1)
        defer[i] = defer[i-1] | IN_defer[i];
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
        if (IN_uop[i].validIQ[PORT_IDX] && HasFU(IN_uop[i].fu) &&

            (!(IN_uop[i].fu == FU_AGU && IN_uop[i].opcode <  LSU_SC_W) || (IN_uop[i].loadSqN[0]  == AGU_PORT_IDX[0])) &&
            (!(IN_uop[i].fu == FU_AGU && IN_uop[i].opcode >= LSU_SC_W) || (IN_uop[i].storeSqN[0] == AGU_PORT_IDX[0])) &&
            (!(IN_uop[i].fu == FU_ATOMIC) || (IN_uop[i].storeSqN[0] == AGU_PORT_IDX[0])) &&

            (PORT_IDX >= NUM_ALUS || IN_uopOrdering[i] == IntUOpOrder_t'(PORT_IDX)) &&

            // Edge Case: INT ports do not enqueue AMOSWAP (no int uop needed)
            (PORT_IDX >= NUM_ALUS || IN_uop[i].fu != FU_ATOMIC || IN_uop[i].opcode != ATOMIC_AMOSWAP_W)
        ) begin
            // check if we have capacity to enqueue this op now
            if (!limit && qIdx != $bits(qIdx)'(SIZE) && !IN_branch.taken && !defer[i]) begin

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

reg[SIZE-1:0] deqCandidate_c;
always_comb begin
    for (integer i = 0; i < SIZE; i=i+1) begin
        deqCandidate_c[i] = (i < insertIndex) &&
            &(queue[i].avail | newAvail[i]) &&
            (!HasFU(FU_DIV)  || queue[i].fu != FU_DIV  || !IN_doNotIssueDiv) &&
            (!HasFU(FU_FDIV) || queue[i].fu != FU_FDIV || !IN_doNotIssueFDiv) &&
            !((queue[i].fu == FU_INT || queue[i].fu == FU_BRANCH || queue[i].fu == FU_BITMANIP ||
                queue[i].fu == FU_FPU || queue[i].fu == FU_FMUL) && reservedWBs[0]) &&

            // Issue CSR accesses in order
            (!HasFU(FU_CSR) ||
                queue[i].fu != FU_CSR || (i == 0 && queue[i].sqN == IN_commitSqN)) &&

            // Only issue loads that fit into load order buffer
            (!HasFU(FU_AGU) ||
                (queue[i].fu != FU_AGU && queue[i].fu != FU_ATOMIC) ||
                (queue[i].opcode >= LSU_SC_W && queue[i].opcode < ATOMIC_AMOSWAP_W) || $signed(queue[i].loadSqN - IN_maxLoadSqN) <= 0) &&

            // Only stores that fit into store queue
            (!HasFU(FU_AGU) ||
                (queue[i].fu != FU_AGU && queue[i].fu != FU_ATOMIC) ||
                (queue[i].opcode < LSU_SC_W) || $signed(queue[i].storeSqN - IN_maxStoreSqN) <= 0) &&

            // Issue SCs in order (currently we don't have a recovery mechanism for reservations)
            (!HasFU(FU_AGU) ||
                queue[i].fu != FU_AGU || queue[i].opcode != LSU_SC_W ||
                    (i == 0 && queue[i].sqN == IN_commitSqN));
    end
end

struct packed
{
    logic[$clog2(SIZE)-1:0] idx;
    logic valid;
} deq;
PriorityEncoder #(SIZE) penc(deqCandidate_c, '{deq.idx}, '{deq.valid});

always_ff@(posedge clk /*or posedge rst*/) begin

    reg[ID_LEN:0] newInsertIndex = 'x;

    // Update availability
    for (integer i = 0; i < SIZE; i=i+1) begin
        queue[i].avail <= queue[i].avail | newAvail[i] | newAvail_dl[i];
    end
    reservedWBs <= {1'b0, reservedWBs[32:1]};

    if (rst) begin
        insertIndex <= 0;
        reservedWBs <= 0;
        OUT_uop <= IS_UOp'{valid: 0, default: 'x};

        for (integer i = 0; i < SIZE; i=i+1)
            queue[i] <= R_ST_UOp'{avail: 0, default: 'x};
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
        newInsertIndex = insertIndex;

        // Issue
        if (!IN_stall) begin
            OUT_uop <= 'x;
            OUT_uop.valid <= 0;

            if (deq.valid) begin

                R_ST_UOp deqEntry = queue[deq.idx];

                OUT_uop.valid <= 1;
                OUT_uop.imm <= {{(IMM_EXT){deqEntry.imm[REGULAR_IMM_BITS-1]}}, deqEntry.imm[REGULAR_IMM_BITS-1:0]};
                OUT_uop.tagA <= deqEntry.tags[0];

                if (NUM_OPERANDS >= 2) begin
                    // verilator lint_off SELRANGE
                    OUT_uop.tagB <= deqEntry.tags[1];
                    // verilator lint_on SELRANGE
                end
                else
                    OUT_uop.tagB <= TAG_ZERO;

                OUT_uop.immB <= deqEntry.immB;
                OUT_uop.sqN <= deqEntry.sqN;
                OUT_uop.tagDst <= deqEntry.tagDst;
                OUT_uop.opcode <= deqEntry.opcode;
                OUT_uop.fetchID <= deqEntry.fetchID;
                OUT_uop.fetchOffs <= deqEntry.fetchOffs;
                OUT_uop.storeSqN <= deqEntry.storeSqN;
                OUT_uop.loadSqN <= deqEntry.loadSqN;
                OUT_uop.fu <= deqEntry.fu;
                OUT_uop.compressed <= deqEntry.compressed;

                if (IMM_BITS == 36 && HasFU(FU_BRANCH)) begin
                    // verilator lint_off SELRANGE
                    OUT_uop.imm12 <= {deqEntry.imm[IMM_BITS-1-:4], deqEntry.imm[0], deqEntry.tags[1][6:0]};
                    // verilator lint_on SELRANGE
                end
                else OUT_uop.imm12 <= 'x;


                // Reserve WB if this is a slow operation
                case (deqEntry.fu)
                    FU_DIV: reservedWBs <= {1'b0, reservedWBs[32:1]} | (1 << (IDIV_DLY - 1));
                    FU_MUL: reservedWBs <= {1'b0, reservedWBs[32:1]} | (1 << (IMUL_DLY - 1));
                    default: ;
                endcase

                newInsertIndex = newInsertIndex - 1;

                // Shift other ops forward
                for (integer i = 0; i < SIZE-1; i=i+1) begin
                    if (i >= deq.idx) begin
                        queue[i] <= queue[i+1];
                        queue[i].avail <= queue[i+1].avail | newAvail[i+1] | newAvail_dl[i+1];
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

                if (temp.fu == FU_ATOMIC) begin
                    // No changes for LD uop
                    // INT port uses value loaded by LD uop as operand
                    if (PORT_IDX < NUM_ALUS) begin
                        assert(HasFU(FU_INT));
                        temp.fu = FU_INT;
                        temp.avail[0] = enqCandidates[i].availC;
                        temp.tags[0] = enqCandidates[i].tagC;
                        temp.tagDst = TAG_ZERO;
                    end
                end


                // Check if the result for this op is being broadcast in the current cycle
                for (integer j = 0; j < RESULT_BUS_COUNT; j=j+1) begin
                    if (IN_flagUOp[j].valid && !IN_flagUOp[j].tagDst[$bits(Tag)-1]) begin
                        for (integer k = 0; k < NUM_OPERANDS; k=k+1)
                            if (temp.tags[k] == IN_flagUOp[j].tagDst) temp.avail[k] = 1;
                    end
                end

                // Special handling for jalr
                if (HasFU(FU_BRANCH) && enqCandidates[i].fu == FU_BRANCH &&
                    (enqCandidates[i].opcode == BR_V_JALR || enqCandidates[i].opcode == BR_V_JR ||
                     enqCandidates[i].opcode == BR_V_RET)
                ) begin
                    assert(IMM_BITS == 36);
                    assert(NUM_OPERANDS == 2);

                    // Use {imm[0], tags[1]} to encode 8 bits of imm12
                    temp.tags[NUM_OPERANDS-1] = Tag'(enqCandidates[i].imm12[6:0]);
                    temp.imm[0] = enqCandidates[i].imm12[7];

                    // rest goes into upper 4 bits of 36 (!) immediate bits
                    temp.imm[IMM_BITS-1-:4] = enqCandidates[i].imm12[11:8];

                    // tags[1] is not used for register encoding, thus is always valid
                    temp.avail[NUM_OPERANDS-1] = 1;
                end
                // verilator lint_on SELRANGE

                queue[newInsertIndex[ID_LEN-1:0]] <= temp;
                newInsertIndex = newInsertIndex + 1;
            end
        end
        insertIndex <= newInsertIndex;
    end
end

`ifdef DEBUG
always_ff@(posedge clk) begin
    for (integer i = 1; i < SIZE; i=i+1) begin
        if (i[$clog2(SIZE):0] < insertIndex) begin
            assert($signed(queue[i].sqN - queue[i-1].sqN) > 0);
        end
    end
end
`endif

endmodule
