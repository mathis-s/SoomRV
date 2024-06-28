module Core
(
    input wire clk,
    input wire rst,
    input wire en,

    input wire IN_irq,

    IF_Cache.HOST IF_cache,
    IF_CTable.HOST IF_ct,
    IF_MMIO.HOST IF_mmio,
    IF_CSR_MMIO.CSR IF_csr_mmio,
    
    IF_ICTable.HOST IF_ict,
    IF_ICache.HOST IF_icache,
        
    output MemController_Req OUT_memc[2:0],
    input MemController_Res IN_memc,

    output DebugInfo OUT_dbg
);

assign OUT_memc[0] = PC_MC_if;
assign OUT_memc[1] = LSU_MC_if;
assign OUT_memc[2] = BLSU_MC_if;

assign OUT_dbg.stallPC = TH_stallPC;
assign OUT_dbg.sqNStall = sqNStall;
assign OUT_dbg.stSqNStall = 0;
assign OUT_dbg.rnStall = RN_stall;
assign OUT_dbg.memBusy = MEMSUB_busy;
assign OUT_dbg.sqBusy = !SQ_empty || SQB_uop.valid;
assign OUT_dbg.lsuBusy = 0;//AGU_LD_uop.valid || LSU_busy;
assign OUT_dbg.ldNack = 0;//LSU_ldAck.valid && LSU_ldAck.fail;
assign OUT_dbg.stNack = 0;//LSU_stAck.valid && LSU_stAck.fail;

localparam NUM_WBS = 4;
RES_UOp wbUOp[5:0] /*verilator public*/;
reg wbHasResult[NUM_WBS-1:0];
always_comb begin
    for (integer i = 0; i < NUM_WBS; i=i+1)
        wbHasResult[i] = wbUOp[i].valid && !wbUOp[i].tagDst[6];
end

CommitUOp comUOps[3:0] /*verilator public*/;

wire ifetchEn = !TH_disableIFetch;

wire[30:0] BP_lateRetAddr;

BranchProv branchProvs[3:0];
BranchProv branch /*verilator public*/;
wire mispredFlush /*verilator public*/;
wire BS_PERFC_branchMispr;

BranchSelector#(4) bsel
(
    .clk(clk),
    .rst(rst),

    .IN_isUOps(IS_uop),
    
    .IN_branches(branchProvs),
    .OUT_branch(branch),
    
    .OUT_PERFC_branchMispr(BS_PERFC_branchMispr),
    
    .IN_ROB_curSqN(ROB_curSqN),
    .IN_RN_nextSqN(RN_nextSqN),
    .IN_mispredFlush(mispredFlush)
);

IF_Instr IF_instrs /*verilator public*/;
BTUpdate BP_btUpdates[1:0];

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
    .IN_MEM_busy(MEMSUB_busy),
    
    .IF_ict(IF_ict),
    .IF_icache(IF_icache),
    
    .IN_ROB_curFetchID(ROB_curFetchID),
    .IN_branch(branch),
    
    .IN_clearICache(TH_clearICache),
    .IN_flushTLB(TH_flushTLB),
    .IN_btUpdates(BP_btUpdates),
    .IN_bpUpdate(ROB_bpUpdate),
    
    .IN_pcReadAddr(PC_readAddress),
    .OUT_pcReadData(PC_readData),
    
    .IN_ready(!PD_full),
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
    .outEn(!RN_stall && frontendEn),

    .OUT_full(PD_full),
    
    .mispred(branch.taken),
    .IN_instrs(IF_instrs),
    .OUT_instrs(PD_instrs)
);

D_UOp DE_uop[`DEC_WIDTH-1:0] /*verilator public*/;
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
    
    .OUT_uop(DE_uop)
);

wire sqNStall = ($signed((RN_nextSqN) - ROB_maxSqN) > -(`DEC_WIDTH));
wire frontendEn /*verilator public*/ = 
    !sqNStall &&
    !branch.taken &&
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
    
    .IN_stalls(IQ_stalls),
    .OUT_stall(RN_stall),

    .IN_uop(DE_uop),

    .IN_comUOp(comUOps),

    .IN_wbHasResult(wbHasResult),
    .IN_wbUOp(wbUOp[3:0]),

    .IN_branch(branch),
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

