typedef struct packed
{
    //logic isJumpBranch;
    logic valid;
} UOpInfo;

module ReservationStation
#(
    parameter NUM_UOPS=3,
    parameter QUEUE_SIZE = 8,
    parameter RESULT_BUS_COUNT = 3,
    parameter STORE_QUEUE_SIZE=8
)
(
    input wire clk,
    input wire rst,
    input wire frontEn,
    
    input wire IN_DIV_doNotIssue,
    input wire IN_MUL_doNotIssue,

    input wire IN_stall[NUM_UOPS-1:0],
    input wire IN_uopValid[NUM_UOPS-1:0],
    input R_UOp IN_uop[NUM_UOPS-1:0],
    
    input wire IN_resultValid[RESULT_BUS_COUNT-1:0],
    input RES_UOp IN_resultUOp[RESULT_BUS_COUNT-1:0],

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

reg[4:0] freeEntries;


R_UOp queue[QUEUE_SIZE-1:0];
UOpInfo queueInfo[QUEUE_SIZE-1:0];

reg enqValid;

reg[2:0] deqIndex[NUM_UOPS-1:0];
reg deqValid[NUM_UOPS-1:0];

// 10 9 8 7 6 5 4 3 2
reg[32:0] reservedWBs[NUM_UOPS-1:0];
  
always_comb begin    

    for (i = 0; i < NUM_UOPS; i=i+1)
        deqValid[i] = 0;
    for (i = NUM_UOPS - 1; i >= 0; i=i-1) begin
    
        reg[2:0] ids0[7:0];
        reg[5:0] sqns0[7:0];
        reg valid0[7:0];
        
        reg[2:0] ids1[3:0];
        reg[5:0] sqns1[3:0];
        reg valid1[3:0];
        
        reg[2:0] ids2[1:0];
        reg[5:0] sqns2[1:0];
        reg valid2[1:0];
        
        deqValid[i] = 1'b0;
        deqIndex[i] = 3'bx;
        
        for (j = 0; j < QUEUE_SIZE; j=j+1) begin
            
            ids0[j] = j[2:0];
            sqns0[j] = queue[j].sqN;
            valid0[j] = 0;
            
            if (queueInfo[j].valid && (!deqValid[1] || deqIndex[1] != j[2:0])) begin
                
                if ((queue[j].availA ||
                        (IN_resultValid[0] && IN_resultUOp[0].tagDst == queue[j].tagA) ||
                        (IN_resultValid[1] && IN_resultUOp[1].tagDst == queue[j].tagA) ||
                        (IN_resultValid[2] && IN_resultUOp[2].tagDst == queue[j].tagA) ||
                        (OUT_valid[0] && OUT_uop[0].nmDst != 0 && OUT_uop[0].tagDst == queue[j].tagA && OUT_uop[0].fu == FU_INT) ||
                        (OUT_valid[1] && OUT_uop[1].nmDst != 0 && OUT_uop[1].tagDst == queue[j].tagA && OUT_uop[1].fu == FU_INT)
                        ) && 
                        
                    (queue[j].availB ||
                        (IN_resultValid[0] && IN_resultUOp[0].tagDst == queue[j].tagB) ||
                        (IN_resultValid[1] && IN_resultUOp[1].tagDst == queue[j].tagB) ||
                        (IN_resultValid[2] && IN_resultUOp[2].tagDst == queue[j].tagB) ||
                        (OUT_valid[0] && OUT_uop[0].nmDst != 0 && OUT_uop[0].tagDst == queue[j].tagB && OUT_uop[0].fu == FU_INT) ||
                        (OUT_valid[1] && OUT_uop[1].nmDst != 0 && OUT_uop[1].tagDst == queue[j].tagB && OUT_uop[1].fu == FU_INT)
                        ) &&
                        
                    // Second FU only gets simple int ops
                    (i == 0 || (queue[j].fu != FU_DIV)) &&
                    (i == 1 || (queue[j].fu != FU_MUL)) &&
                    (i == 2 || (queue[j].fu != FU_LSU)) &&
                    (i != 2 || (queue[j].fu != FU_INT)) &&
                    (!IN_DIV_doNotIssue || queue[j].fu != FU_DIV) &&
                    (!IN_MUL_doNotIssue || queue[j].fu != FU_MUL) &&

                    (queue[j].fu != FU_INT || !reservedWBs[i][0])
                    
                    /*(!deqValid[i] || $signed(queue[j].sqN - queue[deqIndex[i]].sqN) < 0)*/) begin
                    
                    //deqValid[i] = 1;
                    //deqIndex[i] = j[2:0];
                    valid0[j] = 1;
                end
            end
        end
        
        for (j = 0; j < 4; j=j+1) begin
            if (valid0[2*j] && (!valid0[2*j+1] || $signed(sqns0[2*j] - sqns0[2*j+1]) < 0)) begin            
                valid1[j] = 1;
                ids1[j] = ids0[2*j];
                sqns1[j] = sqns0[2*j];
            end
            else if (valid0[2*j+1]) begin
                valid1[j] = 1;
                ids1[j] = ids0[2*j+1];
                sqns1[j] = sqns0[2*j+1];
            end
            else begin
                valid1[j] = 0;
                ids1[j] = 3'bx;
                sqns1[j] = 6'bx;
            end
        end
        
        for (j = 0; j < 2; j=j+1) begin
            if (valid1[2*j] && (!valid1[2*j+1] || $signed(sqns1[2*j] - sqns1[2*j+1]) < 0)) begin            
                valid2[j] = 1;
                ids2[j] = ids1[2*j];
                sqns2[j] = sqns1[2*j];
            end
            else if (valid1[2*j+1]) begin
                valid2[j] = 1;
                ids2[j] = ids1[2*j+1];
                sqns2[j] = sqns1[2*j+1];
            end
            else begin
                valid2[j] = 0;
                ids2[j] = 3'bx;
                sqns2[j] = 6'bx;
            end
        end
        
        for (j = 0; j < 1; j=j+1) begin
            if (valid2[2*j] && (!valid2[2*j+1] || $signed(sqns2[2*j] - sqns2[2*j+1]) < 0)) begin            
                deqValid[i] = 1;
                deqIndex[i] = ids2[2*j];
            end
            else if (valid2[2*j+1]) begin
                deqValid[i] = 1;
                deqIndex[i] = ids2[2*j+1];
            end
        end
        
    end
end


reg[2:0] insertIndex[NUM_UOPS-1:0];
reg insertAvail[NUM_UOPS-1:0];
always_comb begin
    for (i = 0; i < NUM_UOPS; i=i+1) begin
        insertAvail[i] = 0;
        insertIndex[i] = 3'bx;
        
        if (IN_uopValid[i]) begin
            for (j = 0; j < QUEUE_SIZE; j=j+1) begin
                if (!queueInfo[j].valid && 
                    (i == 0 || !insertAvail[0] || insertIndex[0] != j[2:0]) && 
                    (i <= 1 || !insertAvail[1] || insertIndex[1] != j[2:0])) begin
                    insertAvail[i] = 1;
                    insertIndex[i] = j[2:0];
                end
            end
        end
    end
end


always_ff@(posedge clk) begin
    
    for (i = 0; i < NUM_UOPS; i=i+1) begin
        reservedWBs[i] <= {1'b0, reservedWBs[i][32:1]};
        //OUT_valid[i] <= 0;
    end
    
    if (!rst) begin
        // Get relevant results from common data buses
        for (i = 0; i < RESULT_BUS_COUNT; i=i+1) 
            // NOTE: invalidate not required here. If an op depends on an invalid op, it must come after the invalid op,
            // and as such will be deleted anyways.
            if (IN_resultValid[i]/* && (!IN_invalidate || $signed(IN_invalidateSqN - IN_resultSqN[i]) >= 0)*/) begin
                for (j = 0; j < QUEUE_SIZE; j=j+1) begin
                    if (queue[j].availA == 0 && queue[j].tagA == IN_resultUOp[i].tagDst) begin
                        queue[j].availA <= 1;
                    end

                    if (queue[j].availB == 0 && queue[j].tagB == IN_resultUOp[i].tagDst) begin
                        queue[j].availB <= 1;
                    end
                end
            end
        
        // Some results can be forwarded
        for (i = 0; i < NUM_UOPS; i=i+1) begin
            if (OUT_valid[i] && OUT_uop[i].nmDst != 0/* &&
                (!IN_invalidate || $signed(IN_invalidateSqN - OUT_uop[i].sqN) >= 0)*/ &&
                OUT_uop[i].fu == FU_INT) begin
                for (j = 0; j < QUEUE_SIZE; j=j+1) begin
                    if (queue[j].availA == 0 && queue[j].tagA == OUT_uop[i].tagDst) begin
                        queue[j].availA <= 1;
                    end

                    if (queue[j].availB == 0 && queue[j].tagB == OUT_uop[i].tagDst) begin
                        queue[j].availB <= 1;
                    end
                end
            end
        end
        
    end
    
    if (rst) begin
        for (i = 0; i < QUEUE_SIZE; i=i+1) begin
            queueInfo[i].valid <= 0;
        end
        freeEntries = 8;
        OUT_free <= 8;
        for (i = 0; i < NUM_UOPS; i=i+1)
            reservedWBs[i] <= 0;
        for (i = 0; i < NUM_UOPS; i=i+1)
            OUT_valid[i] <= 0;
    end
    else if (IN_invalidate) begin
        for (i = 0; i < QUEUE_SIZE; i=i+1) begin
            if ($signed(queue[i].sqN - IN_invalidateSqN) > 0) begin
                queueInfo[i].valid <= 0;
                if (queueInfo[i].valid)
                    freeEntries = freeEntries + 1;
            end
        end
        for (i = 0; i < NUM_UOPS; i=i+1)
            OUT_valid[i] <= 0;
    end
    else begin
        // issue uops
        for (i = 0; i < NUM_UOPS; i=i+1) begin
        // TODO: Can still push op into OUT if empty, even during stall
            if (!IN_stall[i]) begin
                if (deqValid[i]) begin
                    OUT_uop[i] <= queue[deqIndex[i]];
                    freeEntries = freeEntries + 1;
                    OUT_valid[i] <= 1;
                    queueInfo[deqIndex[i]].valid <= 0;
                    
                    reservedWBs[i] <= {
                        (queue[deqIndex[i]].fu == FU_DIV), 
                        reservedWBs[i][32:10], 
                        (queue[deqIndex[i]].fu == FU_MUL) | reservedWBs[i][9], 
                        reservedWBs[i][8:1]
                    };
                end
                else 
                    OUT_valid[i] <= 0;
            end
            // Make sure to invalidate uops even when stalled
            else if (OUT_valid[i] && IN_invalidate && $signed(OUT_uop[i].sqN - IN_invalidateSqN) > 0) begin
                OUT_valid[i] <= 0;
            end
        end
                

        // enqueue new uop
        for (i = 0; i < NUM_UOPS; i=i+1) begin
            if (frontEn && IN_uopValid[i]) begin

                R_UOp temp = IN_uop[i];
                
                assert(insertAvail[i]);

                for (k = 0; k < RESULT_BUS_COUNT; k=k+1) begin
                    if (IN_resultValid[k]) begin
                        if (!temp.availA && temp.tagA == IN_resultUOp[k].tagDst) begin
                            temp.availA = 1;
                        end

                        if (!temp.availB && temp.tagB == IN_resultUOp[k].tagDst) begin
                            temp.availB = 1;
                        end
                    end
                end
                
                queue[insertIndex[i]] <= temp;
                queueInfo[insertIndex[i]].valid <= 1;

                freeEntries = freeEntries - 1;
            end
        end
    end
    
    OUT_free <= freeEntries;
end

endmodule
