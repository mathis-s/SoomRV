module FPU
(
    input wire clk,
    input wire rst,
    input wire en,
    
    input BranchProv IN_branch,
    input EX_UOp IN_uop,
    
    //output FloatFlagsUpdate OUT_flagsUpdate,
    
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
    .signaling(IN_uop.opcode == FPU_FLT_S || IN_uop.opcode == FPU_FLE_S),
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

wire[32:0] fromInt;
wire[4:0] fromIntFlags;
iNToRecFN#(32, 8, 24)  intToRec
(
    .control(0),
    .signedIn(IN_uop.opcode == FPU_FCVTSW),
    .in(IN_uop.srcA),
    .roundingMode(rm),
    .out(fromInt),
    .exceptionFlags(fromIntFlags)
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

reg[32:0] recResult;
always_comb begin
    case(IN_uop.opcode)
        FPU_FCVTSWU,
        FPU_FCVTSW: recResult = fromInt;
        default: recResult = addSub;
    endcase
end
wire[31:0] fpResult;
recFNToFN#(8, 24) recode
(
    .in(recResult),
    .out(fpResult)
);

wire srcAIsNaN = IN_uop.srcA[30:23] == 8'hFF && IN_uop.srcA[22:0] != 0;
wire srcBIsNaN = IN_uop.srcB[30:23] == 8'hFF && IN_uop.srcB[22:0] != 0;

wire minChooseA = 
    srcBIsNaN || 
    lessThan ||
    (equal && IN_uop.srcA[31] && !IN_uop.srcB[31]);
    
wire maxChooseA = 
    srcBIsNaN || 
    greaterThan ||
    (equal && !IN_uop.srcA[31] && IN_uop.srcB[31]);
    
wire minMaxCanonicalNaN = srcAIsNaN && srcBIsNaN;

always@(posedge clk) begin
    
    //OUT_flagsUpdate.valid <= 0;
    
    if (rst) begin
        OUT_uop.valid <= 0;
    end
    else if (en && IN_uop.valid && (!IN_branch.taken || $signed(IN_uop.sqN - IN_branch.sqN) <= 0)) begin
        
        OUT_uop.tagDst <= IN_uop.tagDst;
        OUT_uop.nmDst <= IN_uop.nmDst;
        OUT_uop.sqN <= IN_uop.sqN;
        OUT_uop.flags <= FLAGS_NONE;
        OUT_uop.valid <= 1;
        OUT_uop.pc <= IN_uop.pc;
        OUT_uop.doNotCommit <= 0;
        OUT_uop.compressed <= 0;
        
        //OUT_flagsUpdate.valid <= 1;
        //OUT_flagsUpdate.sqN <= IN_uop.sqN;
            
        case (IN_uop.opcode)
            
            FPU_FADD_S,
            FPU_FSUB_S,
            FPU_FCVTSWU,
            FPU_FCVTSW: OUT_uop.result <= fpResult;
            
            FPU_FEQ_S: OUT_uop.result <= {31'b0, equal};
            FPU_FLE_S: OUT_uop.result <= {31'b0, equal || lessThan};
            FPU_FLT_S: OUT_uop.result <= {31'b0, lessThan};
            
            FPU_FSGNJ_S: OUT_uop.result <= {IN_uop.srcB[31], IN_uop.srcA[30:0]};
            FPU_FSGNJN_S: OUT_uop.result <= {!IN_uop.srcB[31], IN_uop.srcA[30:0]};
            FPU_FSGNJX_S: OUT_uop.result <= {IN_uop.srcA[31] ^ IN_uop.srcB[31], IN_uop.srcA[30:0]};
            
            FPU_FCVTWS,
            FPU_FCVTWUS: OUT_uop.result <= toInt;
            
            FPU_FMVWX, FPU_FMVXW: OUT_uop.result <= IN_uop.srcA;
                        
            FPU_FMIN_S: begin
                if (minMaxCanonicalNaN)
                    OUT_uop.result <= 32'h7FC00000;
                else if (minChooseA)
                    OUT_uop.result <= IN_uop.srcA;
                else
                    OUT_uop.result <= IN_uop.srcB;
            end
            FPU_FMAX_S: begin
                if (minMaxCanonicalNaN)
                    OUT_uop.result <= 32'h7FC00000;
                else if (maxChooseA)
                    OUT_uop.result <= IN_uop.srcA;
                else
                    OUT_uop.result <= IN_uop.srcB;
            end
            default: begin end
        endcase
        
        begin 
            reg[4:0] except;
            case (IN_uop.opcode)
                FPU_FADD_S: except = addSubFlags;
                FPU_FCVTSWU, 
                FPU_FCVTSW: except = fromIntFlags;
                
                FPU_FMIN_S,
                FPU_FMAX_S,
                FPU_FEQ_S, 
                FPU_FLE_S, 
                FPU_FLT_S: except = compareFlags;
                FPU_FCVTWS, 
                FPU_FCVTWUS: except = {intFlags[2] | intFlags[1], 3'b0, intFlags[0]};
                default: except = 0;
            endcase
            
            //$display("flags %b\n", except);
            
            /* verilator lint_off CASEOVERLAP */
            casez (except)
                5'b00000: OUT_uop.flags <= FLAGS_NONE;
                5'b???1?: OUT_uop.flags <= FLAGS_FP_UF;
                5'b??1??: OUT_uop.flags <= FLAGS_FP_OF;
                5'b?1???: OUT_uop.flags <= FLAGS_FP_DZ;
                5'b1????: OUT_uop.flags <= FLAGS_FP_NV;
                5'b????1: OUT_uop.flags <= FLAGS_FP_NX;
            endcase
            /* verilator lint_on CASEOVERLAP */
        end
        
    end
    else begin
        OUT_uop.valid <= 0;
    end

end

endmodule
