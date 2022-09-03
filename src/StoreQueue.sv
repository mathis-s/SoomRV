typedef struct packed
{
    bit valid;
    bit[5:0] sqN;
    bit[29:0] addr;
    bit[31:0] data;
    bit[3:0] wmask;
} SQEntry;

module LSU
#(
    parameter NUM_PORTS=1,
    parameter NUM_ENTRIES=8
)
(
    input wire clk,
    input wire rst,
    
    input wire IN_valid[NUM_PORTS-1:0],
    input wire IN_isLoad[NUM_PORTS-1:0],
    input wire[31:0] IN_addr[NUM_PORTS-1:0],
    input wire[31:0] IN_data[NUM_PORTS-1:0],
    input wire[31:0] IN_wmask[NUM_PORTS-1:0],
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
    
    output wire OUT_data[NUM_PORTS-1:0]
);

integer i;
integer j;

SQEntry entries[NUM_ENTRIES-1:0];

reg[5:0] baseIndex;

reg[31:0] iValid;
reg[31:0] iAddr;

reg doingDequeue;

// intermediate 
reg[29:0] iAddr;
reg[5:0] iSqN;
reg[3:0] iMask;
reg[31:0] iData;


reg[31:0] queueLookupData;
reg[3:0] queueLookupMask;

assign OUT_data = 
{
    queueLookupMask[3] ? queueLookupData[31:24] : IN_MEM_data[31:24],
    queueLookupMask[2] ? queueLookupData[23:16] : IN_MEM_data[23:16],
    queueLookupMask[1] ? queueLookupData[15:8] : IN_MEM_data[15:8],
    queueLookupMask[0] ? queueLookupData[7:0] : IN_MEM_data[7:0]
};


// Handle Loads combinatorially (SRAM input is registered)
always_comb begin
    doingDequeue = 0;
    iMask = 0;
    iData = 32'bx;
    
    for (i = 0; i < NUM_PORTS; i=i+1) begin
        if (!rst && IN_valid[i] && IN_isLoad[i] && (!IN_branch.taken || $signed(IN_sqN[i] - IN_branch.sqN) <= 0)) begin
            OUT_MEM_addr[i] = IN_addr[i];
            OUT_MEM_we[i] = 1;
            OUT_MEM_wm[i] = 4'bx;
            OUT_MEM_ce[i] = 0;
        end
        
        // Port 0 handles stores as well
        else if (!rst && i == 0 && entries[0].valid && !IN_branch.taken) begin
            doingDequeue = 1;
            OUT_MEM_data[i] <= entries[0].data;
            OUT_MEM_addr[i] <= entries[0].addr;
            OUT_MEM_ce[i] <= 0;
            OUT_MEM_we[i] <= 0;
            OUT_MEM_wm[i] <= entries[0].wmask;
        end
        
        else begin
            OUT_MEM_data[i] = 32'bx;
            OUT_MEM_addr[i] = 32'bx;
            OUT_MEM_we[i] = 1'b1;
            OUT_MEM_ce[i] = 1'b1;
            OUT_MEM_wm[i] = 4'bx;
        end
    end
    
    // Store queue lookup
    for (i = 0; i < NUM_ENTRIES; i=i+1) begin
        if (entries[i].valid && entries[i].addr == iAddr && $signed(entries[i].sqN - iSqN) < 0) begin
            
            // this is pretty neat!
            if (entries[i].wmask[0])
                iData[7:0] = entries[i].data[7:0];
            if (entries[i].wmask[1])
                iData[15:8] = entries[i].data[15:8];
            if (entries[i].wmask[2])
                iData[23:16] = entries[i].data[23:16];
            if (entries[i].wmask[3])
                iData[31:24] = entries[i].data[31:24];
                
            iMask = iMask | entries[i].wmask;
        end
    end
end


always_ff@(posedge clk) begin
    if (rst) begin
        for (i = 0; i < NUM_ENTRIES; i=i+1) begin
            entries[i].valid <= 0;
        end
        baseIndex = 0;
    end
    
    else begin
        // Dequeue
        if (doingDequeue) begin
            for (i = 0; i < NUM_ENTRIES-1; i=i+1)
                entries[i] <= entries[i+1];
                
            entries[i+1].valid <= 0;
            baseIndex = baseIndex + 1;
        end
        
        // Invalidate
        else if (IN_branch.taken) begin
            for (i = 0; i < NUM_ENTRIES; i=i+1) begin
                if (entries[i].valid && $signed(entries[i].sqN - IN_branch.sqN) > 0)
                    entries[i].valid <= 0;
            end
            
            // TODO: is this even possible?
            if ($signed(baseIndex - IN_branchStoreSqN) > 0)
                baseIndex = IN_branchStoreSqN;
        end
    
        // Enqueue
        for (i = 0; i < NUM_PORTS; i=i+1) begin
            if (IN_valid[i] && !IN_isLoad[i] && (!IN_branch.taken || $signed(IN_sqN[i] - IN_branch.sqN) <= 0)) begin
                reg[2:0] index = IN_storeSqN[2:0] - baseIndex[2:0];
                assert(!entries[index].valid);
                entries[index].valid <= 1;
                entries[index].sqN <= IN_sqN[i];
                entries[index].addr <= IN_addr[i][31:2];
                entries[index].data <= IN_data[i];
                entries[index].wmask <= IN_wmask[i];
            end
        end
        
        queueLookupData <= iData;
        queueLookupMask <= iMask;
    end
end


endmodule
