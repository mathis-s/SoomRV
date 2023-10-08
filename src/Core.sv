module Core
(
    input wire clk,
    input wire rst,
    input wire en,

    IF_Cache.HOST IF_cache,
    IF_CTable.HOST IF_ct,
    IF_MMIO.HOST IF_mmio,
    IF_CSR_MMIO.CSR IF_csr_mmio,
    
    output wire[27:0] OUT_instrAddr,
    output wire OUT_instrReadEnable,
    input wire[127:0] IN_instrRaw,
        
    output MemController_Req OUT_memc[2:0],
    input MemController_Res IN_memc
);

assign OUT_memc[0] = PC_MC_if;
assign OUT_memc[1] = LSU_MC_if;
assign OUT_memc[2] = BLSU_MC_if;

localparam NUM_WBS = 4;
RES_UOp wbUOp[NUM_WBS-1:0] /*verilator public*/;
reg wbHasResult[NUM_WBS-1:0];
always_comb begin
    for (integer i = 0; i < 4; i=i+1)
        wbHasResult[i] = wbUOp[i].valid && !wbUOp[i].tagDst[6];
end

CommitUOp comUOps[3:0] /*verilator public*/;

wire ifetchEn = !PD_full && !TH_disableIFetch;

wire[30:0] BP_lateRetAddr;

BranchProv branchProvs[3:0];
BranchProv branch /*verilator public*/;
wire mispredFlush /*verilator public*/;
wire BS_PERFC_branchMispr;

IF_Instr IF_instrs;
BTUpdate BP_btUpdates[2:0];

FetchID_t PC_readAddress[4:0];
PCFileEntry PC_readData[4:0];
wire PC_stall;

MemController_Req PC_MC_if;
PageWalk_Req PC_PW_rq;
IFetch ifetch
(
    .clk(clk),
    .rst(rst),
    .IN_en(ifetchEn),

    .IN_interruptPending(CSR_trapControl.interruptPending),
    
    .OUT_instrReadEnable(OUT_instrReadEnable),
    .OUT_instrAddr(OUT_instrAddr),
    .IN_instrRaw(IN_instrRaw),
    
    .IN_branches(branchProvs),
    .IN_mispredFlush(mispredFlush),
    .IN_ROB_curFetchID(ROB_curFetchID),
    .IN_ROB_curSqN(ROB_curSqN),
    .IN_RN_nextSqN(RN_nextSqN),
    .OUT_PERFC_branchMispr(BS_PERFC_branchMispr),
    .OUT_branch(branch),
    
    .IN_retDecUpd(DEC_retUpd),
    .IN_decBranch(DEC_decBranch),
    
    .IN_clearICache(TH_clearICache),
    .IN_flushTLB(TH_flushTLB),
    .IN_btUpdates(BP_btUpdates),
    .IN_bpUpdate0(ROB_bpUpdate0),
    .IN_bpUpdate(TH_bpUpdate),
    
    .IN_pcReadAddr(PC_readAddress),
    .OUT_pcReadData(PC_readData),
    
    .OUT_instrs(IF_instrs),
    .OUT_lateRetAddr(BP_lateRetAddr),
    
    .IN_vmem(CSR_vmem),
    .OUT_pw(PC_PW_rq),
    .IN_pw(PW_res),

    .OUT_memc(PC_MC_if),
    .IN_memc(IN_memc)
);

SqN RN_nextSqN;
SqN ROB_curSqN /*verilator public*/;

