module Core
#(
    parameter NUM_UOPS=2,
    parameter NUM_WBS=4
)
(
    input wire clk,
    input wire rst,
    input wire en,
    input wire[63:0] IN_instrRaw,

    output wire[29:0] OUT_MEM_writeAddr,
    output wire[31:0] OUT_MEM_writeData,
    output wire OUT_MEM_writeEnable,
    output wire[3:0] OUT_MEM_writeMask,
    
    output wire OUT_MEM_readEnable,
    output wire[29:0] OUT_MEM_readAddr,
    input wire[31:0] IN_MEM_readData,
    
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
//wire wbHasResult_fp[NUM_WBS-1:0];
assign wbHasResult[0] = wbUOp[0].valid && wbUOp[0].nmDst != 0;
assign wbHasResult[1] = wbUOp[1].valid && wbUOp[1].nmDst != 0;
assign wbHasResult[2] = wbUOp[2].valid && wbUOp[2].nmDst != 0;
assign wbHasResult[3] = wbUOp[3].valid && wbUOp[3].nmDst != 0;

assign wbHasResult_int[0] = wbUOp[0].valid && wbUOp[0].nmDst != 0;// && !wbUOp[0].nmDst[5];
assign wbHasResult_int[1] = wbUOp[1].valid && wbUOp[1].nmDst != 0;// && !wbUOp[1].nmDst[5];
assign wbHasResult_int[2] = wbUOp[2].valid && wbUOp[2].nmDst != 0;// && !wbUOp[2].nmDst[5];
assign wbHasResult_int[3] = wbUOp[3].valid && wbUOp[3].nmDst != 0;// && !wbUOp[3].nmDst[5];

//assign wbHasResult_fp[0] = wbUOp[0].valid && wbUOp[0].nmDst[5];
//assign wbHasResult_fp[1] = wbUOp[1].valid && wbUOp[1].nmDst[5];
//assign wbHasResult_fp[2] = wbUOp[2].valid && wbUOp[2].nmDst[5];
//assign wbHasResult_fp[3] = wbUOp[3].valid && wbUOp[3].nmDst[5];


CommitUOp comUOps[3:0];
wire comValid[3:0];

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
    .IN_mispredFlush(mispredFlush)
    //.OUT_mispredFlush()
);

wire[31:0] PC_pc;
assign OUT_instrAddr = PC_pc[31:3];

wire BP_branchTaken;
wire BP_isJump;
wire[31:0] BP_branchSrc;
wire[31:0] BP_branchDst;
BHist_t BP_branchHistory;
BranchPredInfo BP_info;
wire BP_multipleBranches;
wire BP_branchFound;
wire BP_branchCompr;

IF_Instr IF_instrs[3:0];

