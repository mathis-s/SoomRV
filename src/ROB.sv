  
typedef struct packed 
{
    Flags flags;
    Tag tag;
    SqN sqN;
    //bit[30:0] pc;
    RegNm name;
    bit isBranch;
    bit branchTaken;
    bit predicted;
    //BranchPredInfo bpi;
    FetchOff_t fetchOffs;
    FetchID_t fetchID;
    //BHist_t history;
    bit compressed;
    bit valid;
    bit executed;
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
    
    input BranchProv IN_branch,
    
    input wire IN_MEM_busy,

    output SqN OUT_maxSqN,
    output SqN OUT_curSqN,

    output CommitUOp OUT_comUOp[WIDTH-1:0],
    
    output BPUpdate OUT_bpUpdate,
    
    input wire[31:0] IN_irqAddr,
    output Flags OUT_irqFlags,
    output reg[31:0] OUT_irqSrc,
    output reg[31:0] OUT_irqMemAddr,
    
    output FetchID_t OUT_pcReadAddr,
    input PCFileEntry IN_pcReadData,
    
    output reg OUT_fence,
    
    output BranchProv OUT_branch,
    output FetchID_t OUT_curFetchID,
    
    output wire OUT_disableIFetch,
    output reg OUT_halt,
    output reg OUT_mispredFlush
);
localparam ID_LEN = $clog2(LENGTH);

ROBEntry entries[LENGTH-1:0];
SqN baseIndex;

assign OUT_maxSqN = baseIndex + LENGTH - 1;
assign OUT_curSqN = baseIndex;

integer i;
integer j;

ROBEntry pcLookupEntry;
assign OUT_pcReadAddr = pcLookupEntry.fetchID;
wire[30:0] baseIndexPC = {IN_pcReadData.pc[30:2], pcLookupEntry.fetchOffs} - (pcLookupEntry.compressed ? 0 : 1);
BHist_t baseIndexHist;
BranchPredInfo baseIndexBPI;
always_comb begin
    if (IN_pcReadData.bpi.predicted && !IN_pcReadData.bpi.isJump && pcLookupEntry.fetchOffs > IN_pcReadData.branchPos)
        baseIndexHist = {IN_pcReadData.hist[$bits(BHist_t)-2:0], IN_pcReadData.bpi.taken};
    else
        baseIndexHist = IN_pcReadData.hist;
        
        baseIndexBPI = (pcLookupEntry.fetchOffs == IN_pcReadData.branchPos) ?
            IN_pcReadData.bpi :
            0;
end

reg stop;
reg memoryWait;
reg memoryFence;

assign OUT_disableIFetch = memoryWait;

reg misprReplay;
reg misprReplayEnd;
SqN misprReplayIter;
SqN misprReplayEndSqN;

