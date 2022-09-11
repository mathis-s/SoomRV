module Core
#(
    parameter NUM_UOPS=2,
    parameter NUM_WBS=3
)
(
    input wire clk,
    input wire rst,
    input en,
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
    
    output wire OUT_instrMappingMiss,
    input wire[31:0] IN_instrMappingBase,
    input wire IN_instrMappingHalfSize,
    output wire[31:0] OUT_LA_robPCsample
);

integer i;

wire dbgIsPrint = OUT_MEM_addr == 255;

RES_UOp wbUOp[NUM_WBS-1:0];
wire wbHasResult[NUM_WBS-1:0];
assign wbHasResult[0] = wbUOp[0].valid && wbUOp[0].nmDst != 0;
assign wbHasResult[1] = wbUOp[1].valid && wbUOp[1].nmDst != 0;
assign wbHasResult[2] = wbUOp[2].valid && wbUOp[2].nmDst != 0;

wire[4:0] comRegNm[NUM_UOPS-1:0];
wire[5:0] comRegTag[NUM_UOPS-1:0];
wire[5:0] comSqN[NUM_UOPS-1:0];
wire comIsBranch[NUM_UOPS-1:0];
wire comBranchTaken[NUM_UOPS-1:0];
wire[5:0] comBranchID[NUM_UOPS-1:0];
wire[29:0] comPC[NUM_UOPS-1:0];

assign OUT_LA_robPCsample[15:0] = comPC[0][15:0];
assign OUT_LA_robPCsample[31:16] = comPC[1][15:0];

wire comValid[NUM_UOPS-1:0];

wire frontendEn;

// IF -> DE -> RN
reg[3:0] stateValid;
assign OUT_instrReadEnable = !(frontendEn && stateValid[0]);

// 
reg[63:0] instrRawBackup;
reg useInstrRawBackup;
always_ff@(posedge clk) begin
    if (rst)
        useInstrRawBackup <= 0;
    else if (!(frontendEn && stateValid[0])) begin
        instrRawBackup <= instrRaw;
        useInstrRawBackup <= 1;
    end
    else
        useInstrRawBackup <= 0;
end
wire[63:0] instrRaw = useInstrRawBackup ? instrRawBackup : IN_instrRaw;


BranchProv branchProvs[3:0];
BranchProv branch;
always_comb begin
    branch.taken = 0;
    branch = 0;
    for (i = 0; i < 4; i=i+1) begin
        if (branchProvs[i].taken && 
            (!branch.taken || $signed(branchProvs[i].sqN - branch.sqN) < 0) &&
            (!mispredFlush || $signed(branchProvs[i].sqN - mispredFlushSqN) < 0)) begin
            branch.taken = 1;
            branch.dstPC = branchProvs[i].dstPC;
            branch.sqN = branchProvs[i].sqN;
            branch.loadSqN = branchProvs[i].loadSqN;
            branch.storeSqN = branchProvs[i].storeSqN;
            branch.flush = branchProvs[i].flush;
        end
    end
end

reg disableMispredFlush;
reg mispredFlush;
reg[5:0] mispredFlushSqN;

reg [31:0] IF_pc[NUM_UOPS-1:0];
wire[31:0] IF_instr[NUM_UOPS-1:0];
wire IF_instrValid[NUM_UOPS-1:0];

wire[31:0] PC_pc;
assign OUT_instrAddr = PC_pc[31:3];


wire BP_branchTaken;
wire BP_isJump;
wire[31:0] BP_branchSrc;
wire[31:0] BP_branchDst;
wire[5:0] BP_branchID;
wire BP_multipleBranches;
wire BP_branchFound;

wire[5:0] IF_branchID[NUM_UOPS-1:0];
wire IF_branchPred[NUM_UOPS-1:0];

