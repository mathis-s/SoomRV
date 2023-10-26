module IFetch
#(
    parameter NUM_UOPS=3,
    parameter NUM_BLOCKS=8,
    parameter NUM_BP_UPD=3,
    parameter NUM_BRANCH_PROVS=4
)
(
    input wire clk,
    input wire rst,
    input wire IN_en,

    input wire IN_interruptPending,
    input wire IN_MEM_busy,
    
    IF_ICTable.HOST IF_ict,
    IF_ICache.HOST IF_icache,
    
    input BranchProv IN_branches[NUM_BRANCH_PROVS-1:0],
    input wire IN_mispredFlush,
    input FetchID_t IN_ROB_curFetchID,
    input SqN IN_ROB_curSqN,
    input SqN IN_RN_nextSqN,
    
    output wire OUT_PERFC_branchMispr,
    output BranchProv OUT_branch,
    
    input ReturnDecUpdate IN_retDecUpd,
    input DecodeBranchProv IN_decBranch,
    
    input wire IN_clearICache,
    input wire IN_flushTLB,
    input BTUpdate IN_btUpdates[NUM_BP_UPD-1:0],
    input BPUpdate0 IN_bpUpdate0,
    input BPUpdate1 IN_bpUpdate1,
    
    input FetchID_t IN_pcReadAddr[4:0],
    output PCFileEntry OUT_pcReadData[4:0],
    
    input wire IN_ready,
    output IF_Instr OUT_instrs,
    output wire[30:0] OUT_lateRetAddr,
    
    input VirtMemState IN_vmem,
    output PageWalk_Req OUT_pw,
    input PageWalk_Res IN_pw,
    
    output MemController_Req OUT_memc,
    input MemController_Res IN_memc
);

