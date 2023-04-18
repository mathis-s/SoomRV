typedef struct packed
{
    bit valid;
    SqN sqN;
    bit[1:0] size;
    bit[31:0] addr;
} LBEntry;

module LoadBuffer
#(
    parameter NUM_PORTS=2,
    parameter NUM_ENTRIES=`LB_SIZE
)
(
    input wire clk,
    input wire rst,
    
    input SqN commitSqN,
    
    input wire IN_stall[1:0],
    input AGU_UOp IN_uopLd,
    input AGU_UOp IN_uopSt,
    
    input BranchProv IN_branch,
    output BranchProv OUT_branch,
    
    output SqN OUT_maxLoadSqN
);

integer i;

LBEntry entries[NUM_ENTRIES-1:0];

SqN baseIndex;
SqN indexIn;

logic storeIsCollision;
always_comb begin
    storeIsCollision = 0;

    for (i = 0; i < NUM_ENTRIES; i=i+1) begin
        if (entries[i].valid &&
            $signed(IN_uopSt.sqN - entries[i].sqN) <= 0 &&
            entries[i].addr[31:2] == IN_uopSt.addr[31:2] &&
                (entries[i].size == 2 ||
                (entries[i].size == 1 && entries[i].addr[1] == IN_uopSt.addr[1]) ||
                (entries[i].size == 0 && entries[i].addr[1:0] == IN_uopSt.addr[1:0]))
            ) begin
            storeIsCollision = 1;
        end
    end

    if (IN_uopLd.valid && !IN_stall[0] &&
        $signed(IN_uopSt.sqN - IN_uopLd.sqN) <= 0 &&
        IN_uopLd.addr[31:2] == IN_uopSt.addr[31:2] &&
            (IN_uopLd.size == 2 ||
            (IN_uopLd.size == 1 && IN_uopLd.addr[1] == IN_uopSt.addr[1]) ||
            (IN_uopLd.size == 0 && IN_uopLd.addr[1:0] == IN_uopSt.addr[1:0]))
        )
        storeIsCollision = 1;
end

always_ff@(posedge clk) begin
    
    OUT_branch <= 'x;
    OUT_branch.taken <= 0;

    if (rst) begin
        for (i = 0; i < NUM_ENTRIES; i=i+1) begin
            entries[i].valid <= 0;
        end
        baseIndex = 0;
        OUT_maxLoadSqN <= baseIndex + NUM_ENTRIES[$bits(SqN)-1:0] - 1;
    end
    else begin
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
        if (!IN_stall[0] && IN_uopLd.valid && (!IN_branch.taken || $signed(IN_uopLd.sqN - IN_branch.sqN) <= 0)) begin

            reg[$clog2(NUM_ENTRIES)-1:0] index = IN_uopLd.loadSqN[$clog2(NUM_ENTRIES)-1:0] - baseIndex[$clog2(NUM_ENTRIES)-1:0];
            assert(IN_uopLd.loadSqN <= baseIndex + NUM_ENTRIES - 1);
            entries[index].sqN <= IN_uopLd.sqN;
            entries[index].addr <= IN_uopLd.addr;
            entries[index].size <= IN_uopLd.size;
            entries[index].valid <= 1;
        end
        
        if (!IN_stall[1] && IN_uopSt.valid && (!IN_branch.taken || $signed(IN_uopSt.sqN - IN_branch.sqN) <= 0)) begin
            if (storeIsCollision) begin
                OUT_branch.taken <= 1;
                OUT_branch.dstPC <= IN_uopSt.pc + (IN_uopSt.compressed ? 2 : 4);
                OUT_branch.sqN <= IN_uopSt.sqN;
                OUT_branch.loadSqN <= IN_uopSt.loadSqN;
                OUT_branch.storeSqN <= IN_uopSt.storeSqN;
                OUT_branch.fetchID <= IN_uopSt.fetchID;
                OUT_branch.history <= IN_uopSt.history;
                OUT_branch.rIdx <= IN_uopSt.rIdx;
                OUT_branch.flush <= 0;
            end
        end
        
        OUT_maxLoadSqN <= baseIndex + NUM_ENTRIES[$bits(SqN)-1:0] - 1;
    end

end

endmodule