ProgramCounter progCnt
(
    .clk(clk),
    .en0(stateValid[0] && frontendEn),
    .en1(stateValid[1] && frontendEn),
    .rst(rst),
    .IN_pc(branch.dstPC),
    .IN_write(branch.taken),
    .IN_instr(instrRaw),
    
    .IN_BP_branchTaken(BP_branchTaken),
    .IN_BP_isJump(BP_isJump),
    .IN_BP_branchSrc(BP_branchSrc),
    .IN_BP_branchDst(BP_branchDst),
    .IN_BP_branchID(BP_branchID),
    .IN_BP_multipleBranches(BP_multipleBranches),
    .IN_BP_branchFound(BP_branchFound),
    
    .OUT_pcRaw(PC_pc),
    .OUT_pc(IF_pc),
    .OUT_instr(IF_instr),
    .OUT_branchID(IF_branchID),
    .OUT_branchPred(IF_branchPred),
    .OUT_instrValid(IF_instrValid),
    
    .IN_instrMappingBase(IN_instrMappingBase),
    .IN_instrMappingHalfSize(IN_instrMappingHalfSize),
    .OUT_instrMappingMiss(OUT_instrMappingMiss)
);

wire isBranch;
wire[31:0] branchSource;
wire branchIsJump;
wire[5:0] branchID;
wire branchTaken;
BranchPredictor bp
(
    .clk(clk),
    .rst(rst),
    
    .IN_pcValid(stateValid[0] && frontendEn),
    .IN_pc(PC_pc),
    .OUT_branchTaken(BP_branchTaken),
    .OUT_isJump(BP_isJump),
    .OUT_branchSrc(BP_branchSrc),
    .OUT_branchDst(BP_branchDst),
    .OUT_branchID(BP_branchID),
    .OUT_multipleBranches(BP_multipleBranches),
    .OUT_branchFound(BP_branchFound),
    
    .IN_branchValid(isBranch),
    .IN_branchID(branchID),
    .IN_branchAddr(branchSource),
    .IN_branchDest(branchProvs[1].dstPC),
    .IN_branchTaken(branchTaken),
    .IN_branchIsJump(branchIsJump),
    
    .IN_ROB_valid(comValid[0]),
    .IN_ROB_isBranch(comIsBranch[0]),
    .IN_ROB_branchID(comBranchID[0]),
    .IN_ROB_branchAddr(comPC[0]),
    .IN_ROB_branchTaken(comBranchTaken[0]),
    
    .OUT_CSR_branchCommitted(CSR_branchCommitted)
);


wire[5:0] RN_nextSqN;
wire[5:0] ROB_curSqN;

