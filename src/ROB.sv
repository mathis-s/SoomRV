  
typedef struct packed 
{
    Flags flags;
    Tag tag;
    bit sqN_msb;
    RegNm name; // also used to differentiate between decode-time exceptions (these have no dst anyways)
    FetchOff_t fetchOffs;
    FetchID_t fetchID;
    bit isFP;
    bit compressed;
    bit valid;
} ROBEntry;

module ROB
#(
    // how many entries, ie how many instructions can we
    // speculatively execute?
    parameter ID_LEN = `ROB_SIZE_EXP,
    parameter WIDTH_RN = `DEC_WIDTH,
    parameter WIDTH = 4,
    parameter WIDTH_WB = 4
)
(
    input wire clk,
    input wire rst,

    input R_UOp IN_uop[WIDTH_RN-1:0],
    input wire IN_uopValid[WIDTH_RN-1:0],
    input RES_UOp IN_wbUOps[WIDTH_WB-1:0],
    
    input wire IN_interruptPending /*verilator public*/,
    
    // for perf counters
    output reg[WIDTH-1:0] OUT_PERFC_validRetire,
    output reg[WIDTH-1:0] OUT_PERFC_retireBranch,
    
    input BranchProv IN_branch,

    output SqN OUT_maxSqN,
    output SqN OUT_curSqN,

    output CommitUOp OUT_comUOp[WIDTH-1:0],
    output reg[4:0] OUT_fpNewFlags,
    output FetchID_t OUT_curFetchID,
    
    output Trap_UOp OUT_trapUOp,

    output reg OUT_mispredFlush
);


localparam LENGTH = 1 << ID_LEN;

R_UOp rnUOpSorted[WIDTH_RN-1:0];
reg rnUOpValidSorted[WIDTH_RN-1:0];
always_comb begin
    for (integer i = 0; i < WIDTH_RN; i=i+1) begin
        rnUOpValidSorted[i] = 0;
        rnUOpSorted[i] = 'x;
        
        for (integer j = 0; j < WIDTH_RN; j=j+1) begin
            // This could be one-hot...
            if (IN_uopValid[j] && IN_uop[j].sqN[$clog2(WIDTH_RN)-1:0] == i[$clog2(WIDTH_RN)-1:0]) begin
                rnUOpValidSorted[i] = 1;
                rnUOpSorted[i] = IN_uop[j];
            end
        end
    end
end

ROBEntry entries[LENGTH-1:0];
SqN baseIndex;

assign OUT_maxSqN = baseIndex + LENGTH - 1;
assign OUT_curSqN = baseIndex;

reg stop;

reg misprReplay;
reg misprReplayEnd;
SqN misprReplayIter;
SqN misprReplayEndSqN;

// All commits/reads from the ROB are sequential.
// This should convince synthesis of that too.
ROBEntry deqEntries[WIDTH-1:0];
always_comb begin
    reg[ID_LEN-1:0] deqBase = (misprReplay && !IN_branch.taken) ? misprReplayIter[ID_LEN-1:0] : baseIndex[ID_LEN-1:0];
    
    reg[ID_LEN-1:0] deqAddrs[WIDTH-1:0];
    reg[(ID_LEN-1-$clog2(WIDTH)):0] deqAddrsSorted[WIDTH-1:0];
    ROBEntry deqPorts[WIDTH-1:0];
    
    // Generate the sequence of SqNs which could be committed in this cycle
    for (integer i = 0; i < WIDTH; i=i+1)
        deqAddrs[i] = deqBase + i[ID_LEN-1:0];
    
    // So synthesis doesn't generate latches...
    for (integer i = 0; i < WIDTH; i=i+1)
        deqAddrsSorted[i] = 4'bx;
    
    // Sort the sequence by least significant bits
    for (integer i = 0; i < WIDTH; i=i+1)
        deqAddrsSorted[deqAddrs[i][1:0]] = deqAddrs[i][ID_LEN-1:$clog2(WIDTH)];
    
    // With the sorted sequence we can convince synth that this is in fact a sequential access
    for (integer i = 0; i < WIDTH; i=i+1)
        deqPorts[i] = entries[{deqAddrsSorted[i], i[1:0]}];

    // Re-order the accesses into the initial order
    for (integer i = 0; i < WIDTH; i=i+1)
        deqEntries[i] = deqPorts[deqAddrs[i][1:0]];
end

always_comb begin
    for (integer i = 0; i < WIDTH; i=i+1) 
        OUT_PERFC_retireBranch[i] = OUT_PERFC_validRetire[i] && OUT_comUOp[i].isBranch;
end

