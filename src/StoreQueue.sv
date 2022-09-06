typedef struct packed
{
    bit valid;
    bit[5:0] sqN;
    bit[29:0] addr;
    bit[31:0] data;
    bit[3:0] wmask;
} SQEntry;

module StoreQueue
#(
    parameter NUM_PORTS=1,
    parameter NUM_ENTRIES=8
)
(
    input wire clk,
    input wire rst,
    
    input wire IN_valid[NUM_PORTS-1:0],
    input wire IN_isLoad[NUM_PORTS-1:0],
    input wire[29:0] IN_addr[NUM_PORTS-1:0],
    input wire[31:0] IN_data[NUM_PORTS-1:0],
    input wire[3:0] IN_wmask[NUM_PORTS-1:0],
    input wire[5:0] IN_sqN[NUM_PORTS-1:0],
    input wire[5:0] IN_storeSqN[NUM_PORTS-1:0],
    
    input wire[5:0] IN_curSqN,
    
    input BranchProv IN_branch,
    
    input wire[31:0] IN_MEM_data[NUM_PORTS-1:0],
    output reg[29:0] OUT_MEM_addr[NUM_PORTS-1:0],
    output reg[31:0] OUT_MEM_data[NUM_PORTS-1:0],
    output reg OUT_MEM_we[NUM_PORTS-1:0],
    output reg OUT_MEM_ce[NUM_PORTS-1:0],
    output reg[3:0] OUT_MEM_wm[NUM_PORTS-1:0],
    
    output reg[31:0] OUT_data[NUM_PORTS-1:0],
    output reg[5:0] OUT_maxStoreSqN
);

integer i;
integer j;

SQEntry entries[NUM_ENTRIES-1:0];

reg[5:0] baseIndex;

reg doingDequeue;

// intermediate 
reg[29:0] iAddr[NUM_PORTS-1:0];
reg[5:0] iSqN[NUM_PORTS-1:0];
reg[3:0] iMask[NUM_PORTS-1:0];
reg[31:0] iData[NUM_PORTS-1:0];


reg[31:0] queueLookupData[NUM_PORTS-1:0];
reg[3:0] queueLookupMask[NUM_PORTS-1:0];

always_comb begin
    for (i = 0; i < NUM_PORTS; i=i+1) begin
        OUT_data[i][31:24] = queueLookupMask[i][3] ? queueLookupData[i][31:24] : IN_MEM_data[i][31:24];
        OUT_data[i][23:16] = queueLookupMask[i][2] ? queueLookupData[i][23:16] : IN_MEM_data[i][23:16];
        OUT_data[i][15:8] = queueLookupMask[i][1] ? queueLookupData[i][15:8] : IN_MEM_data[i][15:8];
        OUT_data[i][7:0] = queueLookupMask[i][0] ? queueLookupData[i][7:0] : IN_MEM_data[i][7:0];
    end
end


// Handle Loads combinatorially (SRAM input is registered)
always_comb begin
    doingDequeue = 0;
    
    for (i = 0; i < NUM_PORTS; i=i+1) begin
        if (!rst && IN_valid[i] && IN_isLoad[i] && (!IN_branch.taken || $signed(IN_sqN[i] - IN_branch.sqN) <= 0)) begin
            OUT_MEM_data[i] = 32'bx;
            OUT_MEM_addr[i] = IN_addr[i];
            OUT_MEM_we[i] = 1;
            OUT_MEM_wm[i] = 4'bx;
            OUT_MEM_ce[i] = 0;
        end
        
        // Port 0 handles stores as well
        else if (!rst && i == 0 && entries[0].valid && !IN_branch.taken && $signed(IN_curSqN - entries[0].sqN) > 0) begin
            doingDequeue = 1;
            OUT_MEM_data[i] = entries[0].data;
            OUT_MEM_addr[i] = entries[0].addr;
            OUT_MEM_ce[i] = 0;
            OUT_MEM_we[i] = 0;
            OUT_MEM_wm[i] = entries[0].wmask;
        end
        
        else begin
            OUT_MEM_data[i] = 32'bx;
            OUT_MEM_addr[i] = 30'bx;
            OUT_MEM_we[i] = 1'b1;
            OUT_MEM_ce[i] = 1'b1;
            OUT_MEM_wm[i] = 4'bx;
        end
    end
    
    // Store queue lookup
    for (j = 0; j < NUM_PORTS; j=j+1) begin
        iMask[j] = 0;
        iData[j] = 32'bx;
        for (i = 0; i < NUM_ENTRIES; i=i+1) begin
            if (entries[i].valid && entries[i].addr == iAddr[j] && $signed(entries[i].sqN - iSqN[j]) < 0) begin
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


always_ff@(posedge clk) begin
    if (rst) begin
        for (i = 0; i < NUM_ENTRIES; i=i+1) begin
            entries[i].valid <= 0;
        end
        baseIndex = 0;
        OUT_maxStoreSqN <= 0;
    end
    
    else begin
        // Dequeue
        if (doingDequeue) begin
            for (i = 0; i < NUM_ENTRIES-1; i=i+1)
                entries[i] <= entries[i+1];
                
            entries[NUM_ENTRIES-1].valid <= 0;
            baseIndex = baseIndex + 1;
        end
        
        // Invalidate
        else if (IN_branch.taken) begin
            for (i = 0; i < NUM_ENTRIES; i=i+1) begin
                if ($signed(entries[i].sqN - IN_branch.sqN) > 0)
                    entries[i].valid <= 0;
            end
            
            // TODO: is this even possible?
            //if ($signed(baseIndex - IN_branch.storeSqN) > 0)
            //    baseIndex = IN_branch.storeSqN;
        end
    
        // Enqueue
        for (i = 0; i < NUM_PORTS; i=i+1) begin
            if (IN_valid[i] && !IN_isLoad[i] && (!IN_branch.taken || $signed(IN_sqN[i] - IN_branch.sqN) <= 0)) begin
                reg[2:0] index = IN_storeSqN[i][2:0] - baseIndex[2:0];
                assert(IN_storeSqN[i] <= baseIndex + NUM_ENTRIES[5:0] - 1);
                //assert(!entries[index].valid);
                entries[index].valid <= 1;
                entries[index].sqN <= IN_sqN[i];
                entries[index].addr <= IN_addr[i];
                entries[index].data <= IN_data[i];
                entries[index].wmask <= IN_wmask[i];
            end
        end
        
        for (i = 0; i < NUM_PORTS; i=i+1) begin
            iAddr[i] <= IN_addr[i];
            iSqN[i] <= IN_sqN[i];
            queueLookupData[i] <= iData[i];
            queueLookupMask[i] <= iMask[i];
        end
        
        OUT_maxStoreSqN <= baseIndex + NUM_ENTRIES[5:0] - 1;
    end
    
end


endmodule
