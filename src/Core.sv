module Core
#(
    parameter NUM_UOPS=2,
    parameter NUM_WBS=3
)
(
    input wire clk,
    input wire rst,
    input wire en,
    input wire[63:0] IN_instrRaw,

    input wire[31:0] IN_MEM_readData,
    output wire[29:0] OUT_MEM_addr,
    output wire[31:0] OUT_MEM_writeData,
    output wire OUT_MEM_writeEnable,
    output wire OUT_MEM_readEnable,
    output wire[3:0] OUT_MEM_writeMask,
    
    output wire[28:0] OUT_instrAddr,
    output wire OUT_instrReadEnable,
    output wire OUT_halt,

    output wire[15:0] OUT_GPIO_oe,
    output wire[15:0] OUT_GPIO,
    input wire[15:0] IN_GPIO,
    
    output wire OUT_SPI_clk,
    output wire OUT_SPI_mosi,
    input wire IN_SPI_miso,
    
    output wire OUT_MC_ce,
    output wire OUT_MC_we,
    output wire[9:0] OUT_MC_sramAddr,
    output wire[31:0] OUT_MC_extAddr,
    input wire[9:0] IN_MC_progress,
    input wire IN_MC_busy,
    
    output wire OUT_instrMappingMiss,
    input wire[31:0] IN_instrMappingBase,
    input wire IN_instrMappingHalfSize
);

integer i;

RES_UOp wbUOp[NUM_WBS-1:0];
wire wbHasResult[NUM_WBS-1:0];
wire wbHasResult_int[NUM_WBS-1:0];
wire wbHasResult_fp[NUM_WBS-1:0];
assign wbHasResult[0] = wbUOp[0].valid && wbUOp[0].nmDst != 0;
assign wbHasResult[1] = wbUOp[1].valid && wbUOp[1].nmDst != 0;
assign wbHasResult[2] = wbUOp[2].valid && wbUOp[2].nmDst != 0;

assign wbHasResult_int[0] = wbUOp[0].valid && wbUOp[0].nmDst != 0 && !wbUOp[0].nmDst[5];
assign wbHasResult_int[1] = wbUOp[1].valid && wbUOp[1].nmDst != 0 && !wbUOp[1].nmDst[5];
assign wbHasResult_int[2] = wbUOp[2].valid && wbUOp[2].nmDst != 0 && !wbUOp[2].nmDst[5];

assign wbHasResult_fp[0] = wbUOp[0].valid && wbUOp[0].nmDst[5];
assign wbHasResult_fp[1] = wbUOp[1].valid && wbUOp[1].nmDst[5];
assign wbHasResult_fp[2] = wbUOp[2].valid && wbUOp[2].nmDst[5];


CommitUOp comUOps[2:0];

wire comValid[2:0];

wire frontendEn;

wire ifetchEn;

// IF -> DE -> RN
reg[2:0] stateValid;
assign OUT_instrReadEnable = !(ifetchEn && stateValid[0]);

// 
reg[63:0] instrRawBackup;
reg useInstrRawBackup;
always_ff@(posedge clk) begin
    if (rst)
        useInstrRawBackup <= 0;
    else if (!(ifetchEn && stateValid[0])) begin
        instrRawBackup <= instrRaw;
        useInstrRawBackup <= 1;
    end
    else
        useInstrRawBackup <= 0;
end
wire[63:0] instrRaw = useInstrRawBackup ? instrRawBackup : IN_instrRaw;


BranchProv branchProvs[3:0];
BranchProv branch;
wire mispredFlush;
BranchSelector bsel
(
    .clk(clk),
    .rst(rst),
    
    .IN_branches(branchProvs),
    .OUT_branch(branch),
    
    .IN_ROB_curSqN(ROB_curSqN),
    .IN_RN_nextSqN(RN_nextSqN),
    .OUT_mispredFlush(mispredFlush)
);

wire[31:0] PC_pc;
assign OUT_instrAddr = PC_pc[31:3];

wire BP_branchTaken;
wire BP_isJump;
wire[31:0] BP_branchSrc;
wire[31:0] BP_branchDst;
wire[7:0] BP_branchID;
wire BP_multipleBranches;
wire BP_branchFound;
wire BP_branchCompr;

IF_Instr IF_instrs[3:0];

