  
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

    output SqN OUT_maxSqN,
    output SqN OUT_curSqN,

    output CommitUOp OUT_comUOp[WIDTH-1:0],
    
    input wire[31:0] IN_irqAddr,
    output Flags OUT_irqFlags,
    output reg[31:0] OUT_irqSrc,
    output reg[31:0] OUT_irqMemAddr,
    
    output FetchID_t OUT_pcReadAddr,
    input PCFileEntry IN_pcReadData,
    
    output reg OUT_fence,
    
    output BranchProv OUT_branch,
    
    output FetchID_t OUT_curFetchID,
    
    output reg OUT_halt,
    output reg OUT_mispredFlush
);
localparam ID_LEN = $clog2(LENGTH);

ROBEntry entries[LENGTH-1:0];
SqN baseIndex;
reg[31:0] committedInstrs;

assign OUT_maxSqN = baseIndex + LENGTH - 1;
assign OUT_curSqN = baseIndex;

integer i;
integer j;

reg headValid;
always_comb begin
    headValid = 1;
    for (i = 0; i < WIDTH; i=i+1) begin
        if (!entries[baseIndex[ID_LEN-1:0] + i[ID_LEN-1:0]].executed || entries[baseIndex[ID_LEN-1:0] + i[ID_LEN-1:0]].flags != FLAGS_NONE)
            headValid = 0;
    end
    
    //if ($time() < 6000) begin
    if (entries[baseIndex[ID_LEN-1:0]+1].predicted)
        headValid = 0;
    if (entries[baseIndex[ID_LEN-1:0]+2].predicted)
        headValid = 0;
    if (entries[baseIndex[ID_LEN-1:0]+3].predicted)
        headValid = 0;
    //end
end

reg allowSingleDequeue;
always_comb begin
    allowSingleDequeue = 1;
    if (!entries[baseIndex[ID_LEN-1:0]].executed)
        allowSingleDequeue = 0;
end

assign OUT_pcReadAddr = entries[baseIndex[ID_LEN-1:0]].fetchID;
wire[30:0] baseIndexPC = {IN_pcReadData.pc[30:2], entries[baseIndex[ID_LEN-1:0]].fetchOffs} - (entries[baseIndex[ID_LEN-1:0]].compressed ? 0 : 1);

BHist_t baseIndexHist;
BranchPredInfo baseIndexBPI;
always_comb begin
    if (IN_pcReadData.bpi.predicted && !IN_pcReadData.bpi.isJump && entries[baseIndex[ID_LEN-1:0]].fetchOffs > IN_pcReadData.branchPos)
        baseIndexHist = {IN_pcReadData.hist[$bits(BHist_t)-2:0], IN_pcReadData.bpi.taken};
    else
        baseIndexHist = IN_pcReadData.hist;
        
        baseIndexBPI = (entries[baseIndex[ID_LEN-1:0]].fetchOffs == IN_pcReadData.branchPos) ?
                                IN_pcReadData.bpi :
                                0;
end

reg misprReplay;
reg misprReplayEnd;
SqN misprReplayIter;
SqN misprReplayEndSqN;

