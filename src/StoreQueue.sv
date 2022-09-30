typedef struct packed
{
    bit valid;
    bit ready;
    bit[5:0] sqN;
    bit[29:0] addr;
    bit[31:0] data;
    bit[3:0] wmask;
} SQEntry;

module StoreQueue
#(
    parameter NUM_PORTS=1,
    parameter NUM_ENTRIES=16
)
(
    input wire clk,
    input wire rst,
    input wire IN_disable,
    output reg OUT_empty,
    
    input AGU_UOp IN_uop[NUM_PORTS-1:0],
    
    input wire[5:0] IN_curSqN,
    
    input BranchProv IN_branch,
    
    input wire[31:0] IN_MEM_data[NUM_PORTS-1:0],
    output reg[29:0] OUT_MEM_addr[NUM_PORTS-1:0],
    output reg[31:0] OUT_MEM_data[NUM_PORTS-1:0],
    output reg OUT_MEM_we[NUM_PORTS-1:0],
    output reg OUT_MEM_ce[NUM_PORTS-1:0],
    output reg[3:0] OUT_MEM_wm[NUM_PORTS-1:0],
    
    // CSRs can share most ports with regular memory except these
    input wire[31:0] IN_CSR_data[NUM_PORTS-1:0],
    output reg OUT_CSR_ce[NUM_PORTS-1:0],
    
    output RES_UOp OUT_uop[NUM_PORTS-1:0],
    
    output reg[5:0] OUT_maxStoreSqN,
    input wire IN_IO_busy
    
);

integer i;
integer j;

SQEntry entries[NUM_ENTRIES-1:0];

reg[5:0] baseIndex;

reg doingDequeue;
reg isCsrRead[NUM_PORTS-1:0];
reg isCsrWrite[NUM_PORTS-1:0];


// intermediate 
reg[29:0] iAddr[NUM_PORTS-1:0];
reg[5:0] iSqN[NUM_PORTS-1:0];
reg[3:0] iMask[NUM_PORTS-1:0];
reg[31:0] iData[NUM_PORTS-1:0];

AGU_UOp i0[NUM_PORTS-1:0];
AGU_UOp i1[NUM_PORTS-1:0];

reg i0_isCsrRead[NUM_PORTS-1:0];
reg i1_isCsrRead[NUM_PORTS-1:0];

reg[31:0] queueLookupData[NUM_PORTS-1:0];
reg[3:0] queueLookupMask[NUM_PORTS-1:0];

reg didCSRwrite;