wire PD_full;
PD_Instr PD_instrs[`DEC_WIDTH-1:0] /*verilator public*/;
PreDecode preDec
(
    .clk(clk),
    .rst(rst),
    .ifetchValid(ifetchEn),
    .outEn(!RN_stall && frontendEn),

    .OUT_full(PD_full),
    
    .mispred(branch.taken || DEC_decBranch.taken),
    .IN_instrs(IF_instrs),
    .OUT_instrs(PD_instrs)
);

D_UOp DE_uop[`DEC_WIDTH-1:0] /*verilator public*/;
DecodeBranchProv DEC_decBranch /*verilator public*/;
ReturnDecUpdate DEC_retUpd;
InstrDecoder idec
(
    .clk(clk),
    .rst(rst),
    .en(!RN_stall && frontendEn),
    .IN_invalidate(branch.taken),

    .IN_dec(CSR_dec),
    .IN_instrs(PD_instrs),
    .IN_lateRetAddr(BP_lateRetAddr),
    
    .IN_enCustom(1'b1),
    
    .OUT_decBranch(DEC_decBranch),
    .OUT_retUpd(DEC_retUpd),
    .OUT_btUpdate(BP_btUpdates[2]),
    
    .OUT_uop(DE_uop)
);

wire frontendEn /*verilator public*/ = 
    ($signed((RN_nextSqN) - ROB_maxSqN) <= -(`DEC_WIDTH - 1)) &&
    ($signed((RN_nextStoreSqN) - SQ_maxStoreSqN) <= -(`DEC_WIDTH - 1)) &&
    !branch.taken &&
    en &&
    !SQ_flush;

R_UOp RN_uop[`DEC_WIDTH-1:0] /*verilator public*/;
wire RN_uopOrdering[`DEC_WIDTH-1:0];
SqN RN_nextLoadSqN;
SqN RN_nextStoreSqN;
wire RN_stall /*verilator public*/;
Rename rn 
(
    .clk(clk),
    .frontEn(frontendEn),
    .rst(rst),
    
    .IN_stall(!IQS_ready),
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

    .OUT_uop(RN_uop),
    .OUT_uopOrdering(RN_uopOrdering),
    .OUT_nextSqN(RN_nextSqN),
    .OUT_nextLoadSqN(RN_nextLoadSqN),
    .OUT_nextStoreSqN(RN_nextStoreSqN)
);

IS_UOp IS_uop[3:0] /*verilator public*/;

wire stall[3:0] /*verilator public*/;
assign stall[0] = 0;
assign stall[1] = 0;

wire IQS_ready /*verilator public*/ = !IQ0_full && !IQ1_full && !IQ2_full && !IQ3_full;
wire IQ0_full;
IssueQueue#(`IQ_0_SIZE,0,2,`DEC_WIDTH,4,32+4,FU_INT,FU_DIV,FU_FPU,FU_CSR,1,0,33) iq0
(
    .clk(clk),
    .rst(rst),
    .frontEn(IQS_ready),
    
    .IN_stall(stall[0]),
    .IN_doNotIssueFU1(DIV_doNotIssue),
    .IN_doNotIssueFU2(1'b0),
    
    .IN_uop(RN_uop),
    .IN_uopOrdering(RN_uopOrdering),
    
    .IN_resultValid(wbHasResult),
    .IN_resultUOp(wbUOp),
    .IN_loadForwardValid(LSU_loadFwdValid),
    .IN_loadForwardTag(LSU_loadFwdTag),
    
    .IN_branch(branch),
    
    .IN_issueUOps(IS_uop),
    
    .IN_maxStoreSqN(SQ_maxStoreSqN),
    .IN_maxLoadSqN(LB_maxLoadSqN),
    .IN_commitSqN(ROB_curSqN),
    
    .OUT_uop(IS_uop[0]),
    .OUT_full(IQ0_full)
);
wire IQ1_full;
IssueQueue#(`IQ_1_SIZE,1,2,`DEC_WIDTH,4,32+4,FU_INT,FU_MUL,FU_FDIV,FU_FMUL,1,1,9-4) iq1
(
    .clk(clk),
    .rst(rst),
    .frontEn(IQS_ready),
    
    .IN_stall(stall[1]),
    .IN_doNotIssueFU1(MUL_doNotIssue),
    .IN_doNotIssueFU2(FDIV_doNotIssue),
    
    .IN_uop(RN_uop),
    .IN_uopOrdering(RN_uopOrdering),
    
    .IN_resultValid(wbHasResult),
    .IN_resultUOp(wbUOp),
    .IN_loadForwardValid(LSU_loadFwdValid),
    .IN_loadForwardTag(LSU_loadFwdTag),
    
    .IN_branch(branch),
    
    .IN_issueUOps(IS_uop),
    
    .IN_maxStoreSqN(SQ_maxStoreSqN),
    .IN_maxLoadSqN(LB_maxLoadSqN),
    .IN_commitSqN(ROB_curSqN),
    
    .OUT_uop(IS_uop[1]),
    .OUT_full(IQ1_full)
);
wire IQ2_full;
IssueQueue#(`IQ_2_SIZE,2,1,`DEC_WIDTH,4,12,FU_LD,FU_LD,FU_LD,FU_ATOMIC,0,0,0) iq2
(
    .clk(clk),
    .rst(rst),
    .frontEn(IQS_ready),
    
    .IN_stall(stall[2]),
    .IN_doNotIssueFU1(1'b0),
    .IN_doNotIssueFU2(1'b0),
    
    .IN_uop(RN_uop),
    .IN_uopOrdering(RN_uopOrdering),
    
    .IN_resultValid(wbHasResult),
    .IN_resultUOp(wbUOp),
    .IN_loadForwardValid(LSU_loadFwdValid),
    .IN_loadForwardTag(LSU_loadFwdTag),  

    .IN_branch(branch),
    
    .IN_issueUOps(IS_uop),
    
    .IN_maxStoreSqN(SQ_maxStoreSqN),
    .IN_maxLoadSqN(LB_maxLoadSqN),
    .IN_commitSqN(ROB_curSqN),
    
    .OUT_uop(IS_uop[2]),
    .OUT_full(IQ2_full)
);
wire IQ3_full;
IssueQueue#(`IQ_3_SIZE,3,1,`DEC_WIDTH,4,12,FU_ST,FU_ST,FU_ST,FU_ATOMIC,0,0,0) iq3 
(
    .clk(clk),
    .rst(rst),
    .frontEn(IQS_ready),
    
    .IN_stall(stall[3]),
    .IN_doNotIssueFU1(1'b0),
    .IN_doNotIssueFU2(1'b0),
    
    .IN_uop(RN_uop),
    .IN_uopOrdering(RN_uopOrdering),
    
    .IN_resultValid(wbHasResult),
    .IN_resultUOp(wbUOp),
    .IN_loadForwardValid(LSU_loadFwdValid),
    .IN_loadForwardTag(LSU_loadFwdTag),
    
    .IN_branch(branch),
    
    .IN_issueUOps(IS_uop),
    
    .IN_maxStoreSqN(SQ_maxStoreSqN),
    .IN_maxLoadSqN(LB_maxLoadSqN),
    .IN_commitSqN(ROB_curSqN),
    
    .OUT_uop(IS_uop[3]),
    .OUT_full(IQ3_full)
);

wire[5:0] RF_readAddress[7:0];
wire[31:0] RF_readData[7:0];

RF rf
(
    .clk(clk),
    
    .waddr0(wbUOp[0].tagDst[5:0]), .wdata0(wbUOp[0].result), .wen0(wbHasResult[0]),
    .waddr1(wbUOp[1].tagDst[5:0]), .wdata1(wbUOp[1].result), .wen1(wbHasResult[1]),
    .waddr2(wbUOp[2].tagDst[5:0]), .wdata2(wbUOp[2].result), .wen2(wbHasResult[2]),
    .waddr3(wbUOp[3].tagDst[5:0]), .wdata3(wbUOp[3].result), .wen3(wbHasResult[3]),
    
    .raddr0(RF_readAddress[0]), .rdata0(RF_readData[0]),
    .raddr1(RF_readAddress[1]), .rdata1(RF_readData[1]),
    .raddr2(RF_readAddress[2]), .rdata2(RF_readData[2]),
    .raddr3(RF_readAddress[3]), .rdata3(RF_readData[3]),
    .raddr4(RF_readAddress[4]), .rdata4(RF_readData[4]),
    .raddr5(RF_readAddress[5]), .rdata5(RF_readData[5]),
    .raddr6(RF_readAddress[6]), .rdata6(RF_readData[6]),
    .raddr7(SQ_RF_raddr), .rdata7(RF_SQ_rdata)
);

EX_UOp LD_uop[3:0] /*verilator public*/;

ZCForward LD_zcFwd[1:0];

Load ld
(
    .clk(clk),
    .rst(rst),
    
    .IN_uop(IS_uop),
    
    .IN_wbHasResult(wbHasResult),
    .IN_wbUOp(wbUOp),
    
    .IN_invalidate(branch.taken),
    .IN_invalidateSqN(branch.sqN),
    .IN_stall(stall),
    
    .IN_zcFwd(LD_zcFwd),
    
    .OUT_pcReadAddr(PC_readAddress[3:0]),
    .IN_pcReadData(PC_readData[3:0]),
    
    .OUT_rfReadAddr(RF_readAddress),
    .IN_rfReadData(RF_readData),
    
    .OUT_uop(LD_uop)
);


wire INTALU_wbReq;
RES_UOp INT0_uop;
IntALU ialu
(
    .clk(clk),
    .en(LD_uop[0].fu == FU_INT),
    .rst(rst),
    
    .IN_wbStall(1'b0),
    .IN_uop(LD_uop[0]),
    .IN_invalidate(branch.taken),
    .IN_invalidateSqN(branch.sqN),

    .OUT_wbReq(INTALU_wbReq),
    
    .OUT_branch(branchProvs[0]),
    .OUT_btUpdate(BP_btUpdates[0]),
    
    .OUT_zcFwd(LD_zcFwd[0]),
    
    .OUT_uop(INT0_uop)
);


wire DIV_busy;
RES_UOp DIV_uop;
wire DIV_doNotIssue = DIV_busy || (LD_uop[0].valid && LD_uop[0].fu == FU_DIV) || (IS_uop[0].valid && IS_uop[0].fu == FU_DIV);
Divide div
(
    .clk(clk),
    .rst(rst),
    .en(LD_uop[0].fu == FU_DIV),
    
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
    .en(LD_uop[0].fu == FU_FPU),
    
    .IN_branch(branch),
    .IN_uop(LD_uop[0]),
    
    .IN_fRoundMode(CSR_fRoundMode),
    .OUT_uop(FPU_uop)
);

TValProv TVS_tvalProvs[1:0];
TValState TVS_tvalState;
TValSelect tvalSelect
(
    .clk(clk),
    .rst(rst),
    .IN_branch(branch),
    .IN_commitSqN(ROB_curSqN),
    .IN_tvalProvs(TVS_tvalProvs),
    .OUT_tvalState(TVS_tvalState)
);

RES_UOp CSR_uop;
TrapControlState CSR_trapControl /*verilator public*/;
wire[2:0] CSR_fRoundMode;
DecodeState CSR_dec;
VirtMemState CSR_vmem;
CSR csr
(
    .clk(clk),
    .rst(rst),
    .en(LD_uop[0].fu == FU_CSR),
    .IN_uop(LD_uop[0]),
    .IN_branch(branch),
    .IN_fpNewFlags(ROB_fpNewFlags),
    
    .IN_commitValid(ROB_validRetire),
    .IN_commitBranch(ROB_retireBranch),
    .IN_branchMispr(BS_PERFC_branchMispr),
    .IN_mispredFlush(mispredFlush),
    
    .IF_mmio(IF_csr_mmio),

    .IN_tvalState(TVS_tvalState),

    .IN_trapInfo(TH_trapInfo),
    .OUT_trapControl(CSR_trapControl),
    .OUT_fRoundMode(CSR_fRoundMode),
    
    .OUT_dec(CSR_dec),
    .OUT_vmem(CSR_vmem),
    
    .OUT_uop(CSR_uop)
);

assign wbUOp[0] = INT0_uop.valid ? INT0_uop : (CSR_uop.valid ? CSR_uop : (FPU_uop.valid ? FPU_uop : DIV_uop));

PageWalk_Res PW_res;
wire CC_PW_LD_stall;
PW_LD_UOp PW_LD_uop;
PageWalker pageWalker
(
    .clk(clk),
    .rst(rst),

    .IN_rqs('{LDAGU_PW_rq, STAGU_PW_rq, PC_PW_rq}),
    .OUT_res(PW_res),

    .IN_ldStall(CC_PW_LD_stall),
    .OUT_ldUOp(PW_LD_uop),
    .IN_ldAck(LSU_ldAck),
    .IN_ldResUOp(wbUOp[2])
);

wire LS_AGULD_uopStall;
LD_UOp LS_uopLd;
LoadSelector loadSelector
(
    .IN_aguLd(LB_uopLd),
    .OUT_aguLdStall(LS_AGULD_uopStall),

    .IN_pwLd(PW_LD_uop),
    .OUT_pwLdStall(CC_PW_LD_stall),

    .IN_ldUOpStall(CC_loadStall),
    .OUT_ldUOp(LS_uopLd)
);

TLB_Req TLB_rqs[1:0];
TLB_Res TLB_res[1:0];
TLB#(2) dtlb
(
    .clk(clk),
    .rst(rst),
    .clear(TH_flushTLB),
    .IN_pw(PW_res),
    .IN_rqs(TLB_rqs),
    .OUT_res(TLB_res)
);

AGU_UOp AGU_LD_uop /* verilator public */;
ELD_UOp AGU_eLdUOp;
PageWalk_Req LDAGU_PW_rq;
AGU#(.LOAD_AGU(1), .RQ_ID(2)) aguLD
(
    .clk(clk),
    .rst(rst),
    .en(LD_uop[2].fu == FU_LD || LD_uop[2].fu == FU_ATOMIC),
    .IN_stall(LSU_ldAGUStall),
    .OUT_stall(stall[2]),
    
    .IN_branch(branch),
    .IN_vmem(CSR_vmem),
    .OUT_pw(LDAGU_PW_rq),
    .IN_pw(PW_res),

    .OUT_tvalProv(TVS_tvalProvs[0]),
    
    .OUT_tlb(TLB_rqs[1]),
    .IN_tlb(TLB_res[1]),

    .IN_uop(LD_uop[2]),
    .OUT_aguOp(AGU_LD_uop),
    .OUT_eldOp(AGU_eLdUOp),
    .OUT_uop()
);

AGU_UOp AGU_ST_uop /* verilator public */;
PageWalk_Req STAGU_PW_rq;
AGU#(.LOAD_AGU(0), .RQ_ID(1)) aguST
(
    .clk(clk),
    .rst(rst),
    .en(LD_uop[3].fu == FU_ST || LD_uop[3].fu == FU_ATOMIC),
    .IN_stall(1'b0),
    .OUT_stall(stall[3]),
    
    .IN_branch(branch),
    .IN_vmem(CSR_vmem),
    .OUT_pw(STAGU_PW_rq),
    .IN_pw(PW_res),
    
    .OUT_tvalProv(TVS_tvalProvs[1]),

    .OUT_tlb(TLB_rqs[0]),
    .IN_tlb(TLB_res[0]),

    .IN_uop(LD_uop[3]),
    .OUT_aguOp(AGU_ST_uop),
    .OUT_eldOp(),
    .OUT_uop(wbUOp[3])
);


SqN LB_maxLoadSqN;
LD_UOp LB_uopLd;
LD_UOp LB_aguUOpLd;

LoadBuffer lb
(
    .clk(clk),
    .rst(rst),
    .commitSqN(ROB_curSqN),
    
    .IN_stall(LS_AGULD_uopStall),
    .IN_uopLd(AGU_LD_uop),
    .IN_uopSt(AGU_ST_uop),
    
    .IN_ldAck(LSU_ldAck),
    .IN_SQ_done(SQ_done),
    
    .OUT_uopAGULd(LB_aguUOpLd),
    .OUT_uopLd(LB_uopLd),
    
    .IN_branch(branch),
    .OUT_branch(branchProvs[2]),
    
    .OUT_maxLoadSqN(LB_maxLoadSqN)
);

wire CSR_we;
wire[31:0] CSR_dataOut;

wire SQ_empty;
wire SQ_done;
ST_UOp SQ_uop;
StFwdResult SQ_fwd;
SqN SQ_maxStoreSqN;
wire SQ_flush;
SQ_ComInfo SQ_info;

wire[$bits(Tag)-2:0] SQ_RF_raddr;
wire[31:0] RF_SQ_rdata;

StoreQueue sq
(
    .clk(clk),
    .rst(rst),
    .IN_stallSt(CC_storeStall),
    .IN_stallLd(CC_loadStall),
    .OUT_empty(SQ_empty),
    .OUT_done(SQ_done),
    
    .IN_uopSt(AGU_ST_uop),
    .IN_uopLd(CC_SQ_uopLd),
    
    .IN_rnUOp(RN_uop),
    .IN_resultUOp(wbUOp[2:0]),
    .OUT_RF_raddr(SQ_RF_raddr),
    .IN_RF_rdata(RF_SQ_rdata),
    .IN_vmem(CSR_vmem),
    
    .IN_curSqN(ROB_curSqN),
    
    .IN_branch(branch),
    
    .OUT_uopSt(SQ_uop),
    .OUT_fwd(SQ_fwd),

    .IN_stAck(LSU_stAck),
    
    .OUT_flush(SQ_flush),
    .OUT_maxStoreSqN(SQ_maxStoreSqN),
    .OUT_sqInfo(SQ_info)
);

wire LSU_loadFwdValid = 0;
Tag LSU_loadFwdTag = 'x;
wire CC_loadStall;
wire CC_storeStall;
wire LSU_ldAGUStall;
LD_UOp CC_SQ_uopLd;
LD_Ack LSU_ldAck;
wire LSU_busy;

MemController_Req LSU_MC_if;
MemController_Req BLSU_MC_if;
ST_Ack LSU_stAck;
LoadStoreUnit lsu
(
    .clk(clk),
    .rst(rst),

    .IN_flush(TH_startFence),
    .IN_SQ_empty(SQ_empty),
    .OUT_busy(LSU_busy),
    
    .IN_branch(branch),
    .OUT_ldAGUStall(LSU_ldAGUStall),
    .OUT_ldStall(CC_loadStall),
    .OUT_stStall(CC_storeStall),
    
    .IN_uopELd(AGU_eLdUOp),
    .IN_aguLd(LB_aguUOpLd),

    .IN_uopLd(LS_uopLd),
    .OUT_uopLdSq(CC_SQ_uopLd),
    .OUT_ldAck(LSU_ldAck),

    .IN_uopSt(SQ_uop),
    
    .IF_cache(IF_cache),
    .IF_mmio(IF_mmio),
    .IF_ct(IF_ct),

    .IN_stFwd(SQ_fwd),
    .OUT_stAck(LSU_stAck),
    
    .OUT_memc(LSU_MC_if),
    .OUT_BLSU_memc(BLSU_MC_if),
    .IN_memc(IN_memc),

    .OUT_uopLd(wbUOp[2])
);

RES_UOp INT1_uop;
IntALU ialu1
(
    .clk(clk),
    .en(LD_uop[1].fu == FU_INT),
    .rst(rst),
    
    .IN_wbStall(1'b0),
    .IN_uop(LD_uop[1]),
    .IN_invalidate(branch.taken),
    .IN_invalidateSqN(branch.sqN),

    .OUT_wbReq(),

    .OUT_branch(branchProvs[1]),
    .OUT_btUpdate(BP_btUpdates[1]),
    
    .OUT_zcFwd(LD_zcFwd[1]),
    
    .OUT_uop(INT1_uop)
);

RES_UOp MUL_uop;
wire MUL_busy;
wire MUL_doNotIssue = 0;
Multiply mul
(
    .clk(clk),
    .rst(rst),
    .en(LD_uop[1].fu == FU_MUL),
    
    .OUT_busy(MUL_busy),
    
    .IN_branch(branch),
    .IN_uop(LD_uop[1]),
    .OUT_uop(MUL_uop)
);
RES_UOp FMUL_uop;
FMul fmul
(
    .clk(clk),
    .rst(rst), 
    .en(LD_uop[1].fu == FU_FMUL),
    
    .IN_branch(branch),
    .IN_uop(LD_uop[1]),
    
    .IN_fRoundMode(CSR_fRoundMode),
    .OUT_uop(FMUL_uop)
);

wire FDIV_busy;
wire FDIV_doNotIssue = FDIV_busy || (LD_uop[1].valid && LD_uop[1].fu == FU_FDIV) || (IS_uop[1].valid && IS_uop[1].fu == FU_FDIV);
RES_UOp FDIV_uop;
FDiv fdiv
(
    .clk(clk),
    .rst(rst),
    .en(LD_uop[1].fu == FU_FDIV),
    
    .IN_wbAvail(!INT1_uop.valid && !MUL_uop.valid && !FMUL_uop.valid),
    .OUT_busy(FDIV_busy),
    
    .IN_branch(branch),
    .IN_uop(LD_uop[1]),
    .IN_fRoundMode(CSR_fRoundMode),
    .OUT_uop(FDIV_uop)
);

assign wbUOp[1] = INT1_uop.valid ? INT1_uop : (MUL_uop.valid ? MUL_uop : (FMUL_uop.valid ? FMUL_uop : FDIV_uop));

SqN ROB_maxSqN;
FetchID_t ROB_curFetchID;
wire[4:0] ROB_fpNewFlags;
wire[3:0] ROB_validRetire /*verilator public*/;
wire[3:0] ROB_retireBranch;
BPUpdate0 ROB_bpUpdate0;
Trap_UOp ROB_trapUOp /*verilator public*/;
ROB rob
(
    .clk(clk),
    .rst(rst),
    .IN_uop(RN_uop),
    .IN_wbUOps(wbUOp),
    
    .IN_interruptPending(CSR_trapControl.interruptPending),

    .IN_branch(branch),
    .IN_sqInfo(SQ_info),
    
    .OUT_maxSqN(ROB_maxSqN),
    .OUT_curSqN(ROB_curSqN),
    .OUT_comUOp(comUOps),
    .OUT_fpNewFlags(ROB_fpNewFlags),
    .OUT_PERFC_validRetire(ROB_validRetire),
    .OUT_PERFC_retireBranch(ROB_retireBranch),
    .OUT_curFetchID(ROB_curFetchID),
    
    .OUT_trapUOp(ROB_trapUOp),
    .OUT_bpUpdate0(ROB_bpUpdate0),

    .OUT_mispredFlush(mispredFlush)
);

wire MEMSUB_busy = !SQ_empty || SQ_uop.valid || AGU_LD_uop.valid || LSU_busy;

wire TH_flushTLB;
wire TH_startFence;
wire TH_disableIFetch;
wire TH_clearICache;
BPUpdate TH_bpUpdate;
TrapInfoUpdate TH_trapInfo;
TrapHandler trapHandler
(
    .clk(clk),
    .rst(rst),

    .IN_trapInstr(ROB_trapUOp),
    .OUT_pcReadAddr(PC_readAddress[4]),
    .IN_pcReadData(PC_readData[4]),
    .IN_trapControl(CSR_trapControl),
    .OUT_trapInfo(TH_trapInfo),
    .OUT_bpUpdate(TH_bpUpdate),
    .OUT_branch(branchProvs[3]),
    
    .IN_MEM_busy(MEMSUB_busy),
    
    .OUT_flushTLB(TH_flushTLB),
    .OUT_fence(TH_startFence),
    .OUT_clearICache(TH_clearICache),
    .OUT_disableIFetch(TH_disableIFetch)
);

endmodule
