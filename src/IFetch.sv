module IFetch
#(
    parameter NUM_UOPS=3,
    parameter NUM_BLOCKS=8,
    parameter NUM_BP_UPD=2
)
(
    input wire clk,
    input wire rst,
    input wire IN_en,

    input wire IN_interruptPending,
    input wire IN_MEM_busy,

    IF_ICTable.HOST IF_ict,
    IF_ICache.HOST IF_icache,

    input FetchID_t IN_ROB_curFetchID,
    input BranchProv IN_branch,

    input DecodeBranch IN_decBranch,

    input wire IN_clearICache,
    input wire IN_flushTLB,
    input BTUpdate IN_btUpdates[NUM_BP_UPD-1:0],
    input BPUpdate IN_bpUpdate,

    input PCFileReadReq IN_pcRead[NUM_BRANCH_PORTS-1:0],
    output PCFileEntry OUT_pcReadData[NUM_BRANCH_PORTS-1:0],
    input PCFileReadReqTH IN_pcReadTH,
    output PCFileEntry OUT_pcReadDataTH,

    input wire IN_ready,
    output PD_Instr OUT_instrs[`DEC_WIDTH-1:0],

    input VirtMemState IN_vmem,
    output PageWalk_Req OUT_pw,
    input PageWalk_Res IN_pw,

    output MemController_Req OUT_memc,
    input MemController_Res IN_memc
);

wire[30:0] pc;
wire[31:0] pcFull = {pc, 1'b0};

wire BPF_we;
FetchOff_t BP_lastOffs;
PredBranch predBr /*verilator public*/;
wire BP_stall;
wire[30:0] BP_curRetAddr;
RetStackIdx_t BP_rIdx;

PCFileReadReq BP_pcFileRead;
PCFileEntry BP_pcFileRData;

FetchBranchProv BP_mispr;
always_comb begin
    BP_mispr = BH_fetchBranch;
    if (IN_branch.taken) begin
        BP_mispr = FetchBranchProv'{
            taken: IN_branch.taken,
            fetchID: IN_branch.fetchID,
            dst: IN_branch.dstPC[31:1],
            histAct: IN_branch.histAct,
            retAct: IN_branch.retAct,
            fetchOffs: IN_branch.fetchOffs,
            tgtSpec: IN_branch.tgtSpec,
            default: '0
        };
    end
    else if (IN_decBranch.taken) begin
        BP_mispr = FetchBranchProv'{
            taken: IN_decBranch.taken,
            fetchID: IN_decBranch.fetchID,
            dst: 'x,
            histAct: HIST_NONE,
            retAct: RET_NONE,
            fetchOffs: IN_decBranch.fetchOffs,
            tgtSpec: BR_TGT_NEXT,
            default: '0
        };
    end
end

wire[30:0] BP_lateRetAddr;
FetchLimit BP_fetchLimit;
BranchPredictor#(.NUM_IN(NUM_BP_UPD+1)) bp
(
    .clk(clk),
    .rst(rst),
    .en1(BPF_we),

    .OUT_stall(BP_stall),
    .IN_mispr(BP_mispr),

    .IN_pcValid(ifetchEn),
    .OUT_fetchLimit(BP_fetchLimit),
    .IN_fetchID(BPF_writeAddr),
    .IN_comFetchID(IN_ROB_curFetchID),

    .OUT_pc(pc),
    .OUT_lastOffs(BP_lastOffs),

    .OUT_curRetAddr(BP_curRetAddr),
    .OUT_lateRetAddr(BP_lateRetAddr),
    .OUT_rIdx(BP_rIdx),

    .OUT_predBr(predBr),

    .IN_retDecUpd(BH_retDecUpd),

    .OUT_pcFileRead(BP_pcFileRead),
    .IN_pcFileRData(BP_pcFileRData),

    .IN_btUpdates('{BH_btUpdate, IN_btUpdates[1], IN_btUpdates[0]}),
    .IN_bpUpdate(IN_bpUpdate)
);

wire baseEn = IN_en && !waitForInterrupt && !issuedInterrupt && !BP_stall;

// When first encountering a fault, we output a single fake fault instruction.
// Thus ifetch is still enabled during this first fault cycle.
wire ifetchEn /* verilator public */ =
    baseEn && !icacheStall;

wire icacheStall;

FetchBranchProv BH_fetchBranch;
BTUpdate BH_btUpdate;
ReturnDecUpdate BH_retDecUpd;

IFetchPipeline ifp
(
    .clk(clk),
    .rst(rst),
    .IN_MEM_busy(IN_MEM_busy),

    .IN_mispr(IN_branch.taken || IN_decBranch.taken),
    .IN_misprFetchID(IN_branch.taken ? IN_branch.fetchID : IN_decBranch.fetchID),

    .IN_ROB_curFetchID(IN_ROB_curFetchID),
    .IN_BP_fetchLimit(BP_fetchLimit),

    .IN_ifetchOp(ifetchOp),
    .OUT_stall(icacheStall),

    .IN_predBranch(predBr),
    .IN_rIdx(BP_rIdx),
    .IN_lastValid(BP_lastOffs),

    .OUT_bpFileWE(BPF_we),
    .OUT_bpFileAddr(BPF_writeAddr),

    .OUT_pcFileWE(pcFileWriteEn),
    .OUT_pcFileAddr(PCF_writeAddr),
    .OUT_pcFileEntry(PCF_writeData),

    .OUT_fetchBranch(BH_fetchBranch),
    .OUT_btUpdate(BH_btUpdate),
    .OUT_retUpdate(BH_retDecUpd),

    .IN_lateRetAddr(BP_lateRetAddr),

    .IF_icache(IF_icache),
    .IF_ict(IF_ict),

    .IN_ready(IN_ready),
    .OUT_instrs(OUT_instrs),

    .IN_clearICache(IN_clearICache),
    .IN_flushTLB(IN_flushTLB),
    .IN_vmem(IN_vmem),
    .OUT_pw(OUT_pw),
    .IN_pw(IN_pw),

    .OUT_memc(OUT_memc),
    .IN_memc(IN_memc)
);

FetchID_t BPF_writeAddr /* verilator public */;

FetchID_t PCF_writeAddr /* verilator public */;
PCFileEntry PCF_writeData;
wire pcFileWriteEn;


wire PCFileReadReq sharedReq =
    (IN_pcReadTH.valid && (IN_pcReadTH.prio || !IN_pcRead[0].valid)) ? PCFileReadReq'(IN_pcReadTH) : IN_pcRead[0];
PCFileEntry sharedData;
assign OUT_pcReadData[0] = sharedData;
assign OUT_pcReadDataTH = sharedData;
RegFile#($bits(PCFileEntry), 1<<$bits(FetchID_t), NUM_BRANCH_PORTS+1, 1) pcFile
(
    .clk(clk),

    .IN_we({pcFileWriteEn}),
    .IN_waddr({PCF_writeAddr}),
    .IN_wdata({PCF_writeData}),

    .IN_re({BP_pcFileRead.valid, IN_pcRead[1].valid, sharedReq.valid}),
    .IN_raddr({BP_pcFileRead.addr, IN_pcRead[1].addr, sharedReq.addr}),
    .OUT_rdata({BP_pcFileRData, OUT_pcReadData[1], sharedData})
);

IFetchOp ifetchOp;
always_comb begin
    ifetchOp = IFetchOp'{valid: 0, default: 'x};

    if (IN_branch.taken || BH_fetchBranch.taken) begin
    end
    else if (ifetchEn) begin
        ifetchOp.valid = 1;
        ifetchOp.pc = {pc, 1'b0};
        ifetchOp.fetchFault = IN_interruptPending ? IF_INTERRUPT : IF_FAULT_NONE;
    end
end

reg waitForInterrupt /* verilator public */;
reg[$clog2(`RESET_DELAY)-1:0] wfiCount;
reg issuedInterrupt;
reg resetWait;