wire[3:0][`DEC_WIDTH-1:0] IQ_stalls;
//wire IQS_ready /*verilator public*/ = !IQ0_full && !IQ1_full && !IQ2_full && !IQ3_full;
//wire IQ0_full;
IssueQueue#(`IQ_0_SIZE,2,0,2,`DEC_WIDTH,4,32+4,FU_INT,FU_DIV,FU_FPU,FU_CSR,1,0,
`ifdef ENABLE_INT_DIV
    33
`else 
    0
`endif
) iq0
(
    .clk(clk),
    .rst(rst),

    .IN_defer('0),
    .OUT_stall(IQ_stalls[0]),
    
    .IN_stall(stall[0]),
    .IN_doNotIssueFU1(DIV_doNotIssue),
    .IN_doNotIssueFU2(1'b0),
    
    .IN_uop(RN_uop),
    .IN_uopOrdering(RN_uopOrdering),
    
    .IN_resultValid(wbHasResult),
    .IN_resultUOp(wbUOp[3:0]),
    
    .IN_branch(branch),
    
    .IN_issueUOps(IS_uop),
    
    .IN_maxStoreSqN(SQ_maxStoreSqN),
    .IN_maxLoadSqN(LB_maxLoadSqN),
    .IN_commitSqN(ROB_curSqN),
    
    .OUT_uop(IS_uop[0])
);
IssueQueue#(`IQ_1_SIZE,2,1,2,`DEC_WIDTH,4,32+4,FU_INT,FU_MUL,FU_FDIV,FU_FMUL,1,1,
`ifdef ENABLE_INT_MUL
    9-4-2
`else 
    0
`endif
) iq1
(
    .clk(clk),
    .rst(rst),

    .IN_defer('0),
    .OUT_stall(IQ_stalls[1]),
    
    .IN_stall(stall[1]),
    .IN_doNotIssueFU1(MUL_doNotIssue),
    .IN_doNotIssueFU2(FDIV_doNotIssue),
    
    .IN_uop(RN_uop),
    .IN_uopOrdering(RN_uopOrdering),
    
    .IN_resultValid(wbHasResult),
    .IN_resultUOp(wbUOp[3:0]),
    
    .IN_branch(branch),
    
    .IN_issueUOps(IS_uop),
    
    .IN_maxStoreSqN(SQ_maxStoreSqN),
    .IN_maxLoadSqN(LB_maxLoadSqN),
    .IN_commitSqN(ROB_curSqN),
    
    .OUT_uop(IS_uop[1])
);
IssueQueue#(`IQ_2_SIZE,2,2,1,`DEC_WIDTH,4,12,FU_AGU,FU_AGU,FU_AGU,FU_ATOMIC,0,0,0) iq2
(
    .clk(clk),
    .rst(rst),

    .IN_defer(stLookupIQStall[0]),
    .OUT_stall(IQ_stalls[2]),
    
    .IN_stall(stall[2]),
    .IN_doNotIssueFU1(1'b0),
    .IN_doNotIssueFU2(1'b0),
    
    .IN_uop(RN_uop),
    .IN_uopOrdering(RN_uopOrdering),
    
    .IN_resultValid(wbHasResult),
    .IN_resultUOp(wbUOp[3:0]), 

    .IN_branch(branch),
    
    .IN_issueUOps(IS_uop),
    
    .IN_maxStoreSqN(SQ_maxStoreSqN),
    .IN_maxLoadSqN(LB_maxLoadSqN),
    .IN_commitSqN(ROB_curSqN),
    
    .OUT_uop(IS_uop[2])
);
IssueQueue#(`IQ_3_SIZE,2,3,1,`DEC_WIDTH,4,12,FU_AGU,FU_AGU,FU_AGU,FU_ATOMIC,0,0,0) iq3 
(
    .clk(clk),
    .rst(rst),

    .IN_defer(stLookupIQStall[1]),
    .OUT_stall(IQ_stalls[3]),
    
    .IN_stall(stall[3]),
    .IN_doNotIssueFU1(1'b0),
    .IN_doNotIssueFU2(1'b0),
    
    .IN_uop(RN_uop),
    .IN_uopOrdering(RN_uopOrdering),
    
    .IN_resultValid(wbHasResult),
    .IN_resultUOp(wbUOp[3:0]),
    
    .IN_branch(branch),
    
    .IN_issueUOps(IS_uop),
    
    .IN_maxStoreSqN(SQ_maxStoreSqN),
    .IN_maxLoadSqN(LB_maxLoadSqN),
    .IN_commitSqN(ROB_curSqN),
    
    .OUT_uop(IS_uop[3])
);

StDataLookupUOp stLookupUOp[`NUM_AGUS-1:0];
wire stLookupUOp_ready[`NUM_AGUS-1:0];
wire[`DEC_WIDTH-1:0] stLookupIQStall[`NUM_AGUS-1:0];
ComLimit stCommitLimit[`NUM_AGUS-1:0];

generate for (genvar i = 0; i < `NUM_AGUS; i=i+1) begin
    StoreDataIQ #(8, 2, i, 4, 4) iqStD
    (
        .clk(clk),
        .rst(rst),

        .OUT_stall(stLookupIQStall[i]),
        .IN_uop(RN_uop),

        .IN_resultValid(wbHasResult),
        .IN_resultUOp(wbUOp[3:0]),

        .IN_branch(branch),
        
        .IN_issueUOps(IS_uop),

        .IN_aguUOps(LD_uop[3:2]),
        .IN_maxStoreSqN(SQ_maxStoreSqN),

        .OUT_comLimit(stCommitLimit[i]),

        .IN_ready(stLookupUOp_ready[i]),
        .OUT_uop(stLookupUOp[i])
    );
end endgenerate

RFTag RF_readAddress[7:0];
RegT RF_readData[7:0];

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
    .raddr6(SDL_readTag[0]), .rdata6(SDL_readData[0]),
    .raddr7(SDL_readTag[1]), .rdata7(SDL_readData[1])
);

EX_UOp LD_uop[3:0] /*verilator public*/;

ZCForward LD_zcFwd[1:0];

Load ld
(
    .clk(clk),
    .rst(rst),
    
    .IN_uop(IS_uop),
    
    .IN_wbHasResult(wbHasResult),
    .IN_wbUOp(wbUOp[3:0]),
    
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

AMO_Data_UOp SDL_amoData[`NUM_AGUS-1:0];
RFTag SDL_readTag[`NUM_AGUS-1:0];
RegT SDL_readData[`NUM_AGUS-1:0];
StDataUOp SDL_stDataUOp[`NUM_AGUS-1:0];
StoreDataLoad stDataLd
(
    .clk(clk),
    .rst(rst),

    .IN_branch(branch),
    
    .IN_uop(stLookupUOp),
    .OUT_ready(stLookupUOp_ready),

    .IN_atomicUOp(SDL_amoData),

    .OUT_readTag(SDL_readTag),
    .IN_readData(SDL_readData),

    .OUT_uop(SDL_stDataUOp)
);

RES_UOp INT0_uop;
IntALU ialu
(
    .clk(clk),
    .rst(rst),
    
    .IN_wbStall(1'b0),
    .IN_uop(LD_uop[0]),
    .IN_invalidate(branch.taken),
    .IN_invalidateSqN(branch.sqN),
    
    .OUT_branch(branchProvs[0]),
    .OUT_btUpdate(BP_btUpdates[0]),
    
    .OUT_zcFwd(LD_zcFwd[0]),
    
    .OUT_amoData(SDL_amoData[0]),
    .OUT_uop(INT0_uop)
);

`ifdef ENABLE_INT_DIV
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
`else
wire DIV_doNotIssue = 1'b0;
`endif

`ifdef ENABLE_FP
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
`endif

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
    
    .IN_irq(IN_irq),

    .IN_uop(LD_uop[0]),
    .IN_branch(branch),
    .IN_fpNewFlags(ROB_fpNewFlags),
    
    .IN_perfcInfo(ROB_perfcInfo),
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

always_comb begin
    wbUOp[0] = 'x;
    wbUOp[0].valid = 1'b0;

    if (INT0_uop.valid)
        wbUOp[0] = INT0_uop;
    else if (CSR_uop.valid)
        wbUOp[0] = CSR_uop;
    //else if (AGU_resUOp.valid && aguUOpPort_r == 0)
    //    wbUOp[0] = AGU_resUOp;
`ifdef ENABLE_FP
    else if (FPU_uop.valid)
        wbUOp[0] = FPU_uop;
`endif
`ifdef ENABLE_INT_DIV
    else if (DIV_uop.valid)
        wbUOp[0] = DIV_uop;
`endif
    
end

PageWalk_Res PW_res;
wire CC_PW_LD_stall[1:0];
PW_LD_UOp PW_LD_uop[`NUM_AGUS-1:0];
assign PW_LD_uop[1] = PW_LD_UOp'{valid: 0, default: 'x};
PageWalker pageWalker
(
    .clk(clk),
    .rst(rst),

    .IN_rqs('{LDAGU_PW_rq, STAGU_PW_rq, PC_PW_rq}),
    .OUT_res(PW_res),

    .IN_ldStall(CC_PW_LD_stall[0]),
    .OUT_ldUOp(PW_LD_uop[0]),
    .IN_ldAck(LSU_ldAck[0]),
    .IN_ldResUOp(wbUOp[2])
);

wire LS_AGULD_uopStall[`NUM_AGUS-1:0];
LD_UOp LS_uopLd[`NUM_AGUS-1:0];
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
TLB#(2, `DTLB_SIZE, `DTLB_ASSOC) dtlb
(
    .clk(clk),
    .rst(rst),
    .clear(TH_flushTLB),
    .IN_pw(PW_res),
    .IN_rqs(TLB_rqs),
    .OUT_res(TLB_res)
);


AGU_UOp AGU_uop[`NUM_AGUS-1:0];
ELD_UOp AGU_eLdUOp[`NUM_AGUS-1:0];

PageWalk_Req LDAGU_PW_rq;
wire[$clog2(`DTLB_MISS_QUEUE_SIZE):0] LDAGU_TMQ_free;
AGU#(.AGU_IDX(0), .RQ_ID(2)) aguLD
(
    .clk(clk),
    .rst(rst),
    .IN_stall(LSU_ldAGUStall[0]),
    .OUT_stall(stall[2]),

    .OUT_TMQ_free(LDAGU_TMQ_free),
    
    .IN_branch(branch),
    .IN_vmem(CSR_vmem),
    .OUT_pw(LDAGU_PW_rq),
    .IN_pw(PW_res),

    .OUT_tvalProv(TVS_tvalProvs[0]),
    
    .OUT_tlb(TLB_rqs[1]),
    .IN_tlb(TLB_res[1]),

    .IN_uop(LD_uop[2]),
    .OUT_aguOp(AGU_uop[0]),
    .OUT_eldOp(AGU_eLdUOp[0]),
    .OUT_uop(wbUOp[4])
);

AGU_UOp AGU_ST_uop /* verilator public */;
PageWalk_Req STAGU_PW_rq;
wire[$clog2(`DTLB_MISS_QUEUE_SIZE):0] STAGU_TMQ_free;
AGU#(.AGU_IDX(1), .RQ_ID(1)) aguST
(
    .clk(clk),
    .rst(rst),
    .IN_stall(LSU_ldAGUStall[1]),
    .OUT_stall(stall[3]),

    .OUT_TMQ_free(STAGU_TMQ_free),
    
    .IN_branch(branch),
    .IN_vmem(CSR_vmem),
    .OUT_pw(STAGU_PW_rq),
    .IN_pw(PW_res),
    
    .OUT_tvalProv(TVS_tvalProvs[1]),

    .OUT_tlb(TLB_rqs[0]),
    .IN_tlb(TLB_res[0]),

    .IN_uop(LD_uop[3]),
    .OUT_aguOp(AGU_uop[1]),
    .OUT_eldOp(AGU_eLdUOp[1]),
    .OUT_uop(wbUOp[5])
);


SqN LB_maxLoadSqN;
LD_UOp LB_uopLd[`NUM_AGUS-1:0];
LD_UOp LB_aguUOpLd[`NUM_AGUS-1:0];

ComLimit LB_ldComLimit;
LoadBuffer lb
(
    .clk(clk),
    .rst(rst),
    .IN_memc(IN_memc),
    .IN_LSU_memc(LSU_MC_if),
    .IN_comLoadSqN(ROB_comLoadSqN),
    .IN_comSqN(ROB_curSqN),
    
    .IN_stall(LS_AGULD_uopStall),
    .IN_uop(AGU_uop),
    
    .IN_ldAck(LSU_ldAck),
    .IN_SQ_done(SQ_done),
    
    .OUT_uopAGULd(LB_aguUOpLd),
    .OUT_uopLd(LB_uopLd),
    
    .IN_branch(branch),
    .OUT_branch(branchProvs[2]),
    
    .OUT_maxLoadSqN(LB_maxLoadSqN),
    
    .OUT_comLimit(LB_ldComLimit)
);

wire SQ_empty;
wire SQ_done;

StFwdResult SQ_fwd[`NUM_AGUS-1:0];
StFwdResult SQB_fwd[`NUM_AGUS-1:0];

SqN SQ_maxStoreSqN;
wire SQ_flush;
SQ_UOp SQ_uops[`NUM_AGUS-1:0];
wire SQ_stall[`NUM_AGUS-1:0];
StoreQueue sq
(
    .clk(clk),
    .rst(rst),

    .OUT_empty(SQ_empty),
    .OUT_done(SQ_done),
    
    .IN_uopLd(CC_SQ_uopLd),
    .OUT_fwd(SQ_fwd),

    .IN_uopSt(AGU_uop),
    .IN_rnUOp(RN_uop),
    .IN_stDataUOp(SDL_stDataUOp),

    .IN_curSqN(ROB_curSqN),
    .IN_comStSqN(ROB_comStoreSqN),
    
    .IN_branch(branch),
    
    .OUT_uop(SQ_uops),
    .IN_stall(SQ_stall),
    
    .OUT_flush(SQ_flush),
    .OUT_maxStoreSqN(SQ_maxStoreSqN)
);

ST_UOp SQB_uop;
wire SQB_busy;
StoreQueueBackend sqb
(
    .clk(clk),
    .rst(rst),

    .OUT_busy(SQB_busy),

    .IN_uopLd(CC_SQ_uopLd),
    .OUT_fwd(SQB_fwd),

    .IN_uop(SQ_uops),
    .OUT_stall(SQ_stall),
    
    .IN_stallSt(CC_storeStall),
    .OUT_uopSt(SQB_uop),
    .IN_stAck(LSU_stAck)
);

wire CC_loadStall[`NUM_AGUS-1:0];
wire CC_storeStall;
wire LSU_ldAGUStall[`NUM_AGUS-1:0];
LD_UOp CC_SQ_uopLd[`NUM_AGUS-1:0];
LD_Ack LSU_ldAck[`NUM_AGUS-1:0];
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

    .IN_uopSt(SQB_uop),
    
    .IF_cache(IF_cache),
    .IF_mmio(IF_mmio),
    .IF_ct(IF_ct),

    .IN_sqStFwd(SQ_fwd),
    .IN_sqbStFwd(SQB_fwd),
    .OUT_stAck(LSU_stAck),
    
    .OUT_memc(LSU_MC_if),
    .OUT_BLSU_memc(BLSU_MC_if),
    .IN_memc(IN_memc),
    
    .IN_ready('{1'b1, 1'b1}),
    .OUT_uopLd(wbUOp[3:2])
);

RES_UOp INT1_uop;
IntALU ialu1
(
    .clk(clk),
    .rst(rst),
    
    .IN_wbStall(1'b0),
    .IN_uop(LD_uop[1]),
    .IN_invalidate(branch.taken),
    .IN_invalidateSqN(branch.sqN),
    
    .OUT_branch(branchProvs[1]),
    .OUT_btUpdate(BP_btUpdates[1]),
    
    .OUT_zcFwd(LD_zcFwd[1]),
    
    .OUT_amoData(SDL_amoData[1]),
    .OUT_uop(INT1_uop)
);

`ifdef ENABLE_INT_MUL
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
`endif

`ifdef ENABLE_FP
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
`else
wire FDIV_busy = 1;
wire FDIV_doNotIssue = 1;
`endif

always_comb begin
    wbUOp[1] = 'x;
    wbUOp[1].valid = 1'b0;

    if (INT1_uop.valid)
        wbUOp[1] = INT1_uop;
    //else if (AGU_resUOp.valid && aguUOpPort_r == 1)
    //    wbUOp[1] = AGU_resUOp;

    `ifdef ENABLE_INT_MUL
    else if (MUL_uop.valid)
        wbUOp[1] = MUL_uop;
    `endif
    `ifdef ENABLE_FP
    else if (FMUL_uop.valid)
        wbUOp[1] = FMUL_uop;
    else if (FDIV_uop.valid)
        wbUOp[1] = FDIV_uop;
    `endif
end

SqN ROB_maxSqN;
FetchID_t ROB_curFetchID;
wire[4:0] ROB_fpNewFlags;

ROB_PERFC_Info ROB_perfcInfo /*verilator public*/;

BPUpdate ROB_bpUpdate;
Trap_UOp ROB_trapUOp /*verilator public*/;
SqN ROB_comLoadSqN;
SqN ROB_comStoreSqN;
ROB rob
(
    .clk(clk),
    .rst(rst),
    .IN_uop(RN_uop),
    .IN_wbUOps(wbUOp),
    
    .IN_interruptPending(CSR_trapControl.interruptPending),
    .OUT_perfcInfo(ROB_perfcInfo),

    .IN_branch(branch),
    
    .IN_stComLimit(stCommitLimit),
    .IN_ldComLimit(LB_ldComLimit),
    
    .OUT_maxSqN(ROB_maxSqN),
    .OUT_curSqN(ROB_curSqN),
    .OUT_lastLoadSqN(ROB_comLoadSqN),
    .OUT_lastStoreSqN(ROB_comStoreSqN),

    .OUT_comUOp(comUOps),
    .OUT_fpNewFlags(ROB_fpNewFlags),
    .OUT_curFetchID(ROB_curFetchID),
    
    .OUT_trapUOp(ROB_trapUOp),
    .OUT_bpUpdate(ROB_bpUpdate),

    .OUT_mispredFlush(mispredFlush)
);

wire MEMSUB_busy = !SQ_empty || SQB_busy || LSU_busy;

wire TH_flushTLB;
wire TH_startFence;
wire TH_disableIFetch;
wire TH_clearICache;
TrapInfoUpdate TH_trapInfo;
wire[31:0] TH_stallPC;
TrapHandler trapHandler
(
    .clk(clk),
    .rst(rst),

    .IN_trapInstr(ROB_trapUOp),
    .OUT_pcReadAddr(PC_readAddress[4]),
    .IN_pcReadData(PC_readData[4]),
    .IN_trapControl(CSR_trapControl),
    .OUT_trapInfo(TH_trapInfo),
    .OUT_branch(branchProvs[3]),
    
    .IN_MEM_busy(MEMSUB_busy),
    
    .OUT_flushTLB(TH_flushTLB),
    .OUT_fence(TH_startFence),
    .OUT_clearICache(TH_clearICache),
    .OUT_disableIFetch(TH_disableIFetch),
    .OUT_dbgStallPC(TH_stallPC)
);

endmodule
