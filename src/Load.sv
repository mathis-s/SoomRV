module Load
#(
    parameter NUM_UOPS=3,
    parameter NUM_WBS=3,
    parameter NUM_XUS=4,
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
    input wire[5:0] IN_invalidateSqN,
    
    input wire IN_stall[NUM_UOPS-1:0],
    
    // Zero cycle forward inputs
    input wire[31:0] IN_zcFwdResult[NUM_ZC_FWDS-1:0],
    input wire[5:0] IN_zcFwdTag[NUM_ZC_FWDS-1:0],
    input wire IN_zcFwdValid[NUM_ZC_FWDS-1:0],
    
    // Register File read
    output reg[5:0] OUT_rfReadAddr[2*NUM_UOPS-1:0],
    input wire[31:0] IN_rfReadData[2*NUM_UOPS-1:0],

    output reg[NUM_XUS-1:0] OUT_enableXU[NUM_UOPS-1:0],
    output FuncUnit OUT_funcUnit[NUM_UOPS-1:0],
    output EX_UOp OUT_uop[NUM_UOPS-1:0]
);
integer i;
integer j;

always_comb begin
    for (i = 0; i < NUM_UOPS; i=i+1) begin
        OUT_rfReadAddr[i] = IN_uop[i].tagA;

        OUT_rfReadAddr[i+NUM_UOPS] = IN_uop[i].tagB;
    end
end

FuncUnit outFU[NUM_UOPS-1:0];

always_ff@(posedge clk) begin
    if (rst) begin
        for (i = 0; i < NUM_UOPS; i=i+1) begin
            OUT_uop[i].valid <= 0;
            OUT_funcUnit[i] <= 0;
            OUT_enableXU[i] <= 0;
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
                OUT_uop[i].pc <= IN_uop[i].pc;
                OUT_uop[i].branchID <= IN_uop[i].branchID;
                OUT_uop[i].branchPred <= IN_uop[i].branchPred;
                OUT_uop[i].loadSqN <= IN_uop[i].loadSqN;
                OUT_uop[i].storeSqN <= IN_uop[i].storeSqN;
                OUT_uop[i].compressed <= IN_uop[i].compressed;
                
                OUT_funcUnit[i] <= IN_uop[i].fu;
                
                OUT_uop[i].valid <= 1;
                
                if (IN_uop[i].tagA == 6'b0) begin
                    OUT_uop[i].srcA <= 0;
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
                
                if (IN_uop[i].immB) begin
                    OUT_uop[i].srcB <= IN_uop[i].imm;
                end
                else if (IN_uop[i].tagB == 6'b0) begin
                    OUT_uop[i].srcB <= 0;
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
                // Try to get from current WB
                case (IN_uop[i].fu)
                    FU_INT: OUT_enableXU[i] <= 4'b0001;
                    FU_LSU: OUT_enableXU[i] <= 4'b0010;
                    FU_MUL: OUT_enableXU[i] <= 4'b0100;
                    FU_DIV: OUT_enableXU[i] <= 4'b1000;
                    default: begin end
                endcase
                outFU[i] <= IN_uop[i].fu;
            end
            else if (!IN_stall[i] || (OUT_uop[i].valid && IN_invalidate && $signed(OUT_uop[i].sqN - IN_invalidateSqN) > 0)) begin
                OUT_uop[i].valid <= 0;
                OUT_enableXU[i] <= 0;
            end
        
        end 
    end
end


endmodule
