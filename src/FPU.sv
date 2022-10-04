module FPU
(
    input wire clk,
    input wire rst,
    input wire en,
    
    input BranchProv IN_branch,
    input EX_UOp IN_uop,
    
    output RES_UOp OUT_uop
);

wire[32:0] srcArec;
wire[32:0] srcBrec;
fNToRecFN#(8, 24) recA (.in(IN_uop.srcA), .out(srcArec));
fNToRecFN#(8, 24) recB (.in(IN_uop.srcB), .out(srcBrec));

wire[2:0] rm = 0;

wire lessThan;
wire equal;
wire greaterThan;
wire[4:0] compareFlags;
compareRecFN#(8, 24) compare
(
    .a(srcArec),
    .b(srcBrec),
    .signaling(1'b1),
    .lt(lessThan),
    .eq(equal),
    .gt(greaterThan),
    .unordered(),
    .exceptionFlags(compareFlags)
);

wire[31:0] toInt;
wire[2:0] intFlags;
recFNToIN#(8, 24, 32) toIntRec
(
    .control(0),
    .in(srcArec),
    .roundingMode(rm),
    .signedOut(IN_uop.opcode == FPU_FCVTWS),
    .out(toInt),
    .intExceptionFlags(intFlags)
);

wire[32:0] addSub;
wire[4:0] addSubFlags;
addRecFN#(8, 24) addRec
(
    .control(0),
    .subOp(IN_uop.opcode == FPU_FSUB_S),
    .a(srcArec),
    .b(srcBrec),
    .roundingMode(rm),
    .out(addSub),
    .exceptionFlags(addSubFlags)
);

wire[32:0] mul;
wire[4:0] mulFlags;
mulRecFN#(8, 24) mulRec
(
    .control(0),
    .a(srcArec),
    .b(srcBrec),
    .roundingMode(rm),
    .out(mul),
    .exceptionFlags(mulFlags)
);

wire[31:0] fpResult;
recFNToFN#(8, 24) recode
(
    .in(IN_uop.opcode == FPU_FMUL_S ? mul : addSub),
    .out(fpResult)
);

always@(posedge clk) begin
    
    if (rst) begin
        OUT_uop.valid <= 0;
    end
    else if (en && IN_uop.valid && (!IN_branch.taken || $signed(IN_uop.sqN - IN_branch.sqN) <= 0)) begin
        
        OUT_uop.isBranch <= 0;
        OUT_uop.branchTaken <= 0;
        OUT_uop.branchID <= IN_uop.branchID;
        OUT_uop.tagDst <= IN_uop.tagDst;
        OUT_uop.nmDst <= IN_uop.nmDst;
        OUT_uop.sqN <= IN_uop.sqN;
        OUT_uop.flags <= 0;
        OUT_uop.valid <= 1;
        OUT_uop.pc <= IN_uop.pc;
            
        case (IN_uop.opcode)
            
            FPU_FADD_S,
            FPU_FSUB_S,
            FPU_FMUL_S: OUT_uop.result <= fpResult;
            
            FPU_FEQ_S: OUT_uop.result <= {31'b0, equal};
            FPU_FLE_S: OUT_uop.result <= {31'b0, equal || lessThan};
            FPU_FLT_S: OUT_uop.result <= {31'b0, lessThan};
            
            FPU_FCVTWS,
            FPU_FCVTWUS: OUT_uop.result <= toInt;
            default: begin end
        endcase
    end
    else begin
        OUT_uop.valid <= 0;
    end

end

endmodule
