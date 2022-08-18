module Load
#(
    parameter NUM_UOPS=1,
    parameter NUM_WBS=1
)
(
    input wire clk,
    input wire rst,

    input wire IN_uopValid[NUM_UOPS-1:0],
    input R_UOp IN_uop[NUM_UOPS-1:0],

    // Writeback Port (snoop) read
    input wire IN_wbValid[NUM_WBS-1:0],
    input wire[5:0] IN_wbTag[NUM_WBS-1:0],
    input wire[31:0] IN_wbResult[NUM_WBS-1:0],

    // Register File read
    output reg OUT_rfReadValid[2*NUM_UOPS-1:0],
    output reg[5:0] OUT_rfReadAddr[2*NUM_UOPS-1:0],
    input wire[31:0] IN_rfReadData[2*NUM_UOPS-1:0],

    output UOp OUT_uop[NUM_UOPS-1:0]
);
integer i;
integer j;

always_comb begin
    for (i = 0; i < NUM_UOPS; i=i+1) begin
        OUT_rfReadValid[i] = IN_uop[i].availA;
        OUT_rfReadAddr[i] = IN_uop[i].tagA;

        OUT_rfReadValid[i+NUM_UOPS] = IN_uop[i].availB;
        OUT_rfReadAddr[i+NUM_UOPS] = IN_uop[i].tagB;
    end
end

always_ff@(posedge clk) begin
    if (rst) begin

    end
    else begin  
        for (i = 0; i < NUM_UOPS; i=i+1) begin     
            if (IN_uopValid[i]) begin       
                OUT_uop[i].imm <= IN_uop[i].imm;
                OUT_uop[i].tagA <= IN_uop[i].tagA;
                OUT_uop[i].tagB <= IN_uop[i].tagB;
                OUT_uop[i].sqN <= IN_uop[i].sqN;
                OUT_uop[i].tagDst <= IN_uop[i].tagDst;
                OUT_uop[i].nmDst <= IN_uop[i].nmDst;
                OUT_uop[i].opcode <= IN_uop[i].opcode;
                OUT_uop[i].valid <= 1;

                // Default is operand unavailable
                OUT_uop[i].availA <= 0;

                // Some instructions just use the pc as an operand.             
                if (IN_uop[i].pcA) begin
                    OUT_uop[i].availA <= 1;
                    OUT_uop[i].srcA <= IN_uop[i].pc;
                end
                // Try to get from register file
                else if (IN_uop[i].availA) begin
                    OUT_uop[i].availA <= 1;
                    OUT_uop[i].srcA <= IN_rfReadData[i];
                end
                // Try to get from current WB
                //else begin
                //    reg found = 0;
                //    for (j = 0; j < NUM_WBS; j=j+1) begin
                //        // TODO: ignore contention here instead of handling it.
                //        if (!found && IN_wbValid[j] && IN_uop[i].tagA == IN_wbTag[j]) begin
                //            OUT_uop[i].srcA <= IN_wbResult[j];
                //            OUT_uop[i].availA <= 1;
                //            found = 1;
                //        end
                //    end
                //end

                // Default is operand unavailable
                OUT_uop[i].availB <= 0;

                if (IN_uop[i].immB) begin
                    OUT_uop[i].availB <= 1;
                    OUT_uop[i].srcB <= IN_uop[i].imm;
                end
                // Try to get from register file
                else if (IN_uop[i].availB) begin
                    OUT_uop[i].availB <= 1;
                    OUT_uop[i].srcB <= IN_rfReadData[i + NUM_UOPS];
                end
                // Try to get from current WB
                //else begin
                //    reg found = 0;
                //    for (j = 0; j < NUM_WBS; j=j+1) begin
                //        // TODO: ignore contention here instead of handling it.
                //        if (!found && IN_wbValid[j] && IN_uop[i].tagB == IN_wbTag[j]) begin
                //            OUT_uop[i].srcB <= IN_wbResult[j];
                //            OUT_uop[i].availB <= 1;
                //            found = 1;
                //        end
                //    end
                //end
            end
            else begin
                OUT_uop[i].valid <= 0;
            end
        
        end 
    end
end


endmodule