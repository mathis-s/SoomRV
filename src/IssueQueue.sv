module IssueQueue
#(
    parameter SIZE = 8,
    parameter NUM_UOPS = 4,
    parameter RESULT_BUS_COUNT = 4,
    parameter FU0 = FU_LSU,
    parameter FU1 = FU_LSU,
    parameter FU2 = FU_LSU,
    parameter FU0_SPLIT=0,
    parameter FU0_ORDER=0,
    parameter FU1_DLY=0
)
(
    input wire clk,
    input wire rst,
    input wire frontEn,
    
    input wire IN_stall,
    input wire IN_doNotIssueFU1,
    
    input wire IN_uopValid[NUM_UOPS-1:0],
    input R_UOp IN_uop[NUM_UOPS-1:0],
    
    input wire IN_resultValid[RESULT_BUS_COUNT-1:0],
    input RES_UOp IN_resultUOp[RESULT_BUS_COUNT-1:0],
    
    input BranchProv IN_branch,
    
    // All ops that are being issued (including OUT_uop)
    // For operand forwarding
    input wire IN_issueValid[NUM_UOPS-1:0],
    input R_UOp IN_issueUOps[NUM_UOPS-1:0],
    
    output reg OUT_valid,
    output R_UOp OUT_uop,
    
    output wire OUT_full
);

localparam ID_LEN = $clog2(SIZE);

integer i;
integer j;

R_UOp queue[SIZE-1:0];
reg valid[SIZE-1:0];

reg[$clog2(SIZE):0] insertIndex;
reg[32:0] reservedWBs;

assign OUT_full = insertIndex > (SIZE-NUM_UOPS);

reg newAvailA[SIZE-1:0];
reg newAvailB[SIZE-1:0];
always_comb begin
    for (i = 0; i < SIZE; i=i+1) begin
        
        newAvailA[i] = 0;
        newAvailB[i] = 0;
        
        for (j = 0; j < RESULT_BUS_COUNT; j=j+1) begin
            if (IN_resultValid[j] && queue[i].tagA == IN_resultUOp[j].tagDst) newAvailA[i] = 1;
            if (IN_resultValid[j] && queue[i].tagB == IN_resultUOp[j].tagDst) newAvailB[i] = 1;
        end
        
        for (j = 0; j < NUM_UOPS; j=j+1) begin
            if (IN_issueValid[j] && IN_issueUOps[j].fu == FU_INT && IN_issueUOps[j].nmDst != 0) begin
                if (queue[i].tagA == IN_issueUOps[j].tagDst) newAvailA[i] = 1;
                if (queue[i].tagB == IN_issueUOps[j].tagDst) newAvailB[i] = 1;
            end
        end
    end
end

always_ff@(posedge clk) begin
    
    // Update availability
    for (i = 0; i < SIZE; i=i+1) begin
        queue[i].availA <= queue[i].availA | newAvailA[i];
        queue[i].availB <= queue[i].availB | newAvailB[i];
    end
    reservedWBs <= {1'b0, reservedWBs[32:1]};
    
    if (rst) begin
        insertIndex = 0;
        reservedWBs <= 0;
        OUT_valid <= 0;
    end
    else if (IN_branch.taken) begin
        
        reg[ID_LEN:0] newInsertIndex = 0;
        // Set insert index to first invalid entry
        for (i = 0; i < SIZE; i=i+1) begin
            if (i < insertIndex && $signed(queue[i].sqN - IN_branch.sqN) <= 0) begin
                newInsertIndex = i[$clog2(SIZE):0] + 1;
            end
        end
        insertIndex = newInsertIndex;
        if (!IN_stall || $signed(OUT_uop.sqN - IN_branch.sqN) > 0)
            OUT_valid <= 0;
    end
    else begin
        reg issued = 0;
        
        // Issue
        if (!IN_stall) begin
            OUT_valid <= 0;
            
            for (i = 0; i < SIZE; i=i+1) begin
                if (i < insertIndex && !issued) begin
                    if ((queue[i].availA || newAvailA[i]) && (queue[i].availB || newAvailB[i]) && 
                        (queue[i].fu != FU1 || !IN_doNotIssueFU1) && 
                        !((queue[i].fu == FU_INT || queue[i].fu == FU_FPU) && reservedWBs[0])) begin
                        
                        issued = 1;
                        OUT_valid <= 1;
                        OUT_uop <= queue[i];
                        
                        // Shift other ops forward
                        for (j = i; j < SIZE-1; j=j+1) begin
                            queue[j] <= queue[j+1];
                            queue[j].availA <= queue[j+1].availA | newAvailA[j+1];
                            queue[j].availB <= queue[j+1].availB | newAvailB[j+1];
                        end
                        insertIndex = insertIndex - 1;
                        
                        // Reserve WB if this is a slow operation
                        if (queue[i].fu == FU1 && FU1_DLY > 0)
                            reservedWBs <= {1'b0, reservedWBs[32:1]} | (1 << (FU1_DLY - 1));
                    end
                end
            end
        end
        
        // Enqueue
        if (frontEn) begin
            for (i = 0; i < NUM_UOPS; i=i+1) begin
                if (IN_uopValid[i] && 
                    ((IN_uop[i].fu == FU0 && (!FU0_SPLIT || IN_uop[i].sqN[0] == FU0_ORDER)) || 
                        IN_uop[i].fu == FU1 || IN_uop[i].fu == FU2)) begin
                    
                    R_UOp temp = IN_uop[i];

                    // Check if the result for this op is being broadcasted in the current cycle
                    for (j = 0; j < RESULT_BUS_COUNT; j=j+1) begin
                        if (IN_resultValid[j]) begin
                            if (temp.tagA == IN_resultUOp[j].tagDst) temp.availA = 1;
                            if (temp.tagB == IN_resultUOp[j].tagDst) temp.availB = 1;
                        end
                    end
                    
                    queue[insertIndex[ID_LEN-1:0]] <= temp;
                    
                    insertIndex = insertIndex + 1;
                end
            end
        end
    end
end

endmodule
