module Load
#(
    parameter NUM_UOPS=4,
    parameter NUM_WBS=4,
    parameter NUM_XUS=8,
    parameter NUM_ZC_FWDS=2,
    parameter NUM_PC_READS=2
)
(
    input wire clk,
    input wire rst,
    
    input IS_UOp IN_uop[NUM_UOPS-1:0],

    // Writeback Port (snoop) read
    input wire IN_wbHasResult[NUM_WBS-1:0],
    input RES_UOp IN_wbUOp[NUM_WBS-1:0],
    
    input BranchProv IN_branch,
    
    input wire IN_stall[NUM_UOPS-1:0],
    
    // Zero cycle forward inputs
    input ZCForward IN_zcFwd[NUM_ZC_FWDS-1:0],
    
    // PC File read
    output PCFileReadReq OUT_pcRead[NUM_PC_READS-1:0],
    input PCFileEntry IN_pcReadData[NUM_PC_READS-1:0],
    
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
        
        if (i < NUM_PC_READS) begin
            OUT_pcRead[i].valid = IN_uop[i].valid;
            OUT_pcRead[i].addr = IN_uop[i].fetchID;
        end
    end
    
    // LD/ST only use one register read port
    OUT_rfReadAddr[2+NUM_UOPS] = 'x;
    OUT_rfReadAddr[3+NUM_UOPS] = 'x;
end

FuncUnit outFU[NUM_UOPS-1:0];

EX_UOp outUOpReg[NUM_UOPS-1:0];
reg[1:0] operandIsReg[NUM_UOPS-1:0];

always_comb begin
    for (integer i = 0; i < NUM_UOPS; i=i+1) begin

        OUT_uop[i] = EX_UOp'{valid: 0, default: 'x};
        if (outUOpReg[i].valid) begin
            OUT_uop[i] = outUOpReg[i];
            
            // forward values from register file and pc file combinationally
            if (operandIsReg[i][0]) OUT_uop[i].srcA = IN_rfReadData[i];
            if (operandIsReg[i][1]) OUT_uop[i].srcB = IN_rfReadData[i+NUM_UOPS];
            
            OUT_uop[i].bpi = '0;
            if (i < NUM_PC_READS) begin
                OUT_uop[i].pc = {IN_pcReadData[i].pc[30:$bits(FetchOff_t)], outUOpReg[i].fetchOffs, 1'b0};
                OUT_uop[i].fetchStartOffs = IN_pcReadData[i].pc[$bits(FetchOff_t)-1:0];
                OUT_uop[i].fetchPredOffs = IN_pcReadData[i].branchPos;
                if (outUOpReg[i].fetchOffs == IN_pcReadData[i].branchPos)
                    OUT_uop[i].bpi = IN_pcReadData[i].bpi;
            end
        end

    end
end

always_ff@(posedge clk) begin
    if (rst) begin
        for (integer i = 0; i < NUM_UOPS; i=i+1) begin
            outUOpReg[i] <= 'x;
            outUOpReg[i].valid <= 0;
        end
    end
    else begin
        for (integer i = 0; i < NUM_UOPS; i=i+1) begin
            if (!IN_stall[i] && IN_uop[i].valid && (!IN_branch.taken || ($signed(IN_uop[i].sqN - IN_branch.sqN) <= 0))) begin       
                
                outUOpReg[i].imm <= IN_uop[i].imm;
                
                // jalr uses a different encoding
                if ((i == 0 || i == 1) && IN_uop[i].fu == FU_INT && 
                    (IN_uop[i].opcode == INT_V_JALR || IN_uop[i].opcode == INT_V_JR)
                ) begin
                    outUOpReg[i].imm <= 'x;
                    outUOpReg[i].imm[11:0] <= IN_uop[i].imm12;
                end

                outUOpReg[i].fetchOffs <= IN_uop[i].fetchOffs;
                outUOpReg[i].sqN <= IN_uop[i].sqN;
                outUOpReg[i].tagDst <= IN_uop[i].tagDst;
                outUOpReg[i].fetchID <= IN_uop[i].fetchID;
                outUOpReg[i].loadSqN <= IN_uop[i].loadSqN;
                outUOpReg[i].storeSqN <= IN_uop[i].storeSqN;
                outUOpReg[i].compressed <= IN_uop[i].compressed;
                outUOpReg[i].opcode <= IN_uop[i].opcode;
                outUOpReg[i].fu <= IN_uop[i].fu;
                outUOpReg[i].valid <= 1;

                operandIsReg[i] <= 2'b00;
                
                outUOpReg[i].srcA <= 'x;
                if (IN_uop[i].tagA[6]) begin
                    outUOpReg[i].srcA <= {{26{IN_uop[i].tagA[5]}}, IN_uop[i].tagA[5:0]};
                end
                else begin 
                    reg found = 0;
                    
                    // Try to forward from wbs
                    for (integer j = 0; j < NUM_WBS; j=j+1) begin
                        // TODO: one-hot
                        if (IN_wbHasResult[j] && IN_uop[i].tagA == IN_wbUOp[j].tagDst) begin
                            outUOpReg[i].srcA <= IN_wbUOp[j].result;
                            found = 1;
                        end
                    end
                    
                    // Try to forward zero cycle (TODO: one hot too)
                    for (integer j = 0; j < NUM_ZC_FWDS; j=j+1) begin
                        if (IN_zcFwd[j].valid && IN_zcFwd[j].tag == IN_uop[i].tagA) begin
                            outUOpReg[i].srcA <= IN_zcFwd[j].result;
                            found = 1;
                        end
                    end
                
                    if (!found) begin
                        operandIsReg[i][0] <= 1;
                    end
                end
                
                outUOpReg[i].srcB <= 'x;
                if (IN_uop[i].immB || i == 2 || i == 3) begin
                    outUOpReg[i].srcB <= IN_uop[i].imm;
                end
                else if (IN_uop[i].tagB[6]) begin
                    outUOpReg[i].srcB <= {{26{IN_uop[i].tagB[5]}}, IN_uop[i].tagB[5:0]};
                end
                else begin
                    reg found = 0;
                    for (integer j = 0; j < NUM_WBS; j=j+1) begin
                        // TODO: one-hot
                        if (IN_wbHasResult[j] && IN_uop[i].tagB == IN_wbUOp[j].tagDst) begin
                            outUOpReg[i].srcB <= IN_wbUOp[j].result;
                            found = 1;
                        end
                    end
                    
                    // Try to forward zero cycle (TODO: one hot too)
                    for (integer j = 0; j < NUM_ZC_FWDS; j=j+1) begin
                        if (IN_zcFwd[j].valid && IN_zcFwd[j].tag == IN_uop[i].tagB) begin
                            outUOpReg[i].srcB <= IN_zcFwd[j].result;
                            found = 1;
                        end
                    end
                    
                    if (!found) begin
                        operandIsReg[i][1] <= 1;
                    end
                end
            end
            else if (!IN_stall[i] || (outUOpReg[i].valid && IN_branch.taken && $signed(outUOpReg[i].sqN - IN_branch.sqN) > 0)) begin
                outUOpReg[i] <= 'x;
                outUOpReg[i].valid <= 0;
            end
            else if (IN_stall[i]) begin
                if (operandIsReg[i][0]) outUOpReg[i].srcA <= IN_rfReadData[i];
                if (operandIsReg[i][1]) outUOpReg[i].srcB <= IN_rfReadData[i+NUM_UOPS];
                operandIsReg[i] <= 2'b00;
            end
        
        end 
    end
end


endmodule
