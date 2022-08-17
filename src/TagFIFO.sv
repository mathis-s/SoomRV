module TagFIFO
#(
    parameter IN_WIDTH=1,
    parameter OUT_WIDTH=1,
    parameter SIZE=32
)
(
    input wire clk,
    input wire rst,

    input wire IN_tagValid[IN_WIDTH-1:0],
    input wire[5:0] IN_tag[IN_WIDTH-1:0],

    input wire IN_tagUsed[OUT_WIDTH-1:0],
    output reg OUT_tag[OUT_WIDTH-1:0]
);

integer i;


reg[4:0] insertIndex;
reg[4:0] outIndex;
bit[5:0] tags[SIZE-1:0];

always@(posedge clk) begin
    if (rst) begin
        insertIndex = 0;
        outIndex = 0;

        for (i = 0; i < SIZE; i=i+1) begin
            tags[i] <= i[5:0] + 32;
        end
    end
    else begin
        // TODO: make sure to stall frontend when FIFO is empty (insertIndex == outIndex)
        for (i = 0; i < IN_WIDTH; i=i+1) begin
            if (IN_tagValid[i]) begin
                tags[insertIndex] <= IN_tag[i];
                insertIndex = insertIndex + 1;
            end
        end

        for (i = 0; i < IN_WIDTH; i=i+1) begin
            if (IN_tagUsed[i]) begin
                OUT_tag[i] <= tags[outIndex];
                outIndex = outIndex + 1;
            end
        end
    end
end

endmodule