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
assign OUT_dbg.memBusy = MEM_busy;
assign OUT_dbg.sqBusy = !SQ_empty || SQB_uop.valid;
assign OUT_dbg.lsuBusy = 0;//AGU_LD_uop.valid || LSU_busy;
assign OUT_dbg.ldNack = 0;//LSU_ldAck.valid && LSU_ldAck.fail;
assign OUT_dbg.stNack = 0;//LSU_stAck.valid && LSU_stAck.fail;

RES_UOp wbUOp[NUM_PORTS_TOTAL-1:0] /*verilator public*/;
reg wbHasResult[NUM_PORTS-1:0];
always_comb begin
    for (integer i = 0; i < NUM_PORTS; i=i+1)
        wbHasResult[i] = wbUOp[i].valid && !wbUOp[i].tagDst[$bits(Tag)-1];
end

CommitUOp comUOps[3:0] /*verilator public*/;

wire ifetchEn = en && !TH_disableIFetch;

localparam NUM_BRANCHES = NUM_BRANCH_PORTS + 2;
localparam LQ_BRANCH_PORT = NUM_BRANCHES-2;
localparam TH_BRANCH_PORT = NUM_BRANCHES-1;
BranchProv branchProvs[NUM_BRANCHES-1:0];
BranchProv branch /*verilator public*/;
wire mispredFlush /*verilator public*/;
wire BS_PERFC_branchMispr;

BranchSelector#(4) bsel
(
    .clk(clk),
    .rst(rst),

    .IN_isUOps(IS_uop[3:0]),

    .IN_branches(branchProvs[3:0]),
    .OUT_branch(branch),

    .OUT_PERFC_branchMispr(BS_PERFC_branchMispr),

    .IN_ROB_curSqN(ROB_curSqN),
    .IN_RN_nextSqN(RN_nextSqN),
    .IN_mispredFlush(mispredFlush)
);

IF_Instr IF_instrs /*verilator public*/;
BTUpdate BP_btUpdates[NUM_ALUS-1:0];

PCFileReadReq PC_readReq[NUM_BRANCH_PORTS-1:0];
PCFileEntry PC_readData[NUM_BRANCH_PORTS-1:0];
PCFileReadReqTH PC_readReqTH;
PCFileEntry PC_readDataTH;

MemController_Req PC_MC_if;
PageWalk_Req PC_PW_rq;

IFetch ifetch
(
    .clk(clk),
    .rst(rst),
    .IN_en(ifetchEn),

    .IN_interruptPending(CSR_trapControl.interruptPending),
    .IN_MEM_busy(MEM_busy),

    .IF_ict(IF_ict),
    .IF_icache(IF_icache),

    .IN_ROB_curFetchID(ROB_curFetchID),
    .IN_branch(branch),
    .IN_decBranch(decBranch),

    .IN_clearICache(TH_clearICache),
    .IN_flushTLB(TH_flushTLB),
    .IN_btUpdates(BP_btUpdates[NUM_BRANCH_PORTS-1:0]),
    .IN_bpUpdate(ROB_bpUpdate),

    .IN_pcRead(PC_readReq),
    .OUT_pcReadData(PC_readData),
    .IN_pcReadTH(PC_readReqTH),
    .OUT_pcReadDataTH(PC_readDataTH),

    .IN_ready(!PD_full),
    .OUT_instrs(IF_instrs),

    .IN_vmem(CSR_vmem),
    .OUT_pw(PW_reqs[0]),
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

    .IN_en(!RN_stall && frontendEn),
    .IN_invalidate(branch.taken || decBranch.taken),
    .OUT_full(PD_full),

    .IN_instrs(IF_instrs),
    .OUT_instrs(PD_instrs)
);

