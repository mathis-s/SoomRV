module Decode
(
    input wire clk,
    input wire rst,
    input wire[31:0] IN_instr,
    input wire[31:0] IN_pc,

    output UOp OUT_uop,
    output FuncUnit OUT_fu
);


wire[31:0] wbResult;
wire[4:0] wbRegNm;
wire wbValid = (wbRegNm != 0);

reg stateValid;

always_ff@(posedge clk) begin
    stateValid <= !rst;
end

D_UOp decodedInstr;
wire invalidInstr;
wire[31:0] registerSrcA;
wire[31:0] registerSrcB;

UOp uop;

assign OUT_uop = uop;
assign OUT_fu = decodedInstr.fu;

assign uop.valid = stateValid;

assign uop.imm = decodedInstr.imm;
assign uop.opcode = decodedInstr.opcode;

assign uop.srcA = decodedInstr.pcA ? IN_pc : registerSrcA;
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
    .wbResult('{wbResult}),
    .wbValid('{wbValid}),
    .wbRegNm('{wbRegNm}),

    .rdRegValue('{registerSrcA, registerSrcB}),
    .rdRegTag('{uop.tagA, uop.tagB}),

    .wrRegTag('{uop.tagDst})
);


// Later fuse the RV here with the actual integer alu, and only have integer FU
// instantiated here.
wire[31:0] INT_operands[2:0];
wire[5:0] INT_tagDst;
wire[5:0] INT_opcode;
wire INT_valid;
wire INT_full;

wire[31:0] INT_result;
wire[5:0] INT_resTag;

ReservationStation rv
(
    .clk(clk),
    .rst(rst),

    .IN_uop(uop),
    .IN_resultBus('{INT_result}),
    .IN_resultTag('{INT_resTag}),

    .OUT_valid(INT_valid),
    .OUT_operands(INT_operands),
    .OUT_opcode(INT_opcode),
    .OUT_tagDst(INT_tagDst),
    .OUT_full(INT_full)
);

IntALU ialu
(
    .clk(clk),
    .rst(rst),
    
    .IN_valid(INT_valid),
    .IN_operands(INT_operands),
    .IN_opcode(INT_opcode),
    .IN_tagDst(INT_tagDst),
    
    .OUT_result(INT_result),
    .OUT_tagDst(INT_resTag)
);

wire ROB_full;
ROB rob
(
    .clk(clk),
    .rst(rst),
    .IN_valid('{stateValid && INT_resTag != 0}),
    .IN_results('{INT_result}),
    .IN_tags('{INT_resTag}),
    .IN_names('{17}), // placeholder
    .IN_flags('{0}), // placeholder
    .IN_read_tags('{0, 0}), // placeholder
    
    .OUT_full(ROB_full),
    .OUT_results('{wbResult}),
    .OUT_names('{wbRegNm}),

    .OUT_read_results(),
    .OUT_read_avail()
);

endmodule