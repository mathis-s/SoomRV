
typedef struct packed 
{
    bit valid;
    Flags flags;
    bit[6:0] tag;
    // for debugging
    bit[5:0] sqN;
    bit[29:0] pc;
    bit[5:0] name;
    bit isBranch;
    bit branchTaken;
    bit[5:0] branchID;
} ROBEntry;


module ROB
#(
    // how many entries, ie how many instructions can we
    // speculatively execute?
    parameter LENGTH = 32,

    parameter WIDTH = 3,
    parameter WIDTH_WB = 3
)
(
    input wire clk,
    input wire rst,

    input RES_UOp IN_uop[WIDTH_WB-1:0],

    input wire IN_invalidate,
    input wire[5:0] IN_invalidateSqN,

    output wire[5:0] OUT_maxSqN,
    output wire[5:0] OUT_curSqN,

    output CommitUOp OUT_comUOp[WIDTH-1:0],
    
    input wire[31:0] IN_irqAddr,
    output Flags OUT_irqFlags,
    output reg[31:0] OUT_irqSrc,
    output reg[12:0] OUT_irqMemAddr,
    
    output BranchProv OUT_branch,
    
    output reg OUT_halt
);

ROBEntry entries[LENGTH-1:0];
reg[5:0] baseIndex;
reg[31:0] committedInstrs;

assign OUT_maxSqN = baseIndex + LENGTH - 1 - 2;
assign OUT_curSqN = baseIndex;

integer i;
integer j;

reg headValid;
always_comb begin
    headValid = 1;
    for (i = 0; i < WIDTH; i=i+1) begin
        if (!entries[baseIndex[4:0] + i[4:0]].valid || entries[baseIndex[4:0] + i[4:0]].flags != FLAGS_NONE)
            headValid = 0;
    end
    
    if (entries[baseIndex[4:0]+1].isBranch)
        headValid = 0;
    if (entries[baseIndex[4:0]+2].isBranch)
        headValid = 0;
end

reg allowSingleDequeue;
always_comb begin
    allowSingleDequeue = 1;
    
    //for (i = 1; i < LENGTH; i=i+1)
    //    if (entries[i].valid)
    //        allowSingleDequeue = 0;
            
    if (!entries[baseIndex[4:0]].valid)
        allowSingleDequeue = 0;
end

