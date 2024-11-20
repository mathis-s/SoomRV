module StoreDataIQ
#(
    parameter SIZE = 8,
    parameter NUM_ENQUEUE=2,
    parameter PORT_IDX=0,
    parameter NUM_UOPS = 4,
    parameter RESULT_BUS_COUNT = 4

)
(
    input wire clk,
    input wire rst,
    output reg[NUM_UOPS-1:0] OUT_stall,

    input R_UOp IN_uop[NUM_UOPS-1:0],

    input FlagsUOp IN_flagUOp[RESULT_BUS_COUNT-1:0],

    input BranchProv IN_branch,
    input IS_UOp IN_issueUOps[RESULT_BUS_COUNT-1:0],
    input EX_UOp IN_aguUOps[NUM_AGUS-1:0],

    input SqN IN_maxStoreSqN,

    output ComLimit OUT_comLimit,

    input wire IN_ready,
    output StDataLookupUOp OUT_uop
);

localparam ID_LEN = $clog2(SIZE);
localparam NUM_OPERANDS = 1;

typedef struct packed
{
    // Track the lower 2 address bits here for
    // sb/sh. We need to know how much to shift raw
    // store data by before enqueuing in the SQ.
    StOff_t offs;

    logic[NUM_OPERANDS:0] avail;
    Tag[NUM_OPERANDS-1:0] tags;
    SqN storeSqN;
} R_ST_UOp;
R_ST_UOp queue[SIZE-1:0];

reg[$clog2(SIZE):0] insertIndex;

reg[NUM_OPERANDS:0] newAvail[SIZE-1:0];
reg[NUM_OPERANDS:0] newAvail_dl[SIZE-1:0];

StOff_t newOffs[SIZE-1:0];

always_ff@(posedge clk) begin
    OUT_comLimit <= ComLimit'{valid: 0, default: 'x};
    if (insertIndex != 0) begin
        OUT_comLimit <= ComLimit'{valid: 1, sqN: queue[0].storeSqN};
    end
end

