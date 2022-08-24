module Core
#(
    parameter NUM_UOPS=2
)
(
    input wire clk,
    input wire rst,
    input wire[31:0] IN_instr[NUM_UOPS-1:0],

    input wire[31:0] IN_MEM_readData,
    
    output wire[31:0] OUT_MEM_addr,
    output wire[31:0] OUT_MEM_writeData,
    output wire OUT_MEM_writeEnable,
    output wire OUT_MEM_readEnable,
    output wire[3:0] OUT_MEM_writeMask,
    
    output wire[31:0] OUT_pc[NUM_UOPS-1:0],
    output wire OUT_halt
);

integer i;

wire wbValid[NUM_UOPS-1:0];
wire[4:0] wbRegNm[NUM_UOPS-1:0];
wire[5:0] wbRegSqN[NUM_UOPS-1:0];
wire[5:0] wbRegTag[NUM_UOPS-1:0];
wire[31:0] wbResult[NUM_UOPS-1:0];
Flags wbFlags[NUM_UOPS-1:0];

wire wbHasResult[NUM_UOPS-1:0];
assign wbHasResult[0] = wbValid[0] && wbRegNm[0] != 0;
assign wbHasResult[1] = wbValid[1] && wbRegNm[1] != 0;

wire[4:0] comRegNm[NUM_UOPS-1:0];
wire[5:0] comRegTag[NUM_UOPS-1:0];
wire[5:0] comSqN[NUM_UOPS-1:0];
wire comValid[NUM_UOPS-1:0];

wire IF_enable;

// IF -> DE -> RN
reg[2:0] stateValid;

BranchProv branchProvs[1:0];
BranchProv branch;
always_comb begin
    branch.taken = 0;
    branch.sqN = 0;
    for (i = 0; i < 2; i=i+1) begin
        if (branchProvs[i].taken && (!branch.taken || $signed(branchProvs[i].sqN - branch.sqN) < 0)) begin
            branch.taken = 1;
            branch.dstPC = branchProvs[i].dstPC;
            branch.sqN = branchProvs[i].sqN;
        end
    end
end

reg disableMispredFlush;
reg mispredFlush;

wire[31:0] IF_pc[NUM_UOPS-1:0];
reg [31:0] DE_pc[NUM_UOPS-1:0];

assign OUT_pc = IF_pc;
ProgramCounter progCnt
(
    .clk(clk),
    .en(stateValid[0]),
    .rst(rst),
    .IN_pc(branch.dstPC),
    .IN_write(branch.taken),
    .OUT_pc(IF_pc)
);

wire[5:0] RN_nextSqN;
wire[5:0] ROB_curSqN;

always_ff@(posedge clk) begin
    if (rst) begin
        stateValid <= 3'b001;
        mispredFlush <= 0;
        disableMispredFlush <= 0;
    end
    else if (branch.taken) begin
        stateValid <= 3'b000;
        mispredFlush <= (ROB_curSqN != RN_nextSqN);
        disableMispredFlush <= 0;
    end
    // When a branch mispredict happens, we need to let the pipeline
    // run entirely dry.
    else if (mispredFlush) begin
        stateValid <= 3'b000;
        disableMispredFlush <= (ROB_curSqN == RN_nextSqN);
        if (disableMispredFlush)
            mispredFlush <= 0;
        // TODO: Think about mispredict flush to make sure this is correct and clean it up.
        //mispredFlush <= (ROB_curSqN != RN_nextSqN);
    end
    else
        stateValid <= {stateValid[1:0], IF_enable};
    
    if (!rst) begin
        DE_pc[0] <= IF_pc[0];
        DE_pc[1] <= IF_pc[1];
    end
end


D_UOp DE_uop[NUM_UOPS-1:0];

InstrDecoder idec
(
    .IN_instr(IN_instr),
    .IN_pc(DE_pc),

    .OUT_uop(DE_uop)
);

