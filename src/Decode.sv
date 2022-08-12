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
wire[5:0] wbRegTag;
wire wbValid = (wbRegNm != 0);

reg stateValid;

always_ff@(posedge clk) begin
    stateValid <= !rst;
end

D_UOp decodedInstr;
wire invalidInstr;

UOp uop;

assign OUT_uop = uop;
assign OUT_fu = decodedInstr.fu;

wire[5:0]  ratLookupTagA;
wire[5:0]  ratLookupTagB;

wire[31:0] ratLookupSrcA;
wire[31:0] ratLookupSrcB;

wire[31:0] robLookupSrcA;
wire robAvailA;
wire[31:0] robLookupSrcB;
wire robAvailB;

// We will very likely want to transition to doing
// ROB lookup in the next pipeline stage.
// Like this, critical path is quite long, as 
// the tag from RAT lookup is required for ROB lookup.
always_comb begin

    uop.valid = stateValid;
    uop.imm = decodedInstr.imm;
    uop.opcode = decodedInstr.opcode;
    uop.nmDst = decodedInstr.rd;

    if (decodedInstr.pcA) begin
        uop.srcA = IN_pc;
        uop.tagA = 0;
    end
    else if (ratLookupTagA == 0) begin
        uop.srcA = ratLookupSrcA;
        uop.tagA = 0;
    end
    else if (robAvailA) begin
        uop.srcA = robLookupSrcA;
        uop.tagA = 0;
    end
    else begin
        uop.srcA = {32{1'bx}};
        uop.tagA = ratLookupTagA;
    end


    if (decodedInstr.immB) begin
        uop.srcB = uop.imm;
        uop.tagB = 0;
    end
    else if (ratLookupTagB == 0) begin
        uop.srcB = ratLookupSrcB;
        uop.tagB = 0;
    end
    else if (robAvailB) begin
        uop.srcB = robLookupSrcB;
        uop.tagB = 0;
    end
    else begin
        uop.srcB = {32{1'bx}};
        uop.tagB = ratLookupTagB;
    end
end

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
    .wbRegTag('{wbRegTag}),

    .rdRegValue('{ratLookupSrcA, ratLookupSrcB}),
    .rdRegTag('{ratLookupTagA, ratLookupTagB}),

    .wrRegTag('{uop.tagDst})
);


// Later fuse the RV here with the actual integer alu, and only have integer FU
// instantiated here.
wire[31:0] INT_operands[2:0];
wire[5:0] INT_tagDst;
wire[4:0] INT_nmDst;
wire[5:0] INT_opcode;
wire INT_valid;
wire INT_full;

wire[31:0] INT_result;
wire[5:0] INT_resTag;
wire[4:0] INT_resName;

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
    .OUT_nmDst(INT_nmDst),
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
    .IN_nmDst(INT_nmDst),
    
    .OUT_result(INT_result),
    .OUT_tagDst(INT_resTag),
    .OUT_nmDst(INT_resName)
);

wire ROB_full;
ROB rob
(
    .clk(clk),
    .rst(rst),
    .IN_valid('{stateValid && INT_resTag != 0}),
    .IN_results('{INT_result}),
    .IN_tags('{INT_resTag}),
    .IN_names('{INT_resName}), // placeholder
    .IN_flags('{0}), // placeholder
    .IN_read_tags('{ratLookupTagA, ratLookupTagB}),
    
    .OUT_full(ROB_full),
    .OUT_results('{wbResult}),
    .OUT_names('{wbRegNm}),
    .OUT_tags('{wbRegTag}),

    .OUT_read_results('{robLookupSrcA, robLookupSrcB}),
    .OUT_read_avail('{robAvailA, robAvailB})
);

endmodule