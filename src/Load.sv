module Load
#(
    parameter NUM_UOPS=2,
    parameter NUM_WBS=2,
    parameter NUM_XUS=4
)
(
    input wire clk,
    input wire rst,

    // stall for wb contention, on stall simply do nothing and
    // keep the previous output
    input wire IN_wbStall[NUM_UOPS-1:0],
    input wire IN_uopValid[NUM_UOPS-1:0],
    input R_UOp IN_uop[NUM_UOPS-1:0],

    // Writeback Port (snoop) read
    input wire IN_wbValid[NUM_WBS-1:0],
    input wire[5:0] IN_wbTag[NUM_WBS-1:0],
    input wire[31:0] IN_wbResult[NUM_WBS-1:0],
    
    input wire IN_invalidate,
    input wire[5:0] IN_invalidateSqN,

    // Register File read
    output reg OUT_rfReadValid[2*NUM_UOPS-1:0],
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
        OUT_rfReadValid[i] = 1;
        OUT_rfReadAddr[i] = IN_uop[i].tagA;

        OUT_rfReadValid[i+NUM_UOPS] = 1;
        OUT_rfReadAddr[i+NUM_UOPS] = IN_uop[i].tagB;
    end
end

always_ff@(posedge clk) begin
    if (rst) begin

    end
    else begin  
        for (i = 0; i < NUM_UOPS; i=i+1) begin     
            if (!IN_wbStall[i] && IN_uopValid[i] && (!IN_invalidate || ($signed(IN_uop[i].sqN - IN_invalidateSqN) <= 0))) begin       
                OUT_uop[i].imm <= IN_uop[i].imm;
                OUT_uop[i].sqN <= IN_uop[i].sqN;
                OUT_uop[i].tagDst <= IN_uop[i].tagDst;
                OUT_uop[i].nmDst <= IN_uop[i].nmDst;
                OUT_uop[i].opcode <= IN_uop[i].opcode;
                
                OUT_uop[i].zcFwdSrcB <= 0;
                
                OUT_funcUnit[i] <= IN_uop[i].fu;
                
                OUT_uop[i].valid <= 1;

                // Some instructions just use the pc as an operand.             
                if (IN_uop[i].pcA) begin
                    OUT_uop[i].zcFwdSrcA <= 0;
                    OUT_uop[i].srcA <= IN_uop[i].pc;
                    
                end
                // Zero-Cycle forward for INT fu's
                else if (OUT_uop[i].valid && OUT_uop[i].nmDst != 0 && IN_uop[i].tagA == OUT_uop[i].tagDst && OUT_funcUnit[i] == FU_INT && IN_uop[i].fu == FU_INT) begin
                    OUT_uop[i].zcFwdSrcA <= 1;
                    OUT_uop[i].srcA = 32'bx;
                end                
                else begin 
                    reg found = 0;
                    OUT_uop[i].zcFwdSrcA <= 0;
                    for (j = 0; j < NUM_WBS; j=j+1) begin
                        // TODO: ignore contention here instead of handling it.
                        if (!found && IN_wbValid[j] && IN_uop[i].tagA == IN_wbTag[j]) begin
                            OUT_uop[i].srcA <= IN_wbResult[j];
                            found = 1;
                        end
                    end
                
                    if (!found) begin
                        OUT_uop[i].srcA <= IN_rfReadData[i];
                    end
                end
                
                if (IN_uop[i].immB) begin
                    OUT_uop[i].zcFwdSrcB <= 0;
                    OUT_uop[i].srcB <= IN_uop[i].imm;
                end
                // Zero-Cycle forward for INT fu's
                else if (OUT_uop[i].valid && OUT_uop[i].nmDst != 0 && IN_uop[i].tagB == OUT_uop[i].tagDst && OUT_funcUnit[i] == FU_INT && IN_uop[i].fu == FU_INT) begin
                    OUT_uop[i].zcFwdSrcB <= 1;
                    OUT_uop[i].srcB = 32'bx;
                end
                else begin
                    reg found = 0;
                    OUT_uop[i].zcFwdSrcB <= 0;
                    for (j = 0; j < NUM_WBS; j=j+1) begin
                        // TODO: ignore contention here instead of handling it.
                        if (!found && IN_wbValid[j] && IN_uop[i].tagB == IN_wbTag[j]) begin
                            OUT_uop[i].srcB <= IN_wbResult[j];
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
                endcase
            end
            else if (!IN_wbStall[i] || (IN_invalidate && $signed(OUT_uop[i].sqN - IN_invalidateSqN) > 0)) begin
                OUT_uop[i].valid <= 0;
                OUT_enableXU[i] <= 0;
            end
        
        end 
    end
end


endmodule
