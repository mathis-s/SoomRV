  
typedef struct packed 
{
    Flags flags;
    Tag tag;
    bit sqN_msb;
    RegNm name; // also used to differentiate between decode-time exceptions (these have no dst anyways)
    FetchOff_t fetchOffs;
    FetchID_t fetchID;
    bit compressed;
    bit valid;
} ROBEntry;

module ROB
#(
    // how many entries, ie how many instructions can we
    // speculatively execute?
    parameter LENGTH = 64,

    parameter WIDTH = 4,
    parameter WIDTH_WB = 4
)
(
    input wire clk,
    input wire rst,

    input R_UOp IN_uop[WIDTH-1:0],
    input wire IN_uopValid[WIDTH-1:0],
    input RES_UOp IN_wbUOps[WIDTH_WB-1:0],
    
    // for perf counters
    output reg[3:0] OUT_validRetire,
    
    input BranchProv IN_branch,

    output SqN OUT_maxSqN,
    output SqN OUT_curSqN,

    output CommitUOp OUT_comUOp[WIDTH-1:0],
    output reg[4:0] OUT_fpNewFlags,
    output FetchID_t OUT_curFetchID,
    
    output Trap_UOp OUT_trapUOp,

    output reg OUT_mispredFlush
);

integer i;
integer j;

localparam ID_LEN = $clog2(LENGTH);

R_UOp rnUOpSorted[WIDTH-1:0];
reg rnUOpValidSorted[WIDTH-1:0];
always_comb begin
    for (i = 0; i < WIDTH; i=i+1) begin
        rnUOpValidSorted[i] = 0;
        rnUOpSorted[i] = 108'bx;
        
        for (j = 0; j < WIDTH; j=j+1) begin
            // This could be one-hot...
            if (IN_uopValid[j] && IN_uop[j].sqN[1:0] == i[1:0]) begin
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


/* verilator lint_off UNOPTFLAT */
// All commits/reads from the ROB are sequential.
// This should convince synthesis of that too.
reg[3:0] deqAddresses[WIDTH-1:0];
ROBEntry deqPorts[WIDTH-1:0];
always_comb begin
    for (i = 0; i < WIDTH; i=i+1) begin
        deqPorts[i] = entries[{deqAddresses[i], i[1:0]}];
    end
end
ROBEntry deqEntries[WIDTH-1:0];
always_comb begin
    reg[5:0] addr = (misprReplay && !IN_branch.taken) ? misprReplayIter[5:0] : baseIndex[5:0];
    
    // So synthesis doesn't generate latches... (actually, 16 latches seems worth it vs. 1k std cells)
    //for (i = 0; i < WIDTH; i=i+1)
    //    deqAddresses[i] = 4'bx;
    
    for (i = 0; i < WIDTH; i=i+1) begin
    
        deqAddresses[addr[1:0]] = addr[5:2];
        deqEntries[i] = deqPorts[addr[1:0]];
        addr = addr + 6'b1;
    end
end

