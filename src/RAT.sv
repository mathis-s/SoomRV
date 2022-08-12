

typedef struct packed
{
    bit avail;    //[38]
    bit[5:0] tag; //[37:32]
    bit[31:0] value;
} RATEntry;

module RAT
#(
    parameter WIDTH_RD = 2,
    parameter WIDTH_WR = 1
)
(
    input wire clk,
    input wire rst,

    input wire[4:0] rdRegNm[WIDTH_RD-1:0],
    input wire[4:0] wrRegNm[WIDTH_WR-1:0],

    // actual writeback
    input wire[31:0] wbResult[WIDTH_WR-1:0],
    input wire wbValid[WIDTH_WR-1:0],
    input wire[4:0] wbRegNm[WIDTH_WR-1:0],

    output reg[31:0] rdRegValue[WIDTH_RD-1:0],
    output reg[5:0] rdRegTag[WIDTH_RD-1:0],
    output reg[5:0] wrRegTag[WIDTH_WR-1:0]
);
RATEntry rat[31:0];
RATEntry temp;
integer i;

bit[5:0] tagCnt;

always@(*) begin
    for (i = 0; i < WIDTH_RD; i=i+1) begin
        temp = rat[rdRegNm[i]];
        rdRegValue[i] = temp.value;
        rdRegTag[i] = temp.avail ? 0 : temp.tag;
    end
end

// note: ROB has to consider order when multiple instructions
// that write to the same register are committed. Later wbs have prio.
always@(posedge clk) begin
    if (rst) begin
        tagCnt <= 1;
        // set all regs as avail on rst
        for (i = 0; i < 32; i++)
            rat[i].avail <= 1;
    end
    else begin
        // Commit results from ROB.
        for (i = 0; i < WIDTH_WR; i=i+1) begin
            if (wbValid[i] && (wbRegNm[i] != 0)) begin
                // iverilog gives up here unless using explicit indexing.
                //rat[wbRegNm[i]].value <= wbResult[i];
                rat[wbRegNm[i]].value <= wbResult[i];
                rat[wbRegNm[i]].avail = 1; // blocking as might be undone
            end
        end

        // Mark regs used by newly issued instructions as unavailable/pending.
        for (i = 0; i < WIDTH_WR; i=i+1) begin
            if (wrRegNm[i] != 0) begin
                rat[wrRegNm[i]].avail = 0;
                rat[wrRegNm[i]].tag <= wrRegTag[i];
            end
        end

        // Set tags for next instruction(s) and increment tagCnt
        for (i = 0; i < WIDTH_WR; i=i+1) begin
            wrRegTag[i] <= (tagCnt + i[5:0]);
        end

        // need to handle this better, maybe just have
        // an extra bit for invalid instead of zero.
        if (tagCnt == 63)
            tagCnt <= 1;
        else
            tagCnt <= tagCnt + WIDTH_WR[5:0];
    end
    
end
endmodule