module Load
#(
    parameter NUM_UOPS=4,
    parameter NUM_WBS=4,
    parameter NUM_XUS=8,
    parameter NUM_ZC_FWDS=2
)
(
    input wire clk,
    input wire rst,
    
    input wire IN_uopValid[NUM_UOPS-1:0],
    input R_UOp IN_uop[NUM_UOPS-1:0],

    // Writeback Port (snoop) read
    input wire IN_wbHasResult[NUM_WBS-1:0],
    input RES_UOp IN_wbUOp[NUM_WBS-1:0],
    
    input wire IN_invalidate,
    input SqN IN_invalidateSqN,
    
    input wire IN_stall[NUM_UOPS-1:0],
    
    // Zero cycle forward inputs
    input wire[31:0] IN_zcFwdResult[NUM_ZC_FWDS-1:0],
    input Tag IN_zcFwdTag[NUM_ZC_FWDS-1:0],
    input wire IN_zcFwdValid[NUM_ZC_FWDS-1:0],
    
    // PC File read
    output FetchID_t OUT_pcReadAddr[NUM_UOPS-1:0],
    input PCFileEntry IN_pcReadData[NUM_UOPS-1:0],
    
    // Register File read
    output reg[5:0] OUT_rfReadAddr[2*NUM_UOPS-1:0],
    input wire[31:0] IN_rfReadData[2*NUM_UOPS-1:0],
    
    //output reg[5:0] OUT_rfReadAddr_fp[3:0],
    //input wire[31:0] IN_rfReadData_fp[3:0],

    output EX_UOp OUT_uop[NUM_UOPS-1:0]
);
integer i;
integer j;

always_comb begin

    // All ports get to read from integer rf and pc rf
    for (i = 0; i < NUM_UOPS; i=i+1) begin
        OUT_rfReadAddr[i] = IN_uop[i].tagA[5:0];
        OUT_rfReadAddr[i+NUM_UOPS] = IN_uop[i].tagB[5:0];
        
        OUT_pcReadAddr[i] = IN_uop[i].fetchID;
    end
    
    // Second AGU_LD read port is used as third AGU_ST read port (for atomics)
    OUT_rfReadAddr[2+NUM_UOPS] = IN_uop[3].tagC[5:0];
end

FuncUnit outFU[NUM_UOPS-1:0];

