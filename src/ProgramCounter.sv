module ProgramCounter
#(
    parameter NUM_UOPS=2
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

    output reg[31:0] OUT_pcRaw,

    output reg[31:0] OUT_pc[NUM_UOPS-1:0],
    output reg[31:0] OUT_instr[NUM_UOPS-1:0],
    output reg[5:0] OUT_branchID[NUM_UOPS-1:0],
    output reg OUT_branchPred[NUM_UOPS-1:0],
    output reg OUT_instrValid[NUM_UOPS-1:0],
    
    input wire[31:0] IN_instrMappingBase,
    input wire IN_instrMappingHalfSize,
    output wire OUT_instrMappingMiss
);

integer i;

reg[30:0] pc;
reg[30:0] pcLast;
reg[1:0] bMaskLast;
reg[5:0] bIndexLast[1:0];
reg bPredLast[1:0];

assign OUT_pcRaw = {pc, 1'b0};

always_comb begin
    OUT_instr[0] = IN_instr[31:0];
    OUT_instr[1] = IN_instr[63:32];
end

assign OUT_instrMappingMiss = (pc[30:13] != IN_instrMappingBase[31:14]) ||
    (IN_instrMappingHalfSize && pc[12] != IN_instrMappingBase[13]);

always_ff@(posedge clk) begin
    if (rst) begin
        pc <= 0;
    end
    else if (IN_write) begin
        pc <= IN_pc[31:1];
    end
    else begin
        if (en1) begin
            for (i = 0; i < NUM_UOPS; i=i+1) begin
                OUT_pc[i] <= {{pcLast[30:2], 2'b00} + 31'd2 * i[30:0], 1'b0};
                OUT_instrValid[i] <= (i[0] >= pcLast[1]) && bMaskLast[i];
                OUT_branchID[i] <= bIndexLast[i];
                OUT_branchPred[i] <= bPredLast[i];
            end
        end

        if (en0) begin
            if (IN_BP_branchFound) begin
                if (IN_BP_isJump || IN_BP_branchTaken) begin
                
                    assert(IN_BP_branchTaken);
                    
                    pc <= IN_BP_branchDst[31:1];
                    pcLast <= pc;
                    
                    // Jump is second instr in bundle
                    if (IN_BP_branchSrc[2]) begin
                        bMaskLast <= 2'b11;
                        bIndexLast[0] <= 63;
                        bIndexLast[1] <= IN_BP_branchID;
                        bPredLast[0] <= 0;
                        bPredLast[1] <= 1;
                    end
                    // Jump is first instr in bundle
                    else begin
                        bMaskLast <= 2'b01;
                        bIndexLast[0] <= IN_BP_branchID;
                        bIndexLast[1] <= 63;
                        bPredLast[0] <= 1;
                        bPredLast[1] <= 0;
                    end
                end
                // Is branch
                else begin
                    // always predict as not taken for now
                    bPredLast[0] <= 0;
                    bPredLast[1] <= 0;
                
                    pcLast <= pc;
                    
                    // There is a second branch in this block,
                    // go there.
                    if (IN_BP_multipleBranches) begin
                        pc <= IN_BP_branchSrc[31:1] + 2;
                        // only run first instr
                        bMaskLast <= 2'b01;
                    end
                    else begin
                        bMaskLast <= 2'b11;
                        case (pc[1])
                            1'b1: pc <= pc + 2;
                            1'b0: pc <= pc + 4;
                        endcase
                    end
                    
                    if (IN_BP_branchSrc[2]) begin
                        bIndexLast[0] <= 63;
                        bIndexLast[1] <= IN_BP_branchID;
                    end
                    else begin
                        bIndexLast[0] <= IN_BP_branchID;
                        bIndexLast[1] <= 63;
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
                bMaskLast <= 2'b11;
                bIndexLast[0] <= 63;
                bIndexLast[1] <= 63;
                bPredLast[0] <= 0;
                bPredLast[1] <= 0;
            end
        end
    end
end

endmodule