FetchID_t PC_readAddress[4:0];
PCFileEntry PC_readData[4:0];
wire PC_stall;
ProgramCounter progCnt
(
    .clk(clk),
    .en0(stateValid[0] && ifetchEn),
    .en1(stateValid[1] && ifetchEn),
    .rst(rst),
    .IN_pc(branch.taken ? branch.dstPC : {DEC_branchDst, 1'b0}),
    .IN_write(branch.taken || DEC_branch),
    .IN_branchTaken(branch.taken),
    .IN_fetchID(branch.taken ? branch.fetchID : DEC_branchFetchID),
    .IN_instr(instrRaw),
    
    .IN_BP_branchTaken(BP_branchTaken),
    .IN_BP_isJump(BP_isJump),
    .IN_BP_branchSrc(BP_branchSrc),
    .IN_BP_branchDst(BP_branchDst),
    .IN_BP_history(BP_branchHistory),
    .IN_BP_info(BP_info),
    .IN_BP_multipleBranches(BP_multipleBranches),
    .IN_BP_branchFound(BP_branchFound),
    .IN_BP_branchCompr(BP_branchCompr),
    
    .IN_pcReadAddr(PC_readAddress),
    .OUT_pcReadData(PC_readData),
    
    .IN_ROB_curFetchID(ROB_curFetchID),
    
    .OUT_pcRaw(PC_pc),
    .OUT_instrs(IF_instrs),
    
    .IN_instrMappingBase(IN_instrMappingBase),
    .IN_instrMappingHalfSize(IN_instrMappingHalfSize),
    .OUT_instrMappingMiss(OUT_instrMappingMiss),
    
    .OUT_stall(PC_stall)
);

BTUpdate BP_btUpdates[1:0];
BranchPredictor bp
(
    .clk(clk),
    .rst(rst),
    .IN_mispredFlush(mispredFlush),
    .IN_branch(branch),
    
    .IN_pcValid(stateValid[0] && ifetchEn),
    .IN_pc(PC_pc),
    .OUT_branchTaken(BP_branchTaken),
    .OUT_isJump(BP_isJump),
    .OUT_branchSrc(BP_branchSrc),
    .OUT_branchDst(BP_branchDst),
    .OUT_branchHistory(BP_branchHistory),
    .OUT_branchInfo(BP_info),
    .OUT_multipleBranches(BP_multipleBranches),
    .OUT_branchFound(BP_branchFound),
    .OUT_branchCompr(BP_branchCompr),
    
    .IN_btUpdates(BP_btUpdates),
    
    .IN_comUOp(comUOps[0]),
    
    .OUT_CSR_branchCommitted(CSR_branchCommitted)
);

SqN RN_nextSqN;
SqN ROB_curSqN;

always_ff@(posedge clk) begin
    if (rst)
        stateValid <= 3'b000;
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
assign ifetchEn = !PD_full && !PC_stall;

D_UOp DE_uop[3:0];

wire DEC_branch;
wire[30:0] DEC_branchDst;
FetchID_t DEC_branchFetchID;
InstrDecoder idec
(
    .clk(clk),
    .rst(rst),
    .IN_invalidate(branch.taken),
    .en(!FUSE_full),
    .IN_instrs(PD_instrs),
    
    .OUT_decBranch(DEC_branch),
    .OUT_decBranchDst(DEC_branchDst),
    .OUT_decBranchFetchID(DEC_branchFetchID),
    
    .OUT_uop(DE_uop)
);
wire FUSE_full = !frontendEn || RN_stall;
/*wire FUSE_full;
D_UOp FUSE_uop[3:0];
Fuse fuse
(
    .clk(clk),
    .outEn(frontendEn && !RN_stall),
    .rst(rst),
    .mispredict(branch.taken),
    
    .OUT_full(FUSE_full),
    
    .IN_uop(DE_uop),
    .OUT_uop(FUSE_uop)
);*/


R_UOp RN_uop[3:0];
reg RN_uopValid[3:0];
SqN RN_nextLoadSqN;
SqN RN_nextStoreSqN;
wire RN_stall;
Rename rn 
(
    .clk(clk),
    .en(!branch.taken && !mispredFlush),
    .frontEn(frontendEn),
    .rst(rst),
    
    .OUT_stall(RN_stall),

    .IN_uop(DE_uop),

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

wire RV_uopValid[3:0];
R_UOp RV_uop[3:0];

wire stall[3:0];
assign stall[0] = 0;
assign stall[1] = 0;
assign stall[3] = 0;

wire IQ0_full;
IssueQueue#(12,4,4,FU_INT,FU_DIV,FU_FPU,1,0,33) iq0
(
    .clk(clk),
    .rst(rst),
    .frontEn(frontendEn && !branch.taken && !mispredFlush && !RN_stall),
    
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
IssueQueue#(12,4,4,FU_INT,FU_MUL,FU_MUL,1,1,9-4) iq1
(
    .clk(clk),
    .rst(rst),
    .frontEn(frontendEn && !branch.taken && !mispredFlush && !RN_stall),
    
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
IssueQueue#(12,4,4,FU_LSU,FU_LSU,FU_LSU,0,0,0) iq2
(
    .clk(clk),
    .rst(rst),
    .frontEn(frontendEn && !branch.taken && !mispredFlush && !RN_stall),
    
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
wire IQ3_full;
IssueQueue#(12,4,4,FU_ST,FU_ST,FU_ST,0,0,0) iq3
(
    .clk(clk),
    .rst(rst),
    .frontEn(frontendEn && !branch.taken && !mispredFlush && !RN_stall),
    
    .IN_stall(stall[3]),
    .IN_doNotIssueFU1(1'b0),
    
    .IN_uopValid(RN_uopValid),
    .IN_uop(RN_uop),
    
    .IN_resultValid(wbHasResult),
    .IN_resultUOp(wbUOp),
    
    .IN_branch(branch),
    
    .IN_issueValid(RV_uopValid),
    .IN_issueUOps(RV_uop),
    
    .OUT_valid(RV_uopValid[3]),
    .OUT_uop(RV_uop[3]),
    .OUT_full(IQ3_full)
);

wire[5:0] RF_readAddress[7:0];
wire[31:0] RF_readData[7:0];

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
    .raddr6(RF_readAddress[6]), .rdata6(RF_readData[6]),
    .raddr7(RF_readAddress[7]), .rdata7(RF_readData[7])
);
/*
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
);*/

EX_UOp LD_uop[3:0];
wire[5:0] enabledXUs[3:0];
FuncUnit LD_fu[3:0];

wire[31:0] LD_zcFwdResult[1:0];
Tag LD_zcFwdTag[1:0];
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
    
    .OUT_pcReadAddr(PC_readAddress[3:0]),
    .IN_pcReadData(PC_readData[3:0]),
    
    .OUT_rfReadAddr(RF_readAddress),
    .IN_rfReadData(RF_readData),
    
    //.OUT_rfReadAddr_fp(RF_FP_readAddress),
    //.IN_rfReadData_fp(RF_FP_readData),
    
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
wire DIV_doNotIssue = DIV_busy || (LD_uop[0].valid && enabledXUs[0][4]) || (RV_uopValid[0] && RV_uop[0].fu == FU_DIV);
Divide div
(
    .clk(clk),
    .rst(rst),
    .en(enabledXUs[0][4]),
    
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
    .en(enabledXUs[0][5]),
    
    .IN_branch(branch),
    .IN_uop(LD_uop[0]),
    .OUT_uop(FPU_uop)
);

assign wbUOp[0] = INT0_uop.valid ? INT0_uop : (FPU_uop.valid ? FPU_uop : DIV_uop);

AGU_UOp CC_uopLd;
ST_UOp CC_uopSt;
wire CC_storeStall;
CacheController cc
(
    .clk(clk),
    .rst(rst),
    
    .IN_branch(branch),
    .IN_SQ_empty(SQ_empty),
    .OUT_stall('{CC_storeStall, stall[2]}),
    
    .IN_uopLd(AGU_LD_uop),
    .OUT_uopLd(CC_uopLd),
    
    .IN_uopSt(SQ_uop),
    .OUT_uopSt(CC_uopSt),
    
    .OUT_MC_ce(OUT_MC_ce),
    .OUT_MC_we(OUT_MC_we),
    .OUT_MC_sramAddr(OUT_MC_sramAddr),
    .OUT_MC_extAddr(OUT_MC_extAddr),
    .IN_MC_progress(IN_MC_progress),
    .IN_MC_busy(IN_MC_busy)
);

AGU_UOp AGU_LD_uop;
AGU aguLD
(
    .clk(clk),
    .rst(rst),
    .en(enabledXUs[2][1]),
    .stall(stall[2]),
    
    .IN_branch(branch),

    .IN_uop(LD_uop[2]),
    .OUT_uop(AGU_LD_uop)
);

AGU_UOp AGU_ST_uop;
AGU aguST
(
    .clk(clk),
    .rst(rst),
    .en(enabledXUs[3][2]),
    .stall(stall[3]),
    
    .IN_branch(branch),

    .IN_uop(LD_uop[3]),
    .OUT_uop(AGU_ST_uop)
);


SqN LB_maxLoadSqN;
LoadBuffer lb
(
    .clk(clk),
    .rst(rst),
    .commitSqN(ROB_curSqN),
    
    .IN_uop('{AGU_ST_uop, AGU_LD_uop}),
    
    .IN_branch(branch),
    .OUT_branch(branchProvs[2]),
    
    .OUT_maxLoadSqN(LB_maxLoadSqN)
);

SqN SQ_maxStoreSqN;
wire CSR_we;
wire[31:0] CSR_dataOut;

wire SQ_empty;
ST_UOp SQ_uop;
wire[3:0] SQ_lookupMask;
wire[31:0] SQ_lookupData;
StoreQueue sq
(
    .clk(clk),
    .rst(rst),
    .IN_disable(CC_storeStall),
    .IN_stallLd(stall[2]),
    .OUT_empty(SQ_empty),
    
    .IN_uopSt(AGU_ST_uop),
    .IN_uopLd(AGU_LD_uop),
    
    .IN_curSqN(ROB_curSqN),
    
    .IN_branch(branch),
    
    .OUT_uopSt(SQ_uop),
    
    .OUT_lookupData(SQ_lookupData),
    .OUT_lookupMask(SQ_lookupMask),
    
    .OUT_maxStoreSqN(SQ_maxStoreSqN),
    .IN_IO_busy(IO_busy)
);

LoadStoreUnit lsu
(
    .clk(clk),
    .rst(rst),
    
    .IN_branch(branch),
    
    .IN_uopLd(CC_uopLd),
    .IN_uopSt(CC_uopSt),
    
    .OUT_MEM_re(OUT_MEM_readEnable),
    .OUT_MEM_readAddr(OUT_MEM_readAddr),
    .IN_MEM_readData(IN_MEM_readData),
    
    .OUT_MEM_we(OUT_MEM_writeEnable),
    .OUT_MEM_writeAddr(OUT_MEM_writeAddr),
    .OUT_MEM_writeData(OUT_MEM_writeData),
    .OUT_MEM_wm(OUT_MEM_writeMask),
    
    .IN_SQ_lookupMask(SQ_lookupMask),
    .IN_SQ_lookupData(SQ_lookupData),
    
    .IN_CSR_data(CSR_dataOut),
    .OUT_CSR_we(CSR_we),
    
    .OUT_uopLd(wbUOp[2])
);

always_comb begin
    wbUOp[3].result = 32'bx;
    wbUOp[3].tagDst = AGU_ST_uop.tagDst;
    wbUOp[3].nmDst = AGU_ST_uop.nmDst;
    wbUOp[3].sqN = AGU_ST_uop.sqN;
    wbUOp[3].pc = AGU_ST_uop.pc;
    wbUOp[3].flags = AGU_ST_uop.exception ? FLAGS_EXCEPT : FLAGS_NONE;
    wbUOp[3].compressed = AGU_ST_uop.compressed;
    wbUOp[3].isBranch = 0;
    wbUOp[3].bpi = 0;
    wbUOp[3].valid = AGU_ST_uop.valid;
end

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
wire MUL_doNotIssue = MUL_busy || (LD_uop[1].valid && enabledXUs[1][3]) || (RV_uopValid[1] && RV_uop[1].fu == FU_MUL);
MultiplySmall mul
(
    .clk(clk),
    .rst(rst),
    .en(enabledXUs[1][3]),
    
    .OUT_busy(MUL_busy),
    
    .IN_branch(branch),
    .IN_uop(LD_uop[1]),
    .OUT_uop(MUL_uop)
);

assign wbUOp[1] = INT1_uop.valid ? INT1_uop : MUL_uop;

SqN ROB_maxSqN;

wire[31:0] CR_irqAddr;
Flags ROB_irqFlags;
wire[31:0] ROB_irqSrc;
wire[31:0] ROB_irqMemAddr;

FetchID_t ROB_curFetchID;
ROB rob
(
    .clk(clk),
    .rst(rst),
    .IN_uop(RN_uop),
    .IN_uopValid(RN_uopValid),
    
    .IN_wbUOps(wbUOp),

    .IN_branch(branch),
    
    .OUT_maxSqN(ROB_maxSqN),
    .OUT_curSqN(ROB_curSqN),
    
    .OUT_comUOp(comUOps),
    
    .IN_irqAddr(CR_irqAddr),
    .OUT_irqFlags(ROB_irqFlags),
    .OUT_irqSrc(ROB_irqSrc),
    .OUT_irqMemAddr(ROB_irqMemAddr),
    
    .OUT_pcReadAddr(PC_readAddress[4]),
    .IN_pcReadData(PC_readData[4]),
    
    .OUT_fence(),
    
    .OUT_branch(branchProvs[3]),
    
    .OUT_curFetchID(ROB_curFetchID),
    
    .OUT_halt(OUT_halt),
    .OUT_mispredFlush(mispredFlush)
);

wire IO_busy;
wire CSR_branchCommitted;
ControlRegs cr
(
    .clk(clk),
    .rst(rst),
    .IN_mispredFlush(mispredFlush),
    
    .IN_we(CSR_we),
    .IN_wm(OUT_MEM_writeMask),
    .IN_writeAddr(OUT_MEM_writeAddr[6:0]),
    .IN_data(OUT_MEM_writeData),
    
    .IN_re(OUT_MEM_readEnable),
    .IN_readAddr(OUT_MEM_readAddr[6:0]),
    .OUT_data(CSR_dataOut),

    .IN_comValid('{comUOps[0].valid, comUOps[1].valid, comUOps[2].valid, comUOps[3].valid}),
    .IN_branchMispred((branchProvs[1].taken || branchProvs[0].taken) && !mispredFlush),
    .IN_wbValid('{wbUOp[0].valid, wbUOp[1].valid, wbUOp[2].valid, wbUOp[3].valid}),
    .IN_ifValid('{DE_uop[0].valid&&!FUSE_full, DE_uop[1].valid&&!FUSE_full, DE_uop[2].valid&&!FUSE_full, DE_uop[3].valid&&!FUSE_full}),
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

assign frontendEn = !IQ0_full && !IQ1_full && !IQ2_full && !IQ3_full &&
    ($signed(RN_nextLoadSqN - LB_maxLoadSqN) <= -4) && 
    ($signed(RN_nextStoreSqN - SQ_maxStoreSqN) <= -4) && 
    ($signed(RN_nextSqN - ROB_maxSqN) <= -4) && 
    !branch.taken &&
    en &&
    !OUT_instrMappingMiss &&
    !mispredFlush;

`ifdef IVERILOG_DEBUG
`include "src/Debug.svi"
`endif

endmodule