always_ff@(posedge clk ) begin

    if (rst) begin
        issuedInterrupt <= 0;
        waitForInterrupt <= 1;
        wfiCount <= $bits(wfiCount)'(`RESET_DELAY - 1);
        resetWait <= 1;
    end
    else begin

        if (waitForInterrupt) begin
            reg[$bits(wfiCount)-1:0] wfiCount_next;
            reg wfiDone;
            {wfiDone, wfiCount_next} = wfiCount - 1;
            wfiCount <= wfiCount_next;

            if ((IN_interruptPending && !resetWait) || wfiDone)
                waitForInterrupt <= 0;
        end

        if (IN_branch.taken || BH_fetchBranch.taken || IN_decBranch.taken) begin
            if (IN_branch.taken) begin
                waitForInterrupt <= 0;
            end
            else begin
                // We also use WFI to temporarily disable the frontend for ops that always flush the pipeline
                if ((BH_fetchBranch.taken && BH_fetchBranch.wfi) || (IN_decBranch.taken && IN_decBranch.wfi)) begin
                    waitForInterrupt <= 1;
                    wfiCount <= $bits(wfiCount)'(`WFI_DELAY - 1);
                end
            end
            issuedInterrupt <= 0;
        end
        else if (ifetchEn) begin
            // Interrupts
            if (IN_interruptPending) begin
                issuedInterrupt <= 1;
            end
            // Valid Fetch
            else begin

            end
        end
    end
end

endmodule
