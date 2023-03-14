typedef struct packed
{
    bit valid;
    SqN sqN;
    bit[29:0] addr;
} LBEntry;

module LoadBuffer
#(
    parameter NUM_PORTS=2,
    parameter NUM_ENTRIES=16
)
(
    input wire clk,
    input wire rst,
    
    input SqN commitSqN,
    
    input wire IN_stall[1:0],
    input AGU_UOp IN_uop[NUM_PORTS-1:0],
    
    input BranchProv IN_branch,
    output BranchProv OUT_branch,
    
    output SqN OUT_maxLoadSqN
);

integer i;
integer j;

LBEntry entries[NUM_ENTRIES-1:0];

SqN baseIndex;
SqN indexIn;

reg mispredict[NUM_PORTS-1:0];

always_ff@(posedge clk) begin

    if (rst) begin
        for (i = 0; i < NUM_ENTRIES; i=i+1) begin
            entries[i].valid <= 0;
        end
        baseIndex = 0;
        OUT_branch.taken <= 0;
        OUT_maxLoadSqN <= baseIndex + NUM_ENTRIES[6:0] - 1;
    end
    else begin
    
        OUT_branch.taken <= 0;
        
        if (IN_branch.taken) begin
            for (i = 0; i < NUM_ENTRIES; i=i+1) begin
                if ($signed(entries[i].sqN - IN_branch.sqN) >= 0)
                    entries[i].valid <= 0;
            end
            
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
            if (!IN_stall[i] && IN_uop[i].valid && (!IN_branch.taken || $signed(IN_uop[i].sqN - IN_branch.sqN) <= 0)) begin
            
                if (i == 0) begin
                    reg[$clog2(NUM_ENTRIES)-1:0] index = IN_uop[i].loadSqN[$clog2(NUM_ENTRIES)-1:0] - baseIndex[$clog2(NUM_ENTRIES)-1:0];
                    assert(IN_uop[i].loadSqN <= baseIndex + NUM_ENTRIES - 1);
                    
                    //mispredict[i] <= 0;

                    entries[index].sqN <= IN_uop[i].sqN;
                    entries[index].addr <= IN_uop[i].addr[31:2];
                    entries[index].valid <= 1;
                end
                
                else if (i == 1 && IN_uop[1].wmask != 0) begin
                    reg temp = 0;
                    for (j = 0; j < NUM_ENTRIES; j=j+1) begin
                        if (entries[j].valid && entries[j].addr == IN_uop[i].addr[31:2] && $signed(IN_uop[i].sqN - entries[j].sqN) <= 0) begin
                            temp = 1;
                        end
                    end
                    
                    // TODO: Delay SQ lookup by one cycle instead of this.
                    if (IN_uop[0].valid && !IN_stall[0] && $signed(IN_uop[1].sqN - IN_uop[0].sqN) <= 0
                        && IN_uop[0].addr[31:2] == IN_uop[1].addr[31:2])
                        temp = 1;
                    
                    if (temp) begin
                        OUT_branch.taken <= 1;
                        OUT_branch.dstPC <= IN_uop[i].pc + (IN_uop[i].compressed ? 2 : 4);
                        OUT_branch.sqN <= IN_uop[i].sqN;
                        OUT_branch.loadSqN <= IN_uop[i].loadSqN;
                        OUT_branch.storeSqN <= IN_uop[i].storeSqN;
                        OUT_branch.fetchID <= IN_uop[i].fetchID;
                        OUT_branch.history <= IN_uop[i].history;
                        OUT_branch.flush <= 0;
                    end
                end
            end
        end
        
        OUT_maxLoadSqN <= baseIndex + NUM_ENTRIES[6:0] - 1;
    end

end

endmodule