always_ff@(posedge clk) begin

    OUT_fpNewFlags <= 0;
    OUT_PERFC_validRetire <= 0;
    
    OUT_trapUOp <= 'x;
    OUT_trapUOp.valid <= 0;
    
    for (integer i = 0; i < WIDTH; i=i+1) begin
        OUT_comUOp[i] <= 'x;
        OUT_comUOp[i].valid <= 0;
    end
    
    if (rst) begin
        baseIndex <= 0;
        for (integer i = 0; i < LENGTH; i=i+1) begin
            entries[i].valid <= 0;
        end
        misprReplay <= 0;
        OUT_mispredFlush <= 0;
        OUT_curFetchID <= -1;
        stop <= 0;
    end
    else if (IN_branch.taken) begin
        for (integer i = 0; i < LENGTH; i=i+1) begin
            if ($signed(({entries[i].sqN_msb, i[ID_LEN-1:0]}) - IN_branch.sqN) > 0) begin
                entries[i].valid <= 0;
            end
        end
        if (IN_branch.flush) 
            OUT_curFetchID <= IN_branch.fetchID;
        misprReplay <= 1;
        misprReplayEndSqN <= IN_branch.sqN;
        misprReplayIter <= baseIndex;
        misprReplayEnd <= 0;
        OUT_mispredFlush <= 0;
    end
    
    if (!rst) begin
        stop <= 0;
        
        // After mispredict, we replay all ops from last committed to the branch
        // without actually committing them, to roll back the Rename Map.
        if (misprReplay && !IN_branch.taken) begin
            
            if (misprReplayEnd) begin
                misprReplay <= 0;
                OUT_mispredFlush <= 0;
            end
            else begin
                OUT_mispredFlush <= 1;
                for (integer i = 0; i < WIDTH; i=i+1) begin
                    if ($signed((misprReplayIter + i[$bits(SqN)-1:0]) - misprReplayEndSqN) <= 0) begin
                        
                        reg[$clog2(LENGTH)-1:0] id = misprReplayIter[ID_LEN-1:0]+i[ID_LEN-1:0];
                        
                        assert(deqEntries[i].valid);
                        OUT_comUOp[i].valid <= 1;
                        OUT_comUOp[i].sqN <= 'x;//{deqEntries[i].sqN_msb, id[5:0]};
                        OUT_comUOp[i].nmDst <= (deqEntries[i].flags == FLAGS_TRAP) ? 5'b0 : deqEntries[i].name;
                        OUT_comUOp[i].tagDst <= deqEntries[i].tag;
                        OUT_comUOp[i].compressed <= (deqEntries[i].flags != FLAGS_NX);
                        for (integer j = 0; j < WIDTH_WB; j=j+1)
                            if (IN_wbUOps[j].valid && IN_wbUOps[j].tagDst == deqEntries[i].tag && !IN_wbUOps[j].tagDst[$bits(Tag)-1])
                                OUT_comUOp[i].compressed <= 1;
                    end
                    else
                        misprReplayEnd <= 1;
                end
                misprReplayIter <= misprReplayIter + WIDTH;
            end
        end
        else if (!stop && !IN_branch.taken) begin
            
            reg temp = 0;
            reg pred = 0;
            reg[ID_LEN-1:0] cnt = 0;
            reg[WIDTH-1:0] deqMask = 0;
            
            for (integer i = 0; i < WIDTH; i=i+1) begin
            
                reg[ID_LEN-1:0] id = baseIndex[ID_LEN-1:0] + i[ID_LEN-1:0];
                
                if (!temp && deqEntries[i].valid && deqEntries[i].flags != FLAGS_NX && (!pred || (deqEntries[i].flags == FLAGS_NONE))) begin
                
                    OUT_comUOp[i].nmDst <= deqEntries[i].name;
                    OUT_comUOp[i].tagDst <= deqEntries[i].tag;
                    OUT_comUOp[i].sqN <= {deqEntries[i].sqN_msb, id};
                    OUT_comUOp[i].isBranch <= deqEntries[i].flags == FLAGS_BRANCH || 
                        deqEntries[i].flags == FLAGS_PRED_TAKEN || deqEntries[i].flags == FLAGS_PRED_NTAKEN;
                        
                    OUT_comUOp[i].compressed <= deqEntries[i].compressed;
                    OUT_comUOp[i].valid <= 1;
                    
                    // Synchronous exceptions do not increment minstret, but mret/sret do.
                    OUT_PERFC_validRetire[i] <= (deqEntries[i].flags <= FLAGS_ORDERING) || deqEntries[i].flags == FLAGS_XRET
                        || (deqEntries[i].isFP && deqEntries[i].flags != FLAGS_ILLEGAL_INSTR);
                    
                    OUT_curFetchID <= deqEntries[i].fetchID;
                    
                    deqMask[id[1:0]] = 1;
                                   
                    if ((deqEntries[i].flags >= FLAGS_PRED_TAKEN && (!deqEntries[i].isFP || deqEntries[i].flags == FLAGS_ILLEGAL_INSTR))) begin
                        
                        OUT_trapUOp.flags <= deqEntries[i].flags;
                        OUT_trapUOp.tag <= deqEntries[i].tag;
                        OUT_trapUOp.sqN <= {deqEntries[i].sqN_msb, id};
                        OUT_trapUOp.name <= deqEntries[i].name;
                        OUT_trapUOp.fetchOffs <= deqEntries[i].fetchOffs;
                        OUT_trapUOp.fetchID <= deqEntries[i].fetchID;
                        OUT_trapUOp.compressed <= deqEntries[i].compressed;
                        OUT_trapUOp.allowInterrupt <= 0;//IN_interruptPending;
                        OUT_trapUOp.valid <= 1;
                        
                        if (deqEntries[i].flags >= FLAGS_PRED_TAKEN)
                            pred = 1;
                        
                        if (deqEntries[i].flags >= FLAGS_FENCE) begin
                            // Redirect result of exception to x0
                            // The exception causes an invalidation to committed state,
                            // so changing these is fine (does not leave us with inconsistent RAT/TB)
                            if ((deqEntries[i].flags >= FLAGS_ILLEGAL_INSTR &&
                                deqEntries[i].flags <= FLAGS_ST_PF)) begin
                                OUT_comUOp[i].nmDst <= 0;
                                OUT_comUOp[i].tagDst <= 7'h40;
                            end
                            
                            stop <= 1;
                            temp = 1;
                        end
                    end
                    else if (deqEntries[i].isFP && deqEntries[i].flags >= Flags'(FLAGS_FP_NX) && deqEntries[i].flags <= Flags'(FLAGS_FP_NV)) begin
                        OUT_fpNewFlags[deqEntries[i].flags[2:0] - 3'(FLAGS_FP_NX)] <= 1;
                        
                        // Underflow and overflow imply inexact
                        if (deqEntries[i].flags == Flags'(FLAGS_FP_UF) || deqEntries[i].flags == Flags'(FLAGS_FP_OF)) begin
                            OUT_fpNewFlags[3'(FLAGS_FP_NX)] <= 1;
                        end
                    end
                    
                    entries[id].valid <= 0;

                    cnt = cnt + 1;
                end
                else temp = 1;
                    
            end
            
            baseIndex <= baseIndex + cnt;
        end
        
        // Enqueue ops directly from Rename
        for (integer i = 0; i < WIDTH_RN; i=i+1) begin
            if (rnUOpValidSorted[i] && (!IN_branch.taken)) begin
                
                reg[ID_LEN-1:0] id = {rnUOpSorted[i].sqN[ID_LEN-1:$clog2(`DEC_WIDTH)], i[$clog2(`DEC_WIDTH)-1:0]};
                
                entries[id].valid <= 1;
                entries[id].tag <= rnUOpSorted[i].tagDst;
                entries[id].name <= rnUOpSorted[i].nmDst;
                entries[id].sqN_msb <= rnUOpSorted[i].sqN[ID_LEN];
                entries[id].compressed <= rnUOpSorted[i].compressed;
                entries[id].fetchID <= rnUOpSorted[i].fetchID;
                entries[id].isFP <= rnUOpSorted[i].fu == FU_FPU || rnUOpSorted[i].fu == FU_FDIV || rnUOpSorted[i].fu == FU_FMUL;
                
                if (rnUOpSorted[i].fu == FU_RN)
                    entries[id].flags <= FLAGS_NONE;
                else if (rnUOpSorted[i].fu == FU_TRAP)
                    entries[id].flags <= FLAGS_TRAP;
                else
                    entries[id].flags <= FLAGS_NX;
                    
                entries[id].fetchOffs <= rnUOpSorted[i].fetchOffs;
            end
        end
        
        // Mark committed ops as valid and set flags
        for (integer i = 0; i < WIDTH_WB; i=i+1) begin
            if (IN_wbUOps[i].valid && (!IN_branch.taken || $signed(IN_wbUOps[i].sqN - IN_branch.sqN) <= 0) && !IN_wbUOps[i].doNotCommit) begin
                
                reg[$clog2(LENGTH)-1:0] id = IN_wbUOps[i].sqN[ID_LEN-1:0];
                entries[id].flags <= IN_wbUOps[i].flags;
                assert(IN_wbUOps[i].flags != FLAGS_NX);
            end
        end
        
    end
end


endmodule
