
typedef struct packed 
{
    bit valid;
    Flags flags;
    bit[5:0] tag;
    // for debugging
    bit[5:0] sqN;
    bit[29:0] pc;
    bit[4:0] name;
    bit isBranch;
    bit branchTaken;
    bit[5:0] branchID;
} ROBEntry;

module ROB
#(
    // how many entries, ie how many instructions can we
    // speculatively execute?
    parameter LENGTH = 30,

    parameter WIDTH = 2,
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

    output reg[4:0] OUT_comNames[WIDTH-1:0],
    output reg[5:0] OUT_comTags[WIDTH-1:0],
    output reg[5:0] OUT_comSqNs[WIDTH-1:0],
    output reg OUT_comIsBranch[WIDTH-1:0],
    output reg OUT_comBranchTaken[WIDTH-1:0],
    output reg[5:0] OUT_comBranchID[WIDTH-1:0],
    output reg[29:0] OUT_comPC[WIDTH-1:0],
    output reg OUT_comValid[WIDTH-1:0],
    
    input wire[31:0] IN_irqAddr,
    output Flags OUT_irqFlags,
    output reg[31:0] OUT_irqSrc,
    
    output BranchProv OUT_branch,
    
    output reg OUT_halt
);

ROBEntry entries[LENGTH-1:0];
reg[5:0] baseIndex;
reg[31:0] committedInstrs;

assign OUT_maxSqN = baseIndex + LENGTH - 1;
assign OUT_curSqN = baseIndex;

integer i;
integer j;

reg headValid;
always_comb begin
    headValid = 1;
    for (i = 0; i < WIDTH; i=i+1) begin
        if (!entries[i].valid || entries[i].flags != FLAGS_NONE)
            headValid = 0;
    end
    
    if (entries[1].isBranch)
        headValid = 0;
end

