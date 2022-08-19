module ReservationStation
#(
    parameter QUEUE_SIZE = 4,
    parameter RESULT_BUS_COUNT = 1,
    parameter STORE_QUEUE_SIZE=8
)
(
    input wire clk,
    input wire rst,

    input wire IN_wbStall,
    input wire IN_uopValid,
    input R_UOp IN_uop,

    input wire IN_resultValid[RESULT_BUS_COUNT-1:0],
    input wire[5:0] IN_resultTag[RESULT_BUS_COUNT-1:0],

    input wire IN_invalidate,
    input wire[5:0] IN_invalidateSqN,
    
    input wire IN_maxCommitSqNValid,
    input wire[5:0] IN_maxCommitSqN,

    output reg OUT_valid,
    output R_UOp OUT_uop,
    output reg OUT_full
);

integer i;
integer j;

// Alternatively to storeQueue one could also order the entire queue.
reg[2:0] storeQueueIn;
reg[2:0] storeQueueOut;
wire storeQueueEmpty = (storeQueueIn == storeQueueOut);
reg[5:0] storeQueue[STORE_QUEUE_SIZE-1:0];


R_UOp queue[QUEUE_SIZE-1:0];
reg valid[QUEUE_SIZE-1:0];

reg enqValid;

reg[1:0] deqIndex;
reg deqValid;

always_comb begin
    OUT_full = 1;
    for (i = 0; i < QUEUE_SIZE; i=i+1) begin
        if (!valid[i])
            OUT_full = 0;
    end
end

reg isLoad;
reg isStore;
always_comb begin
    deqValid = 0;
    deqIndex = 0;
    
    isLoad = 0;
    isStore = 0;
    
    for (i = 0; i < QUEUE_SIZE; i=i+1) begin
        if (valid[i]) begin
            
            // maybe just store these as a bit in the uop?
            isLoad = (queue[i].fu == FU_LSU) && (queue[i].opcode == LSU_LB || queue[i].opcode == LSU_LH ||
                queue[i].opcode == LSU_LW || queue[i].opcode == LSU_LBU || queue[i].opcode == LSU_LHU);
            
            isStore = (queue[i].fu == FU_LSU) && 
                (queue[i].opcode == LSU_SB || queue[i].opcode == LSU_SH || queue[i].opcode == LSU_SW);
                
            
            if (queue[i].availA && queue[i].availB && 
                // Loads are only issued when all stores before them are handled.
                (!isLoad || storeQueueEmpty || $signed(storeQueue[storeQueueOut] - queue[i].sqN) > 0) &&
                // Stores are issued in-order and non-speculatively
                (!isStore || (storeQueue[storeQueueOut] == queue[i].sqN && 
                    (!IN_maxCommitSqNValid || $signed(IN_maxCommitSqN - queue[i].sqN) > 0))) &&
                
                (!deqValid || $signed(queue[i].sqN - queue[deqIndex].sqN) < 0)) begin
                deqValid = 1;
                deqIndex = i[1:0];
            end
        end
    end
end

always_ff@(posedge clk) begin

    if (rst) begin
        for (i = 0; i < QUEUE_SIZE; i=i+1) begin
            valid[i] <= 0;
        end
        storeQueueIn <= 0;
        storeQueueOut <= 0;
    end
    else if (IN_invalidate) begin
        for (i = 0; i < QUEUE_SIZE; i=i+1) begin
            if ($signed(queue[i].sqN - IN_invalidateSqN) > 0)
                valid[i] <= 0;
        end
    end
    else begin
        // Get relevant results from common data buses
        for (i = 0; i < RESULT_BUS_COUNT; i=i+1) 
            if (IN_resultValid[i]) begin
                for (j = 0; j < QUEUE_SIZE; j=j+1) begin
                    if (queue[j].availA == 0 && queue[j].tagA == IN_resultTag[i]) begin
                        queue[j].availA <= 1;
                    end

                    if (queue[j].availB == 0 && queue[j].tagB == IN_resultTag[i]) begin
                        queue[j].availB <= 1;
                    end
                end
            end

        if (!IN_wbStall) begin
            if (deqValid) begin
                OUT_uop <= queue[deqIndex];
                if (isStore)
                    storeQueueOut <= storeQueueOut + 1;
                    
                valid[deqIndex] = 0;
            end
            OUT_valid <= deqValid;
        end

        // enqueue new uop
        if (IN_uopValid) begin
            enqValid = 0;
            for (i = 0; i < QUEUE_SIZE; i=i+1) begin
                if (enqValid == 0 && !valid[i]) begin
                    R_UOp temp = IN_uop;

                    for (j = 0; j < RESULT_BUS_COUNT; j=j+1) begin
                        if (!temp.availA && temp.tagA == IN_resultTag[j]) begin
                            temp.availA = 1;
                        end

                        if (!temp.availB && temp.tagB == IN_resultTag[j]) begin
                            temp.availB = 1;
                        end
                    end
                    
                    queue[i] <= temp;
                    valid[i] <= 1;
                    enqValid = 1;
                end
            end
            
            if (enqValid) begin
                if (IN_uop.fu == FU_LSU && 
                    (IN_uop.opcode == LSU_SB || IN_uop.opcode == LSU_SH || IN_uop.opcode == LSU_SW)) begin
                   storeQueue[storeQueueIn] <= IN_uop.sqN;
                   storeQueueIn <= storeQueueIn + 1;
                end
            end
            //TODO check for enqueue fail/RV full here and stall frontend if so.
            
        end
    end
end

endmodule
