`include "../hardfloat/HardFloat_consts.vi"

module FPU
(
    input wire clk,
    input wire rst,
    input wire en,
    
    input BranchProv IN_branch,
    input EX_UOp IN_uop,
    
    input wire[2:0] IN_fRoundMode,
    
    output RES_UOp OUT_uop
);

wire[32:0] srcArec;
wire[32:0] srcBrec;
fNToRecFN#(8, 24) recA (.in(IN_uop.srcA), .out(srcArec));
fNToRecFN#(8, 24) recB (.in(IN_uop.srcB), .out(srcBrec));

wire[2:0] rm = IN_fRoundMode;

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
    .control(`flControl_tininessAfterRounding),
    .in(srcArec),
    .roundingMode(rm),
    .signedOut(IN_uop.opcode[2:0] == FPU_FCVTWS),
    .out(toInt),
    .intExceptionFlags(intFlags)
);

wire[32:0] fromInt;
wire[4:0] fromIntFlags;
iNToRecFN#(32, 8, 24)  intToRec
(
    .control(`flControl_tininessAfterRounding),
    .signedIn(IN_uop.opcode[2:0] == FPU_FCVTSW),
    .in(IN_uop.srcA),
    .roundingMode(rm),
    .out(fromInt),
    .exceptionFlags(fromIntFlags)
);

wire[32:0] addSub;
wire[4:0] addSubFlags;
addRecFN#(8, 24) addRec
(
    .control(`flControl_tininessAfterRounding),
    .subOp(IN_uop.opcode[2:0] == FPU_FSUB_S),
    .a(srcArec),
    .b(srcBrec),
    .roundingMode(rm),
    .out(addSub),
    .exceptionFlags(addSubFlags)
);

reg[32:0] recResult;
always_comb begin
    case(IN_uop.opcode[2:0])
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
    
    OUT_uop <= 'x;
    OUT_uop.valid <= 0;

    if (!rst && en && IN_uop.valid && (!IN_branch.taken || $signed(IN_uop.sqN - IN_branch.sqN) <= 0)) begin
        
        reg[4:0] except = 0;
        
        OUT_uop.tagDst <= IN_uop.tagDst;
        OUT_uop.nmDst <= IN_uop.nmDst;
        OUT_uop.sqN <= IN_uop.sqN;
        OUT_uop.valid <= 1;
        OUT_uop.doNotCommit <= 0;
        
        if (IN_uop.opcode[5:3] == 3'b101) begin
            case (IN_uop.opcode)
                
                FPU_FEQ_S: begin
                    OUT_uop.result <= {31'b0, equal};
                    except = compareFlags;
                end
                FPU_FLE_S: begin
                    OUT_uop.result <= {31'b0, equal || lessThan};
                    except = compareFlags;
                end
                FPU_FLT_S: begin
                    OUT_uop.result <= {31'b0, lessThan};
                    except = compareFlags;
                end
                            
                FPU_FMIN_S: begin
                    if (minMaxCanonicalNaN)
                        OUT_uop.result <= 32'h7FC00000;
                    else if (minChooseA)
                        OUT_uop.result <= IN_uop.srcA;
                    else
                        OUT_uop.result <= IN_uop.srcB;
                    except = compareFlags;
                end
                FPU_FMAX_S: begin
                    if (minMaxCanonicalNaN)
                        OUT_uop.result <= 32'h7FC00000;
                    else if (maxChooseA)
                        OUT_uop.result <= IN_uop.srcA;
                    else
                        OUT_uop.result <= IN_uop.srcB;
                    except = compareFlags;
                end
                default: begin end
            endcase
        end
        else begin
            case (IN_uop.opcode[2:0])
                FPU_FADD_S,
                FPU_FSUB_S: begin
                     except = addSubFlags;
                     OUT_uop.result <= fpResult;
                end
                FPU_FCVTSWU,
                FPU_FCVTSW: begin
                    except = fromIntFlags;
                    OUT_uop.result <= fpResult;
                end
    
                FPU_FCVTWS,
                FPU_FCVTWUS: begin
                    except = {intFlags[2] | intFlags[1], 3'b0, intFlags[0]};
                    OUT_uop.result <= toInt;
                end
                default: begin end
            endcase
        end
        
        /* verilator lint_off CASEOVERLAP */
        casez (except)
            5'b00000: OUT_uop.flags <= FLAGS_NONE;
            5'b???1?: OUT_uop.flags <= Flags'(FLAGS_FP_UF);
            5'b??1??: OUT_uop.flags <= Flags'(FLAGS_FP_OF);
            5'b?1???: OUT_uop.flags <= Flags'(FLAGS_FP_DZ);
            5'b1????: OUT_uop.flags <= Flags'(FLAGS_FP_NV);
            5'b????1: OUT_uop.flags <= Flags'(FLAGS_FP_NX);
        endcase
        /* verilator lint_on CASEOVERLAP */
        
        if (IN_uop.opcode[5:3] == 3'b111 && IN_fRoundMode >= 3'b101)
            OUT_uop.flags <= FLAGS_ILLEGAL_INSTR;

        
    end
end

endmodule
