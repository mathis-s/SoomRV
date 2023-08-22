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
    
    input IS_UOp IN_uop[NUM_UOPS-1:0],

    // Writeback Port (snoop) read
    input wire IN_wbHasResult[NUM_WBS-1:0],
    input RES_UOp IN_wbUOp[NUM_WBS-1:0],
    
    input wire IN_invalidate,
    input SqN IN_invalidateSqN,
    
    input wire IN_stall[NUM_UOPS-1:0],
    
    // Zero cycle forward inputs
    input ZCForward IN_zcFwd[NUM_ZC_FWDS-1:0],
    
    // PC File read
    output FetchID_t OUT_pcReadAddr[NUM_UOPS-1:0],
    input PCFileEntry IN_pcReadData[NUM_UOPS-1:0],
    
    // Register File read
    output reg[5:0] OUT_rfReadAddr[2*NUM_UOPS-1:0],
    input wire[31:0] IN_rfReadData[2*NUM_UOPS-1:0],

    output EX_UOp OUT_uop[NUM_UOPS-1:0]
);

always_comb begin

    // All ports get to read from integer rf and pc rf
    for (integer i = 0; i < NUM_UOPS; i=i+1) begin
        OUT_rfReadAddr[i] = IN_uop[i].tagA[5:0];
        OUT_rfReadAddr[i+NUM_UOPS] = IN_uop[i].tagB[5:0];
        
        OUT_pcReadAddr[i] = IN_uop[i].fetchID;
    end
    
    // LD/ST only use one register read port
    OUT_rfReadAddr[2+NUM_UOPS] = 'x;
    OUT_rfReadAddr[3+NUM_UOPS] = 'x;
end

FuncUnit outFU[NUM_UOPS-1:0];

always_ff@(posedge clk) begin
    if (rst) begin
        for (integer i = 0; i < NUM_UOPS; i=i+1) begin
            OUT_uop[i] <= 'x;
            OUT_uop[i].valid <= 0;
        end
    end
    else begin
        for (integer i = 0; i < NUM_UOPS; i=i+1) begin
            if (!IN_stall[i] && IN_uop[i].valid && (!IN_invalidate || ($signed(IN_uop[i].sqN - IN_invalidateSqN) <= 0))) begin       
                
                OUT_uop[i].imm <= IN_uop[i].imm;
                
                // jalr uses a different encoding
                if ((i == 0 || i == 1) && IN_uop[i].fu == FU_INT && 
                    (IN_uop[i].opcode == INT_V_JALR || IN_uop[i].opcode == INT_V_JR)
                ) begin
                    OUT_uop[i].imm <= 'x;
                    OUT_uop[i].imm[11:0] <= IN_uop[i].imm12;
                end

                OUT_uop[i].sqN <= IN_uop[i].sqN;
                OUT_uop[i].tagDst <= IN_uop[i].tagDst;
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
                
                OUT_uop[i].bpi <= IN_pcReadData[i].bpi;

                if (IN_uop[i].fetchOffs != IN_pcReadData[i].branchPos) begin
                    OUT_uop[i].bpi.predicted <= 0;
                    OUT_uop[i].bpi.taken <= 0;
                    OUT_uop[i].bpi.isJump <= 0;
                end
                
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
                    for (integer j = 0; j < NUM_WBS; j=j+1) begin
                        // TODO: one-hot
                        if (IN_wbHasResult[j] && IN_uop[i].tagA == IN_wbUOp[j].tagDst) begin
                            OUT_uop[i].srcA <= IN_wbUOp[j].result;
                            found = 1;
                        end
                    end
                    
                    // Try to forward zero cycle (TODO: one hot too)
                    for (integer j = 0; j < NUM_ZC_FWDS; j=j+1) begin
                        if (IN_zcFwd[j].valid && IN_zcFwd[j].tag == IN_uop[i].tagA) begin
                            OUT_uop[i].srcA <= IN_zcFwd[j].result;
                            found = 1;
                        end
                    end
                
                    if (!found) begin
                        OUT_uop[i].srcA <= IN_rfReadData[i];
                    end
                end
                
                if (IN_uop[i].immB || i == 2 || i == 3) begin
                    OUT_uop[i].srcB <= IN_uop[i].imm;
                end
                else if (IN_uop[i].tagB[6]) begin
                    OUT_uop[i].srcB <= {{26{IN_uop[i].tagB[5]}}, IN_uop[i].tagB[5:0]};
                end
                else begin
                    reg found = 0;
                    for (integer j = 0; j < NUM_WBS; j=j+1) begin
                        // TODO: one-hot
                        if (IN_wbHasResult[j] && IN_uop[i].tagB == IN_wbUOp[j].tagDst) begin
                            OUT_uop[i].srcB <= IN_wbUOp[j].result;
                            found = 1;
                        end
                    end
                    
                    // Try to forward zero cycle (TODO: one hot too)
                    for (integer j = 0; j < NUM_ZC_FWDS; j=j+1) begin
                        if (IN_zcFwd[j].valid && IN_zcFwd[j].tag == IN_uop[i].tagB) begin
                            OUT_uop[i].srcB <= IN_zcFwd[j].result;
                            found = 1;
                        end
                    end
                    
                    if (!found) begin
                        OUT_uop[i].srcB <= IN_rfReadData[i + NUM_UOPS];
                    end
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