ProgramCounter progCnt
(
    .clk(clk),
    .en0(stateValid[0] && ifetchEn),
    .en1(stateValid[1] && ifetchEn),
    .rst(rst),
    .IN_pc(branch.taken ? branch.dstPC : {DEC_branchDst, 1'b0}),
    .IN_write(branch.taken || DEC_branch),
    .IN_instr(instrRaw),
    
    .IN_BP_branchTaken(BP_branchTaken),
    .IN_BP_isJump(BP_isJump),
    .IN_BP_branchSrc(BP_branchSrc),
    .IN_BP_branchDst(BP_branchDst),
    .IN_BP_branchID(BP_branchID),
    .IN_BP_multipleBranches(BP_multipleBranches),
    .IN_BP_branchFound(BP_branchFound),
    .IN_BP_branchCompr(BP_branchCompr),
    
    .OUT_pcRaw(PC_pc),
    .OUT_instrs(IF_instrs),
    
    .IN_instrMappingBase(IN_instrMappingBase),
    .IN_instrMappingHalfSize(IN_instrMappingHalfSize),
    .OUT_instrMappingMiss(OUT_instrMappingMiss)
);

BTUpdate BP_btUpdates[1:0];
BranchPredictor bp
(
    .clk(clk),
    .rst(rst),
    .IN_mispredFlush(mispredFlush),
    
    .IN_pcValid(stateValid[0] && ifetchEn),
    .IN_pc(PC_pc),
    .OUT_branchTaken(BP_branchTaken),
    .OUT_isJump(BP_isJump),
    .OUT_branchSrc(BP_branchSrc),
    .OUT_branchDst(BP_branchDst),
    .OUT_branchID(BP_branchID),
    .OUT_multipleBranches(BP_multipleBranches),
    .OUT_branchFound(BP_branchFound),
    .OUT_branchCompr(BP_branchCompr),
    
    .IN_btUpdates(BP_btUpdates),
    
    .IN_comUOp(comUOps[0]),
    
    .OUT_CSR_branchCommitted(CSR_branchCommitted)
);

wire[5:0] RN_nextSqN;
wire[5:0] ROB_curSqN;

always_ff@(posedge clk) begin
    if (rst)
        stateValid <= 3'b000;
    // When a branch mispredict happens, we need to let the pipeline
    // run entirely dry.
    else if (branch.taken || DEC_branch)
        stateValid <= 3'b000;
    else if (ifetchEn)
        stateValid <= {stateValid[1:0], 1'b1};
end

wire PD_full;
PD_Instr PD_instrs[3:0];
PreDecode preDec
(
    .clk(clk),
    .rst(rst),
    .ifetchValid(stateValid[2] && ifetchEn),
    .outEn(!FUSE_full),
    
    .OUT_full(PD_full),
    
    .mispred(branch.taken || DEC_branch),
    .IN_instrs(IF_instrs),
    .OUT_instrs(PD_instrs)
);
assign ifetchEn = !PD_full;

D_UOp DE_uop[3:0];

wire DEC_branch;
wire[30:0] DEC_branchDst;
InstrDecoder idec
(
    .clk(clk),
    .rst(rst),
    .IN_invalidate(branch.taken),
    .en(!FUSE_full),
    .IN_instrs(PD_instrs),
    
    .OUT_decBranch(DEC_branch),
    .OUT_decBranchDst(DEC_branchDst),
    
    .OUT_uop(DE_uop)
);

wire FUSE_full;
D_UOp FUSE_uop[2:0];
Fuse fuse
(
    .clk(clk),
    .outEn(frontendEn && !RN_stall),
    .rst(rst),
    .mispredict(branch.taken),
    
    .OUT_full(FUSE_full),
    
    .IN_uop(DE_uop),
    .OUT_uop(FUSE_uop)
);


R_UOp RN_uop[2:0];
reg RN_uopValid[2:0];
wire[5:0] RN_nextLoadSqN;
wire[5:0] RN_nextStoreSqN;
wire RN_stall;
Rename rn 
(
    .clk(clk),
    .en(!branch.taken && !mispredFlush),
    .frontEn(frontendEn),
    .rst(rst),
    
    .OUT_stall(RN_stall),

    .IN_uop(FUSE_uop),

    .IN_comUOp(comUOps),

    .IN_wbHasResult(wbHasResult),
    .IN_wbUOp(wbUOp),

    .IN_branchTaken(branch.taken),
    .IN_branchFlush(branch.flush),
    .IN_branchSqN(branch.sqN),
    .IN_branchLoadSqN(branch.loadSqN),
    .IN_branchStoreSqN(branch.storeSqN),
    .IN_mispredFlush(mispredFlush),   

    .OUT_uopValid(RN_uopValid),
    .OUT_uop(RN_uop),
    .OUT_nextSqN(RN_nextSqN),
    .OUT_nextLoadSqN(RN_nextLoadSqN),
    .OUT_nextStoreSqN(RN_nextStoreSqN)
);

wire RV_uopValid[2:0];
R_UOp RV_uop[2:0];

wire stall[2:0];
assign stall[0] = 0;
assign stall[1] = 0;

wire[4:0] RV_freeEntries;
/*ReservationStation rv
(
    .clk(clk),
    .rst(rst),
    .frontEn(frontendEn),
    
    .IN_DIV_doNotIssue(DIV_doNotIssue),
    .IN_MUL_doNotIssue(MUL_doNotIssue),

    .IN_stall(stall),
    .IN_uopValid(RN_uopValid),
    .IN_uop(RN_uop),
    
    .IN_loadFwdUOp(CC_uop),
    
    .IN_resultValid(wbHasResult),
    .IN_resultUOp(wbUOp),

    .IN_invalidate(branch.taken),
    .IN_invalidateSqN(branch.sqN),
    
    .IN_nextCommitSqN(ROB_curSqN),

    .OUT_valid(RV_uopValid),
    .OUT_uop(RV_uop),
    .OUT_free(RV_freeEntries)
);*/
wire IQ0_full;
IssueQueue#(8,3,3,FU_INT,FU_DIV,FU_FPU,1,0,33) iq0
(
    .clk(clk),
    .rst(rst),
    .frontEn(frontendEn),
    
    .IN_stall(stall[0]),
    .IN_doNotIssueFU1(DIV_doNotIssue),
    
    .IN_uopValid(RN_uopValid),
    .IN_uop(RN_uop),
    
    .IN_resultValid(wbHasResult),
    .IN_resultUOp(wbUOp),
    
    .IN_branch(branch),
    
    .IN_issueValid(RV_uopValid),
    .IN_issueUOps(RV_uop),
    
    .OUT_valid(RV_uopValid[0]),
    .OUT_uop(RV_uop[0]),
    .OUT_full(IQ0_full)
);
wire IQ1_full;
IssueQueue#(8,3,3,FU_INT,FU_MUL,FU_MUL,1,1,9) iq1
(
    .clk(clk),
    .rst(rst),
    .frontEn(frontendEn),
    
    .IN_stall(stall[1]),
    .IN_doNotIssueFU1(MUL_doNotIssue),
    
    .IN_uopValid(RN_uopValid),
    .IN_uop(RN_uop),
    
    .IN_resultValid(wbHasResult),
    .IN_resultUOp(wbUOp),
    
    .IN_branch(branch),
    
    .IN_issueValid(RV_uopValid),
    .IN_issueUOps(RV_uop),
    
    .OUT_valid(RV_uopValid[1]),
    .OUT_uop(RV_uop[1]),
    .OUT_full(IQ1_full)
);
wire IQ2_full;
IssueQueue#(8,3,3,FU_LSU,FU_LSU,FU_LSU,0,0,0) iq2
(
    .clk(clk),
    .rst(rst),
    .frontEn(frontendEn),
    
    .IN_stall(stall[2]),
    .IN_doNotIssueFU1(1'b0),
    
    .IN_uopValid(RN_uopValid),
    .IN_uop(RN_uop),
    
    .IN_resultValid(wbHasResult),
    .IN_resultUOp(wbUOp),
    
    .IN_branch(branch),
    
    .IN_issueValid(RV_uopValid),
    .IN_issueUOps(RV_uop),
    
    .OUT_valid(RV_uopValid[2]),
    .OUT_uop(RV_uop[2]),
    .OUT_full(IQ2_full)
);


wire[5:0] RF_readAddress[5:0];
wire[31:0] RF_readData[5:0];

RF rf
(
    .clk(clk),
    
    .waddr0(wbUOp[0].tagDst[5:0]), .wdata0(wbUOp[0].result), .wen0(wbHasResult_int[0]),
    .waddr1(wbUOp[1].tagDst[5:0]), .wdata1(wbUOp[1].result), .wen1(wbHasResult_int[1]),
    .waddr2(wbUOp[2].tagDst[5:0]), .wdata2(wbUOp[2].result), .wen2(wbHasResult_int[2]),
    .waddr3(6'bx), .wdata3(32'bx), .wen3(1'b0),
    
    .raddr0(RF_readAddress[0]), .rdata0(RF_readData[0]),
    .raddr1(RF_readAddress[1]), .rdata1(RF_readData[1]),
    .raddr2(RF_readAddress[2]), .rdata2(RF_readData[2]),
    .raddr3(RF_readAddress[3]), .rdata3(RF_readData[3]),
    .raddr4(RF_readAddress[4]), .rdata4(RF_readData[4]),
    .raddr5(RF_readAddress[5]), .rdata5(RF_readData[5]),
    .raddr6(6'b0), .rdata6(),
    .raddr7(6'b0), .rdata7()
);

wire[5:0] RF_FP_readAddress[3:0];
wire[31:0] RF_FP_readData[3:0];
RF_FP rf_fp
(
    .clk(clk),
    .waddr0(wbUOp[0].tagDst[5:0]), .wdata0(wbUOp[0].result), .wen0(wbHasResult_fp[0]),
    .waddr1(wbUOp[2].tagDst[5:0]), .wdata1(wbUOp[2].result), .wen1(wbHasResult_fp[2]),
    
    .raddr0(RF_FP_readAddress[0]), .rdata0(RF_FP_readData[0]),
    .raddr1(RF_FP_readAddress[1]), .rdata1(RF_FP_readData[1]),
    .raddr2(RF_FP_readAddress[2]), .rdata2(RF_FP_readData[2]),
    .raddr3(RF_FP_readAddress[3]), .rdata3(RF_FP_readData[3])
);

EX_UOp LD_uop[2:0];
wire[4:0] enabledXUs[2:0];
FuncUnit LD_fu[2:0];

wire[31:0] LD_zcFwdResult[1:0];
wire[6:0] LD_zcFwdTag[1:0];
wire LD_zcFwdValid[1:0];
Load ld
(
    .clk(clk),
    .rst(rst),
    
    .IN_uopValid(RV_uopValid),
    .IN_uop(RV_uop),
    
    .IN_wbHasResult(wbHasResult),
    .IN_wbUOp(wbUOp),
    
    .IN_invalidate(branch.taken),
    .IN_invalidateSqN(branch.sqN),
    .IN_stall(stall),
    
    .IN_zcFwdResult(LD_zcFwdResult),
    .IN_zcFwdTag(LD_zcFwdTag),
    .IN_zcFwdValid(LD_zcFwdValid),

    .OUT_rfReadAddr(RF_readAddress),
    .IN_rfReadData(RF_readData),
    
    .OUT_rfReadAddr_fp(RF_FP_readAddress),
    .IN_rfReadData_fp(RF_FP_readData),
    
    .OUT_enableXU(enabledXUs),
    .OUT_funcUnit(LD_fu),
    .OUT_uop(LD_uop)
);


wire INTALU_wbReq;
RES_UOp INT0_uop;
IntALU ialu
(
    .clk(clk),
    .en(enabledXUs[0][0]),
    .rst(rst),
    
    .IN_wbStall(1'b0),
    .IN_uop(LD_uop[0]),
    .IN_invalidate(branch.taken),
    .IN_invalidateSqN(branch.sqN),

    .OUT_wbReq(INTALU_wbReq),
    
    .OUT_branch(branchProvs[0]),
    .OUT_btUpdate(BP_btUpdates[0]),
    
    .OUT_zcFwdResult(LD_zcFwdResult[0]),
    .OUT_zcFwdTag(LD_zcFwdTag[0]),
    .OUT_zcFwdValid(LD_zcFwdValid[0]),
    
    .OUT_uop(INT0_uop)
);


wire DIV_busy;
RES_UOp DIV_uop;
wire DIV_doNotIssue = DIV_busy || (LD_uop[0].valid && enabledXUs[0][3]) || (RV_uopValid[0] && RV_uop[0].fu == FU_DIV);
Divide div
(
    .clk(clk),
    .rst(rst),
    .en(enabledXUs[0][3]),
    
    .OUT_busy(DIV_busy),
    
    .IN_branch(branch),
    .IN_uop(LD_uop[0]),
    .OUT_uop(DIV_uop)

);

RES_UOp FPU_uop;
FPU fpu
(
    .clk(clk),
    .rst(rst),
    .en(enabledXUs[0][4]),
    
    .IN_branch(branch),
    .IN_uop(LD_uop[0]),
    .OUT_uop(FPU_uop)
);

assign wbUOp[0] = INT0_uop.valid ? INT0_uop : (FPU_uop.valid ? FPU_uop : DIV_uop);
//assign wbStall[0] = DIV_busy;

AGU_UOp CC_uop;
CacheController cc
(
    .clk(clk),
    .rst(rst),
    
    .IN_branch(branch),
    .IN_SQ_empty(SQ_empty),
    .OUT_stall(stall[2]),
    
    .IN_uop('{AGU_uop}),
    .OUT_uop('{CC_uop}),
    
    .OUT_MC_ce(OUT_MC_ce),
    .OUT_MC_we(OUT_MC_we),
    .OUT_MC_sramAddr(OUT_MC_sramAddr),
    .OUT_MC_extAddr(OUT_MC_extAddr),
    .IN_MC_progress(IN_MC_progress),
    .IN_MC_busy(IN_MC_busy)
);

AGU_UOp AGU_uop;
AGU agu
(
    .clk(clk),
    .rst(rst),
    .en(enabledXUs[2][1]),
    .stall(stall[2]),
    
    .IN_branch(branch),

    .IN_uop(LD_uop[2]),
    .OUT_uop(AGU_uop)
);

wire[5:0] LB_maxLoadSqN;
LoadBuffer lb
(
    .clk(clk),
    .rst(rst),
    .commitSqN(ROB_curSqN),
    
    .valid('{AGU_uop.valid}),
    .isLoad('{AGU_uop.isLoad}),
    .pc('{AGU_uop.pc}),
    .addr('{AGU_uop.addr}),
    .sqN('{AGU_uop.sqN}),
    .loadSqN('{AGU_uop.loadSqN}),
    .storeSqN('{AGU_uop.storeSqN}),
    
    .IN_branch(branch),
    .OUT_branch(branchProvs[2]),
    
    .OUT_maxLoadSqN(LB_maxLoadSqN)
);

wire[5:0] SQ_maxStoreSqN;
wire CSR_ce[0:0];
wire[31:0] CSR_dataOut[0:0];

wire SQ_empty;
StoreQueue sq
(
    .clk(clk),
    .rst(rst),
    .IN_disable(IN_MC_busy || OUT_MC_ce),
    .OUT_empty(SQ_empty),
    
    .IN_uop('{CC_uop}),
    
    .IN_curSqN(ROB_curSqN),
    
    .IN_branch(branch),
    
    .IN_MEM_data('{IN_MEM_readData}),
    .OUT_MEM_addr('{OUT_MEM_addr}),
    .OUT_MEM_data('{OUT_MEM_writeData}),
    .OUT_MEM_we('{OUT_MEM_writeEnable}),
    .OUT_MEM_ce('{OUT_MEM_readEnable}),
    .OUT_MEM_wm('{OUT_MEM_writeMask}),
    
    .IN_CSR_data(CSR_dataOut),
    .OUT_CSR_ce(CSR_ce),
    
    .OUT_uop('{wbUOp[2]}),
    .OUT_maxStoreSqN(SQ_maxStoreSqN),
    
    .IN_IO_busy(IO_busy)
);

RES_UOp INT1_uop;
IntALU ialu1
(
    .clk(clk),
    .en(enabledXUs[1][0]),
    .rst(rst),
    
    .IN_wbStall(1'b0),
    .IN_uop(LD_uop[1]),
    .IN_invalidate(branch.taken),
    .IN_invalidateSqN(branch.sqN),

    .OUT_wbReq(),

    .OUT_branch(branchProvs[1]),
    .OUT_btUpdate(BP_btUpdates[1]),
    
    .OUT_zcFwdResult(LD_zcFwdResult[1]),
    .OUT_zcFwdTag(LD_zcFwdTag[1]),
    .OUT_zcFwdValid(LD_zcFwdValid[1]),
    
    .OUT_uop(INT1_uop)
);

RES_UOp MUL_uop;
wire MUL_wbReq;
wire MUL_busy;
wire MUL_doNotIssue = MUL_busy || (LD_uop[1].valid && enabledXUs[1][2]) || (RV_uopValid[1] && RV_uop[1].fu == FU_MUL);
MultiplySmall mul
(
    .clk(clk),
    .rst(rst),
    .en(enabledXUs[1][2]),
    
    .OUT_busy(MUL_busy),
    
    .IN_branch(branch),
    .IN_uop(LD_uop[1]),
    .OUT_uop(MUL_uop)
);

assign wbUOp[1] = INT1_uop.valid ? INT1_uop : MUL_uop;
//assign wbStall[1] = enabledXUs[1][0] && MUL_wbReq && LD_uop[1].valid;

wire[5:0] ROB_maxSqN;

wire[31:0] CR_irqAddr;
Flags ROB_irqFlags;
wire[31:0] ROB_irqSrc;
wire[14:0] ROB_irqMemAddr;
ROB rob
(
    .clk(clk),
    .rst(rst),
    .IN_uop(wbUOp),

    .IN_invalidate(branch.taken),
    .IN_invalidateSqN(branch.sqN),
    
    .OUT_maxSqN(ROB_maxSqN),
    .OUT_curSqN(ROB_curSqN),
    
    .OUT_comUOp(comUOps),
    
    .IN_irqAddr(CR_irqAddr),
    .OUT_irqFlags(ROB_irqFlags),
    .OUT_irqSrc(ROB_irqSrc),
    .OUT_irqMemAddr(ROB_irqMemAddr),
    
    .OUT_fence(),
    
    .OUT_branch(branchProvs[3]),
    
    .OUT_halt(OUT_halt)
);

wire IO_busy;
wire CSR_branchCommitted;
ControlRegs cr
(
    .clk(clk),
    .rst(rst),
    .IN_ce(CSR_ce[0]),
    .IN_we(OUT_MEM_writeEnable),
    .IN_wm(OUT_MEM_writeMask),
    .IN_addr(OUT_MEM_addr[6:0]),
    .IN_data(OUT_MEM_writeData),
    .OUT_data(CSR_dataOut[0]),

    .IN_comValid('{comUOps[0].valid, comUOps[1].valid, comUOps[2].valid}),
    .IN_branch(branchProvs[1]),
    .IN_wbValid('{wbUOp[0].valid, wbUOp[1].valid, wbUOp[2].valid}),
    .IN_ifValid('{DE_uop[0].valid, DE_uop[1].valid, DE_uop[2].valid}),
    .IN_comBranch(CSR_branchCommitted),
    
    .OUT_irqAddr(CR_irqAddr),
    .IN_irqTaken(branchProvs[3].taken),
    .IN_irqSrc(ROB_irqSrc),
    .IN_irqFlags(ROB_irqFlags),
    .IN_irqMemAddr(ROB_irqMemAddr),
    
    .OUT_GPIO_oe(OUT_GPIO_oe),
    .OUT_GPIO(OUT_GPIO),
    .IN_GPIO(IN_GPIO),
    
    .OUT_SPI_clk(OUT_SPI_clk),
    .OUT_SPI_mosi(OUT_SPI_mosi),
    .IN_SPI_miso(IN_SPI_miso),

    .OUT_IO_busy(IO_busy)
);

assign frontendEn = !IQ0_full && !IQ1_full && !IQ2_full && 
    ($signed(RN_nextLoadSqN - LB_maxLoadSqN) <= -NUM_UOPS) && 
    ($signed(RN_nextStoreSqN - SQ_maxStoreSqN) <= -NUM_UOPS) && 
    ($signed(RN_nextSqN - ROB_maxSqN) <= -NUM_UOPS) && 
    !branch.taken &&
    en &&
    !OUT_instrMappingMiss &&
    !mispredFlush;

`ifdef IVERILOG_DEBUG
`include "src/Debug.svi"
`endif

endmodule