wire doDequeue = headValid; // placeholder
always_ff@(posedge clk) begin

    OUT_branch.taken <= 0;
    OUT_halt <= 0;
    
    if (rst) begin
        baseIndex = 0;
        for (i = 0; i < LENGTH; i=i+1) begin
            entries[i].valid <= 0;
        end
        for (i = 0; i < WIDTH; i=i+1) begin
            OUT_comUOp[i].valid <= 0;
        end
        committedInstrs <= 0;
        OUT_branch.taken <= 0;
    end
    else if (IN_invalidate) begin
        for (i = 0; i < LENGTH; i=i+1) begin
            if ($signed(entries[i].sqN - IN_invalidateSqN) > 0) begin
                entries[i].valid <= 0;
            end
        end
    end
    
    if (!rst) begin
        // Dequeue and push forward fifo entries
        
        // Two Entries
        if (doDequeue && !IN_invalidate) begin
            committedInstrs <= committedInstrs + 3;

            for (i = 0; i < WIDTH; i=i+1) begin
                OUT_comUOp[i].nmDst <= entries[baseIndex[4:0]+i[4:0]].name;
                OUT_comUOp[i].tagDst <= entries[baseIndex[4:0]+i[4:0]].tag;
                OUT_comUOp[i].sqN <= baseIndex + i[5:0];
                OUT_comUOp[i].isBranch <= entries[baseIndex[4:0]+i[4:0]].isBranch;
                OUT_comUOp[i].branchTaken <= entries[baseIndex[4:0]+i[4:0]].branchTaken;
                OUT_comUOp[i].branchID <= entries[baseIndex[4:0]+i[4:0]].branchID;
                OUT_comUOp[i].valid <= 1;
                OUT_comUOp[i].pc <= entries[baseIndex[4:0]+i[4:0]].pc;
                entries[baseIndex[4:0]+i[4:0]].valid <= 0;
            end
            // Blocking for proper insertion
            baseIndex = baseIndex + WIDTH;
        end
        
        // One entry
        else if (allowSingleDequeue && !IN_invalidate) begin

            OUT_comUOp[0].nmDst <= entries[baseIndex[4:0]].name;
            OUT_comUOp[0].tagDst <= entries[baseIndex[4:0]].tag;
            OUT_comUOp[0].sqN <= baseIndex;
            OUT_comUOp[0].isBranch <= entries[baseIndex[4:0]].isBranch;
            OUT_comUOp[0].branchTaken <= entries[baseIndex[4:0]].branchTaken;
            OUT_comUOp[0].branchID <= entries[baseIndex[4:0]].branchID;
            OUT_comUOp[0].valid <= 1;
            OUT_comUOp[0].pc <= entries[baseIndex[4:0]].pc;
            entries[baseIndex[4:0]].valid <= 0;
            
            if (entries[baseIndex[4:0]].flags == FLAGS_BRK) begin
                // ebreak does a jump to the instruction after itself,
                // this way the debugger can see the state right after ebreak exec'd.
                OUT_halt <= 1;
                OUT_branch.taken <= 1;
                OUT_branch.dstPC <= {entries[baseIndex[4:0]].pc + 1'b1, 2'b0};
                OUT_branch.sqN <= baseIndex;
                OUT_branch.flush <= 1;
                OUT_branch.storeSqN <= 0;
                OUT_branch.loadSqN <= 0;
                // Do not write back result, redirect to x0
                OUT_comUOp[0].nmDst <= 0;
            end
            else if (entries[baseIndex[4:0]].flags == FLAGS_TRAP || entries[baseIndex[4:0]].flags == FLAGS_EXCEPT) begin
                OUT_branch.taken <= 1;
                OUT_branch.dstPC <= IN_irqAddr;
                OUT_branch.sqN <= baseIndex;
                OUT_branch.flush <= 1;
                // These don't matter, the entire pipeline will be flushed
                OUT_branch.storeSqN <= 0;
                OUT_branch.loadSqN <= 0;
                
                // Do not write back result, redirect to x0
                if (entries[baseIndex[4:0]].flags == FLAGS_EXCEPT)
                    OUT_comUOp[0].nmDst <= 0;
                
                OUT_irqFlags <= entries[baseIndex[4:0]].flags;
                OUT_irqSrc <= {entries[baseIndex[4:0]].pc, 2'b0};
                // For exceptions, some fields are reused to get the segment of the violating address
                OUT_irqMemAddr <= {entries[baseIndex[4:0]].name, entries[baseIndex[4:0]].branchTaken, entries[baseIndex[4:0]].branchID};
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

        // Enqueue if entries are unused (or if we just dequeued, which frees space).
        for (i = 0; i < WIDTH_WB; i=i+1) begin
            if (IN_uop[i].valid && (!IN_invalidate || $signed(IN_uop[i].sqN - IN_invalidateSqN) <= 0)) begin
                
                //assert(!IN_invalidate || !entries[IN_uop[i].sqN[4:0]].valid);
                //$display("insert %d", IN_uop[i].sqN);
                
                entries[IN_uop[i].sqN[4:0]].valid <= 1;
                entries[IN_uop[i].sqN[4:0]].flags <= IN_uop[i].flags;
                entries[IN_uop[i].sqN[4:0]].tag <= IN_uop[i].tagDst;
                entries[IN_uop[i].sqN[4:0]].name <= IN_uop[i].nmDst;
                entries[IN_uop[i].sqN[4:0]].sqN <= IN_uop[i].sqN;
                entries[IN_uop[i].sqN[4:0]].pc <= IN_uop[i].pc[31:2];
                entries[IN_uop[i].sqN[4:0]].isBranch <= IN_uop[i].isBranch;
                entries[IN_uop[i].sqN[4:0]].branchTaken <= IN_uop[i].branchTaken;
                entries[IN_uop[i].sqN[4:0]].branchID <= IN_uop[i].branchID;
            end
        end
    end
end


endmodule