always_comb begin
    for (i = 0; i < NUM_PORTS; i=i+1) begin
        
        reg[31:0] result = 32'bx;
        
        if (i1[i].isLoad) begin
            reg[31:0] data;
            data[31:24] = queueLookupMask[i][3] ? queueLookupData[i][31:24] : 
                (i1_isCsrRead[i] ?  IN_CSR_data[i][31:24] : IN_MEM_data[i][31:24]);
            data[23:16] = queueLookupMask[i][2] ? queueLookupData[i][23:16] : 
                (i1_isCsrRead[i] ? IN_CSR_data[i][23:16] : IN_MEM_data[i][23:16]);
            data[15:8] = queueLookupMask[i][1] ? queueLookupData[i][15:8] : 
                (i1_isCsrRead[i] ? IN_CSR_data[i][15:8] : IN_MEM_data[i][15:8]);
            data[7:0] = queueLookupMask[i][0] ? queueLookupData[i][7:0] : 
                (i1_isCsrRead[i] ? IN_CSR_data[i][7:0] : IN_MEM_data[i][7:0]);
            
            case (i1[i].size)
                
                0: begin
                    case (i1[i].shamt)
                        0: result[7:0] = data[7:0];
                        1: result[7:0] = data[15:8];
                        2: result[7:0] = data[23:16];
                        3: result[7:0] = data[31:24];
                    endcase
                    
                    result[31:8] = {24{i1[i].signExtend ? result[7] : 1'b0}};
                end
                
                1: begin
                    case (i1[i].shamt)
                        default: result[15:0] = data[15:0];
                        2: result[15:0] = data[31:16];
                    endcase
                    
                    result[31:16] = {16{i1[i].signExtend ? result[15] : 1'b0}};
                end
                
                default: result = data;
            endcase
        end

        OUT_uop[i].result = result;
        OUT_uop[i].tagDst = i1[i].tagDst;
        OUT_uop[i].nmDst = i1[i].exception ? i1[i].addr[22:18] : i1[i].nmDst;
        OUT_uop[i].sqN = i1[i].sqN;
        OUT_uop[i].pc = i1[i].pc;
        OUT_uop[i].valid = i1[i].valid;
        OUT_uop[i].flags = i1[i].exception ? FLAGS_EXCEPT : FLAGS_NONE;
        OUT_uop[i].isBranch = 0;
        OUT_uop[i].branchTaken = i1[i].addr[17];
        OUT_uop[i].branchID = i1[i].addr[16:11];
    end
end

reg empty;
always_comb begin
    empty = 1;
    for (i = 0; i < NUM_ENTRIES; i=i+1) begin
        if (entries[i].valid)
            empty = 0;
    end
end

// Handle Loads combinatorially (SRAM input is registered)
always_comb begin
    doingDequeue = 0;
    
    for (i = 0; i < NUM_PORTS; i=i+1) begin
        
        isCsrRead[i] = 0;
        isCsrWrite[i] = 0;
        if (!rst && IN_uop[i].valid && IN_uop[i].isLoad && (!IN_branch.taken || $signed(IN_uop[i].sqN - IN_branch.sqN) <= 0)) begin
            OUT_MEM_data[i] = 32'bx;
            OUT_MEM_addr[i] = IN_uop[i].addr[31:2];
            OUT_MEM_we[i] = 1;
            OUT_MEM_wm[i] = 4'bx;
            if (IN_uop[i].addr[31:24] == 8'hff) begin
                OUT_MEM_ce[i] = 1;
                OUT_CSR_ce[i] = 0;
                isCsrRead[i] = 1;
            end
            else begin
                OUT_MEM_ce[i] = 0;
                OUT_CSR_ce[i] = 1;
            end
        end
        
        // Port 0 handles stores as well
        else if (!IN_disable && !rst && i == 0 && entries[0].valid && !IN_branch.taken && entries[0].ready &&
            // Don't issue Memory Mapped IO ops while IO is not ready
            (!(IN_IO_busy || didCSRwrite) || entries[0].addr[29:22] != 8'hff)) begin
            doingDequeue = 1;
            OUT_MEM_data[i] = entries[0].data;
            OUT_MEM_addr[i] = entries[0].addr;
            OUT_MEM_we[i] = 0;
            OUT_MEM_wm[i] = entries[0].wmask;
            
            if (entries[0].addr[29:22] == 8'hff) begin
                OUT_MEM_ce[i] = 1;
                OUT_CSR_ce[i] = 0;
                isCsrWrite[i] = 1;
            end
            else begin
                OUT_MEM_ce[i] = 0;
                OUT_CSR_ce[i] = 1;
            end
        end
        
        else begin
            OUT_MEM_data[i] = 32'bx;
            OUT_MEM_addr[i] = 30'bx;
            OUT_MEM_we[i] = 1'b1;
            OUT_MEM_ce[i] = 1'b1;
            OUT_MEM_wm[i] = 4'bx;
            OUT_CSR_ce[i] = 1'b1;
        end
    end
    
    // Store queue lookup
    for (j = 0; j < NUM_PORTS; j=j+1) begin
        iMask[j] = 0;
        iData[j] = 32'bx;
        for (i = 0; i < NUM_ENTRIES; i=i+1) begin
            if (i0[j].isLoad && entries[i].valid && entries[i].addr == i0[j].addr[31:2] && $signed(entries[i].sqN - i0[j].sqN) < 0) begin
                // this is pretty neat!
                if (entries[i].wmask[0])
                    iData[j][7:0] = entries[i].data[7:0];
                if (entries[i].wmask[1])
                    iData[j][15:8] = entries[i].data[15:8];
                if (entries[i].wmask[2])
                    iData[j][23:16] = entries[i].data[23:16];
                if (entries[i].wmask[3])
                    iData[j][31:24] = entries[i].data[31:24];
                    
                iMask[j] = iMask[j] | entries[i].wmask;
            end
        end
    end
end

reg doingEnqueue;
always_ff@(posedge clk) begin
    
    didCSRwrite <= 0;
    doingEnqueue = 0;

    if (rst) begin
        for (i = 0; i < NUM_ENTRIES; i=i+1) begin
            entries[i].valid <= 0;
        end
        for (i = 0; i < NUM_PORTS; i=i+1) begin
            i0[i].valid <= 0;
            i1[i].valid <= 0;
        end
        baseIndex = 0;
        OUT_maxStoreSqN <= baseIndex + NUM_ENTRIES[5:0] - 1;
        OUT_empty <= 1;
    end
    
    else begin
        
        // Set entries of commited instructions to ready
        for (i = 0; i < NUM_ENTRIES; i=i+1) begin
            if ($signed(IN_curSqN - entries[i].sqN) > 0)
                entries[i].ready <= 1;
        end
        
        // Dequeue
        if (doingDequeue) begin
            for (i = 0; i < NUM_ENTRIES-1; i=i+1)
                entries[i] <= entries[i+1];
                
            entries[NUM_ENTRIES-1].valid <= 0;
            didCSRwrite <= isCsrWrite[0]; 
            baseIndex = baseIndex + 1;
        end
        
        // Invalidate
        else if (IN_branch.taken) begin
            for (i = 0; i < NUM_ENTRIES; i=i+1) begin
                if ($signed(entries[i].sqN - IN_branch.sqN) > 0 && !entries[i].ready)
                    entries[i].valid <= 0;
            end
            
            if (IN_branch.flush)
                baseIndex = IN_branch.storeSqN + 1;
        end
    
        // Enqueue
        for (i = 0; i < NUM_PORTS; i=i+1) begin
            if (IN_uop[i].valid && !IN_uop[i].isLoad && (!IN_branch.taken || $signed(IN_uop[i].sqN - IN_branch.sqN) <= 0) && !IN_uop[i].exception) begin
                reg[$clog2(NUM_ENTRIES)-1:0] index = IN_uop[i].storeSqN[$clog2(NUM_ENTRIES)-1:0] - baseIndex[$clog2(NUM_ENTRIES)-1:0];
                assert(IN_uop[i].storeSqN <= baseIndex + NUM_ENTRIES[5:0] - 1);
                entries[index].valid <= 1;
                entries[index].ready <= 0;
                entries[index].sqN <= IN_uop[i].sqN;
                entries[index].addr <= IN_uop[i].addr[31:2];
                entries[index].data <= IN_uop[i].data;
                entries[index].wmask <= IN_uop[i].wmask;
                doingEnqueue = 1;
            end
        end
        
        for (i = 0; i < NUM_PORTS; i=i+1) begin
            if (IN_uop[i].valid && (!IN_branch.taken || $signed(IN_uop[i].sqN - IN_branch.sqN) <= 0)) begin
                i0[i] <= IN_uop[i];
                i0_isCsrRead[i] <= isCsrRead[i];
            end
            else
                i0[i].valid <= 0;
                
            if (i0[i].valid && (!IN_branch.taken || $signed(i0[i].sqN - IN_branch.sqN) <= 0)) begin
                if (i0[i].isLoad) begin
                    queueLookupData[i] <= iData[i];
                    queueLookupMask[i] <= iMask[i];
                end
                i1[i] <= i0[i];
                i1_isCsrRead[i] <= i0_isCsrRead[i];
            end
            else
                i1[i].valid <= 0;
        end
        
        OUT_empty <= empty && !doingEnqueue;
        OUT_maxStoreSqN <= baseIndex + NUM_ENTRIES[5:0] - 1;
    end
    
end


endmodule
