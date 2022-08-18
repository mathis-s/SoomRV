module Decode
(
    input wire clk,
    input wire rst,
    input wire[31:0] IN_instr,
    
    output wire[31:0] OUT_pc
);

wire wbValid;
wire[4:0] wbRegNm;
wire[5:0] wbRegTag;
wire[31:0] wbResult;

wire[4:0] comRegNm;
wire[5:0] comRegTag;
wire comValid;

wire DEC_enable;

// (IF ->) DE -> RN -> (RS -> LD -> EX -> ROB -> WB)
reg[1:0] stateValid;

wire PC_enable = !pcWrite;

wire[31:0] pcIn;
wire pcWrite;
wire[5:0] branchSqN;

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
        stateValid <= 2'b00;
    else
        stateValid <= {DEC_enable, 1'b1};

    DE_pc <= IF_pc;
end

D_UOp DE_uop;
wire invalidInstr;

InstrDecoder idec
(
    .IN_instr(IN_instr),
    .IN_pc(DE_pc),

    .OUT_uop(DE_uop),
    .OUT_invalid(invalidInstr)
);

wire[5:0] BQ_maxCommitSqN;
wire BQ_maxCommitSqNValid;

R_UOp RN_uop;
reg RN_uopValid[0:0];
Rename rn 
(
    .clk(clk),
    .en(stateValid[0] && !pcWrite),
    .rst(rst),

    .IN_uop('{DE_uop}),

    .comValid('{comValid}),
    .comRegNm('{comRegNm}),
    .comRegTag('{comRegTag}),

    .IN_wbValid('{wbValid}),
    .IN_wbTag('{wbRegTag}),
    .IN_wbNm('{wbRegNm}),

    .IN_branchTaken(pcWrite),
    .IN_branchSqN(branchSqN),    

    .OUT_uopValid(RN_uopValid),
    .OUT_uop('{RN_uop})
);

// jumps also in here for now
wire isBranch = 
    RN_uop.opcode == INT_BEQ || 
    RN_uop.opcode == INT_BNE || 
    RN_uop.opcode == INT_BLT || 
    RN_uop.opcode == INT_BGE || 
    RN_uop.opcode == INT_BLTU || 
    RN_uop.opcode == INT_BGEU || 
    RN_uop.opcode == INT_JAL || 
    RN_uop.opcode == INT_JALR;
BranchQueue bq
(
    .clk(clk),
    .rst(rst),
    .IN_valid(RN_uopValid[0]),
    .IN_isBranch(isBranch),
    .IN_tag(RN_uop.sqN),
    
    .IN_checkedValid(INTALU_valid && INTALU_isBranch),
    .IN_checkedTag(branchSqN),
    .IN_checkedCorrect(!pcWrite),
    
    .OUT_full(),
    .OUT_commitLimitValid(BQ_maxCommitSqNValid),
    .OUT_commitLimitTag(BQ_maxCommitSqN)
);

// Later fuse the RV here with the actual integer alu, and only have integer FU
// instantiated here.
wire INT_full;

wire[31:0] INT_result;
wire[5:0] INT_resTag;
wire[4:0] INT_resName;

wire RV_uopValid;
R_UOp RV_uop;

ReservationStation rv
(
    .clk(clk),
    .rst(rst),

    .IN_uopValid(RN_uopValid[0]),
    .IN_uop(RN_uop),
    .IN_resultValid('{INTALU_valid}),
    .IN_resultTag('{INT_resTag}),

    .IN_invalidate(pcWrite),
    .IN_invalidateSqN(branchSqN),

    .OUT_valid(RV_uopValid),
    .OUT_uop(RV_uop),
    .OUT_full(INT_full)
);


wire RF_readEnable[1:0];
wire[5:0] RF_readAddress[1:0];
wire[31:0] RF_readData[1:0];

wire RF_writeEnable[0:0];
wire[5:0] RF_writeAddress[0:0];
wire[31:0] RF_writeData[0:0];

RF rf
(
    .clk(clk),
    .rst(rst),
    .IN_readEnable(RF_readEnable),
    .IN_readAddress(RF_readAddress),
    .OUT_readData(RF_readData),

    .IN_writeEnable(RF_writeEnable),
    .IN_writeAddress(RF_writeAddress),
    .IN_writeData(RF_writeData)
);

UOp LD_uop;
Load ld
(
    .clk(clk),
    .rst(rst),
    .IN_uopValid('{RV_uopValid}),
    .IN_uop('{RV_uop}),
    
    .IN_wbValid('{wbValid}),
    .IN_wbTag('{wbRegTag}),
    .IN_wbResult('{wbResult}),

    .OUT_rfReadValid(RF_readEnable),
    .OUT_rfReadAddr(RF_readAddress),
    .IN_rfReadData(RF_readData),

    .OUT_uop('{LD_uop})
);


wire INTALU_valid;
wire INTALU_isBranch;
wire[5:0] INTALU_sqN;
IntALU ialu
(
    .clk(clk),
    .en(1),
    .rst(rst),
    
    .IN_valid(LD_uop.valid),
    .IN_operands('{LD_uop.imm, LD_uop.srcB, LD_uop.srcA}),
    .IN_opcode(LD_uop.opcode),
    .IN_tagDst(LD_uop.tagDst),
    .IN_nmDst(LD_uop.nmDst),
    .IN_sqN(LD_uop.sqN),    

    .OUT_isBranch(INTALU_isBranch),
    .OUT_valid(INTALU_valid),
    .OUT_branchTaken(pcWrite),
    .OUT_branchAddress(pcIn),
    .OUT_branchSqN(branchSqN),
    
    .OUT_result(INT_result),
    .OUT_tagDst(INT_resTag),
    .OUT_nmDst(INT_resName),
    .OUT_sqN(INTALU_sqN)
    
);
assign RF_writeEnable[0] = INTALU_valid && (INT_resName != 0);
assign RF_writeAddress[0] = INT_resTag;
assign RF_writeData[0] = INT_result;
assign wbValid = INTALU_valid;
assign wbRegNm = INT_resName;
assign wbRegTag = INT_resTag;
assign wbResult = INT_result;

wire[5:0] ROB_maxSqN;
ROB rob
(
    .clk(clk),
    .rst(rst),
    .IN_valid('{INTALU_valid}),
    .IN_tags('{INT_resTag}),
    .IN_names('{INT_resName}),
    .IN_sqNs('{INTALU_sqN}),
    .IN_flags('{0}), // placeholder

    .IN_invalidate(pcWrite),
    .IN_invalidateSqN(branchSqN),

    .IN_maxCommitSqNValid(BQ_maxCommitSqNValid),
    .IN_maxCommitSqN(BQ_maxCommitSqN),
    
    .OUT_maxTag(ROB_maxSqN),

    .OUT_comNames('{comRegNm}),
    .OUT_comTags('{comRegTag}),
    .OUT_comValid('{comValid})
);

assign DEC_enable = stateValid[0] && !INT_full && ($signed(RN_uop.sqN - ROB_maxSqN) <= 0) && !pcWrite;

endmodule