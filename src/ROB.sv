module ROB
#(
    // how many entries, ie how many instructions can we
    // speculatively execute?
    parameter ID_LEN = `ROB_SIZE_EXP,
    parameter WIDTH_RN = `DEC_WIDTH,
    parameter WIDTH = `DEC_WIDTH,
    parameter WIDTH_WB = NUM_PORTS_TOTAL
)
(
    input wire clk,
    input wire rst,

    input R_UOp IN_uop[WIDTH_RN-1:0],
    input RES_UOp IN_wbUOps[WIDTH_WB-1:0],

    input wire IN_interruptPending /*verilator public*/,

    // for perf counters
    output ROB_PERFC_Info OUT_perfcInfo,

    input BranchProv IN_branch,
    input ComLimit IN_stComLimit[NUM_AGUS-1:0],
    input ComLimit IN_ldComLimit,

    output SqN OUT_maxSqN,
    output SqN OUT_curSqN,

    output SqN OUT_lastLoadSqN,
    output SqN OUT_lastStoreSqN,

    output CommitUOp OUT_comUOp[WIDTH-1:0],
    output reg[4:0] OUT_fpNewFlags,
    output FetchID_t OUT_curFetchID,

    output Trap_UOp OUT_trapUOp,
    output BPUpdate OUT_bpUpdate,

    output reg OUT_mispredFlush
);

typedef struct packed
{
    Tag tag;
    RegNm rd; // also used to differentiate between decode-time exceptions (these have no dst anyways)
    FetchOff_t fetchOffs;
    FetchID_t fetchID;
    logic isFP;
    logic compressed;

    logic isLd;
    logic isSt;
} ROBEntry;

localparam LENGTH = 1 << ID_LEN;

function automatic SqN GetSqN(logic[ID_LEN-1:0] idx);
    logic[0:0] hiBits = baseIndex[ID_LEN+:1];
    SqN rv = {idx >= baseIndex[0+:ID_LEN] ? hiBits : hiBits + 1'b1, idx};
    return rv;
endfunction

R_UOp rnUOpSorted[WIDTH_RN-1:0];
always_comb begin
    for (integer i = 0; i < WIDTH_RN; i=i+1) begin
        rnUOpSorted[i] = 'x;
        rnUOpSorted[i].valid = 0;

        for (integer j = 0; j < WIDTH_RN; j=j+1) begin
            // This could be one-hot...
            if (IN_uop[j].valid && IN_uop[j].sqN[$clog2(WIDTH_RN)-1:0] == i[$clog2(WIDTH_RN)-1:0]) begin
                rnUOpSorted[i] = IN_uop[j];
            end
        end
    end
end

// "entries" is written to sequentially by rename
// "flags" is written to out-of-order as ops execute
generate
for (genvar i = 0; i < `DEC_WIDTH; i=i+1) begin : gen
    (* ram_style = "distributed" *)
    ROBEntry entries[LENGTH/`DEC_WIDTH-1:0];
end
endgenerate

Flags flags[LENGTH-1:0];
SqN baseIndex;
SqN lastIndex;

assign OUT_maxSqN = baseIndex + LENGTH - 1;
assign OUT_curSqN = baseIndex;

// All commits/reads from the ROB are sequential.
// This should convince synthesis of that too.
ROBEntry deqEntries[WIDTH-1:0];
Flags deqFlags[WIDTH-1:0];

reg[ID_LEN-1:0] deqAddrs[WIDTH-1:0];
reg[(ID_LEN-1-$clog2(WIDTH)):0] deqAddrsSorted[WIDTH-1:0];
ROBEntry deqPorts[WIDTH-1:0];
Flags deqFlagPorts[WIDTH-1:0];
always_comb begin
    reg[ID_LEN-1:0] deqBase = (misprReplay_c.valid) ? misprReplay_c.iterSqN[ID_LEN-1:0] : baseIndex[ID_LEN-1:0];

    // Generate the sequence of SqNs that possibly can be committed in this cycle
    for (integer i = 0; i < WIDTH; i=i+1)
        deqAddrs[i] = deqBase + i[ID_LEN-1:0];

    // So synthesis doesn't generate latches...
    for (integer i = 0; i < WIDTH; i=i+1)
        deqAddrsSorted[i] = 'x;

    // Sort the sequence by least significant bits
    for (integer i = 0; i < WIDTH; i=i+1)
        deqAddrsSorted[deqAddrs[i][1:0]] = deqAddrs[i][ID_LEN-1:$clog2(WIDTH)];
end
// With the sorted sequence we can convince synth that this is in fact a sequential access
always_comb begin
    for (integer i = 0; i < WIDTH; i=i+1)
        deqFlagPorts[i] = flags[{deqAddrsSorted[i], i[1:0]}];
end
generate
    for (genvar i = 0; i < WIDTH; i=i+1)
        always_comb deqPorts[i] = gen[i].entries[{deqAddrsSorted[i]}];
endgenerate
always_comb begin
    // Re-order the accesses into the initial order
    for (integer i = 0; i < WIDTH; i=i+1) begin
        deqEntries[i] = deqPorts[deqAddrs[i][1:0]];
        deqFlags[i] = deqFlagPorts[deqAddrs[i][1:0]];
    end
end

// Recover load/store sqNs from instruction stream
SqN storeSqN_r;
SqN loadSqN_r;

SqN storeSqNs_c[WIDTH:0];
SqN loadSqNs_c[WIDTH:0];
always_comb begin
    storeSqNs_c[0] = storeSqN_r;
    loadSqNs_c[0] = loadSqN_r;

    for (integer i = 0; i < WIDTH; i=i+1) begin
        storeSqNs_c[i+1] = storeSqNs_c[i] + SqN'(deqEntries[i].isSt ? 1 : 0);
        loadSqNs_c[i+1] = loadSqNs_c[i] + SqN'(deqEntries[i].isLd ? 1 : 0);
    end
end


typedef struct packed
{
    SqN endSqN;
    SqN iterSqN;
    logic valid;
} MisprReplay;

MisprReplay misprReplay_r;
MisprReplay misprReplay_c;

always_comb begin
    misprReplay_c = misprReplay_r;
    if (IN_branch.taken) begin
        misprReplay_c = MisprReplay'{
            endSqN: IN_branch.sqN,
            iterSqN: baseIndex,
            valid: 1
        };
    end
end

always_ff@(posedge clk) begin
    if (rst) begin
        misprReplay_r <= MisprReplay'{valid: 0, default: 'x};
    end
    else if (misprReplay_c.valid) begin
        if (misprReplayEnd)
            misprReplay_r <= MisprReplay'{valid: 0, default: 'x};
        else begin
            misprReplay_r <= misprReplay_c;
            misprReplay_r.iterSqN <= misprReplay_c.iterSqN + WIDTH;
        end
    end
end

reg[WIDTH-1:0] misprReplayFwdMask;
reg misprReplayEnd;
always_comb begin
    for (integer i = 0; i < WIDTH; i=i+1) begin
        SqN curSqN = (misprReplay_c.iterSqN + SqN'(i));
        misprReplayFwdMask[i] = $signed(curSqN - misprReplay_c.endSqN) <= 0;

        if (i == WIDTH-1)
            misprReplayEnd = !misprReplayFwdMask[i] || $signed(curSqN - misprReplay_c.endSqN) == 0;
    end
end

always_ff@(posedge clk)
    OUT_mispredFlush <= rst ? 0 : (misprReplay_c.valid && (|misprReplayFwdMask));

reg stop;

reg didCommit;
always_ff@(posedge clk) begin

    OUT_fpNewFlags <= 0;

    OUT_perfcInfo.validRetire <= 0;
    OUT_perfcInfo.branchRetire <= 0;
    // by default (if nothing is in the pipeline at all), blame the frontend
    OUT_perfcInfo.stallWeigth <= 3;
    OUT_perfcInfo.stallCause <= STALL_FRONTEND;

    OUT_trapUOp <= 'x;
    OUT_trapUOp.valid <= 0;

    OUT_bpUpdate <= 'x;
    OUT_bpUpdate.valid <= 0;

    didCommit <= 0;

    for (integer i = 0; i < WIDTH; i=i+1) begin
        OUT_comUOp[i] <= 'x;
        OUT_comUOp[i].valid <= 0;
    end

    if (rst) begin
        baseIndex <= 0;
        OUT_curFetchID <= -1;
        stop <= 0;
        lastIndex <= 0;
        OUT_lastLoadSqN <= 0;
        OUT_lastStoreSqN <= 0;
        loadSqN_r <= 0;
        storeSqN_r <= -1;
    end
    else begin
        stop <= 0;

        if (IN_branch.taken) begin
            if (IN_branch.flush)
                OUT_curFetchID <= IN_branch.fetchID;
            lastIndex <= IN_branch.sqN + 1;
        end

        // After mispredict, we replay all ops from last committed to the branch
        // without actually committing them to roll back the Rename Map.
        if (misprReplay_c.valid) begin
            for (integer i = 0; i < WIDTH; i=i+1) begin
                if (misprReplayFwdMask[i]) begin
                    OUT_comUOp[i].valid <= 1;
                    OUT_comUOp[i].sqN <= 'x;
                    OUT_comUOp[i].rd <= (deqFlags[i] == FLAGS_TRAP) ? 5'b0 : deqEntries[i].rd;
                    OUT_comUOp[i].tagDst <= deqEntries[i].tag;
                    OUT_comUOp[i].compressed <= 'x;
                end
            end
        end

        else if (!stop) begin

            reg temp = 0;
            reg temp2 = 0;
            reg pred = 0;
            reg[ID_LEN-1:0] cnt = 0;

            OUT_perfcInfo.stallCause <= STALL_NONE;

            for (integer i = 0; i < WIDTH; i=i+1) begin

                reg[ID_LEN-1:0] id = baseIndex[ID_LEN-1:0] + i[ID_LEN-1:0];
                SqN loadSqN = loadSqNs_c[i];
                SqN storeSqN = storeSqNs_c[i+1]; // +1 for pre-increment

                reg timeoutCommit = (i == 0) && hangDetected;

                reg isRenamed = (i[$clog2(LENGTH):0] < $signed(lastIndex - baseIndex));
                reg isExecuted = deqFlags[i] != FLAGS_NX;
                reg noFlagConflict = (!pred || (deqFlags[i] == FLAGS_NONE));
                reg lbAllowsCommit = (!IN_ldComLimit.valid || $signed(loadSqN - IN_ldComLimit.sqN) < 0);
                reg sqAllowsCommit = 1;
                for (integer j = 0; j < NUM_AGUS-1; j=j+1)
                    sqAllowsCommit &= (!IN_stComLimit[j].valid ||
                        $signed(storeSqN - IN_stComLimit[j].sqN) < 0);

                if (!temp && isRenamed &&
                    ((isExecuted && noFlagConflict && sqAllowsCommit && lbAllowsCommit) || timeoutCommit)
                ) begin

                    reg isBranch = deqFlags[i] == FLAGS_BRANCH ||
                        deqFlags[i] == FLAGS_PRED_TAKEN || deqFlags[i] == FLAGS_PRED_NTAKEN;
                    // Synchronous exceptions do not increment minstret, but mret/sret do.
                    reg minstretRetire = (deqFlags[i] <= FLAGS_ORDERING) ||
                        (deqFlags[i] == FLAGS_XRET) ||
                        (deqEntries[i].isFP && deqFlags[i] != FLAGS_ILLEGAL_INSTR) ||
                        (deqFlags[i] == FLAGS_TRAP && deqEntries[i].rd == RegNm'(TRAP_V_SFENCE_VMA));

                    reg isException = timeoutCommit ||
                        (deqFlags[i] >= FLAGS_ILLEGAL_INSTR && deqFlags[i] <= FLAGS_ST_PF);

                    reg sendTrapUOp = timeoutCommit ||
                        (deqFlags[i] >= FLAGS_FENCE && (!deqEntries[i].isFP || deqFlags[i] == FLAGS_ILLEGAL_INSTR));

                    SqN sqN = GetSqN(id);

                    OUT_comUOp[i].rd <= deqEntries[i].rd;
                    OUT_comUOp[i].tagDst <= deqEntries[i].tag;
                    OUT_comUOp[i].sqN <= sqN;
                    OUT_comUOp[i].isBranch <= isBranch;
                    OUT_comUOp[i].compressed <= deqEntries[i].compressed;
                    OUT_comUOp[i].valid <= 1;

                    OUT_perfcInfo.validRetire[i] <= minstretRetire && !timeoutCommit;
                    OUT_perfcInfo.branchRetire[i] <= minstretRetire && isBranch && !timeoutCommit;

                    OUT_curFetchID <= deqEntries[i].fetchID;

                    if (!isException) begin
                        if (deqEntries[i].isLd) OUT_lastLoadSqN <= loadSqN + 1;
                        if (deqEntries[i].isSt) OUT_lastStoreSqN <= storeSqN + 1;
                        storeSqN_r <= storeSqN;
                        loadSqN_r <= loadSqNs_c[i+1];
                    end


                    if (deqFlags[i] == FLAGS_PRED_TAKEN || deqFlags[i] == FLAGS_PRED_NTAKEN) begin
                        OUT_bpUpdate.valid <= 1;
                        OUT_bpUpdate.branchTaken <= (deqFlags[i] == FLAGS_PRED_TAKEN);
                        OUT_bpUpdate.fetchID <= deqEntries[i].fetchID;
                        OUT_bpUpdate.fetchOffs <= deqEntries[i].fetchOffs;
                        pred = 1;
                    end

                    if (sendTrapUOp) begin
                        OUT_trapUOp.timeout <= timeoutCommit;
                        OUT_trapUOp.flags <= deqFlags[i];
                        OUT_trapUOp.tag <= deqEntries[i].tag;
                        OUT_trapUOp.sqN <= sqN;
                        OUT_trapUOp.loadSqN <= loadSqN;
                        OUT_trapUOp.storeSqN <= storeSqN;
                        OUT_trapUOp.rd <= deqEntries[i].rd;
                        OUT_trapUOp.fetchOffs <= deqEntries[i].fetchOffs;
                        OUT_trapUOp.fetchID <= deqEntries[i].fetchID;
                        OUT_trapUOp.compressed <= deqEntries[i].compressed;
                        OUT_trapUOp.valid <= 1;

                        // Redirect result of exception to x0
                        // The exception causes an invalidation to committed state,
                        // so changing these is fine (does not leave us with inconsistent RAT/TB)
                        if (isException) begin
                            OUT_comUOp[i].rd <= 0;
                            OUT_comUOp[i].tagDst <= TAG_ZERO;
                        end

                        stop <= 1;
                        temp = 1;
                    end
                    else if (deqEntries[i].isFP &&
                        (deqFlags[i] >= Flags'(FLAGS_FP_NX) && deqFlags[i] <= Flags'(FLAGS_FP_NV))
                    ) begin
                        OUT_fpNewFlags[deqFlags[i][2:0] - 3'(FLAGS_FP_NX)] <= 1;

                        // Underflow and overflow imply inexact
                        if (deqFlags[i] == Flags'(FLAGS_FP_UF) || deqFlags[i] == Flags'(FLAGS_FP_OF)) begin
                            OUT_fpNewFlags[3'(FLAGS_FP_NX)] <= 1;
                        end
                    end

                    didCommit <= 1;
                    cnt = cnt + 1;
                end
                else begin
                    // If we are unable to commit anything in this cycle, we use the TrapHandler's PCFile
                    // lookup to get the address of the instruction we're stalled on (for debugging/analysis).
                    if (i == 0 && (i[$clog2(LENGTH):0] < $signed(lastIndex - baseIndex))) begin
                        OUT_trapUOp.timeout <= 0;
                        OUT_trapUOp.fetchOffs <= deqEntries[i].fetchOffs;
                        OUT_trapUOp.fetchID <= deqEntries[i].fetchID;
                        OUT_trapUOp.compressed <= deqEntries[i].compressed;
                        OUT_trapUOp.flags <= FLAGS_NX;
                        OUT_trapUOp.valid <= 1;
                    end

                    // General stall/commit debug info
                    if (!temp2) begin
                        OUT_perfcInfo.stallWeigth <= 3 - i[1:0];

                        if (!isRenamed || temp) OUT_perfcInfo.stallCause <= STALL_FRONTEND;
                        else if (!isExecuted) begin
                            if (deqPorts[i].isSt) OUT_perfcInfo.stallCause <= STALL_STORE;
                            else if (deqPorts[i].isLd) OUT_perfcInfo.stallCause <= STALL_LOAD;
                            else OUT_perfcInfo.stallCause <= STALL_BACKEND;
                        end
                        else if (!sqAllowsCommit) OUT_perfcInfo.stallCause <= STALL_STORE;
                        else if (!lbAllowsCommit) OUT_perfcInfo.stallCause <= STALL_LOAD;
                        else if (!noFlagConflict) OUT_perfcInfo.stallCause <= STALL_ROB;
                        temp2 = 1;
                    end

                    temp = 1;
                end

            end
            baseIndex <= baseIndex + cnt;
        end

        // Enqueue ops directly from Rename
        for (integer i = 0; i < WIDTH_RN; i=i+1) begin
            if (rnUOpSorted[i].valid && (!IN_branch.taken)) begin

                reg[ID_LEN-1:0] id = {rnUOpSorted[i].sqN[ID_LEN-1:$clog2(`DEC_WIDTH)], i[$clog2(`DEC_WIDTH)-1:0]};
                reg[$clog2(LENGTH/WIDTH_RN)-1:0] id1 = {rnUOpSorted[i].sqN[ID_LEN-1:$clog2(`DEC_WIDTH)]};
                reg[$clog2(WIDTH_RN)-1:0] id0 = {i[$clog2(`DEC_WIDTH)-1:0]};

                ROBEntry entry = 'x;

                entry.tag = rnUOpSorted[i].tagDst;
                entry.rd = rnUOpSorted[i].rd;
                entry.compressed = rnUOpSorted[i].compressed;
                entry.fetchID = rnUOpSorted[i].fetchID;
                entry.isFP = rnUOpSorted[i].fu == FU_FPU || rnUOpSorted[i].fu == FU_FDIV || rnUOpSorted[i].fu == FU_FMUL;
                entry.fetchOffs = rnUOpSorted[i].fetchOffs;
                entry.isLd = (rnUOpSorted[i].fu == FU_AGU && rnUOpSorted[i].opcode <  LSU_SC_W) || rnUOpSorted[i].fu == FU_ATOMIC;
                entry.isSt = (rnUOpSorted[i].fu == FU_AGU && rnUOpSorted[i].opcode >= LSU_SC_W) || rnUOpSorted[i].fu == FU_ATOMIC;

                case (id0)
                    0: gen[0].entries[id1] <= entry;
                    1: gen[1].entries[id1] <= entry;
                    2: gen[2].entries[id1] <= entry;
                    3: gen[3].entries[id1] <= entry;
                endcase

                if (rnUOpSorted[i].fu == FU_RN)
                    flags[id] <= FLAGS_NONE;
                else if (rnUOpSorted[i].fu == FU_TRAP)
                    flags[id] <= FLAGS_TRAP;
                else
                    flags[id] <= FLAGS_NX;
            end
        end

        for (integer i = 0; i < WIDTH_RN; i=i+1)
            if (IN_uop[i].valid && !IN_branch.taken)
                lastIndex <= IN_uop[i].sqN + 1;

        // Mark committed ops as valid and set flags
        for (integer i = 0; i < WIDTH_WB; i=i+1) begin
            if (IN_wbUOps[i].valid && (!IN_branch.taken || $signed(IN_wbUOps[i].sqN - IN_branch.sqN) <= 0) && !IN_wbUOps[i].doNotCommit) begin

                reg[$clog2(LENGTH)-1:0] id = IN_wbUOps[i].sqN[ID_LEN-1:0];
                flags[id] <= IN_wbUOps[i].flags;
                assert(IN_wbUOps[i].flags != FLAGS_NX);
            end
        end
    end
end

// Core Hang Detection
logic[HANG_COUNTER_LEN-1:0] hangCounter;
logic hangDetected;
always_ff@(posedge clk) begin
    if (rst) begin
        hangCounter <= 0;
        hangDetected <= 0;
    end
    else begin
        if (didCommit) begin
            hangCounter <= 0;
            hangDetected <= 0;
        end
        else if (!hangDetected) begin
            {hangDetected, hangCounter} <= hangCounter + 1;
        end
    end
end

endmodule