wire doDequeue = headValid; // placeholder
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
        committedInstrs <= 0;
        OUT_branch.taken <= 0;
        misprReplay <= 0;
        OUT_mispredFlush <= 0;
        OUT_curFetchID <= -1;
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
        
        //if (entries[baseIndex[ID_LEN-1:0]].valid)
            
        
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
        // Two Entries
        else if (doDequeue && !IN_branch.taken) begin
            committedInstrs <= committedInstrs + 3;

            for (i = 0; i < WIDTH; i=i+1) begin
                OUT_comUOp[i].nmDst <= entries[baseIndex[ID_LEN-1:0]+i[ID_LEN-1:0]].name;
                OUT_comUOp[i].tagDst <= entries[baseIndex[ID_LEN-1:0]+i[ID_LEN-1:0]].tag;
                OUT_comUOp[i].sqN <= baseIndex + i[5:0];
                OUT_comUOp[i].isBranch <= entries[baseIndex[ID_LEN-1:0]+i[ID_LEN-1:0]].isBranch;
                OUT_comUOp[i].branchTaken <= entries[baseIndex[ID_LEN-1:0]+i[ID_LEN-1:0]].branchTaken;
                OUT_comUOp[i].bpi <= baseIndexBPI;
                OUT_comUOp[i].history <= baseIndexHist;
                OUT_comUOp[i].valid <= 1;
                OUT_comUOp[i].pc <= IN_pcReadData.pc;//baseIndexPC;
                OUT_comUOp[i].compressed <= entries[baseIndex[ID_LEN-1:0]+i[ID_LEN-1:0]].compressed;
                entries[baseIndex[ID_LEN-1:0]+i[ID_LEN-1:0]].valid <= 0;
                entries[baseIndex[ID_LEN-1:0]+i[ID_LEN-1:0]].executed <= 0;
            end
            OUT_curFetchID <= entries[baseIndex[ID_LEN-1:0] + WIDTH - 1].fetchID;
            // Blocking for proper insertion
            baseIndex = baseIndex + WIDTH;
        end
        
        // One entry
        else if (allowSingleDequeue && !IN_branch.taken) begin
            
            //assert(baseIndexPC == entries[baseIndex[ID_LEN-1:0]].pc);
            OUT_comUOp[0].nmDst <= entries[baseIndex[ID_LEN-1:0]].name;
            OUT_comUOp[0].tagDst <= entries[baseIndex[ID_LEN-1:0]].tag;
            OUT_comUOp[0].sqN <= baseIndex;
            OUT_comUOp[0].isBranch <= entries[baseIndex[ID_LEN-1:0]].isBranch;
            OUT_comUOp[0].branchTaken <= entries[baseIndex[ID_LEN-1:0]].branchTaken;
            OUT_comUOp[0].bpi <= baseIndexBPI;
            OUT_comUOp[0].history <= baseIndexHist;
            OUT_comUOp[0].valid <= 1;
            OUT_comUOp[0].pc <= IN_pcReadData.pc;//baseIndexPC;
            OUT_comUOp[0].compressed <= entries[baseIndex[ID_LEN-1:0]].compressed;
            entries[baseIndex[ID_LEN-1:0]].valid <= 0;
            entries[baseIndex[ID_LEN-1:0]].executed <= 0;
            
            OUT_curFetchID <= entries[baseIndex[ID_LEN-1:0]].fetchID;
            
            if (entries[baseIndex[ID_LEN-1:0]].flags == FLAGS_BRK) begin
                // ebreak does a jump to the instruction after itself,
                // this way the debugger can see the state right after ebreak exec'd.
                OUT_halt <= 1;
                OUT_branch.taken <= 1;
                OUT_branch.dstPC <= {baseIndexPC + 31'h2, 1'b0};
                OUT_branch.sqN <= baseIndex;
                OUT_branch.flush <= 1;
                OUT_branch.storeSqN <= 0;
                OUT_branch.loadSqN <= 0;
                OUT_branch.fetchID <= entries[baseIndex[ID_LEN-1:0]].fetchID;
                OUT_branch.history <= baseIndexHist;
                // Do not write back result, redirect to x0
                OUT_comUOp[0].nmDst <= 0;
            end
            else if (entries[baseIndex[ID_LEN-1:0]].flags == FLAGS_TRAP || entries[baseIndex[ID_LEN-1:0]].flags == FLAGS_EXCEPT) begin
                OUT_branch.taken <= 1;
                OUT_branch.dstPC <= IN_irqAddr;
                OUT_branch.sqN <= baseIndex;
                OUT_branch.flush <= 1;
                // These don't matter, the entire pipeline will be flushed
                OUT_branch.storeSqN <= 0;
                OUT_branch.loadSqN <= 0;
                OUT_branch.fetchID <= entries[baseIndex[ID_LEN-1:0]].fetchID;
                OUT_branch.history <= baseIndexHist;
                
                // Do not write back result, redirect to x0
                if (entries[baseIndex[ID_LEN-1:0]].flags == FLAGS_EXCEPT)
                    OUT_comUOp[0].nmDst <= 0;
                
                OUT_irqFlags <= entries[baseIndex[ID_LEN-1:0]].flags;
                OUT_irqSrc <= {baseIndexPC, 1'b0};
                // For exceptions, some fields are reused to get the segment of the violating address
                //OUT_irqMemAddr <= {7'b0, entries[baseIndex[ID_LEN-1:0]].name, entries[baseIndex[ID_LEN-1:0]].branchTaken, entries[baseIndex[ID_LEN-1:0]].branchID, 10'b0};
            end
            else if (entries[baseIndex[ID_LEN-1:0]].flags == FLAGS_FENCE) begin
                
                // Jump to instruction after fence to invalidate all speculative state
                OUT_branch.taken <= 1;
                OUT_branch.dstPC <= {baseIndexPC + 31'h2, 1'b0};
                OUT_branch.flush <= 1;
                OUT_branch.storeSqN <= 0;
                OUT_branch.loadSqN <= 0;
                OUT_branch.fetchID <= entries[baseIndex[ID_LEN-1:0]].fetchID;
                OUT_branch.history <= baseIndexHist;
                
                OUT_fence <= 1;
            end

            for (i = 1; i < WIDTH; i=i+1) begin
                OUT_comUOp[i].valid <= 0;
            end
            committedInstrs <= committedInstrs + 1;
            // Blocking for proper insertion
            baseIndex = baseIndex + 1;
        end
        else begin
            for (i = 0; i < WIDTH; i=i+1)
                OUT_comUOp[i].valid <= 0;
        end

        // Enqueue ops directly from Rename
        for (i = 0; i < WIDTH; i=i+1) begin
            if (IN_uopValid[i] && (!IN_branch.taken/* || $signed(IN_uop[i].sqN - IN_branch.takenSqN) <= 0*/)) begin
                entries[IN_uop[i].sqN[ID_LEN-1:0]].valid <= 1;
                entries[IN_uop[i].sqN[ID_LEN-1:0]].tag <= IN_uop[i].tagDst;
                entries[IN_uop[i].sqN[ID_LEN-1:0]].name <= IN_uop[i].nmDst;
                entries[IN_uop[i].sqN[ID_LEN-1:0]].sqN <= IN_uop[i].sqN;
                entries[IN_uop[i].sqN[ID_LEN-1:0]].compressed <= IN_uop[i].compressed;
                entries[IN_uop[i].sqN[ID_LEN-1:0]].fetchID <= IN_uop[i].fetchID;
                entries[IN_uop[i].sqN[ID_LEN-1:0]].executed <= 0;
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
                //entries[IN_wbUOps[i].sqN[ID_LEN-1:0]].pc <= IN_wbUOps[i].pc[31:1];
                //entries[IN_wbUOps[i].sqN[ID_LEN-1:0]].bpi <= IN_wbUOps[i].bpi;
                //entries[IN_wbUOps[i].sqN[ID_LEN-1:0]].history <= IN_wbUOps[i].history;
                entries[IN_wbUOps[i].sqN[ID_LEN-1:0]].predicted <= IN_wbUOps[i].bpi.predicted;
            end
        end
        
        
    end
end


endmodule
