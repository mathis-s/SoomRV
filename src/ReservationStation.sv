module ReservationStation
#(
    parameter QUEUE_SIZE = 4,
    parameter RESULT_BUS_COUNT = 1
)
(
    input wire clk,
    input wire rst,

    input UOp IN_uop,

    input wire IN_resultValid[RESULT_BUS_COUNT-1:0],
    input wire[31:0] IN_resultBus[RESULT_BUS_COUNT-1:0],
    input wire[5:0] IN_resultTag[RESULT_BUS_COUNT-1:0],

    input wire IN_invalidate,
    input wire[5:0] IN_invalidateTag,

    output reg OUT_valid,
    output reg[31:0] OUT_operands[2:0],
    output reg[5:0] OUT_opcode,
    output reg[5:0] OUT_tagDst,
    output reg[4:0] OUT_nmDst,
    output reg[5:0] OUT_sqN,
    output reg OUT_full
);

integer i;
integer j;

//UOp enqUOp;
UOp queue[QUEUE_SIZE-1:0];

reg enqValid;

reg[1:0] deqIndex;
reg deqValid;

always_comb begin
    OUT_full = 1;
    for (i = 0; i < QUEUE_SIZE; i=i+1) begin
        if (!queue[i].valid)
            OUT_full = 0;
    end
end

always_comb begin
    deqValid = 0;
    deqIndex = 0;
    for (i = 0; i < QUEUE_SIZE; i=i+1) begin
        if (queue[i].valid && queue[i].availA && queue[i].availB && (!deqValid || $signed(queue[i].sqN - queue[deqIndex].sqN) < 0)) begin
            deqValid = 1;
            deqIndex = i[1:0];
        end
    end
end

always_ff@(posedge clk) begin

    if (rst) begin
        for (i = 0; i < QUEUE_SIZE; i=i+1) begin
            queue[i].valid <= 0;
            //enqUOp.valid <= 0;
        end
    end
    else if (IN_invalidate) begin
        for (i = 0; i < QUEUE_SIZE; i=i+1) begin
            if ($signed(queue[i].tagDst - IN_invalidateTag) > 0)
                queue[i].valid <= 0;
        end
        //enqUOp.valid <= 0;
    end
    else begin
        // Get relevant results from common data buses
        for (i = 0; i < RESULT_BUS_COUNT; i=i+1) 
            if (IN_resultValid[i]) begin
                for (j = 0; j < QUEUE_SIZE; j=j+1) begin
                    if (queue[j].availA == 0 && queue[j].tagA == IN_resultTag[i]) begin
                        queue[j].availA <= 1;
                        queue[j].srcA <= IN_resultBus[i];
                    end

                    if (queue[j].availB == 0 && queue[j].tagB == IN_resultTag[i]) begin
                        queue[j].availB <= 1;
                        queue[j].srcB <= IN_resultBus[i];
                    end
                end
            end

        // dequeue old uop (should always dequeue smallest tag one...)
        if (deqValid) begin
            OUT_operands[0] <= queue[deqIndex].srcA;
            OUT_operands[1] <= queue[deqIndex].srcB;
            OUT_operands[2] <= queue[deqIndex].imm;
            OUT_tagDst <= queue[deqIndex].tagDst;
            OUT_opcode <= queue[deqIndex].opcode;
            OUT_nmDst <= queue[deqIndex].nmDst;
            OUT_sqN <= queue[deqIndex].sqN;
            // TODO: it might be worth it to construct this in such a manner that a queue entry
            // can be enqueued and dequeued in the same cycle, ie have this be blocking assignment. 
            // (Did this for now)
            queue[deqIndex].valid = 0;
        end
        // if an op was dequeued, output is valid, otherwise not.
        OUT_valid <= deqValid;

        // enqueue new uop
        if (IN_uop.valid) begin
            enqValid = 0;
            for (i = 0; i < QUEUE_SIZE; i=i+1) begin
                if (enqValid == 0 && !queue[i].valid) begin
                    queue[i] <= IN_uop;
                    enqValid = 1;
                end
            end
        end

        //enqUOp <= IN_uop;
    end
end

endmodule