D_UOp DE_uop[`DEC_WIDTH-1:0] /*verilator public*/;
DecodeBranch decBranch;
InstrDecoder idec
(
    .clk(clk),
    .rst(rst),
    .en(!RN_stall && frontendEn),
    .IN_branch(branch),

    .IN_dec(CSR_dec),
    .IN_instrs(PD_instrs),

    .IN_enCustom(1'b1),

    .OUT_uop(DE_uop),
    .OUT_decBranch(decBranch)
);

wire sqNStall = ($signed((RN_nextSqN) - ROB_maxSqN) > -(`DEC_WIDTH));
wire frontendEn /*verilator public*/ =
    !sqNStall &&
    !branch.taken &&
    !SQ_flush;

R_UOp RN_uop[`DEC_WIDTH-1:0] /*verilator public*/;
IntUOpOrder_t RN_uopOrdering[`DEC_WIDTH-1:0];
SqN RN_nextLoadSqN;
SqN RN_nextStoreSqN;
wire RN_stall /*verilator public*/;
Rename#(.WIDTH_WR(NUM_PORTS)) rn
(
    .clk(clk),
    .frontEn(frontendEn),
    .rst(rst),

    .IN_stalls(IQ_stalls),
    .OUT_stall(RN_stall),

    .IN_uop(DE_uop),

    .IN_comUOp(comUOps),

    .IN_wbHasResult(wbHasResult),
    .IN_wbUOp(wbUOp[NUM_PORTS-1:0]),

    .IN_branch(branch),
    .IN_mispredFlush(mispredFlush),

    .OUT_uop(RN_uop),
    .OUT_uopOrdering(RN_uopOrdering),
    .OUT_nextSqN(RN_nextSqN),
    .OUT_nextLoadSqN(RN_nextLoadSqN),
    .OUT_nextStoreSqN(RN_nextStoreSqN)
);

IS_UOp IS_uop[NUM_PORTS-1:0] /*verilator public*/;
wire stall[NUM_PORTS-1:0] /*verilator public*/;