always_ff@(posedge clk) begin

    OUT_branch.taken <= 0;
    OUT_halt <= 0;
    OUT_fence <= 0;
    
    if (rst) begin
        baseIndex = 0;
        for (i = 0; i < LENGTH; i=i+1) begin
            entries[i].valid <= 0;
            entries[i].executed <= 0;
        end
        for (i = 0; i < WIDTH; i=i+1) begin
            OUT_comUOp[i].valid <= 0;
        end
        OUT_branch.taken <= 0;
        misprReplay <= 0;
        OUT_mispredFlush <= 0;
        OUT_curFetchID <= -1;
        OUT_bpUpdate.valid <= 0;
        pcLookupEntry.valid <= 0;
        stop <= 0;
        memoryWait <= 0;
    end
    else if (IN_branch.taken) begin
        for (i = 0; i < LENGTH; i=i+1) begin
            if ($signed(entries[i].sqN - IN_branch.sqN) > 0) begin
                entries[i].valid <= 0;
                entries[i].executed <= 0;
            end
        end
        misprReplay <= 1;
        misprReplayEndSqN <= IN_branch.sqN;
        misprReplayIter <= baseIndex;
        misprReplayEnd <= 0;
        OUT_mispredFlush <= 0;
    end
    
    if (!rst) begin
    
        OUT_bpUpdate.valid <= 0;
        
        if (memoryWait && !IN_MEM_busy) begin
            if (memoryFence) begin
                OUT_fence <= 1;
                memoryFence <= 0;
            end
            else begin
                memoryWait <= 0;
            end
        end
        
        // Exception and branch prediction update handling
        pcLookupEntry.valid <= 0;
        if (pcLookupEntry.valid) begin
            if (pcLookupEntry.flags == FLAGS_BRK || pcLookupEntry.flags == FLAGS_FENCE || pcLookupEntry.flags == FLAGS_ORDERING) begin
                
                if (pcLookupEntry.flags == FLAGS_BRK)
                    OUT_halt <= 1;
                else if (pcLookupEntry.flags == FLAGS_ORDERING) begin
                    memoryWait <= 1;
                end
                else if (pcLookupEntry.flags == FLAGS_FENCE) begin
                    memoryFence <= 1;
                    memoryWait <= 1;
                end
                
                OUT_branch.taken <= 1;
                OUT_branch.dstPC <= {baseIndexPC + (pcLookupEntry.compressed ? 31'd1 : 31'd2), 1'b0};
                OUT_branch.sqN <= pcLookupEntry.sqN;
                OUT_branch.flush <= 1;
                OUT_branch.storeSqN <= 0;
                OUT_branch.loadSqN <= 0;
                OUT_branch.fetchID <= pcLookupEntry.fetchID;
                OUT_branch.history <= baseIndexHist;
                stop <= 0;
            end
            else if (pcLookupEntry.flags == FLAGS_TRAP || pcLookupEntry.flags == FLAGS_EXCEPT) begin
                
                OUT_branch.taken <= 1;
                OUT_branch.dstPC <= IN_irqAddr;
                OUT_branch.sqN <= pcLookupEntry.sqN;
                OUT_branch.flush <= 1;
                // These don't matter, the entire pipeline will be flushed
                OUT_branch.storeSqN <= 0;
                OUT_branch.loadSqN <= 0;
                OUT_branch.fetchID <= pcLookupEntry.fetchID;
                OUT_branch.history <= baseIndexHist;
                
                OUT_irqSrc <= {baseIndexPC, 1'b0};
                OUT_irqFlags <= pcLookupEntry.flags;
                
                stop <= 0;
            end
            else if (pcLookupEntry.predicted) begin
                OUT_bpUpdate.valid <= 1;
                OUT_bpUpdate.pc <= IN_pcReadData.pc;
                OUT_bpUpdate.compressed <= pcLookupEntry.compressed;
                OUT_bpUpdate.history <= IN_pcReadData.hist;
                OUT_bpUpdate.bpi <= IN_pcReadData.bpi;
                OUT_bpUpdate.branchTaken <= pcLookupEntry.branchTaken;
            end
        end
        
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
                        OUT_comUOp[i].valid <= 1;
                        OUT_comUOp[i].nmDst <= entries[misprReplayIter[ID_LEN-1:0]+i[ID_LEN-1:0]].name;
                        OUT_comUOp[i].tagDst <= entries[misprReplayIter[ID_LEN-1:0]+i[ID_LEN-1:0]].tag;
                        OUT_comUOp[i].compressed <= entries[misprReplayIter[ID_LEN-1:0]+i[ID_LEN-1:0]].executed;
                        for (j = 0; j < WIDTH_WB; j=j+1)
                            if (IN_wbUOps[j].valid && IN_wbUOps[j].nmDst != 0 && IN_wbUOps[j].tagDst == entries[misprReplayIter[ID_LEN-1:0]+i[ID_LEN-1:0]].tag)
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
            
            for (i = 0; i < WIDTH; i=i+1) begin
                
                ROBEntry cur = entries[baseIndex[ID_LEN-1:0]+i[ID_LEN-1:0]];
                
                if (!temp && cur.executed && (!pred || (!cur.predicted && cur.flags == FLAGS_NONE))) begin
                    OUT_comUOp[i].nmDst <= entries[baseIndex[ID_LEN-1:0]+i[ID_LEN-1:0]].name;
                    OUT_comUOp[i].tagDst <= entries[baseIndex[ID_LEN-1:0]+i[ID_LEN-1:0]].tag;
                    OUT_comUOp[i].sqN <= entries[baseIndex[ID_LEN-1:0]+i[ID_LEN-1:0]].sqN;
                    OUT_comUOp[i].isBranch <= entries[baseIndex[ID_LEN-1:0]+i[ID_LEN-1:0]].isBranch;
                    OUT_comUOp[i].branchTaken <= entries[baseIndex[ID_LEN-1:0]+i[ID_LEN-1:0]].branchTaken;
                    OUT_comUOp[i].valid <= 1;
                    OUT_comUOp[i].compressed <= entries[baseIndex[ID_LEN-1:0]+i[ID_LEN-1:0]].compressed;
                    OUT_curFetchID <= entries[baseIndex[ID_LEN-1:0]+i[ID_LEN-1:0]].fetchID;
                    
                    entries[baseIndex[ID_LEN-1:0]+i[ID_LEN-1:0]].valid <= 0;
                    entries[baseIndex[ID_LEN-1:0]+i[ID_LEN-1:0]].executed <= 0;
                    
                    if (entries[baseIndex[ID_LEN-1:0]+i[ID_LEN-1:0]].predicted || 
                        entries[baseIndex[ID_LEN-1:0]+i[ID_LEN-1:0]].flags != 0) begin
                        pcLookupEntry <= entries[baseIndex[ID_LEN-1:0]+i[ID_LEN-1:0]];
                        pred = 1;
                    end
                        
                    if (entries[baseIndex[ID_LEN-1:0]+i[ID_LEN-1:0]].flags != FLAGS_NONE) begin
                        // Redirect result of exception to x0 (TODO: make sure this doesn't leak registers?)
                        if (entries[baseIndex[ID_LEN-1:0]+i[ID_LEN-1:0]].flags == FLAGS_EXCEPT)
                            OUT_comUOp[i].nmDst <= 0;
                        stop <= 1;
                        temp = 1;
                    end
                    
                    cnt = cnt + 1;
                end
                else begin
                    temp = 1;
                    OUT_comUOp[i].valid <= 0;
                end
            end
            
            baseIndex = baseIndex + cnt;
        end
        else
            for (i = 0; i < WIDTH; i=i+1)
                OUT_comUOp[i].valid <= 0;

        // Enqueue ops directly from Rename
        for (i = 0; i < WIDTH; i=i+1) begin
            if (IN_uopValid[i] && (!IN_branch.taken/* || $signed(IN_uop[i].sqN - IN_branch.takenSqN) <= 0*/)) begin
                entries[IN_uop[i].sqN[ID_LEN-1:0]].valid <= 1;
                entries[IN_uop[i].sqN[ID_LEN-1:0]].tag <= IN_uop[i].tagDst;
                entries[IN_uop[i].sqN[ID_LEN-1:0]].name <= IN_uop[i].nmDst;
                entries[IN_uop[i].sqN[ID_LEN-1:0]].sqN <= IN_uop[i].sqN;
                entries[IN_uop[i].sqN[ID_LEN-1:0]].compressed <= IN_uop[i].compressed;
                entries[IN_uop[i].sqN[ID_LEN-1:0]].fetchID <= IN_uop[i].fetchID;
                entries[IN_uop[i].sqN[ID_LEN-1:0]].executed <= IN_uop[i].fu == FU_RN;
                entries[IN_uop[i].sqN[ID_LEN-1:0]].predicted <= 0;
                entries[IN_uop[i].sqN[ID_LEN-1:0]].flags <= 0;
            end
        end
        
        // Mark committed ops as valid and set flags
        for (i = 0; i < WIDTH_WB; i=i+1) begin
            if (IN_wbUOps[i].valid && (!IN_branch.taken || $signed(IN_wbUOps[i].sqN - IN_branch.sqN) <= 0)) begin
                entries[IN_wbUOps[i].sqN[ID_LEN-1:0]].executed <= 1;
                entries[IN_wbUOps[i].sqN[ID_LEN-1:0]].flags <= IN_wbUOps[i].flags;
                entries[IN_wbUOps[i].sqN[ID_LEN-1:0]].isBranch <= IN_wbUOps[i].isBranch;
                entries[IN_wbUOps[i].sqN[ID_LEN-1:0]].branchTaken <= IN_wbUOps[i].branchTaken;
                entries[IN_wbUOps[i].sqN[ID_LEN-1:0]].fetchOffs <= IN_wbUOps[i].pc[2:1] + (IN_wbUOps[i].compressed ? 2'b0 : 2'b1);
                entries[IN_wbUOps[i].sqN[ID_LEN-1:0]].predicted <= IN_wbUOps[i].bpi.predicted;
            end
        end
        
        
    end
end


endmodule
