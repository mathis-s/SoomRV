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
    input wire[31:0] addr[NUM_PORTS-1:0],
    input wire[5:0] sqN[NUM_PORTS-1:0],
    
    output reg mispredict[NUM_PORTS-1:0],
    
    output wire full
);

assign full = 0; // placeholder

integer i;
integer j;

LBEntry entries[NUM_ENTRIES-1:0];

reg[2:0] freeIndicies[NUM_PORTS-1:0];
reg freeFound[NUM_PORTS-1:0];
reg[2:0] searchIndicies[NUM_PORTS-1:0];
reg searchFound[NUM_PORTS-1:0];

always_comb begin
    for (i = 0; i < NUM_PORTS; i=i+1) begin

        // Find free indicies
        freeIndicies[i] = 0;
        freeFound[i] = 0;
        for (j = 0; j < NUM_ENTRIES; j=j+1) begin
            if (!entries[j].valid && (i == 0 || (j[2:0] != freeIndicies[0]))) begin
                freeIndicies[i] = j[2:0];
                freeFound[i] = 1;
            end
        end
        
        // Try to find address
        // TODO: One-hot here
        searchIndicies[i] = 0;
        searchFound[i] = 0;
        for (j = 0; j < NUM_ENTRIES; j=j+1) begin
            if (entries[j].valid && entries[j].addr == addr[i][31:2]) begin
                searchFound[i] = 1;
                searchIndicies[i] = j[2:0];
            end
        end
    
    end
end

always_ff@(posedge clk) begin

    if (rst) begin
        for (i = 0; i < NUM_ENTRIES; i=i+1) begin
            entries[i].valid <= 0;
        end
    end
    else begin
        
        // Delete entries that have been committed
        for (i = 0; i < NUM_ENTRIES; i=i+1) begin
            if (entries[i].valid && $signed(commitSqN - entries[i].sqN) > 0)
                entries[i].valid <= 0;
        end
    
    
        // Insert new entries, check stores
        for (i = 0; i < NUM_PORTS; i=i+1) begin
            if (valid[i]) begin
            
                if (isLoad[i]) begin
                
                    mispredict[i] <= 0;
                    
                    if (searchFound[i]) begin
                        if ($signed(sqN[i] - entries[searchIndicies[i]].sqN) > 0) begin
                            entries[searchIndicies[i]].sqN <= sqN[i];
                            entries[searchIndicies[i]].valid <= 1;
                            // NOTE: make sure that this is valid if eg the same sqn is commited in this cycle
                        end
                    end
                    else begin
                        // TODO: Make sure no loads are issued when this buffer is full!
                        assert(freeFound[i]);
                        entries[freeIndicies[i]].sqN <= sqN[i];
                        entries[freeIndicies[i]].addr <= addr[i][31:2];
                        entries[freeIndicies[i]].valid <= 1;
                    end
                end
                
                else begin
                    if (searchFound[i] && $signed(sqN[i] - entries[searchIndicies[i]].sqN) <= 0) begin
                        mispredict[i] <= 1;
                    end
                end
            end
            else
                mispredict[i] <= 0;
        end
    end

end

endmodule
