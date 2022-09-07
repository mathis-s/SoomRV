typedef struct packed
{
    bit valid;
    bit[5:0] sqN;
    bit[29:0] addr;
} LBEntry;

module LoadBuffer
#(
    parameter NUM_PORTS=1,
    parameter NUM_ENTRIES=8
)
(
    input wire clk,
    input wire rst,
    
    input wire[5:0] commitSqN,
    
    input wire valid[NUM_PORTS-1:0],
    input wire isLoad[NUM_PORTS-1:0],
    input wire[31:0] pc[NUM_PORTS-1:0],
    input wire[31:0] addr[NUM_PORTS-1:0],
    input wire[5:0] sqN[NUM_PORTS-1:0],
    input wire[5:0] loadSqN[NUM_PORTS-1:0],
    input wire[5:0] storeSqN[NUM_PORTS-1:0],
    
    input BranchProv IN_branch,
    output BranchProv OUT_branch,
    
    output reg[5:0] OUT_maxLoadSqN
);

integer i;
integer j;

LBEntry entries[NUM_ENTRIES-1:0];

reg[5:0] baseIndex;
reg[5:0] indexIn;

reg mispredict[NUM_PORTS-1:0];

always_ff@(posedge clk) begin

    if (rst) begin
        for (i = 0; i < NUM_ENTRIES; i=i+1) begin
            entries[i].valid <= 0;
        end
        baseIndex = 0;
    end
    else begin
        
        if (IN_branch.taken) begin
            for (i = 0; i < NUM_ENTRIES; i=i+1) begin
                if ($signed(entries[i].sqN - IN_branch.sqN) > 0)
                    entries[i].valid <= 0;
            end
            //if ($signed(baseIndex - IN_branch.loadSqN) > 0)
            //    baseIndex = IN_branch.loadSqN;
            if (IN_branch.flush)
                baseIndex = IN_branch.loadSqN;
        end
        else begin
            // Delete entries that have been committed
            if (entries[0].valid && $signed(commitSqN - entries[0].sqN) > 0) begin
                for (i = 0; i < NUM_ENTRIES-1; i=i+1)
                    entries[i] <= entries[i+1];
                entries[NUM_ENTRIES - 1].valid <= 0;
                
                baseIndex = baseIndex + 1;
            end
        end
    
        // Insert new entries, check stores
        for (i = 0; i < NUM_PORTS; i=i+1) begin
            if (valid[i] && (!IN_branch.taken || $signed(sqN[i] - IN_branch.sqN) <= 0)) begin
            
                if (isLoad[i]) begin
                    reg[2:0] index = loadSqN[i][2:0] - baseIndex[2:0];
                    assert(loadSqN[i] < baseIndex + NUM_ENTRIES);
                    
                    //mispredict[i] <= 0;

                    entries[index].sqN <= sqN[i];
                    entries[index].addr <= addr[i][31:2];
                    entries[index].valid <= 1;
                end
                
                else begin
                    reg temp = 0;
                    for (j = 0; j < NUM_ENTRIES; j=j+1) begin
                        if (entries[j].valid && entries[j].addr == addr[i][31:2] && $signed(sqN[i] - entries[j].sqN) <= 0) begin
                            temp = 1;
                        end
                    end
                    
                    if (temp) begin
                        OUT_branch.taken <= 1;
                        OUT_branch.dstPC <= pc[i];
                        OUT_branch.sqN <= sqN[i];
                        OUT_branch.loadSqN <= loadSqN[i];
                        OUT_branch.storeSqN <= storeSqN[i];
                        OUT_branch.flush <= 0;
                    end
                    else 
                        OUT_branch.taken <= 0;
                end
            end
            else 
                OUT_branch.taken <= 0;
        end
        
        OUT_maxLoadSqN <= baseIndex + NUM_ENTRIES[5:0] - 1;
    end

end

endmodule
