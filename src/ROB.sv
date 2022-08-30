
typedef struct packed 
{
    bit valid;
    bit flags;
    bit[5:0] tag;
    // for debugging
    bit[5:0] sqN;
    bit[4:0] name;
} ROBEntry;

module ROB
#(
    // how many entries, ie how many instructions can we
    // speculatively execute?
    parameter LENGTH = 16,
    // how many ops are en/dequeued per cycle?
    parameter WIDTH = 2
)
(
    input wire clk,
    input wire rst,

    input wire IN_valid[WIDTH-1:0],
    input wire[5:0] IN_tags[WIDTH-1:0],
    input wire[4:0] IN_names[WIDTH-1:0],
    input wire[5:0] IN_sqNs[WIDTH-1:0],
    input wire IN_flags[WIDTH-1:0],

    input wire IN_invalidate,
    input wire[5:0] IN_invalidateSqN,

    output wire[5:0] OUT_maxSqN,
    output wire[5:0] OUT_curSqN,

    output reg[4:0] OUT_comNames[WIDTH-1:0],
    output reg[5:0] OUT_comTags[WIDTH-1:0],
    output reg[5:0] OUT_comSqNs[WIDTH-1:0],
    output reg OUT_comValid[WIDTH-1:0],
    
    output reg OUT_halt
);

ROBEntry entries[LENGTH-1:0];
reg[5:0] baseIndex;

assign OUT_maxSqN = baseIndex + LENGTH - 1;
assign OUT_curSqN = baseIndex;

integer i;
integer j;

reg headValid;
always_comb begin
    headValid = 1;
    for (i = 0; i < WIDTH; i=i+1) begin
        if (!entries[i].valid || entries[i].flags != 0)
            headValid = 0;
    end
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

    if (rst) begin
        OUT_halt <= 0;
        baseIndex = 0;
        for (i = 0; i < LENGTH; i=i+1) begin
            entries[i].valid <= 0;
        end
        for (i = 0; i < WIDTH; i=i+1) begin
            OUT_comValid[i] <= 0;
        end
    end
    else if (IN_invalidate) begin
        for (i = 0; i < LENGTH; i=i+1) begin
            if ($signed((baseIndex + i[5:0]) - IN_invalidateSqN) > 0) begin
                entries[i].valid <= 0;
            end
        end
        if ($signed(baseIndex - IN_invalidateSqN) > 0)
            baseIndex = IN_invalidateSqN;
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

            for (i = 0; i < WIDTH; i=i+1) begin
                OUT_comNames[i] <= entries[i].name;
                OUT_comTags[i] <= entries[i].tag;
                OUT_comSqNs[i] <= baseIndex + i[5:0];
                OUT_comValid[i] <= 1;
                // TODO: handle exceptions here.
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
                OUT_comValid[i] <= 1;
                if (entries[i].flags != 0)
                    OUT_halt <= 1;
            end
            for (i = 1; i < WIDTH; i=i+1) begin
                OUT_comValid[i] <= 0;
            end
            // Blocking for proper insertion
            baseIndex = baseIndex + 1;
            
            /*OUT_comNames[0] <= entries[0].name;
            OUT_comTags[0] <= entries[0].tag;
            OUT_comSqNs[0] <= baseIndex;
            OUT_comValid[0] <= 1;
            
            entries[0].valid <= 0;
            
            for (i = 1; i < WIDTH; i=i+1)
                OUT_comValid[i] <= 0;
                
            baseIndex = baseIndex + 1;*/
        end
        else begin
            for (i = 0; i < WIDTH; i=i+1)
                OUT_comValid[i] <= 0;
        end

        // Enqueue if entries are unused (or if we just dequeued, which frees space).
        for (i = 0; i < WIDTH; i=i+1) begin
            if (IN_valid[i] && (!IN_invalidate || $signed(IN_sqNs[i] - IN_invalidateSqN) <= 0)) begin
                entries[IN_sqNs[i][3:0] - baseIndex[3:0]].valid <= 1;
                entries[IN_sqNs[i][3:0] - baseIndex[3:0]].flags <= IN_flags[i];
                entries[IN_sqNs[i][3:0] - baseIndex[3:0]].tag <= IN_tags[i];
                entries[IN_sqNs[i][3:0] - baseIndex[3:0]].name <= IN_names[i];
                entries[IN_sqNs[i][3:0] - baseIndex[3:0]].sqN <= IN_sqNs[i];
            end
        end
    end
end


endmodule
