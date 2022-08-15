module Decode
(
    input wire clk,
    input wire rst,
    input wire[31:0] IN_instr,
    
    output wire[31:0] OUT_pc,
    output UOp OUT_uop,
    output FuncUnit OUT_fu
);


wire[31:0] wbResult;
wire[4:0] wbRegNm;
wire[5:0] wbRegTag;
wire wbValid = (wbRegNm != 0);

wire DEC_enable;

// IF -> RS -> EX -> ROB -> WB
reg[4:0] stateValid;

wire PC_enable = !pcWrite;

wire[31:0] pcIn;
wire pcWrite;
wire[5:0] branchTag;

wire[31:0] IF_pc;
reg [31:0] DE_pc;

assign OUT_pc = IF_pc;
ProgramCounter progCnt
(
    .clk(clk),
    .en(PC_enable),
    .rst(rst),
    .IN_pc(pcIn),
    .IN_write(pcWrite),
    .OUT_pc(IF_pc)
);

always_ff@(posedge clk) begin
    if (rst)
        stateValid <= 0;
    else if (pcWrite)
        stateValid <= 5'b10000;
    else
        stateValid <= {stateValid[3:1], stateValid[0] && DEC_enable, 1'b1};

    DE_pc <= IF_pc;
end

D_UOp decodedInstr;
wire invalidInstr;

UOp uop;

assign OUT_uop = uop;
assign OUT_fu = decodedInstr.fu;

wire[5:0] RAT_dstTag;

wire ratLookupAvailA;
wire ratLookupAvailB;

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

    uop.valid = stateValid[0] && DEC_enable && !pcWrite;
    uop.imm = decodedInstr.imm;
    uop.opcode = decodedInstr.opcode;
    uop.nmDst = decodedInstr.rd;
    uop.tagDst = RAT_dstTag;

    if (decodedInstr.pcA) begin
        uop.srcA = DE_pc;
        uop.tagA = 6'bx;
        uop.availA = 1;
    end
    else if (ratLookupAvailA) begin
        uop.srcA = ratLookupSrcA;
        uop.tagA = 6'bx;
        uop.availA = 1;
    end
    else if (ratLookupTagA == wbRegTag) begin
        uop.srcA = wbResult;
        uop.tagA = 6'bx;
        uop.availA = 1;
    end
    else if (ratLookupTagA == INT_resTag) begin
        uop.srcA = INT_result;
        uop.tagA = 6'bx;
        uop.availA = 1;
    end
    else if (robAvailA) begin
        uop.srcA = robLookupSrcA;
        uop.tagA = 6'bx;
        uop.availA = 1;
    end
    else begin
        uop.srcA = {32{1'bx}};
        uop.tagA = ratLookupTagA;
        uop.availA = 0;
    end


    if (decodedInstr.immB) begin
        uop.srcB = uop.imm;
        uop.tagB = 6'bx;
        uop.availB = 1;
    end
    else if (ratLookupAvailB) begin
        uop.srcB = ratLookupSrcB;
        uop.tagB = 6'bx;
        uop.availB = 1;
    end
    else if (ratLookupTagB == wbRegTag) begin
        uop.srcB = wbResult;
        uop.tagB = 6'bx;
        uop.availB = 1;
    end
    else if (ratLookupTagB == INT_resTag) begin
        uop.srcB = INT_result;
        uop.tagB = 6'bx;
        uop.availB = 1;
    end
    else if (robAvailB) begin
        uop.srcB = robLookupSrcB;
        uop.tagB = 6'bx;
        uop.availB = 1;
    end
    else begin
        uop.srcB = {32{1'bx}};
        uop.tagB = ratLookupTagB;
        uop.availB = 0;
    end
end

InstrDecoder idec
(
    .IN_instr(IN_instr),
    .IN_pc(DE_pc),

    .OUT_uop(decodedInstr),
    .OUT_invalid(invalidInstr)
);

RAT rat
(
    .clk(clk),
    .en(stateValid[0] && DEC_enable && !pcWrite),
    .rst(rst),
    .rdRegNm('{decodedInstr.rs0, decodedInstr.rs1}),
    .wrRegNm('{decodedInstr.rd}),
    .wbResult('{wbResult}),
    .wbValid('{wbValid}),
    .wbRegNm('{wbRegNm}),
    .wbRegTag('{wbRegTag}),

    .IN_branchTaken(pcWrite),
    .IN_branchTag(branchTag),

    .rdRegValue('{ratLookupSrcA, ratLookupSrcB}),
    .rdRegTag('{ratLookupTagA, ratLookupTagB}),
    .rdRegAvail('{ratLookupAvailA, ratLookupAvailB}),
    .wrRegTag('{RAT_dstTag})
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

    .IN_invalidate(pcWrite),
    .IN_invalidateTag(branchTag),

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
    
    .IN_valid(INT_valid && stateValid[2]),
    .IN_operands(INT_operands),
    .IN_opcode(INT_opcode),
    .IN_tagDst(INT_tagDst),
    .IN_nmDst(INT_nmDst),

    .OUT_branchTaken(pcWrite),
    .OUT_branchAddress(pcIn),
    .OUT_branchTag(branchTag),
    
    .OUT_result(INT_result),
    .OUT_tagDst(INT_resTag),
    .OUT_nmDst(INT_resName)
);

wire[5:0] ROB_maxTag;

ROB rob
(
    .clk(clk),
    .rst(rst),
    .IN_valid('{stateValid[3]}),
    .IN_results('{INT_result}),
    .IN_tags('{INT_resTag}),
    .IN_names('{INT_resName}),
    .IN_flags('{0}), // placeholder
    .IN_read_tags('{ratLookupTagA, ratLookupTagB}),

    .IN_invalidate(pcWrite),
    .IN_invalidateTag(branchTag),
    
    .OUT_maxTag(ROB_maxTag),
    .OUT_results('{wbResult}),
    .OUT_names('{wbRegNm}),
    .OUT_tags('{wbRegTag}),

    .OUT_read_results('{robLookupSrcA, robLookupSrcB}),
    .OUT_read_avail('{robAvailA, robAvailB})
);

assign DEC_enable = !INT_full && ($signed(RAT_dstTag - ROB_maxTag) <= 0);

endmodule