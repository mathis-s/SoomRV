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
                    
                    // Jump is second instr in bundle
                    if (IN_BP_branchSrc[2]) begin
                        bMaskLast <= 4'b1111;
                        bIndexLast[0] <= 63;
                        bIndexLast[2] <= IN_BP_branchID;
                        bPredLast[0] <= 0;
                        bPredLast[2] <= 1;
                    end
                    // Jump is first instr in bundle
                    else begin
                        bMaskLast <= 4'b0011;
                        bIndexLast[0] <= IN_BP_branchID;
                        bIndexLast[2] <= 63;
                        bPredLast[0] <= 1;
                        bPredLast[2] <= 0;
                    end
                end
                // Branch found, not taken
                else begin

                    bPredLast[0] <= 0;
                    bPredLast[2] <= 0;
                
                    pcLast <= pc;
                    
                    // There is a second branch in this block,
                    // go there.
                    if (IN_BP_multipleBranches) begin
                        pc <= IN_BP_branchSrc[31:1] + 2;
                        // only run first instr
                        bMaskLast <= 4'b0011;
                    end
                    else begin
                        bMaskLast <= 4'b1111;
                        case (pc[1])
                            1'b1: pc <= pc + 2;
                            1'b0: pc <= pc + 4;
                        endcase
                    end
                    
                    if (IN_BP_branchSrc[2]) begin
                        bIndexLast[0] <= 63;
                        bIndexLast[2] <= IN_BP_branchID;
                    end
                    else begin
                        bIndexLast[0] <= IN_BP_branchID;
                        bIndexLast[2] <= 63;
                    end
                    
                end
            end
            else begin
                case (pc[1])
                    1'b1: begin
                        pc <= pc + 2;
                    end
                    1'b0: begin
                        pc <= pc + 4;
                    end
                endcase
                pcLast <= pc;
                bMaskLast <= 4'b1111;
                bIndexLast[0] <= 63;
                bIndexLast[2] <= 63;
                bPredLast[0] <= 0;
                bPredLast[2] <= 0;
            end
        end
    end
end

endmodule
