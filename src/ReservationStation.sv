module ReservationStation
#(
    parameter NUM_UOPS=1,
    parameter QUEUE_SIZE = 4,
    parameter RESULT_BUS_COUNT = 1,
    parameter STORE_QUEUE_SIZE=8
)
(
    input wire clk,
    input wire rst,

    input wire IN_wbStall[NUM_UOPS-1:0],
    input wire IN_uopValid[NUM_UOPS-1:0],
    input R_UOp IN_uop[NUM_UOPS-1:0],

    input wire IN_resultValid[RESULT_BUS_COUNT-1:0],
    input wire[5:0] IN_resultTag[RESULT_BUS_COUNT-1:0],

    input wire IN_invalidate,
    input wire[5:0] IN_invalidateSqN,
    
    input wire IN_maxCommitSqNValid,
    input wire[5:0] IN_maxCommitSqN,

    output reg OUT_valid[NUM_UOPS-1:0],
    output R_UOp OUT_uop[NUM_UOPS-1:0],
    output reg OUT_full
);

integer i;
integer j;
integer k;

// Alternatively to storeQueue one could also order the entire queue.
reg[2:0] storeQueueIn;
reg[2:0] storeQueueOut;
wire storeQueueEmpty = (storeQueueIn == storeQueueOut);
reg[5:0] storeQueue[STORE_QUEUE_SIZE-1:0];


R_UOp queue[QUEUE_SIZE-1:0];
reg valid[QUEUE_SIZE-1:0];

reg enqValid;

reg[1:0] deqIndex[NUM_UOPS-1:0];
reg deqValid[NUM_UOPS-1:0];

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
    
    for (i = 0; i < NUM_UOPS; i=i+1) begin
        
        deqValid[i] = 0;
        deqIndex[i] = 0;
        isLoad = 0;
        isStore = 0;
        
        for (j = 0; j < QUEUE_SIZE; j=j+1) begin
            if (valid[j]) begin
                
                // maybe just store these as a bit in the uop?
                isLoad = (queue[j].fu == FU_LSU) && (queue[j].opcode == LSU_LB || queue[j].opcode == LSU_LH ||
                    queue[j].opcode == LSU_LW || queue[j].opcode == LSU_LBU || queue[j].opcode == LSU_LHU);
                
                isStore = (queue[j].fu == FU_LSU) && 
                    (queue[j].opcode == LSU_SB || queue[j].opcode == LSU_SH || queue[j].opcode == LSU_SW);
                    
                
                if (queue[j].availA && queue[j].availB && 
                    // Loads are only issued when all stores before them are handled.
                    (!isLoad || storeQueueEmpty || $signed(storeQueue[storeQueueOut] - queue[j].sqN) > 0) &&
                    // Stores are issued in-order and non-speculatively
                    (!isStore || (storeQueue[storeQueueOut] == queue[j].sqN && 
                        (!IN_maxCommitSqNValid || $signed(IN_maxCommitSqN - queue[j].sqN) > 0))) &&
                    
                    (!deqValid[i] || $signed(queue[j].sqN - queue[deqIndex[i]].sqN) < 0)) begin
                    deqValid[i] = 1;
                    deqIndex[i] = j[1:0];
                end
            end
        end
    end
end

always_ff@(posedge clk) begin

    if (rst) begin
        for (i = 0; i < QUEUE_SIZE; i=i+1) begin
            valid[i] <= 0;
        end
        storeQueueIn = 0;
        storeQueueOut = 0;
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
        
        // issue uops
        for (i = 0; i < NUM_UOPS; i=i+1) begin
            if (!IN_wbStall[i]) begin
                if (deqValid[i]) begin
                    OUT_uop[i] <= queue[deqIndex[i]];
                    if (isStore)
                        storeQueueOut = storeQueueOut + 1;
                        
                    valid[deqIndex[i]] = 0;
                end
                OUT_valid[i] <= deqValid[i];
            end
        end

        // enqueue new uop
        for (i = 0; i < NUM_UOPS; i=i+1) begin
            if (IN_uopValid[i]) begin
                enqValid = 0;
                for (j = 0; j < QUEUE_SIZE; j=j+1) begin
                    if (enqValid == 0 && !valid[j]) begin
                        R_UOp temp = IN_uop[i];

                        for (k = 0; k < RESULT_BUS_COUNT; k=k+1) begin
                            if (!temp.availA && temp.tagA == IN_resultTag[k]) begin
                                temp.availA = 1;
                            end

                            if (!temp.availB && temp.tagB == IN_resultTag[k]) begin
                                temp.availB = 1;
                            end
                        end
                        
                        queue[j] <= temp;
                        valid[j] <= 1;
                        enqValid = 1;
                    end
                end
                
                if (enqValid) begin
                    if (IN_uop[i].fu == FU_LSU && 
                        (IN_uop[i].opcode == LSU_SB || IN_uop[i].opcode == LSU_SH || IN_uop[i].opcode == LSU_SW)) begin
                    storeQueue[storeQueueIn] <= IN_uop[i].sqN;
                    storeQueueIn = storeQueueIn + 1;
                    end
                end
            end
        end
    end
end

endmodule