always_ff@(posedge clk) begin

    OUT_fpNewFlags <= 0;
    OUT_validRetire <= 0;
    
    if (rst) begin
        baseIndex <= 0;
        for (i = 0; i < LENGTH; i=i+1) begin
            entries[i].valid <= 0;
        end
        for (i = 0; i < WIDTH; i=i+1) begin
            OUT_comUOp[i].valid <= 0;
        end
        misprReplay <= 0;
        OUT_mispredFlush <= 0;
        OUT_curFetchID <= -1;
        OUT_trapUOp.valid <= 0;
        stop <= 0;
    end
    else if (IN_branch.taken) begin
        for (i = 0; i < LENGTH; i=i+1) begin
            if ($signed(({entries[i].sqN_msb, i[5:0]}) - IN_branch.sqN) > 0) begin
                entries[i].valid <= 0;
            end
        end
        misprReplay <= 1;
        misprReplayEndSqN <= IN_branch.sqN;
        misprReplayIter <= baseIndex;
        misprReplayEnd <= 0;
        OUT_mispredFlush <= 0;
    end
    
    if (!rst) begin
    
        OUT_trapUOp.valid <= 0;
        stop <= 0;
        
        // After mispredict, we replay all ops from last committed to the branch
        // without actually committing them, to roll back the Rename Map.
        if (misprReplay && !IN_branch.taken) begin
            
            if (misprReplayEnd) begin
                misprReplay <= 0;
                for (i = 0; i < WIDTH; i=i+1)
                    OUT_comUOp[i].valid <= 0;
                OUT_mispredFlush <= 0;
            end
            else begin
                OUT_mispredFlush <= 1;
                for (i = 0; i < WIDTH; i=i+1) begin
                    if ($signed((misprReplayIter + i[$bits(SqN)-1:0]) - misprReplayEndSqN) <= 0) begin
                        
                        reg[$clog2(LENGTH)-1:0] id = misprReplayIter[ID_LEN-1:0]+i[ID_LEN-1:0];
                        
                        assert(deqEntries[i].valid);
                        OUT_comUOp[i].valid <= 1;
                        //OUT_comUOp[i].sqN <= {deqEntries[i].sqN_msb, id[5:0]};
                        OUT_comUOp[i].nmDst <= (deqEntries[i].flags == FLAGS_TRAP) ? 5'b0 : deqEntries[i].name;
                        OUT_comUOp[i].tagDst <= deqEntries[i].tag;
                        OUT_comUOp[i].compressed <= (deqEntries[i].flags != FLAGS_NX);
                        for (j = 0; j < WIDTH_WB; j=j+1)
                            if (IN_wbUOps[j].valid && IN_wbUOps[j].nmDst != 0 && IN_wbUOps[j].tagDst == deqEntries[i].tag)
                                OUT_comUOp[i].compressed <= 1;
                    end
                    else begin
                        OUT_comUOp[i].valid <= 0;
                        misprReplayEnd <= 1;
                    end
                end
                misprReplayIter <= misprReplayIter + WIDTH;
            end
        end
        else if (!stop && !IN_branch.taken) begin
            
            reg temp = 0;
            reg pred = 0;
            reg[ID_LEN-1:0] cnt = 0;
            reg[WIDTH-1:0] deqMask = 0;
            
            for (i = 0; i < WIDTH; i=i+1) begin
            
                reg[$clog2(LENGTH)-1:0] id = baseIndex[ID_LEN-1:0] + i[ID_LEN-1:0];
                
                if (!temp && deqEntries[i].valid && deqEntries[i].flags != FLAGS_NX && (!pred || (deqEntries[i].flags == FLAGS_NONE))) begin
                
                    OUT_comUOp[i].nmDst <= deqEntries[i].name;
                    OUT_comUOp[i].tagDst <= deqEntries[i].tag;
                    OUT_comUOp[i].sqN <= {deqEntries[i].sqN_msb, id[5:0]};
                    OUT_comUOp[i].isBranch <= deqEntries[i].flags == FLAGS_BRANCH || 
                        deqEntries[i].flags == FLAGS_PRED_TAKEN || deqEntries[i].flags == FLAGS_PRED_NTAKEN;
                    OUT_comUOp[i].compressed <= deqEntries[i].compressed;
                    OUT_comUOp[i].valid <= 1;
                    
                    // Synchronous exceptions do not increment minstret, but mret/sret do.
                    OUT_validRetire[i] <= deqEntries[i].flags <= FLAGS_ORDERING || deqEntries[i].flags == FLAGS_XRET;
                    
                    OUT_curFetchID <= deqEntries[i].fetchID;
                    
                    deqMask[id[1:0]] = 1;
                                   
                    if (deqEntries[i].flags >= FLAGS_PRED_TAKEN) begin
                        
                        OUT_trapUOp.flags <= deqEntries[i].flags;
                        OUT_trapUOp.tag <= deqEntries[i].tag;
                        OUT_trapUOp.sqN <= {deqEntries[i].sqN_msb, id[5:0]};
                        OUT_trapUOp.name <= deqEntries[i].name;
                        OUT_trapUOp.fetchOffs <= deqEntries[i].fetchOffs;
                        OUT_trapUOp.fetchID <= deqEntries[i].fetchID;
                        OUT_trapUOp.compressed <= deqEntries[i].compressed;
                        OUT_trapUOp.valid <= 1;
                        
                        pred = 1;
                        
                        if (deqEntries[i].flags >= FLAGS_FENCE) begin
                            if (deqEntries[i].flags == FLAGS_ILLEGAL_INSTR || 
                                deqEntries[i].flags == FLAGS_ACCESS_FAULT ||
                                deqEntries[i].flags == FLAGS_TRAP) begin
                                
                                // Redirect result of exception to x0
                                // The exception causes an invalidation to committed state,
                                // so changing these is fine (does not leave us with inconsistent RAT/TB)
                                OUT_comUOp[i].nmDst <= 0;
                                OUT_comUOp[i].tagDst <= 7'h40;
                            end
                            
                            stop <= 1;
                            temp = 1;
                        end
                    end
                    
                    if (deqEntries[i].flags >= FLAGS_FP_NX && deqEntries[i].flags <= FLAGS_FP_NV) begin
                        OUT_fpNewFlags[deqEntries[i].flags[2:0] - FLAGS_FP_NX[2:0]] <= 1;
                        
                        // Underflow and overflow imply inexact
                        if (deqEntries[i].flags == FLAGS_FP_UF || deqEntries[i].flags == FLAGS_FP_OF) begin
                            OUT_fpNewFlags[FLAGS_FP_NX[2:0]] <= 1;
                        end
                    end
                    
                    entries[id].valid <= 0;

                    cnt = cnt + 1;
                end
                else begin
                    temp = 1;
                    OUT_comUOp[i].valid <= 0;
                end
            end
            
            baseIndex <= baseIndex + cnt;
        end
        else
            for (i = 0; i < WIDTH; i=i+1)
                OUT_comUOp[i].valid <= 0;
        
        // Enqueue ops directly from Rename
        for (i = 0; i < WIDTH; i=i+1) begin
            if (rnUOpValidSorted[i] && (!IN_branch.taken)) begin
                
                reg[5:0] id = {rnUOpSorted[i].sqN[5:2], i[1:0]};
                
                entries[id].valid <= 1;
                entries[id].tag <= rnUOpSorted[i].tagDst;
                entries[id].name <= rnUOpSorted[i].nmDst;
                entries[id].sqN_msb <= rnUOpSorted[i].sqN[6];
                entries[id].compressed <= rnUOpSorted[i].compressed;
                entries[id].fetchID <= rnUOpSorted[i].fetchID;
                
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
        for (i = 0; i < WIDTH_WB; i=i+1) begin
            if (IN_wbUOps[i].valid && (!IN_branch.taken || $signed(IN_wbUOps[i].sqN - IN_branch.sqN) <= 0) && !IN_wbUOps[i].doNotCommit) begin
                
                reg[$clog2(LENGTH)-1:0] id = IN_wbUOps[i].sqN[ID_LEN-1:0];
                entries[id].flags <= IN_wbUOps[i].flags;
                assert(IN_wbUOps[i].flags != FLAGS_NX);
            end
        end
        
    end
end


endmodule