always_ff@(posedge clk) begin
    if (rst) begin
        stateValid <= 4'b0000;
        mispredFlush <= 0;
        disableMispredFlush <= 0;
        mispredFlushSqN <= 0;
    end
    else if (branch.taken) begin
        stateValid <= 4'b0000;
        mispredFlush <= (ROB_curSqN != RN_nextSqN);
        disableMispredFlush <= 0;
        mispredFlushSqN <= branch.sqN;
    end
    // When a branch mispredict happens, we need to let the pipeline
    // run entirely dry.
    else if (mispredFlush) begin
        stateValid <= 4'b0000;
        disableMispredFlush <= (ROB_curSqN == RN_nextSqN);
        if (disableMispredFlush)
            mispredFlush <= 0;
    end
    else if (frontendEn)
        stateValid <= {stateValid[2:0], 1'b1};
end


D_UOp DE_uop[NUM_UOPS-1:0];

InstrDecoder idec
(
    .IN_instr(IF_instr),
    .IN_branchID(IF_branchID),
    .IN_branchPred(IF_branchPred),
    .IN_instrValid(IF_instrValid),
    .IN_pc(IF_pc),

    .OUT_uop(DE_uop)
);

wire[31:0] dbg_DUOp_pc0 = DE_uop[0].pc;
wire[31:0] dbg_DUOp_pc1 = DE_uop[1].pc;

wire[4:0] dbg_DUOp_nmDst = DE_uop[0].rd;
wire[4:0] dbg_DUOp_nmDst = DE_uop[1].rd;

wire[4:0] dbg_DUOp_srcA0 = DE_uop[0].rs0;
wire[4:0] dbg_DUOp_srcA1 = DE_uop[1].rs0;

wire[4:0] dbg_DUOp_srcB0 = DE_uop[0].rs1;
wire[4:0] dbg_DUOp_srcB1 = DE_uop[1].rs1;

R_UOp RN_uop[NUM_UOPS-1:0];
reg RN_uopValid[NUM_UOPS-1:0];
wire[5:0] RN_nextLoadSqN;
wire[5:0] RN_nextStoreSqN;

Rename rn 
(
    .clk(clk),
    .en(!branch.taken && stateValid[2]),
    .frontEn(frontendEn),
    .rst(rst),

    .IN_uop(DE_uop),

    .comValid(comValid),
    .comRegNm(comRegNm),
    .comRegTag(comRegTag),
    .comSqN(comSqN),

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

wire[31:0] dbg_RUOp_pc0 = RN_uop[0].pc;
wire[31:0] dbg_RUOp_pc1 = RN_uop[1].pc;

wire[5:0] dbg_RUOp_sqN0 = RN_uop[0].sqN;
wire[5:0] dbg_RUOp_sqN1 = RN_uop[1].sqN;

wire[5:0] dbg_RUOp_tagDst0 = RN_uop[0].tagDst;
wire[5:0] dbg_RUOp_tagDst1 = RN_uop[1].tagDst;

wire[4:0] dbg_RUOp_nmDst0 = RN_uop[0].nmDst;
wire[4:0] dbg_RUOp_nmDst1 = RN_uop[1].nmDst;


wire[5:0] dbg_RUOp_tagA0 = RN_uop[0].tagA;
wire[5:0] dbg_RUOp_tagA1 = RN_uop[1].tagA;

wire[5:0] dbg_RUOp_tagB0 = RN_uop[0].tagB;
wire[5:0] dbg_RUOp_tagB1 = RN_uop[1].tagB;


wire dbg_RUOp_availA0 = RN_uop[0].availA;
wire dbg_RUOp_availA1 = RN_uop[1].availA;

wire dbg_RUOp_availB0 = RN_uop[0].availB;
wire dbg_RUOp_availB1 = RN_uop[1].availB;

wire RV_uopValid[NUM_UOPS-1:0];
R_UOp RV_uop[NUM_UOPS-1:0];

wire stall[1:0];
assign stall[0] = 0;
assign stall[1] = 0;
wire wbStall[1:0];
assign wbStall[0] = 0;
assign wbStall[1] = 0;

wire[4:0] RV_freeEntries;
ReservationStation rv
(
    .clk(clk),
    .rst(rst),
    .frontEn(stateValid[3] && frontendEn),
    
    .IN_DIV_doNotIssue(DIV_doNotIssue),
    .IN_MUL_doNotIssue(MUL_doNotIssue),

    .IN_stall(stall),
    .IN_uopValid(RN_uopValid),
    .IN_uop(RN_uop),
    
    .IN_resultValid(wbHasResult),
    .IN_resultUOp(wbUOp),

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

wire[5:0] RF_writeAddress[2:0];
assign RF_writeAddress[0] = wbUOp[0].tagDst;
assign RF_writeAddress[1] = wbUOp[1].tagDst;
assign RF_writeAddress[2] = wbUOp[2].tagDst;
wire[31:0] RF_writeData[2:0];
assign RF_writeData[0] = wbUOp[0].result;
assign RF_writeData[1] = wbUOp[1].result;
assign RF_writeData[2] = wbUOp[2].result;

RF rf
(
    .clk(clk),
    .rst(rst),
    .IN_readEnable(RF_readEnable),
    .IN_readAddress(RF_readAddress),
    .OUT_readData(RF_readData),

    .IN_writeEnable(wbHasResult),
    .IN_writeAddress(RF_writeAddress),
    .IN_writeData(RF_writeData)
);

EX_UOp LD_uop[NUM_UOPS-1:0];
wire[3:0] enabledXUs[NUM_UOPS-1:0];
FuncUnit LD_fu[NUM_UOPS-1:0];

wire[31:0] LD_zcFwdResult[1:0];
wire[5:0] LD_zcFwdTag[1:0];
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
    
    .IN_zcFwdResult(LD_zcFwdResult),
    .IN_zcFwdTag(LD_zcFwdTag),
    .IN_zcFwdValid(LD_zcFwdValid),

    .OUT_rfReadValid(RF_readEnable),
    .OUT_rfReadAddr(RF_readAddress),
    .IN_rfReadData(RF_readData),
    
    .OUT_enableXU(enabledXUs),
    .OUT_funcUnit(LD_fu),
    .OUT_uop(LD_uop)
);


wire INTALU_wbReq;
initial branchProvs[0].flush = 0;
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
    
    .OUT_isBranch(),
    .OUT_branchTaken(),
    .OUT_branchMispred(branchProvs[0].taken),
    .OUT_branchSource(),
    .OUT_branchAddress(branchProvs[0].dstPC),
    .OUT_branchIsJump(),
    .OUT_branchID(),
    .OUT_branchSqN(branchProvs[0].sqN),
    .OUT_branchLoadSqN(branchProvs[0].loadSqN),
    .OUT_branchStoreSqN(branchProvs[0].storeSqN),
    
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

assign wbUOp[0] = INT0_uop.valid ? INT0_uop : DIV_uop;
//assign wbStall[0] = DIV_busy;


/*CacheController cc
(
    .clk(clk),
    .rst(rst),
    
    .IN_uop(),
    .OUT_cacheLookupAddr(),
    .OUT_cacheLookupFound(),
    
    .IN_LSU_avail(0),
    .OUT_uop(),
    .OUT_MC_startRead(),
    .OUT_MC_writeBack(),
    .OUT_MC_sramAddr(),
    .OUT_MC_extAddr(),
    .OUT_MC_extWBAddr(),
    .OUT_MC_size(),
    
    .IN_MC_busy()
);*/

AGU_UOp AGU_uop;
wire[20:0] AGU_mapping[3:0];
AGU agu
(
    .clk(clk),
    .rst(rst),
    .en(enabledXUs[0][1]),
    
    .IN_branch(branch),
    .IN_mapping(AGU_mapping),
    
    .IN_uop(LD_uop[0]),
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

StoreQueue sq
(
    .clk(clk),
    .rst(rst),
    
    .IN_uop('{AGU_uop}),
    
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

initial branchProvs[1].flush = 0;
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
    
    .OUT_isBranch(isBranch),
    .OUT_branchTaken(branchTaken),
    .OUT_branchMispred(branchProvs[1].taken),
    .OUT_branchSource(branchSource),
    .OUT_branchAddress(branchProvs[1].dstPC),
    .OUT_branchIsJump(branchIsJump),
    .OUT_branchID(branchID),
    .OUT_branchSqN(branchProvs[1].sqN),
    .OUT_branchLoadSqN(branchProvs[1].loadSqN),
    .OUT_branchStoreSqN(branchProvs[1].storeSqN),
    
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
wire[11:0] ROB_irqMemAddr;
ROB rob
(
    .clk(clk),
    .rst(rst),
    .IN_uop(wbUOp),

    .IN_invalidate(branch.taken),
    .IN_invalidateSqN(branch.sqN),
    
    .OUT_maxSqN(ROB_maxSqN),
    .OUT_curSqN(ROB_curSqN),

    .OUT_comNames(comRegNm),
    .OUT_comTags(comRegTag),
    .OUT_comIsBranch(comIsBranch),
    .OUT_comBranchTaken(comBranchTaken),
    .OUT_comBranchID(comBranchID),
    .OUT_comPC(comPC),
    .OUT_comValid(comValid),
    .OUT_comSqNs(comSqN),
    
    .IN_irqAddr(CR_irqAddr),
    .OUT_irqFlags(ROB_irqFlags),
    .OUT_irqSrc(ROB_irqSrc),
    .OUT_irqMemAddr(ROB_irqMemAddr),
    
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
    .IN_addr(OUT_MEM_addr[5:0]),
    .IN_data(OUT_MEM_writeData),
    .OUT_data(CSR_dataOut[0]),

    .IN_comValid(comValid),
    .IN_branch(branchProvs[1]),
    .IN_wbValid('{wbUOp[0].valid, wbUOp[1].valid, wbUOp[2].valid}),
    .IN_ifValid(IF_instrValid),
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
    
    .OUT_AGU_mapping(AGU_mapping),
    
    .OUT_IO_busy(IO_busy)
);

// this should be done properly, ideally effects in rename cycle instead of IF
assign frontendEn = (RV_freeEntries > NUM_UOPS) && 
    ($signed(RN_nextLoadSqN - LB_maxLoadSqN) <= -NUM_UOPS) && 
    ($signed(RN_nextStoreSqN - SQ_maxStoreSqN) <= -NUM_UOPS) && 
    ($signed(RN_nextSqN - ROB_maxSqN) <= -NUM_UOPS) && 
    !branch.taken &&
    en &&
    !OUT_instrMappingMiss;
    
endmodule
