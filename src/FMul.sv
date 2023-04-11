`include "../hardfloat/HardFloat_consts.vi"

module FMul
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

wire[2:0] rm = IN_uop.opcode[5:3] == 3'b111 ? IN_fRoundMode : IN_uop.opcode[5:3];

wire[32:0] mul;
wire[4:0] mulFlags;
mulRecFN#(8, 24) mulRec
(
    .control(`flControl_tininessAfterRounding),
    .a(srcArec),
    .b(srcBrec),
    .roundingMode(rm),
    .out(mul),
    .exceptionFlags(mulFlags)
);

wire[31:0] fpResult;
recFNToFN#(8, 24) recode
(
    .in(mul),
    .out(fpResult)
);

always@(posedge clk) begin
    
    OUT_uop <= 'x;
    OUT_uop.valid <= 0;
    
    if (!rst && en && IN_uop.valid && (!IN_branch.taken || $signed(IN_uop.sqN - IN_branch.sqN) <= 0)) begin
        
        OUT_uop.tagDst <= IN_uop.tagDst;
        OUT_uop.nmDst <= IN_uop.nmDst;
        OUT_uop.sqN <= IN_uop.sqN;
        OUT_uop.valid <= 1;
        OUT_uop.result <= fpResult;
        OUT_uop.doNotCommit <= 0;

        /* verilator lint_off CASEOVERLAP */
        casez (mulFlags)
            5'b00000: OUT_uop.flags <= FLAGS_NONE;
            5'b???1?: OUT_uop.flags <= Flags'(FLAGS_FP_UF);
            5'b??1??: OUT_uop.flags <= Flags'(FLAGS_FP_OF);
            5'b?1???: OUT_uop.flags <= Flags'(FLAGS_FP_DZ);
            5'b1????: OUT_uop.flags <= Flags'(FLAGS_FP_NV);
            5'b????1: OUT_uop.flags <= Flags'(FLAGS_FP_NX);
        endcase
        /* verilator lint_on CASEOVERLAP */
        if (rm >= 3'b101)
            OUT_uop.flags <= FLAGS_ILLEGAL_INSTR;
    end
end

endmodule