wire[NUM_PORTS_TOTAL-1:0][`DEC_WIDTH-1:0] IQ_stalls;
wire DIV_doNotIssue[NUM_PORTS-1:0];
wire FDIV_doNotIssue[NUM_PORTS-1:0];

generate for (genvar i = 0; i < NUM_PORTS; i=i+1)
    IssueQueue#(
        .SIZE(PORT_IQ_SIZE[i]),
        .NUM_ENQUEUE(2),
        .PORT_IDX(i),
        .NUM_OPERANDS((i<NUM_ALUS) ? 2 : 1),
        .NUM_UOPS(`DEC_WIDTH),
        .RESULT_BUS_COUNT(NUM_PORTS),
        .IMM_BITS((i<NUM_ALUS) ? 36 : 12),
        .FUS(PORT_FUS[i])
    ) iq (
        .clk(clk),
        .rst(rst),

        .IN_defer((i<NUM_ALUS) ? '0 : IQ_stalls[i+NUM_AGUS]),
        .OUT_stall(IQ_stalls[i]),

        .IN_stall(stall[i]),
        .IN_doNotIssueDiv((i < NUM_ALUS) ? DIV_doNotIssue[i] : 1'b0),
        .IN_doNotIssueFDiv((i < NUM_ALUS) ? FDIV_doNotIssue[i] : 1'b0),

        .IN_uop(RN_uop),
        .IN_uopOrdering(RN_uopOrdering),

        .IN_resultValid(wbHasResult),
        .IN_resultUOp(wbUOp[NUM_PORTS-1:0]),

        .IN_branch(branch),

        .IN_issueUOps(IS_uop),

        .IN_maxStoreSqN(SQ_maxStoreSqN),
        .IN_maxLoadSqN(LB_maxLoadSqN),
        .IN_commitSqN(ROB_curSqN),

        .OUT_uop(IS_uop[i])
    );
endgenerate

StDataLookupUOp stLookupUOp[NUM_AGUS-1:0];
wire stLookupUOp_ready[NUM_AGUS-1:0];
ComLimit stCommitLimit[NUM_AGUS-1:0];

generate for (genvar i = 0; i < NUM_AGUS; i=i+1) begin
    StoreDataIQ #(8, 2, i, `DEC_WIDTH, NUM_PORTS) iqStD
    (
        .clk(clk),
        .rst(rst),

        .OUT_stall(IQ_stalls[NUM_PORTS+i]),
        .IN_uop(RN_uop),

        .IN_resultValid(wbHasResult),
        .IN_resultUOp(wbUOp[NUM_PORTS-1:0]),

        .IN_branch(branch),

        .IN_issueUOps(IS_uop),

        .IN_aguUOps(LD_uop[NUM_ALUS+:NUM_AGUS]),
        .IN_maxStoreSqN(SQ_maxStoreSqN),

        .OUT_comLimit(stCommitLimit[i]),

        .IN_ready(stLookupUOp_ready[i]),
        .OUT_uop(stLookupUOp[i])
    );
end endgenerate

RF_ReadReq[NUM_RF_READS-1:0] RF_reads;

logic[NUM_RF_READS-1:0] RF_readEnable;
RFTag[NUM_RF_READS-1:0] RF_readAddress;
RegT[NUM_RF_READS-1:0] RF_readData;
for (genvar i = 0; i < NUM_RF_READS; i=i+1) begin
    assign RF_readEnable[i] = RF_reads[i].valid;
    assign RF_readAddress[i] = RF_reads[i].tag;
end
logic[NUM_RF_WRITES-1:0] RF_writeEnable;
RFTag[NUM_RF_WRITES-1:0] RF_writeAddress;
RegT[NUM_RF_WRITES-1:0] RF_writeData;
always_comb begin
    for (integer i = 0; i < NUM_RF_WRITES; i=i+1) begin
        RF_writeAddress[i] = RFTag'(wbUOp[i].tagDst);
        RF_writeData[i] = wbUOp[i].result;
        RF_writeEnable[i] = wbHasResult[i];
    end
end
RegFile#(32, 1 << $bits(RFTag), NUM_RF_READS, NUM_RF_WRITES, 1) rf
(
    .clk(clk),

    .IN_re(RF_readEnable),
    .IN_raddr(RF_readAddress),
    .OUT_rdata(RF_readData),

    .IN_we(RF_writeEnable),
    .IN_waddr(RF_writeAddress),
    .IN_wdata(RF_writeData)
);

EX_UOp LD_uop[NUM_PORTS-1:0] /*verilator public*/;

ZCForward LD_zcFwd[NUM_ALUS-1:0];

Load#(
    .NUM_UOPS(NUM_PORTS),
    .NUM_WBS(NUM_PORTS),
    .NUM_ZC_FWDS(NUM_ALUS),
    .NUM_PC_READS(NUM_BRANCH_PORTS)
) ld
(
    .clk(clk),
    .rst(rst),

    .IN_uop(IS_uop),

    .IN_wbHasResult(wbHasResult),
    .IN_wbUOp(wbUOp[NUM_PORTS-1:0]),

    .IN_branch(branch),
    .IN_stall(stall),

    .IN_zcFwd(LD_zcFwd),

    .OUT_pcRead(PC_readReq),
    .IN_pcReadData(PC_readData),

    .OUT_rfReadReq(RF_reads[0 +: 2*NUM_ALUS + NUM_AGUS]),
    .IN_rfReadData(RF_readData[0 +: 2*NUM_ALUS + NUM_AGUS]),

    .OUT_uop(LD_uop)
);

AMO_Data_UOp SDL_amoData[NUM_ALUS-1:0];
logic SDL_readEnable[NUM_AGUS-1:0];
RFTag SDL_readTag[NUM_AGUS-1:0];
StDataUOp SDL_stDataUOp[NUM_AGUS-1:0];
StoreDataLoad#(NUM_AGUS) stDataLd
(
    .clk(clk),
    .rst(rst),

    .IN_branch(branch),

    .IN_uop(stLookupUOp),
    .OUT_ready(stLookupUOp_ready),

    .IN_atomicUOp(SDL_amoData[NUM_AGUS-1:0]),

    .OUT_readReq(RF_reads[NUM_RF_READS-1 -: NUM_AGUS]),
    .IN_readData(RF_readData[NUM_RF_READS-1 -: NUM_AGUS]),

    .OUT_uop(SDL_stDataUOp)
);

TrapControlState CSR_trapControl /*verilator public*/;
wire[2:0] CSR_fRoundMode;
DecodeState CSR_dec;
VirtMemState CSR_vmem;

generate for (genvar i = 0; i < NUM_ALUS; i=i+1) begin : intPortsGen
    // verilator lint_off UNDRIVEN
    RES_UOp[(1<<$bits(FuncUnit))-1:0] resUOps;
    // verilator lint_on UNDRIVEN

    assign stall[i] = 1'b0;

    if ((PORT_FUS[i] & (FU_INT_OH|FU_BRANCH_OH|FU_BITMANIP_OH|FU_ATOMIC_OH)) != 0) begin
        BranchProv ialuBranch;
        IntALU#(PORT_FUS[i] & (FU_INT_OH|FU_BRANCH_OH|FU_BITMANIP_OH|FU_ATOMIC_OH)) ialu
        (
            .clk(clk),
            .rst(rst),

            .IN_uop(LD_uop[i]),
            .IN_branch(branch),

            .OUT_branch(ialuBranch),
            .OUT_btUpdate(BP_btUpdates[i]),

            .OUT_zcFwd(LD_zcFwd[i]),

            .OUT_amoData(SDL_amoData[i]),
            .OUT_uop(resUOps[FU_INT])
        );
        if (i < NUM_BRANCH_PORTS)
            assign branchProvs[i] = ialuBranch;
    end

    if ((PORT_FUS[i] & FU_DIV_OH) != 0) begin
        wire DIV_busy;
        Divide div
        (
            .clk(clk),
            .rst(rst),
            .en(LD_uop[i].fu == FU_DIV),

            .OUT_busy(DIV_busy),

            .IN_branch(branch),
            .IN_uop(LD_uop[i]),
            .OUT_uop(resUOps[FU_DIV])
        );
        assign DIV_doNotIssue[i] = DIV_busy ||
            (LD_uop[i].valid && LD_uop[i].fu == FU_DIV) ||
            (IS_uop[i].valid && IS_uop[i].fu == FU_DIV);
    end
    else assign DIV_doNotIssue[i] = 1'b1;


    if ((PORT_FUS[i] & FU_FPU_OH) != 0)
        FPU fpu
        (
            .clk(clk),
            .rst(rst),
            .en(LD_uop[i].fu == FU_FPU),

            .IN_branch(branch),
            .IN_uop(LD_uop[i]),

            .IN_fRoundMode(CSR_fRoundMode),
            .OUT_uop(resUOps[FU_FPU])
        );

    if ((PORT_FUS[i] & FU_MUL_OH) != 0)
        Multiply mul
        (
            .clk(clk),
            .rst(rst),
            .en(LD_uop[i].fu == FU_MUL),

            .OUT_busy(),

            .IN_branch(branch),
            .IN_uop(LD_uop[i]),
            .OUT_uop(resUOps[FU_MUL])
        );

    if ((PORT_FUS[i] & FU_FMUL_OH) != 0)
        FMul fmul
        (
            .clk(clk),
            .rst(rst),
            .en(LD_uop[i].fu == FU_FMUL),

            .IN_branch(branch),
            .IN_uop(LD_uop[i]),

            .IN_fRoundMode(CSR_fRoundMode),
            .OUT_uop(resUOps[FU_FMUL])
        );

    if ((PORT_FUS[i] & FU_FDIV_OH) != 0) begin
        wire FDIV_busy;
        FDiv fdiv
        (
            .clk(clk),
            .rst(rst),
            .en(LD_uop[i].fu == FU_FDIV),

            .IN_wbAvail(1'b1),
            .OUT_busy(FDIV_busy),

            .IN_branch(branch),
            .IN_uop(LD_uop[i]),
            .IN_fRoundMode(CSR_fRoundMode),
            .OUT_uop(resUOps[FU_FDIV])
        );
        assign FDIV_doNotIssue[i] = FDIV_busy ||
            (LD_uop[i].valid && LD_uop[i].fu == FU_FDIV) ||
            (IS_uop[i].valid && IS_uop[i].fu == FU_FDIV);
    end
    else assign FDIV_doNotIssue[i] = 1;

    if ((PORT_FUS[i] & FU_CSR_OH) != 0) begin
        CSR csr
        (
            .clk(clk),
            .rst(rst),
            .en(LD_uop[i].fu == FU_CSR),

            .IN_irq(IN_irq),

            .IN_uop(LD_uop[i]),
            .IN_branch(branch),
            .IN_fpNewFlags(ROB_fpNewFlags),

            .IN_perfcInfo(ROB_perfcInfo),
            .IN_branchMispr(BS_PERFC_branchMispr),

            .IF_mmio(IF_csr_mmio),

            .IN_tvalState(TVS_tvalState),

            .IN_trapInfo(TH_trapInfo),
            .OUT_trapControl(CSR_trapControl),
            .OUT_fRoundMode(CSR_fRoundMode),

            .OUT_dec(CSR_dec),
            .OUT_vmem(CSR_vmem),

            .OUT_uop(resUOps[FU_CSR])
        );
    end

    always_comb begin
        wbUOp[i] = RES_UOp'{valid: 0, default: 'x};
        for (integer j = 0; j < (1 << $bits(FuncUnit)); j=j+1) begin
            if ((PORT_FUS[i] & (1 << j)) != 0 && resUOps[j].valid)
                wbUOp[i] = resUOps[j];
        end
    end
end endgenerate

TValProv TVS_tvalProvs[NUM_AGUS-1:0];
TValState TVS_tvalState;
TValSelect#(NUM_AGUS) tvalSelect
(
    .clk(clk),
    .rst(rst),
    .IN_branch(branch),
    .IN_commitSqN(ROB_curSqN),
    .IN_tvalProvs(TVS_tvalProvs),
    .OUT_tvalState(TVS_tvalState)
);

PageWalk_Req PW_reqs[(NUM_AGUS+1)-1:0];
PageWalk_Res PW_res;
wire CC_PW_LD_stall[NUM_AGUS-1:0];
PW_LD_UOp PW_LD_uop[NUM_AGUS-1:0];
assign PW_LD_uop[1] = PW_LD_UOp'{valid: 0, default: 'x};
PageWalker#(NUM_AGUS+1) pageWalker
(
    .clk(clk),
    .rst(rst),

    .IN_rqs(PW_reqs),
    .OUT_res(PW_res),

    .IN_ldStall(CC_PW_LD_stall[0]),
    .OUT_ldUOp(PW_LD_uop[0]),
    .IN_ldAck(LSU_ldAck),
    .IN_ldResUOp(wbUOp[NUM_ALUS+:NUM_AGUS])
);

wire LS_AGULD_uopStall[NUM_AGUS-1:0];
LD_UOp LS_uopLd[NUM_AGUS-1:0];
LoadSelector loadSelector
(
    .IN_aguLd(LB_uopLd),
    .OUT_aguLdStall(LS_AGULD_uopStall),

    .IN_pwLd(PW_LD_uop),
    .OUT_pwLdStall(CC_PW_LD_stall),

    .IN_ldUOpStall(CC_loadStall),
    .OUT_ldUOp(LS_uopLd)
);

TLB_Req TLB_rqs[NUM_AGUS-1:0];
TLB_Res TLB_res[NUM_AGUS-1:0];
TLB#(NUM_AGUS, `DTLB_SIZE, `DTLB_ASSOC) dtlb
(
    .clk(clk),
    .rst(rst),
    .clear(TH_flushTLB),
    .IN_pw(PW_res),
    .IN_rqs(TLB_rqs),
    .OUT_res(TLB_res)
);

AGU_UOp AGU_uop[NUM_AGUS-1:0];
ELD_UOp AGU_eLdUOp[NUM_AGUS-1:0];
generate for (genvar i = 0; i < NUM_AGUS; i=i+1) begin : aguPortsGen
    AGU#(.RQ_ID(1+i)) agu
    (
        .clk(clk),
        .rst(rst),
        .IN_stall(LSU_AGUStall[i]),
        .OUT_stall(stall[NUM_ALUS+i]),

        .OUT_TMQ_free(),

        .IN_branch(branch),
        .IN_vmem(CSR_vmem),
        .OUT_pw(PW_reqs[i+1]),
        .IN_pw(PW_res),

        .OUT_tvalProv(TVS_tvalProvs[i]),

        .OUT_tlb(TLB_rqs[i]),
        .IN_tlb(TLB_res[i]),

        .IN_uop(LD_uop[NUM_ALUS+i]),
        .OUT_aguOp(AGU_uop[i]),
        .OUT_eldOp(AGU_eLdUOp[i]),
        .OUT_uop(wbUOp[NUM_ALUS+NUM_AGUS+i])
    );
end endgenerate

SqN LB_maxLoadSqN;
LD_UOp LB_uopLd[NUM_AGUS-1:0];
LD_UOp LB_aguUOpLd[NUM_AGUS-1:0];

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
    .OUT_branch(branchProvs[LQ_BRANCH_PORT]),

    .OUT_maxLoadSqN(LB_maxLoadSqN),

    .OUT_comLimit(LB_ldComLimit)
);

