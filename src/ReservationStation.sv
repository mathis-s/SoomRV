module ReservationStation
#(
    parameter QUEUE_SIZE = 2,
    parameter RESULT_BUS_COUNT = 1
)
(
    input wire clk,
    input wire rst,

    input UOp IN_uop,

    input wire[31:0] IN_resultBus[RESULT_BUS_COUNT-1:0],
    input wire[5:0] IN_resultTag[RESULT_BUS_COUNT-1:0],

    output reg[31:0] OUT_operands[2:0],
    output reg[5:0] OUT_opcode,
    output reg[5:0] OUT_tagDst,
    output reg OUT_full
);

integer i;
integer j;

UOp enqUOp;
UOp queue[QUEUE_SIZE-1:0];


reg enqValid;
reg deqValid;

always@(*) begin
    OUT_full = 1;
    for (i = 0; i < QUEUE_SIZE; i=i+1) begin
        if (!queue[i].valid)
            OUT_full = 0;
    end
end

always@(posedge clk) begin

    if (rst) begin
        for (i = 0; i < QUEUE_SIZE; i=i+1) begin
            queue[i].valid <= 0;
            enqUOp.valid <= 0;
        end
    end
    else begin
        // Get relevant results from common data buses
        for (i = 0; i < RESULT_BUS_COUNT; i=i+1) 
            for (j = 0; j < QUEUE_SIZE; j=j+1) begin
                if (queue[j].tagA != 0 && queue[j].tagA == IN_resultTag[i]) begin
                    queue[j].tagA <= 0;
                    queue[j].srcA <= IN_resultBus[i];
                end

                if (queue[j].tagB != 0 && queue[j].tagB == IN_resultTag[i]) begin
                    queue[j].tagB <= 0;
                    queue[j].srcB <= IN_resultBus[i];
                end
            end

        // dequeue old uop
        deqValid = 0;
        for (i = 0; i < QUEUE_SIZE; i=i+1) begin
            if (deqValid == 0 && queue[i].valid && queue[i].tagA == 0 && queue[i].tagB == 0) begin
                OUT_operands[0] <= queue[i].srcA;
                OUT_operands[1] <= queue[i].srcB;
                OUT_operands[2] <= queue[i].imm;
                OUT_tagDst <= queue[i].tagDst;
                OUT_opcode <= queue[i].opcode;
                // TODO: it might be worth it to construct this in such a manner that a queue entry
                // can be enqueued and dequeued in the same cycle, ie have this be blocking assignment.
                queue[i].valid = 0;
                deqValid = 1;
            end
        end

        // enqueue new uop
        if (enqUOp.valid) begin
            enqValid = 0;
            for (i = 0; i < QUEUE_SIZE; i=i+1) begin
                if (enqValid == 0 && !queue[i].valid) begin
                    queue[i] <= enqUOp;
                    enqValid = 1;
                end
            end
        end

        enqUOp <= IN_uop;
    end
end

endmodule