R_UOp RN_uop[NUM_UOPS-1:0];
reg RN_uopValid[NUM_UOPS-1:0];
Rename rn 
(
    .clk(clk),
    .en(stateValid[1] && !branch.taken),
    .rst(rst),

    .IN_uop(DE_uop),

    .comValid(comValid),
    .comRegNm(comRegNm),
    .comRegTag(comRegTag),
    .comSqN(comSqN),

    .IN_wbValid(wbHasResult),
    .IN_wbTag(wbRegTag),
    .IN_wbNm(wbRegNm),

    .IN_branchTaken(branch.taken),
    .IN_branchSqN(branch.sqN), 
    .IN_mispredFlush(mispredFlush),   

    .OUT_uopValid(RN_uopValid),
    .OUT_uop(RN_uop),
    .OUT_nextSqN(RN_nextSqN)
);

wire[31:0] INT_result;
wire[5:0] INT_resTag;
wire[4:0] INT_resName;

wire RV_uopValid[NUM_UOPS-1:0];
R_UOp RV_uop[NUM_UOPS-1:0];

wire wbStall;

wire[4:0] RV_freeEntries;
ReservationStation rv
(
    .clk(clk),
    .rst(rst),

    .IN_wbStall('{0, wbStall}),
    .IN_uopValid(RN_uopValid),
    .IN_uop(RN_uop),
    
    .IN_LD_fu(LD_fu),
    .IN_LD_uop(LD_uop),
    .IN_LD_wbStall('{0, wbStall}),
    .IN_LD_wbStallNext('{0, wbStallNext}),
    
    .IN_resultValid(wbHasResult),
    .IN_resultTag(wbRegTag),

    .IN_invalidate(branch.taken),
    .IN_invalidateSqN(branch.sqN),
    
    .IN_nextCommitSqN(ROB_curSqN),

    .OUT_valid(RV_uopValid),
    .OUT_uop(RV_uop),
    .OUT_free(RV_freeEntries)
);


wire RF_readEnable[3:0];
wire[5:0] RF_readAddress[3:0];
wire[31:0] RF_readData[3:0];

RF rf
(
    .clk(clk),
    .rst(rst),
    .IN_readEnable(RF_readEnable),
    .IN_readAddress(RF_readAddress),
    .OUT_readData(RF_readData),

    .IN_writeEnable(wbHasResult),
    .IN_writeAddress(wbRegTag),
    .IN_writeData(wbResult)
);

EX_UOp LD_uop[NUM_UOPS-1:0];
wire[3:0] enabledXUs[NUM_UOPS-1:0];
FuncUnit LD_fu[NUM_UOPS-1:0];
Load ld
(
    .clk(clk),
    .rst(rst),
    .IN_wbStall('{0, wbStall}),
    .IN_uopValid(RV_uopValid),
    .IN_uop(RV_uop),
    
    .IN_wbValid(wbHasResult),
    .IN_wbTag(wbRegTag),
    .IN_wbResult(wbResult),
    .IN_invalidate(branch.taken),
    .IN_invalidateSqN(branch.sqN),

    .OUT_rfReadValid(RF_readEnable),
    .OUT_rfReadAddr(RF_readAddress),
    .IN_rfReadData(RF_readData),
    
    .OUT_enableXU(enabledXUs),
    .OUT_funcUnit(LD_fu),
    .OUT_uop(LD_uop)
);
wire LSU_wbReq;


wire INTALU_valid;
wire[5:0] INTALU_sqN;
wire INTALU_wbReq;
Flags INTALU_flags;
IntALU ialu
(
    .clk(clk),
    .en(enabledXUs[0][0]),
    .rst(rst),
    
    .IN_wbStall(LSU_wbReq),
    .IN_uop(LD_uop[0]),
    .IN_invalidate(branch.taken),
    .IN_invalidateSqN(branch.sqN),

    .OUT_wbReq(INTALU_wbReq),
    .OUT_valid(INTALU_valid),
    
    .OUT_branchTaken(branchProvs[0].taken),
    .OUT_branchAddress(branchProvs[0].dstPC),
    .OUT_branchSqN(branchProvs[0].sqN),
    
    .OUT_result(INT_result),
    .OUT_tagDst(INT_resTag),
    .OUT_nmDst(INT_resName),
    .OUT_sqN(INTALU_sqN),
    .OUT_flags(INTALU_flags)
);

wire LSU_uopValid;
RES_UOp LSU_uop;
assign wbStall = LSU_wbReq && INTALU_wbReq;
LSU lsu
(
    .clk(clk),
    .rst(rst),
    .IN_valid(LD_uop[0].valid && enabledXUs[0][1]),
    .IN_uop(LD_uop[0]),
    
    .IN_invalidate(branch.taken),
    .IN_invalidateSqN(branch.sqN),
    
    .IN_MEM_readData(IN_MEM_readData),
    .OUT_MEM_addr(OUT_MEM_addr),
    .OUT_MEM_writeData(OUT_MEM_writeData),
    .OUT_MEM_writeEnable(OUT_MEM_writeEnable),
    .OUT_MEM_writeMask(OUT_MEM_writeMask),
    .OUT_MEM_readEnable(OUT_MEM_readEnable),

    .OUT_wbReq(LSU_wbReq),

    .OUT_valid(LSU_uopValid),
    .OUT_uop(LSU_uop)
);
assign wbRegNm[0] = !LSU_uopValid ? 
    INT_resName :
    LSU_uop.nmDst;
assign wbRegTag[0] = !LSU_uopValid ? 
    INT_resTag :
    LSU_uop.tagDst;
assign wbResult[0] = !LSU_uopValid ? 
    INT_result :
    LSU_uop.result;

assign wbRegSqN[0] = !LSU_uopValid ? 
    INTALU_sqN :
    LSU_uop.sqN;
    
assign wbFlags[0] = !LSU_uopValid ?
    INTALU_flags :
    FLAGS_NONE;
    
assign wbValid[0] = (INTALU_valid || LSU_uopValid);

wire wbStallNext = LD_uop[0].valid && enabledXUs[0][1] && !wbStall && RV_uopValid[0] && RV_uop[0].fu == FU_INT;

IntALU ialu1
(
    .clk(clk),
    .en(enabledXUs[1][0]),
    .rst(rst),
    
    .IN_wbStall(0),
    .IN_uop(LD_uop[1]),
    .IN_invalidate(branch.taken),
    .IN_invalidateSqN(branch.sqN),

    .OUT_wbReq(),
    .OUT_valid(wbValid[1]),
    
    .OUT_branchTaken(branchProvs[1].taken),
    .OUT_branchAddress(branchProvs[1].dstPC),
    .OUT_branchSqN(branchProvs[1].sqN),
    
    .OUT_result(wbResult[1]),
    .OUT_tagDst(wbRegTag[1]),
    .OUT_nmDst(wbRegNm[1]),
    .OUT_sqN(wbRegSqN[1]),
    .OUT_flags(wbFlags[1])
);

wire[5:0] ROB_maxSqN;
ROB rob
(
    .clk(clk),
    .rst(rst),
    .IN_valid(wbValid),
    .IN_tags(wbRegTag),
    .IN_names(wbRegNm),
    .IN_sqNs(wbRegSqN),
    .IN_flags(wbFlags), // placeholder

    .IN_invalidate(branch.taken),
    .IN_invalidateSqN(branch.sqN),
    
    .OUT_maxSqN(ROB_maxSqN),
    .OUT_curSqN(ROB_curSqN),

    .OUT_comNames(comRegNm),
    .OUT_comTags(comRegTag),
    .OUT_comValid(comValid),
    .OUT_comSqNs(comSqN),
    
    .OUT_halt(OUT_halt)
);

// this should be done properly, ideally effects in rename cycle instead of IF
assign IF_enable = (RV_freeEntries > 3 * NUM_UOPS) && ($signed(RN_nextSqN - ROB_maxSqN) <= -2*NUM_UOPS) && !branch.taken;

endmodule