always_comb begin
    for (integer i = 0; i < SIZE; i=i+1) begin

        for (integer k = 0; k < NUM_OPERANDS; k=k+1) begin
            newAvail[i][k] = 0;
            newAvail_dl[i][k] = 0;
        end

        for (integer j = 0; j < RESULT_BUS_COUNT; j=j+1) begin
            for (integer k = 0; k < NUM_OPERANDS; k=k+1)
                if (IN_flagUOp[j].valid && !IN_flagUOp[j].tagDst[$bits(Tag)-1] && queue[i].tags[k] == IN_flagUOp[j].tagDst)
                    newAvail_dl[i][k] = 1;
        end
    end

    // Snoop issued store uops to get lower two address bits for sh/sb.
    for (integer i = 0; i < SIZE; i=i+1) begin
        newOffs[i] = queue[i].offs;
        newAvail[i][1] = 0;
        newAvail_dl[i][1] = 0;

        for (integer j = 0; j < NUM_AGUS; j=j+1) begin
            if (IN_aguUOps[j].valid && IN_aguUOps[j].fu == FU_AGU &&
                (IN_aguUOps[j].opcode == LSU_SB || IN_aguUOps[j].opcode == LSU_SH)
            ) begin
                if (queue[i].storeSqN == IN_aguUOps[j].storeSqN) begin
                    newAvail_dl[i][1] = 1;
                    newOffs[i] = StOff_t'(IN_aguUOps[j].srcA + IN_aguUOps[j].srcB);
                end
            end
        end
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
        if (IN_uop[i].validIQ[NUM_PORTS+PORT_IDX] && //(IN_uop[i].storeSqN[0] == PORT_IDX[0]) &&
            ((IN_uop[i].fu == FU_AGU && IN_uop[i].opcode >= LSU_SC_W) ||
             (IN_uop[i].fu == FU_ATOMIC && IN_uop[i].opcode == ATOMIC_AMOSWAP_W)
            )
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

reg[SIZE-1:0] deqCandidate_c;
always_comb begin
    for (integer i = 0; i < SIZE; i=i+1) begin
        deqCandidate_c[i] = (i < insertIndex) && &(queue[i].avail | newAvail[i]) &&
            $signed(queue[i].storeSqN - IN_maxStoreSqN) <= 0;
    end
end

struct packed
{
    logic[$clog2(SIZE)-1:0] idx;
    logic valid;
} deq;
PriorityEncoder #(SIZE) penc(deqCandidate_c, '{deq.idx}, '{deq.valid});

always_ff@(posedge clk or posedge rst) begin

    reg[ID_LEN:0] newInsertIndex = 'x;

    // Update availability
    for (integer i = 0; i < SIZE; i=i+1) begin
        queue[i].avail <= queue[i].avail | newAvail[i] | newAvail_dl[i];
        queue[i].offs <= newOffs[i];
    end

    if (rst) begin
        insertIndex <= 0;
        OUT_uop <= StDataLookupUOp'{valid: 0, default: 'x};

        for (integer i = 0; i < SIZE; i=i+1) begin
            queue[i] <= R_ST_UOp'{avail: 0, offs: 0, default: 'x};
        end
    end
    else if (IN_branch.taken) begin

        newInsertIndex = 0;
        // Set insert index to first invalid entry
        for (integer i = 0; i < SIZE; i=i+1) begin
            if (i < insertIndex && ($signed(queue[i].storeSqN - IN_branch.storeSqN) <= 0) && !IN_branch.flush) begin
                newInsertIndex = i[$clog2(SIZE):0] + 1;
            end
        end
        insertIndex <= newInsertIndex;


        if (IN_ready || $signed(OUT_uop.storeSqN - IN_branch.storeSqN) > 0 || IN_branch.flush) begin
            OUT_uop <= StDataLookupUOp'{valid: 0, default: 'x};
        end
    end
    else begin
        newInsertIndex = insertIndex;

        // Issue
        if (IN_ready || !OUT_uop.valid) begin
            OUT_uop <= StDataLookupUOp'{valid: 0, default: 'x};

            if (deq.valid) begin
                R_ST_UOp deqEntry = queue[deq.idx];

                OUT_uop.valid <= 1;
                OUT_uop.tag <= deqEntry.tags[0];
                OUT_uop.storeSqN <= deqEntry.storeSqN;
                OUT_uop.offs <= deqEntry.offs;

                newInsertIndex = newInsertIndex - 1;

                // Shift other ops forward
                for (integer i = 0; i < SIZE-1; i=i+1) begin
                    if (i >= deq.idx) begin
                        queue[i] <= queue[i+1];
                        queue[i].avail <= queue[i+1].avail | newAvail[i+1] | newAvail_dl[i+1];
                        queue[i].offs <= newOffs[i+1];
                    end
                end
            end
        end

        // Enqueue
        for (integer i = 0; i < NUM_ENQUEUE; i=i+1) begin
            if (enqCandidates[i].validIQ[NUM_PORTS+PORT_IDX]) begin
                R_ST_UOp temp;

                temp.avail[0] = enqCandidates[i].availB;
                temp.tags[0] = enqCandidates[i].tagB;
                temp.storeSqN = enqCandidates[i].storeSqN;
                temp.avail[1] = !(
                    enqCandidates[i].opcode == LSU_SB ||
                    enqCandidates[i].opcode == LSU_SH);
                temp.offs = temp.avail[1] ? '0 : 'x;


                // For cache management ops we encode the type of operation as store data via an immediate tag
                if (enqCandidates[i].fu == FU_AGU &&
                    enqCandidates[i].opcode >= LSU_CBO_CLEAN && enqCandidates[i].opcode <= LSU_CBO_FLUSH) begin
                    temp.avail[0] = 1;
                    temp.tags[0] = TAG_ZERO + Tag'(enqCandidates[i].opcode) - Tag'(LSU_CBO_CLEAN);
                end


                // Check if the result for this op is being broadcast in the current cycle
                for (integer j = 0; j < RESULT_BUS_COUNT; j=j+1) begin
                    if (IN_flagUOp[j].valid && !IN_flagUOp[j].tagDst[$bits(Tag)-1]) begin
                        for (integer k = 0; k < NUM_OPERANDS; k=k+1)
                            if (temp.tags[k] == IN_flagUOp[j].tagDst) temp.avail[k] = 1;
                    end
                end

                queue[newInsertIndex[ID_LEN-1:0]] <= temp;
                newInsertIndex = newInsertIndex + 1;
            end
        end
        insertIndex <= newInsertIndex;
    end
end

endmodule
