typedef struct packed
{
    logic isJumpBranch;
    logic isStore;
    logic isLoad;
} UOpInfo;

module ReservationStation
#(
    parameter NUM_UOPS=2,
    parameter QUEUE_SIZE = 8,
    parameter RESULT_BUS_COUNT = 2,
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
    
    input wire[5:0] IN_nextCommitSqN,

    output reg OUT_valid[NUM_UOPS-1:0],
    output R_UOp OUT_uop[NUM_UOPS-1:0],
    output reg[4:0] OUT_free
);

integer i;
integer j;
integer k;

// Alternatively to storeQueue one could also order the entire queue.
reg[2:0] storeQueueIn;
reg[2:0] storeQueueOut;
wire storeQueueEmpty = (storeQueueIn == storeQueueOut);
reg[5:0] storeQueue[STORE_QUEUE_SIZE-1:0];

reg[4:0] freeEntries;


R_UOp queue[QUEUE_SIZE-1:0];
UOpInfo queueInfo[QUEUE_SIZE-1:0];

reg valid[QUEUE_SIZE-1:0];

reg enqValid;

reg[2:0] deqIndex[NUM_UOPS-1:0];
reg deqValid[NUM_UOPS-1:0];


always_comb begin    
    for (i = 0; i < NUM_UOPS; i=i+1) begin
        
        deqValid[i] = 0;
        deqIndex[i] = 0;
        
        for (j = 0; j < QUEUE_SIZE; j=j+1) begin
            
            if (valid[j] && (!deqValid[0] || deqIndex[0] != j[2:0])) begin
                // maybe just store these as a bit in the uop?
                
                if (queue[j].availA && queue[j].availB && 
                    // Second FU only gets simple int ops
                    (i == 0 || (!queueInfo[j].isLoad && !queueInfo[j].isStore && !queueInfo[j].isJumpBranch)) &&
                    // Loads are only issued when all stores before them are handled.
                    (!queueInfo[j].isLoad || storeQueueEmpty || $signed(storeQueue[storeQueueOut] - queue[j].sqN) > 0) &&
                    // Stores are issued in-order and non-speculatively
                    (!queueInfo[j].isStore || (storeQueue[storeQueueOut] == queue[j].sqN && 
                        (IN_nextCommitSqN == queue[j].sqN))) &&
                    
                    (!deqValid[i] || $signed(queue[j].sqN - queue[deqIndex[i]].sqN) < 0)) begin
                    deqValid[i] = 1;
                    deqIndex[i] = j[2:0];
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
        freeEntries = 16;
    end
    else if (IN_invalidate) begin
        for (i = 0; i < QUEUE_SIZE; i=i+1) begin
            if ($signed(queue[i].sqN - IN_invalidateSqN) > 0) begin
                valid[i] <= 0;
                if (valid[i])
                    freeEntries = freeEntries + 1;
            end
        end
        
        for (i = 0; i < QUEUE_SIZE; i=i+1)
            OUT_valid[i] <= 0;
        
        // TODO
        while (storeQueueIn != storeQueueOut && $signed(storeQueue[storeQueueIn - 1] - IN_invalidateSqN) > 0)
            storeQueueIn = storeQueueIn - 1;
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
                    if ((queue[deqIndex[i]].fu == FU_LSU) && 
                        (queue[deqIndex[i]].opcode == LSU_SB || 
                            queue[deqIndex[i]].opcode == LSU_SH || queue[deqIndex[i]].opcode == LSU_SW)) begin
                        storeQueueOut = storeQueueOut + 1;
                    end
                        
                    valid[deqIndex[i]] = 0;
                    freeEntries = freeEntries + 1;
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
                            if (IN_resultValid[k]) begin
                                if (!temp.availA && temp.tagA == IN_resultTag[k]) begin
                                    temp.availA = 1;
                                end

                                if (!temp.availB && temp.tagB == IN_resultTag[k]) begin
                                    temp.availB = 1;
                                end
                            end
                        end
                        
                        queue[j] <= temp;
                        
                        queueInfo[j].isJumpBranch <= (temp.fu == FU_INT) && (
                            temp.opcode == INT_BEQ || 
                            temp.opcode == INT_BNE || 
                            temp.opcode == INT_BLT || 
                            temp.opcode == INT_BGE || 
                            temp.opcode == INT_BLTU || 
                            temp.opcode == INT_BGEU || 
                            temp.opcode == INT_JAL || 
                            temp.opcode == INT_JALR ||
                            temp.opcode == INT_SYS ||
                            temp.opcode == INT_UNDEFINED
                        );
                        
                        queueInfo[j].isStore <= (temp.fu == FU_LSU) && 
                            (temp.opcode == LSU_SB || temp.opcode == LSU_SH || temp.opcode == LSU_SW);
                            
                        queueInfo[j].isLoad <= (temp.fu == FU_LSU) && (temp.opcode == LSU_LB || temp.opcode == LSU_LH ||
                            temp.opcode == LSU_LW || temp.opcode == LSU_LBU || temp.opcode == LSU_LHU);
                    
                        valid[j] = 1;
                        enqValid = 1;
                    end
                end
                
                if (enqValid) begin
                    if (IN_uop[i].fu == FU_LSU && 
                        (IN_uop[i].opcode == LSU_SB || IN_uop[i].opcode == LSU_SH || IN_uop[i].opcode == LSU_SW)) begin
                    storeQueue[storeQueueIn] <= IN_uop[i].sqN;
                    storeQueueIn = storeQueueIn + 1;
                    end
                    freeEntries = freeEntries - 1;
                end
            end
        end
    end
    
    OUT_free <= freeEntries;
end

endmodule