always_ff@(posedge clk) begin
    if (rst) begin
        for (i = 0; i < NUM_UOPS; i=i+1) begin
            OUT_uop[i] <= 'x;
            OUT_uop[i].valid <= 0;
        end
    end
    else begin
        for (i = 0; i < NUM_UOPS; i=i+1) begin
            if (!IN_stall[i] && IN_uopValid[i] && (!IN_invalidate || ($signed(IN_uop[i].sqN - IN_invalidateSqN) <= 0))) begin       
                
                OUT_uop[i].imm <= IN_uop[i].imm;
                OUT_uop[i].sqN <= IN_uop[i].sqN;
                OUT_uop[i].tagDst <= IN_uop[i].tagDst;
                OUT_uop[i].nmDst <= IN_uop[i].nmDst;
                OUT_uop[i].opcode <= IN_uop[i].opcode;
                
                OUT_uop[i].pc <= {IN_pcReadData[i].pc[30:3], IN_uop[i].fetchOffs, 1'b0} - (IN_uop[i].compressed ? 0 : 2);
                //assert(
                //    ({IN_pcReadData[i].pc[30:2], IN_uop[i].fetchOffs, 1'b0} - (IN_uop[i].compressed ? 0 : 2)) ==
                //    IN_uop[i].pc
                //);
                
                OUT_uop[i].fetchID <= IN_uop[i].fetchID;
                
                if (IN_pcReadData[i].bpi.isJump || !IN_pcReadData[i].bpi.predicted || IN_uop[i].fetchOffs <= IN_pcReadData[i].branchPos)
                    OUT_uop[i].history <= IN_pcReadData[i].hist;
                else
                    OUT_uop[i].history <= {IN_pcReadData[i].hist[$bits(BHist_t)-2:0], IN_pcReadData[i].bpi.taken};
                
                if (IN_uop[i].fetchOffs == IN_pcReadData[i].branchPos)
                    OUT_uop[i].bpi <= IN_pcReadData[i].bpi;
                else
                    OUT_uop[i].bpi <= 0;
                
                OUT_uop[i].loadSqN <= IN_uop[i].loadSqN;
                OUT_uop[i].storeSqN <= IN_uop[i].storeSqN;
                OUT_uop[i].compressed <= IN_uop[i].compressed;
                
                OUT_uop[i].fu <= IN_uop[i].fu;
                
                OUT_uop[i].valid <= 1;
                
                if (IN_uop[i].tagA[6]) begin
                    OUT_uop[i].srcA <= {{26{IN_uop[i].tagA[5]}}, IN_uop[i].tagA[5:0]};
                end
                else begin 
                    reg found = 0;
                    
                    // Try to forward from wbs
                    for (j = 0; j < NUM_WBS; j=j+1) begin
                        // TODO: one-hot
                        if (IN_wbHasResult[j] && IN_uop[i].tagA == IN_wbUOp[j].tagDst) begin
                            OUT_uop[i].srcA <= IN_wbUOp[j].result;
                            found = 1;
                        end
                    end
                    
                    // Try to forward zero cycle (TODO: one hot too)
                    for (j = 0; j < NUM_ZC_FWDS; j=j+1) begin
                        if (IN_zcFwdValid[j] && IN_zcFwdTag[j] == IN_uop[i].tagA) begin
                            OUT_uop[i].srcA <= IN_zcFwdResult[j];
                            found = 1;
                        end
                    end
                
                    if (!found) begin
                        OUT_uop[i].srcA <= IN_rfReadData[i];
                    end
                end
                
                if (IN_uop[i].immB || i == 2) begin
                    OUT_uop[i].srcB <= IN_uop[i].imm;
                end
                else if (IN_uop[i].tagB[6]) begin
                    OUT_uop[i].srcB <= {{26{IN_uop[i].tagB[5]}}, IN_uop[i].tagB[5:0]};
                end
                else begin
                    reg found = 0;
                    for (j = 0; j < NUM_WBS; j=j+1) begin
                        // TODO: one-hot
                        if (IN_wbHasResult[j] && IN_uop[i].tagB == IN_wbUOp[j].tagDst) begin
                            OUT_uop[i].srcB <= IN_wbUOp[j].result;
                            found = 1;
                        end
                    end
                    
                    // Try to forward zero cycle (TODO: one hot too)
                    for (j = 0; j < NUM_ZC_FWDS; j=j+1) begin
                        if (IN_zcFwdValid[j] && IN_zcFwdTag[j] == IN_uop[i].tagB) begin
                            OUT_uop[i].srcB <= IN_zcFwdResult[j];
                            found = 1;
                        end
                    end
                    
                    if (!found) begin
                        OUT_uop[i].srcB <= IN_rfReadData[i + NUM_UOPS];
                    end
                end
                
                // Store Pipeline has a third read port for atomics
                if (i == 3) begin
                    reg found = 0;
                    // Try to forward from wbs
                    for (j = 0; j < NUM_WBS; j=j+1) begin
                        // TODO: one-hot
                        if (IN_wbHasResult[j] && IN_uop[i].tagC == IN_wbUOp[j].tagDst) begin
                            OUT_uop[i].srcC <= IN_wbUOp[j].result;
                            found = 1;
                        end
                    end
                    
                    // ZC is impossible as the atomic memory operand always comes from the Load port
                    /*for (j = 0; j < NUM_ZC_FWDS; j=j+1) begin
                        if (IN_zcFwdValid[j] && IN_zcFwdTag[j] == IN_uop[i].tagC) begin
                            OUT_uop[i].srcC <= IN_zcFwdResult[j];
                            found = 1;
                        end
                    end*/
                    
                    if (!found)
                        OUT_uop[i].srcC <= IN_rfReadData[2 + NUM_UOPS];
                end
                
            end
            else if (!IN_stall[i] || (OUT_uop[i].valid && IN_invalidate && $signed(OUT_uop[i].sqN - IN_invalidateSqN) > 0)) begin
                OUT_uop[i] <= 'x;
                OUT_uop[i].valid <= 0;
            end
        
        end 
    end
end


endmodule
