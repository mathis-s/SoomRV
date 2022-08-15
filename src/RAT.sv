

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
    input wire en,
    input wire rst,

    input wire[4:0] rdRegNm[WIDTH_RD-1:0],
    input wire[4:0] wrRegNm[WIDTH_WR-1:0],

    // actual writeback
    input wire[31:0] wbResult[WIDTH_WR-1:0],
    input wire wbValid[WIDTH_WR-1:0],
    input wire[4:0] wbRegNm[WIDTH_WR-1:0],
    input wire[5:0] wbRegTag[WIDTH_WR-1:0],

    input wire IN_branchTaken,
    input wire[5:0] IN_branchTag,

    output reg[31:0] rdRegValue[WIDTH_RD-1:0],
    output reg[5:0] rdRegTag[WIDTH_RD-1:0],
    output reg rdRegAvail[WIDTH_RD-1:0],
    output reg[5:0] wrRegTag[WIDTH_WR-1:0]
);
RATEntry rat[31:0];
integer i;

bit[5:0] tagCnt;

always_comb begin
    for (i = 0; i < WIDTH_RD; i=i+1) begin
        rdRegValue[i] = rat[rdRegNm[i]].value;
        rdRegTag[i] = rat[rdRegNm[i]].tag;
        rdRegAvail[i] = rat[rdRegNm[i]].avail;
    end
end

// note: ROB has to consider order when multiple instructions
// that write to the same register are committed. Later wbs have prio.
always_ff@(posedge clk) begin

    if (!rst && !IN_branchTaken) begin
        // Commit results from ROB.
        for (i = 0; i < WIDTH_WR; i=i+1) begin
            if (wbValid[i] && (wbRegNm[i] != 0)) begin
                rat[wbRegNm[i]].value <= wbResult[i];
                // The entry is only valid if the wb tag is unchanged from
                // when this instruction was issued, otherwise another
                // instruction is already issued to change the reg again.
                if (wbRegTag[i] == rat[wbRegNm[i]].tag)
                    rat[wbRegNm[i]].avail = 1; // blocking as might be undone
            end
        end
    end

    if (rst) begin
        tagCnt <= WIDTH_WR;
        // set all regs as avail on rst
        for (i = 0; i < 32; i=i+1)
            rat[i].avail <= 1;
        for (i = 0; i < WIDTH_WR; i=i+1)
            wrRegTag[i] <= i[5:0];
    end
    else if (IN_branchTaken) begin
        tagCnt <= IN_branchTag + 1 + WIDTH_WR;
        for (i = 0; i < WIDTH_WR; i=i+1) begin
            wrRegTag[i] <= (IN_branchTag + i[5:0] + 1);
        end
    end
    else if (en) begin
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
        tagCnt <= tagCnt + WIDTH_WR[5:0];
    end
    
end
endmodule