wire SQ_empty;
wire SQ_done;

StFwdResult SQ_fwd[NUM_AGUS-1:0];
StFwdResult SQB_fwd[NUM_AGUS-1:0];

SqN SQ_maxStoreSqN;
wire SQ_flush;
SQ_UOp SQ_uops[NUM_AGUS-1:0];
wire SQ_stall[NUM_AGUS-1:0];
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

wire CC_loadStall[NUM_AGUS-1:0];
wire CC_storeStall;
wire LSU_AGUStall[NUM_AGUS-1:0];
LD_UOp CC_SQ_uopLd[NUM_AGUS-1:0];
LD_Ack LSU_ldAck[NUM_AGUS-1:0];
wire LSU_busy;

MemController_Req LSU_MC_if;
MemController_Req BLSU_MC_if;
ST_Ack LSU_stAck;
LoadStoreUnit lsu
(
    .clk(clk),
    .rst(rst),

    .IN_flush(TH_startFence),
    .IN_storeBusy(STORE_busy),
    .OUT_busy(LSU_busy),

    .IN_branch(branch),
    .OUT_ldAGUStall(LSU_AGUStall),
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

    .IN_ready({NUM_AGUS{1'b1}}),
    .OUT_uopLd(wbUOp[NUM_ALUS+:NUM_AGUS])
);

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

wire STORE_busy = !SQ_empty || SQB_busy;
wire MEM_busy = STORE_busy || LSU_busy;

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
    .OUT_pcRead(PC_readReqTH),
    .IN_pcReadData(PC_readDataTH),
    .IN_trapControl(CSR_trapControl),
    .OUT_trapInfo(TH_trapInfo),
    .OUT_branch(branchProvs[TH_BRANCH_PORT]),

    .IN_MEM_busy(MEM_busy),

    .OUT_flushTLB(TH_flushTLB),
    .OUT_fence(TH_startFence),
    .OUT_clearICache(TH_clearICache),
    .OUT_disableIFetch(TH_disableIFetch),
    .OUT_dbgStallPC(TH_stallPC)
);

endmodule
