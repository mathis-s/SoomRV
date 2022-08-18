
typedef struct packed 
{
    bit valid;
    bit flags;
    bit[5:0] tag;
    bit[5:0] sqN;
    bit[4:0] name;
} ROBEntry;

module ROB
#(
    // how many entries, ie how many instructions can we
    // speculatively execute?
    parameter LENGTH = 8,
    // how many ops are en/dequeued per cycle?
    parameter WIDTH = 1
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

    input wire IN_maxCommitSqNValid,
    input wire[5:0] IN_maxCommitSqN,

    output wire[5:0] OUT_maxTag,

    output reg[4:0] OUT_comNames[WIDTH-1:0],
    output reg[5:0] OUT_comTags[WIDTH-1:0],
    output reg OUT_comValid[WIDTH-1:0]
);

ROBEntry entries[LENGTH-1:0];
reg[5:0] baseIndex;

assign OUT_maxTag = baseIndex + LENGTH - 1;

integer i;
integer j;

reg headValid;
always_comb begin
    headValid = 1;
    for (i = 0; i < WIDTH; i=i+1) begin
        if (!entries[i].valid || (IN_maxCommitSqNValid && $signed(entries[i].sqN - IN_maxCommitSqN) > 0))
            headValid = 0;
    end
end

wire doDequeue = headValid; // placeholder
always_ff@(posedge clk) begin

    if (rst) begin
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
            if ($signed((i[5:0] + baseIndex) - IN_invalidateSqN) > 0) begin
                entries[i].valid <= 0;
            end
        end
        if ($signed(baseIndex - IN_invalidateSqN) > 0)
            baseIndex = IN_invalidateSqN;
        for (i = 0; i < WIDTH; i=i+1) begin
            OUT_comValid[i] <= 0;
        end
    end
    else begin
        // Dequeue and push forward fifo entries
        if (doDequeue) begin
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
                OUT_comValid[i] <= entries[i].valid;
                // TODO: handle exceptions here.
            end
            // Blocking for proper insertion
            baseIndex = baseIndex + WIDTH;
        end
        else begin
            for (i = 0; i < WIDTH; i=i+1)
                OUT_comValid[i] <= 0;
        end

        // Enqueue if entries are unused (or if we just dequeued, which frees space).
        for (i = 0; i < WIDTH; i=i+1) begin
            if (IN_valid[i]) begin
                entries[{IN_sqNs[i][5:0] - baseIndex[5:0]}[2:0]].valid <= 1;
                entries[{IN_sqNs[i][5:0] - baseIndex[5:0]}[2:0]].flags <= 0;
                entries[{IN_sqNs[i][5:0] - baseIndex[5:0]}[2:0]].tag <= IN_tags[i];
                entries[{IN_sqNs[i][5:0] - baseIndex[5:0]}[2:0]].name <= IN_names[i];
                entries[{IN_sqNs[i][5:0] - baseIndex[5:0]}[2:0]].sqN <= IN_sqNs[i];
            end
        end
    end
end


endmodule