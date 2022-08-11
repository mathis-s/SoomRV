module Decode
(
    input wire clk,
    input wire rst,
    input wire[31:0] IN_instr,
    input wire[31:0] IN_pc,

    input wire[31:0] IN_wbResult,
    input wire IN_wbValid,
    input wire[4:0] IN_wbRegNm,

    output UOp OUT_uop
);

D_UOp decodedInstr;
wire invalidInstr;
wire[31:0] registerSrcB;
UOp uop;

assign OUT_uop = uop;

assign uop.imm = decodedInstr.imm;
assign uop.immPC = decodedInstr.immPC;
assign uop.opcode = decodedInstr.opcode;
assign uop.fu = decodedInstr.fu;
assign uop.srcB = decodedInstr.immB ? decodedInstr.imm : registerSrcB;

// todo immb field

InstrDecoder idec
(
    .IN_instr(IN_instr),
    .IN_pc(IN_pc),

    .OUT_uop(decodedInstr),
    .OUT_invalid(invalidInstr)
);


RAT rat
(
    .clk(clk),
    .rst(rst),
    .rdRegNm('{decodedInstr.rs0, decodedInstr.rs1}),
    .wrRegNm('{decodedInstr.rd}),
    .wbResult('{IN_wbResult}),
    .wbValid('{IN_wbValid}),
    .wbRegNm('{IN_wbRegNm}),

    .rdRegValue('{uop.srcA, registerSrcB}),
    .rdRegTag('{uop.tagA, uop.tagB}),

    .wrRegTag('{uop.tagDst})
);

endmodule