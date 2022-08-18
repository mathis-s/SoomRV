typedef struct packed
{
    bit avail;
    bit[5:0] comTag;
    bit[5:0] specTag;
    bit[5:0] newSqN;
} RATEntry;

module Rename
#(
    parameter WIDTH_UOPS = 1,
    parameter WIDTH_WR = 1,
    parameter FREE_TAG_FIFO_SIZE=32
)
(
    input wire clk,
    input wire en,
    input wire rst,

    // Tag lookup for just decoded instrs
    input D_UOp IN_uop[WIDTH_UOPS-1:0],

    // Committed changes from ROB
    input wire comValid[WIDTH_WR-1:0],
    input wire[4:0] comRegNm[WIDTH_WR-1:0],
    input wire[5:0] comRegTag[WIDTH_WR-1:0],

    // WB for uncommitted but speculatively available values
    input wire IN_wbValid[WIDTH_WR-1:0],
    input wire[5:0] IN_wbTag[WIDTH_WR-1:0],
    input wire[4:0] IN_wbNm[WIDTH_WR-1:0],

    // Taken branch
    input wire IN_branchTaken,
    input wire[5:0] IN_branchSqN,
    input wire IN_mispredFlush,
    
    output reg OUT_uopValid[WIDTH_UOPS-1:0],
    output R_UOp OUT_uop[WIDTH_UOPS-1:0],
    output wire[5:0] OUT_nextSqN
);

reg[4:0] freeTagInsertIndex;
reg[4:0] freeTagOutputIndex;
reg[5:0] freeTags[FREE_TAG_FIFO_SIZE-1:0];

RATEntry rat[31:0];
integer i;

bit[5:0] counterSqN;
assign OUT_nextSqN = counterSqN;

// note: ROB has to consider order when multiple instructions
// that write to the same register are committed. Later wbs have prio.
always_ff@(posedge clk) begin
    if (!rst && !IN_branchTaken) begin
        // Commit results from ROB.
        for (i = 0; i < WIDTH_WR; i=i+1) begin
            if (comValid[i] && (comRegNm[i] != 0)) begin
                freeTags[freeTagInsertIndex] <= rat[comRegNm[i]].comTag;
                freeTagInsertIndex = freeTagInsertIndex + 1;
                
                rat[comRegNm[i]].comTag <= comRegTag[i];

                if (IN_mispredFlush) 
                    rat[comRegNm[i]].specTag <= comRegTag[i];
            end
        end

        // Written back values are speculatively available
        for (i = 0; i < WIDTH_WR; i=i+1) begin
            if (IN_wbValid[i] && rat[IN_wbNm[i]].specTag == IN_wbTag[i]) begin
                rat[IN_wbNm[i]].avail = 1;
            end
        end
    end

    if (rst) begin
        // Free comTag FIFO initialized with tags 32..
        freeTagInsertIndex = 0;
        freeTagOutputIndex = 0;
        for (i = 0; i < FREE_TAG_FIFO_SIZE; i=i+1) begin
            freeTags[i] <= i[5:0] + 32;
        end
        counterSqN <= 0;
        
        // Registers initialized with tags 0..31
        for (i = 0; i < 32; i=i+1) begin
            rat[i].avail <= 1;
            rat[i].comTag <= i[5:0];
            rat[i].specTag <= i[5:0];
        end
        for (i = 0; i < WIDTH_UOPS; i=i+1) begin
            OUT_uop[i].sqN <= i[5:0];
            OUT_uopValid[i] <= 0;
        end
    end
    else if (IN_branchTaken) begin
        
        counterSqN <= IN_branchSqN + WIDTH_UOPS;
        for (i = 0; i < WIDTH_UOPS; i=i+1) begin
            OUT_uop[i].sqN <= (IN_branchSqN + i[5:0]);
            OUT_uopValid[i] <= 0;
        end

        for (i = 0; i < 32; i=i+1) begin
            if (rat[i].comTag != rat[i].specTag && $signed(rat[i].newSqN - IN_branchSqN) > 0) begin
                rat[i].avail <= 1;
                // free tag
                freeTags[freeTagInsertIndex] <= rat[i].specTag;
                freeTagInsertIndex = freeTagInsertIndex + 1;

                rat[i].specTag <= rat[i].comTag;
            end
        end
    end

    else if (en) begin
        // Look up tags and availability of operands for new instructions
        for (i = 0; i < WIDTH_UOPS; i=i+1) begin
            OUT_uop[i].imm <= IN_uop[i].imm;
            OUT_uop[i].opcode <= IN_uop[i].opcode;
            OUT_uop[i].fu <= IN_uop[i].fu;
            OUT_uop[i].nmDst <= IN_uop[i].rd;
            OUT_uop[i].pc <= IN_uop[i].pc;
            OUT_uop[i].immB <= IN_uop[i].immB;
            OUT_uop[i].pcA <= IN_uop[i].pcA;

            OUT_uopValid[i] <= 1;

            OUT_uop[i].tagA <= rat[IN_uop[i].rs0].specTag;
            OUT_uop[i].availA <= rat[IN_uop[i].rs0].avail;

            OUT_uop[i].tagB <= rat[IN_uop[i].rs1].specTag;
            OUT_uop[i].availB <= rat[IN_uop[i].rs1].avail;
        end

        // Set seqnum/tags for next instruction(s)
        for (i = 0; i < WIDTH_UOPS; i=i+1) begin
            OUT_uop[i].sqN <= (counterSqN + i[5:0]);

            if (IN_uop[i].rd != 0) begin
                OUT_uop[i].tagDst <= freeTags[freeTagOutputIndex];

                // Mark regs written to by newly issued instructions as unavailable/pending.
                rat[IN_uop[i].rd].avail <= 0;
                rat[IN_uop[i].rd].specTag <= freeTags[freeTagOutputIndex];
                rat[IN_uop[i].rd].newSqN <= counterSqN + i[5:0];

                freeTagOutputIndex = freeTagOutputIndex + 1;
            end
        end
        counterSqN <= counterSqN + WIDTH_WR[5:0];
    end
    else begin
        for (i = 0; i < WIDTH_UOPS; i=i+1)
            OUT_uopValid[i] <= 0;
    end
    
end
endmodule