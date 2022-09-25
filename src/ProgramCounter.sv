module ProgramCounter
#(
    parameter NUM_UOPS=2,
    parameter NUM_BLOCKS=4
)
(
    input wire clk,
    input wire en0,
    input wire en1,
    input wire rst,

    input wire[31:0] IN_pc,
    input wire IN_write,

    input wire[63:0] IN_instr,
    
    input wire IN_BP_branchFound,
    input wire IN_BP_branchTaken,
    input wire IN_BP_isJump,
    input wire[31:0] IN_BP_branchSrc,
    input wire[31:0] IN_BP_branchDst,
    input wire[5:0] IN_BP_branchID,
    input wire IN_BP_multipleBranches,
    input wire IN_BP_branchCompr,

    output reg[31:0] OUT_pcRaw,
    
    output IF_Instr OUT_instrs[NUM_BLOCKS-1:0],
    
    input wire[31:0] IN_instrMappingBase,
    input wire IN_instrMappingHalfSize,
    output wire OUT_instrMappingMiss
);

integer i;

reg[30:0] pc;
reg[30:0] pcLast;
reg[3:0] bMaskLast;
reg[5:0] bIndexLast[3:0];
reg bPredLast[3:0];

assign OUT_pcRaw = {pc, 1'b0};

always_comb begin
    for (i = 0; i < NUM_BLOCKS; i=i+1)
        OUT_instrs[i].instr = IN_instr[(16*i)+:16];
end

assign OUT_instrMappingMiss = 0;//(pc[30:13] != IN_instrMappingBase[31:14]) ||
    //(IN_instrMappingHalfSize && pc[12] != IN_instrMappingBase[13]);

always_ff@(posedge clk) begin
    if (rst) begin
        pc <= 0;
    end
    else if (IN_write) begin
        pc <= IN_pc[31:1];
    end
    else begin
        if (en1) begin
            for (i = 0; i < NUM_BLOCKS; i=i+1) begin
                OUT_instrs[i].pc <= {{pcLast[30:2], 2'b00} + 31'd1 * i[30:0]};
                OUT_instrs[i].valid <= (i[1:0] >= pcLast[1:0]) && bMaskLast[i];
                OUT_instrs[i].branchID <= bIndexLast[i];
                OUT_instrs[i].branchPred <= bPredLast[i];
            end
        end

        if (en0) begin
            if (IN_BP_branchFound) begin
                if (IN_BP_isJump || IN_BP_branchTaken) begin
                    
                    pc <= IN_BP_branchDst[31:1];
                    pcLast <= pc;
                    
                    case (IN_BP_branchSrc[2:1])
                        2'b00: bMaskLast <= 4'b0001;
                        2'b01: bMaskLast <= 4'b0011;
                        2'b10: bMaskLast <= 4'b0111;
                        2'b11: bMaskLast <= 4'b1111;
                    endcase
                    for (i = 0; i < 4; i=i+1) begin
                        bIndexLast[i] <= 63;
                        bPredLast[i] <= 0;
                    end
                    
                    bIndexLast[IN_BP_branchSrc[2:1]] <= IN_BP_branchID;
                    bPredLast[IN_BP_branchSrc[2:1]] <= 1;
                end
                // Branch found, not taken
                else begin
                    pcLast <= pc;
                    
                    // There is a second branch in this block,
                    // go there.
                    if (IN_BP_multipleBranches) begin
                        pc <= IN_BP_branchSrc[31:1] + 1;
                        case (IN_BP_branchSrc[2:1])
                            2'b00: bMaskLast <= 4'b0001;
                            2'b01: bMaskLast <= 4'b0011;
                            2'b10: bMaskLast <= 4'b0111;
                            2'b11: bMaskLast <= 4'b1111;
                        endcase
                    end
                    else begin
                        bMaskLast <= 4'b1111;
                        pc <= {pc[30:2] + 29'b1, 2'b00};
                    end
                    
                    for (i = 0; i < 4; i=i+1) begin
                        bIndexLast[i] <= 63;
                        bPredLast[i] <= 0;
                    end
                    bIndexLast[IN_BP_branchSrc[2:1]] <= IN_BP_branchID;
                    bPredLast[IN_BP_branchSrc[2:1]] <= 0;
                end
            end
            else begin
                pc <= {pc[30:2] + 29'b1, 2'b00};
                pcLast <= pc;
                bMaskLast <= 4'b1111;
                for (i = 0; i < 4; i=i+1) begin
                    bIndexLast[i] <= 63;
                    bPredLast[i] <= 0;
                end
            end
        end
    end
end

endmodule