reg[30:0] pc;
wire[31:0] pcFull = {pc, 1'b0};

BranchSelector#(.NUM_BRANCHES(NUM_BRANCH_PROVS)) bsel
(
    .clk(clk),
    .rst(rst),
    
    .IN_branches(IN_branches),
    .OUT_branch(OUT_branch),
    
    .OUT_PERFC_branchMispr(OUT_PERFC_branchMispr),
    
    .IN_ROB_curSqN(IN_ROB_curSqN),
    .IN_RN_nextSqN(IN_RN_nextSqN),
    .IN_mispredFlush(IN_mispredFlush)
);

FetchOff_t BP_lastOffs;
PredBranch predBr /*verilator public*/;
wire BP_stall;
wire[30:0] BP_curRetAddr;
RetStackIdx_t BP_rIdx;
BranchPredictor#(.NUM_IN(NUM_BP_UPD)) bp
(
    .clk(clk),
    .rst(rst),
    .en1(pcFileWriteEn),

    .OUT_stall(BP_stall),
    
    .IN_clearICache(IN_clearICache),
    
    .IN_mispredFlush(IN_mispredFlush),
    .IN_mispr(OUT_branch.taken || IN_decBranch.taken || icacheMiss),
    .IN_misprFetchID(OUT_branch.taken ? OUT_branch.fetchID : IN_decBranch.taken ? IN_decBranch.fetchID : icacheMissFetchID),
    .IN_misprRetAct(OUT_branch.taken ? OUT_branch.retAct : IN_decBranch.taken ? IN_decBranch.retAct : RET_NONE),
    .IN_misprHistAct(OUT_branch.taken ? OUT_branch.histAct : IN_decBranch.taken ? IN_decBranch.histAct : HIST_NONE),
    .IN_misprDst(OUT_branch.taken ? OUT_branch.dstPC[31:1] : IN_decBranch.taken ? IN_decBranch.dst : icacheMissPC[31:1]),
    
    .IN_pcValid(ifetchEn),
    .IN_fetchID(fetchID),
    .IN_comFetchID(IN_ROB_curFetchID),
    
    .OUT_pc(pc),
    .OUT_lastOffs(BP_lastOffs),

    .OUT_curRetAddr(BP_curRetAddr),
    .OUT_lateRetAddr(OUT_lateRetAddr),
    .OUT_rIdx(BP_rIdx),

    .OUT_predBr(predBr),

    .IN_retDecUpd(IN_retDecUpd),
    .IN_btUpdates(IN_btUpdates),
    .IN_bpUpdate0(IN_bpUpdate0),
    .IN_bpUpdate1(IN_bpUpdate1)
);

wire baseEn = IN_en && !waitForInterrupt && !issuedInterrupt && !BP_stall;

// When first encountering a fault, we output a single fake fault instruction.
// Thus ifetch is still enabled during this first fault cycle.
wire ifetchEn /* verilator public */ = 
    baseEn && !icacheStall;

wire icacheStall;
wire icacheMiss;
wire[31:0] icacheMissPC;
FetchID_t icacheMissFetchID;
ICacheTable ict
(
    .clk(clk),
    .rst(rst || IN_clearICache),
    .IN_MEM_busy(IN_MEM_busy),

    .IN_mispr(OUT_branch.taken || IN_decBranch.taken),
    .IN_misprFetchID(OUT_branch.taken ? OUT_branch.fetchID : IN_decBranch.fetchID),
    
    .IN_ROB_curFetchID(IN_ROB_curFetchID),

    .IN_ifetchOp(ifetchOp),
    .OUT_stall(icacheStall),

    .IN_predBranch(predBr),
    .IN_rIdx(BP_rIdx),
    .IN_lastValid(BP_lastOffs),

    .OUT_fetchID(fetchID),
    .OUT_pcFileWE(pcFileWriteEn),
    .OUT_pcFileEntry(PCF_writeData),

    .OUT_icacheMiss(icacheMiss),
    .OUT_icacheMissFetchID(icacheMissFetchID),
    .OUT_icacheMissPC(icacheMissPC),
    
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

FetchID_t fetchID /* verilator public */;
PCFileEntry PCF_writeData;
wire pcFileWriteEn;
PCFile#($bits(PCFileEntry)) pcFile
(
    .clk(clk),
    
    .wen0(pcFileWriteEn),
    .waddr0(fetchID),
    .wdata0(PCF_writeData),
    
    .raddr0(IN_pcReadAddr[0]), .rdata0(OUT_pcReadData[0]),
    .raddr1(IN_pcReadAddr[1]), .rdata1(OUT_pcReadData[1]),
    .raddr2(IN_pcReadAddr[2]), .rdata2(OUT_pcReadData[2]),
    .raddr3(IN_pcReadAddr[3]), .rdata3(OUT_pcReadData[3]),
    .raddr4(IN_pcReadAddr[4]), .rdata4(OUT_pcReadData[4])
);

IFetchOp ifetchOp;
always_comb begin
    ifetchOp = IFetchOp'{valid: 0, default: 'x};

    if (OUT_branch.taken || IN_decBranch.taken || icacheMiss) begin
    end
    else if (ifetchEn) begin
        ifetchOp.valid = 1;
        ifetchOp.pc = {pc, 1'b0};
        ifetchOp.fetchFault = IN_interruptPending ? IF_INTERRUPT : IF_FAULT_NONE;

        // set in next cycle
        //ifetchOp.rIdx = BP_rIdx;
        //ifetchOp.fetchID = 'x;
        //ifetchOp.lastValid = BP_lastOffs;
        //ifetchOp.predPos = BP_info.predicted ? (predBr.valid ? predBr.offs : 3'b111) : 3'b111;
        //ifetchOp.bpi = BP_info;
        //ifetchOp.predTarget = BP_info.taken ? predBr.dst : BP_curRetAddr;
    end
end

reg waitForInterrupt /* verilator public */;
reg issuedInterrupt;

always_ff@(posedge clk) begin
    
    if (rst) begin
        waitForInterrupt <= 0;
        issuedInterrupt <= 0;
    end
    else begin

        if (IN_interruptPending)
            waitForInterrupt <= 0;
    
        if (OUT_branch.taken || IN_decBranch.taken || icacheMiss) begin
            if (OUT_branch.taken) begin
                //pc <= OUT_branch.dstPC[31:1];
                waitForInterrupt <= 0;
            end
            else if (IN_decBranch.taken) begin
                //pc <= IN_decBranch.dst;
                // We also use WFI to temporarily disable the frontend
                // for ops that always flush the pipeline
                waitForInterrupt <= IN_decBranch.wfi;
            end
            else if (icacheMiss) begin
                //pc <= icacheMissPC[31:1];
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