reg allowSingleDequeue;
always_comb begin
    allowSingleDequeue = 1;
    
    //for (i = 1; i < LENGTH; i=i+1)
    //    if (entries[i].valid)
    //        allowSingleDequeue = 0;
            
    if (!entries[0].valid)
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
            OUT_comValid[i] <= 0;
        end
        committedInstrs <= 0;
        OUT_branch.taken <= 0;
    end
    else if (IN_invalidate) begin
        for (i = 0; i < LENGTH; i=i+1) begin
            if ($signed((baseIndex + i[5:0]) - IN_invalidateSqN) > 0) begin
                entries[i].valid <= 0;
            end
        end
        //if ($signed(baseIndex - IN_invalidateSqN) > 0)
        //    baseIndex = IN_invalidateSqN;
    end
    
    if (!rst) begin
        // Dequeue and push forward fifo entries
        
        // Two Entries
        if (doDequeue && !IN_invalidate) begin
            // Push forward fifo
            for (i = 0; i < LENGTH - WIDTH; i=i+1) begin
                entries[i] <= entries[i + WIDTH];
            end

            for (i = LENGTH - WIDTH; i < LENGTH; i=i+1) begin
                entries[i].valid <= 0;
            end
            
            committedInstrs <= committedInstrs + 2;

            for (i = 0; i < WIDTH; i=i+1) begin
                OUT_comNames[i] <= entries[i].name;
                OUT_comTags[i] <= entries[i].tag;
                OUT_comSqNs[i] <= baseIndex + i[5:0];
                OUT_comIsBranch[i] <= entries[i].isBranch;
                OUT_comBranchTaken[i] <= entries[i].branchTaken;
                OUT_comBranchID[i] <= entries[i].branchID;
                OUT_comValid[i] <= 1;
                OUT_comPC[i] <= entries[i].pc;
            end
            // Blocking for proper insertion
            baseIndex = baseIndex + WIDTH;
        end
        
        // One entry
        else if (allowSingleDequeue && !IN_invalidate) begin
            
            // Push forward fifo
            for (i = 0; i < LENGTH - 1; i=i+1) begin
                entries[i] <= entries[i + 1];
            end

            for (i = LENGTH - 1; i < LENGTH; i=i+1) begin
                entries[i].valid <= 0;
            end

            for (i = 0; i < 1; i=i+1) begin
                OUT_comNames[i] <= entries[i].name;
                OUT_comTags[i] <= entries[i].tag;
                OUT_comSqNs[i] <= baseIndex + i[5:0];
                OUT_comIsBranch[i] <= entries[i].isBranch;
                OUT_comBranchTaken[i] <= entries[i].branchTaken;
                OUT_comBranchID[i] <= entries[i].branchID;
                OUT_comValid[i] <= 1;
                OUT_comPC[i] <= entries[i].pc;
                
                
                if (entries[i].flags == FLAGS_BRK) begin
                    // ebreak does a jump to the instruction after itself,
                    // this way the debugger can see the state right after ebreak exec'd.
                    OUT_halt <= 1;
                    OUT_branch.taken <= 1;
                    OUT_branch.dstPC <= {entries[i].pc + 1'b1, 2'b0};
                    OUT_branch.sqN <= baseIndex + i[5:0];
                    OUT_branch.flush <= 1;
                    OUT_branch.storeSqN <= 0;
                    OUT_branch.loadSqN <= 0;
                end
                else if (entries[i].flags == FLAGS_TRAP || entries[i].flags == FLAGS_EXCEPT) begin
                    OUT_branch.taken <= 1;
                    OUT_branch.dstPC <= IN_irqAddr;
                    OUT_branch.sqN <= baseIndex + i[5:0];
                    OUT_branch.flush <= 1;
                    // These don't matter, the entire pipeline will be flushed
                    OUT_branch.storeSqN <= 0;
                    OUT_branch.loadSqN <= 0;
                    
                    OUT_irqFlags <= entries[i].flags;
                    OUT_irqSrc <= {entries[i].pc, 2'b0};
                end
                
            end
            for (i = 1; i < WIDTH; i=i+1) begin
                OUT_comValid[i] <= 0;
            end
            committedInstrs <= committedInstrs + 1;
            // Blocking for proper insertion
            baseIndex = baseIndex + 1;
        end
        else begin
            for (i = 0; i < WIDTH; i=i+1)
                OUT_comValid[i] <= 0;
        end

        // Enqueue if entries are unused (or if we just dequeued, which frees space).
        for (i = 0; i < WIDTH_WB; i=i+1) begin
            if (IN_uop[i].valid && (!IN_invalidate || $signed(IN_uop[i].sqN - IN_invalidateSqN) <= 0)) begin
                
                //assert(!IN_invalidate || !entries[IN_uop[i].sqN[4:0]].valid);
                //$display("insert %d", IN_uop[i].sqN);
                
                entries[IN_uop[i].sqN[4:0] - baseIndex[4:0]].valid <= 1;
                entries[IN_uop[i].sqN[4:0] - baseIndex[4:0]].flags <= IN_uop[i].flags;
                entries[IN_uop[i].sqN[4:0] - baseIndex[4:0]].tag <= IN_uop[i].tagDst;
                entries[IN_uop[i].sqN[4:0] - baseIndex[4:0]].name <= IN_uop[i].nmDst;
                entries[IN_uop[i].sqN[4:0] - baseIndex[4:0]].sqN <= IN_uop[i].sqN;
                entries[IN_uop[i].sqN[4:0] - baseIndex[4:0]].pc <= IN_uop[i].pc[31:2];
                entries[IN_uop[i].sqN[4:0] - baseIndex[4:0]].isBranch <= IN_uop[i].isBranch;
                entries[IN_uop[i].sqN[4:0] - baseIndex[4:0]].branchTaken <= IN_uop[i].branchTaken;
                entries[IN_uop[i].sqN[4:0] - baseIndex[4:0]].branchID <= IN_uop[i].branchID;
            end
        end
    end
end


endmodule
