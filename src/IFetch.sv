module IFetch
#(
    parameter NUM_UOPS=3,
    parameter NUM_BLOCKS=8,
    parameter NUM_BP_UPD=3,
    parameter NUM_BRANCH_PROVS=4,
    parameter RQ_ID=0
)
(
    input wire clk,
    input wire rst,
    input wire IN_en,

    input wire IN_interruptPending,
    
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
    
    output IF_Instr OUT_instrs,
    output wire[30:0] OUT_lateRetAddr,
    
    input VirtMemState IN_vmem,
    output PageWalk_Req OUT_pw,
    input PageWalk_Res IN_pw,
    
    output MemController_Req OUT_memc,
    input MemController_Res IN_memc
);

// these are virtual addresses when address translation is active
reg[30:0] pc;
reg[30:0] pcLast;
wire[31:0] pcFull = {pc, 1'b0};

wire[31:0] phyPCFull = {physicalPC, 1'b0};

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

wire BP_branchTaken;
BranchPredInfo BP_info;
wire BP_multipleBranches;
PredBranch predBr;
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
    .IN_mispr(OUT_branch.taken || IN_decBranch.taken),
    .IN_misprFetchID(OUT_branch.taken ? OUT_branch.fetchID : IN_decBranch.fetchID),
    .IN_misprRetAct(OUT_branch.taken ? OUT_branch.retAct : IN_decBranch.retAct),
    .IN_misprHistAct(OUT_branch.taken ? OUT_branch.histAct : IN_decBranch.histAct),
    
    .IN_pcValid(ifetchEn && fault == IF_FAULT_NONE && !pageWalkRequired),
    .IN_pc({pc, 1'b0}),
    .IN_fetchID(fetchID),
    .IN_comFetchID(IN_ROB_curFetchID),
    .OUT_branchTaken(BP_branchTaken),
    .OUT_branchInfo(BP_info),
    .OUT_rIdx(BP_rIdx),
    .OUT_multipleBranches(BP_multipleBranches),
    .OUT_curRetAddr(BP_curRetAddr),
    .OUT_lateRetAddr(OUT_lateRetAddr),
    
    .OUT_predBr(predBr),

    .IN_retDecUpd(IN_retDecUpd),
    .IN_btUpdates(IN_btUpdates),
    .IN_bpUpdate0(IN_bpUpdate0),
    .IN_bpUpdate1(IN_bpUpdate1)
);

TLB_Req TLB_req;
always_comb begin
    TLB_req.vpn = pcVPN;
    TLB_req.valid = baseEn && !fetchIsFault;
end
TLB_Res TLB_res;
TLB#(1, 8, 4, 1) itlb
(
    .clk(clk),
    .rst(rst),
    .clear(IN_clearICache || IN_flushTLB),
    .IN_pw(IN_pw),
    .IN_rqs('{TLB_req}),
    .OUT_res('{TLB_res})
);
wire pageWalkRequired = IN_vmem.sv32en_ifetch && 
    ((pcPPNsuperpage ? (pcVPN[19:10] != lastVPN[19:10]) : (pcVPN != lastVPN)) || !lastVPN_valid);

wire[30:0] physicalPC = IN_vmem.sv32en_ifetch ? {pcPPN[19:10], (pcPPNsuperpage ? pc[20:11] : pcPPN[9:0]), pc[10:0]} : pc;

IFetchFault fault_c;
reg fetchIsFault;
always_comb begin
    fault_c = IF_FAULT_NONE;

    if (IN_vmem.sv32en_ifetch && pcPPNfault == IF_PAGE_FAULT)
        fault_c = IF_PAGE_FAULT;

    else if (IN_vmem.sv32en_ifetch && (
        (IN_vmem.priv == PRIV_USER && !pcPPNuser) ||
        (IN_vmem.priv == PRIV_SUPERVISOR && pcPPNuser))
    ) begin
        fault_c = IF_PAGE_FAULT;
    end

    else if (IN_vmem.sv32en_ifetch && pcPPNfault == IF_ACCESS_FAULT)
        fault_c = IF_ACCESS_FAULT;

    else if (`IS_MMIO_PMA(phyPCFull))
        fault_c = IF_ACCESS_FAULT;

    else if (IN_interruptPending)
        fault_c = IF_INTERRUPT;
    
    fetchIsFault = fault_c != IF_FAULT_NONE;
end

wire baseEn = IN_en && !waitForInterrupt && !BP_stall &&
    (IN_ROB_curFetchID != fetchID);

wire tryReadICache = 
    baseEn &&
    fault == IF_FAULT_NONE &&
    !fetchIsFault &&
    !pageWalkRequired;

// When first encountering a fault, we output a single fake fault instruction.
// Thus ifetch is still enabled during this first fault cycle.
wire ifetchEn /* verilator public */ = 
    baseEn &&
    (!icacheStall || fetchIsFault);

wire icacheStall;
wire icacheMiss;
wire[127:0] instrRaw;
ICacheTable ict
(
    .clk(clk),
    .rst(rst || IN_clearICache),
    .IN_mispr(OUT_branch.taken || IN_decBranch.taken),

    .IN_lookupValid(tryReadICache),
    .IN_lookupPC(phyPCFull),
    .OUT_stall(icacheStall),
    .OUT_icacheMiss(icacheMiss),
    
    .IF_icache(IF_icache),
    .IF_ict(IF_ict),
    
    .IN_dataReady(IN_en && outInstrs_r.valid),
    .OUT_instrData(instrRaw),
    
    .OUT_memc(OUT_memc),
    .IN_memc(IN_memc)
);


IF_Instr outInstrs_r;
always_comb begin
    OUT_instrs = 'x;
    OUT_instrs.valid = 0;
    if (!icacheMiss) begin
        OUT_instrs = outInstrs_r;
        for (integer i = 0; i < NUM_BLOCKS; i=i+1)
            OUT_instrs.instrs[i] = (outInstrs_r.fetchFault != IF_FAULT_NONE) ? 16'b0 : instrRaw[(16*i)+:16];
    end
end

// virtual page number
// If this has changed, we do a page walk to find the new PPN
wire[19:0] pcVPN = pc[30:11];
reg lastVPN_valid;
reg[19:0] lastVPN;

// physical page number
// used for instruction lookup
reg[19:0] pcPPN;
reg pcPPNsuperpage;
reg pcPPNuser;
IFetchFault pcPPNfault;

IFetchFault fault;

FetchID_t fetchID /* verilator public */;
BranchPredInfo infoLast;
reg[2:0] branchPosLast;
reg[30:0] returnAddrPredLast;
reg multipleLast;
RetStackIdx_t rIdxLast;

PCFileEntry PCF_writeData;
assign PCF_writeData.pc = pcLast;
assign PCF_writeData.bpi = infoLast;
assign PCF_writeData.branchPos = branchPosLast;
wire pcFileWriteEn = ifetchEn && en1;
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

reg pageWalkActive;
reg pageWalkAccepted;
reg waitForPWComplete;
reg[19:0] pageWalkVPN;

reg waitForInterrupt /* verilator public */;

reg en1 /* verilator public */;
always_ff@(posedge clk) begin
    OUT_pw.valid <= 0;
    if (rst) begin
        pc <= 31'(`ENTRY_POINT >> 1);
        fetchID <= 0;
        en1 <= 0;
        outInstrs_r <= 'x;
        outInstrs_r.valid <= 0;
        lastVPN_valid <= 0;
        pageWalkActive <= 0;
        pageWalkAccepted <= 0;
        fault <= IF_FAULT_NONE;
        pcPPNfault <= IF_FAULT_NONE;
        waitForPWComplete <= 0;
        waitForInterrupt <= 0;
    end
    else begin
        
        if (IN_en) begin
            outInstrs_r <= 'x;
            outInstrs_r.valid <= 0;
        end

        if (IN_interruptPending)
            waitForInterrupt <= 0;
        
        // TLB Flush
        if (IN_clearICache || IN_flushTLB) begin
            lastVPN_valid <= 0;
            waitForPWComplete <= pageWalkActive;
            pageWalkAccepted <= 0;
            pageWalkActive <= 0;
        end
        // Wait until stale page walk is completed
        else if (waitForPWComplete) begin
            if (!IN_pw.busy || IN_pw.rqID != RQ_ID)
                waitForPWComplete <= 0;
        end
        // Page Walk request was accepted
        else if (!pageWalkAccepted && pageWalkActive) begin
            if (IN_pw.busy && IN_pw.rqID == RQ_ID)
                pageWalkAccepted <= 1;
            else begin
                OUT_pw.valid <= 1;
                OUT_pw.rootPPN <= IN_vmem.rootPPN;
                OUT_pw.addr[31:12] <= pageWalkVPN;
                OUT_pw.addr[11:0] <= 'x;
            end
        end
        // Finalize Page Walk
        else if (IN_pw.valid && pageWalkActive) begin
            pageWalkActive <= 0;
            pageWalkAccepted <= 0;
            lastVPN <= pageWalkVPN;
            
            pcPPN <= IN_pw.ppn[19:0];
            pcPPNsuperpage <= IN_pw.isSuperPage;
            pcPPNuser <= IN_pw.user;
            lastVPN_valid <= 1;

            pcPPNfault <= IF_FAULT_NONE;
            if (IN_pw.pageFault || !IN_pw.rwx[0])
                pcPPNfault <= IF_PAGE_FAULT;
            else if (IN_pw.ppn[21:20] != 0)
                pcPPNfault <= IF_ACCESS_FAULT;
        end
        else if (pageWalkRequired && IN_en && !(OUT_branch.taken || IN_decBranch.taken) && fault == IF_FAULT_NONE) begin
            // Check if TLB hit
            if (TLB_res.hit) begin
                pcPPN <= TLB_res.isSuper ? {TLB_res.ppn[19:10], 10'b0} : TLB_res.ppn;
                pcPPNfault <= (TLB_res.pageFault || !TLB_res.rwx[0]) ? IF_PAGE_FAULT : (TLB_res.accessFault ? IF_ACCESS_FAULT : IF_FAULT_NONE);
                pcPPNsuperpage <= TLB_res.isSuper;
                pcPPNuser <= TLB_res.user;
                lastVPN <= pcVPN;
                lastVPN_valid <= 1;
            end
            // Otherwise, start page walk
            else if (!pageWalkActive && !IN_pw.busy) begin
                pageWalkActive <= 1;
                pageWalkAccepted <= 0;
                pageWalkVPN <= pcVPN;
            end
        end
    
        if (OUT_branch.taken || IN_decBranch.taken || icacheMiss) begin
            if (OUT_branch.taken) begin
                pc <= OUT_branch.dstPC[31:1];
                fetchID <= OUT_branch.fetchID + 1;
                waitForInterrupt <= 0;
            end
            else if (IN_decBranch.taken) begin
                pc <= IN_decBranch.dst;
                fetchID <= IN_decBranch.fetchID + 1;
                // We also use WFI to temporarily disable the frontend
                // for ops that always flush the pipeline
                waitForInterrupt <= IN_decBranch.wfi;
            end
            else if (icacheMiss) begin
                pc <= {outInstrs_r.pc, outInstrs_r.firstValid};
                fetchID <= outInstrs_r.fetchID; // no increment
            end
            fault <= IF_FAULT_NONE;
            en1 <= 0;
            outInstrs_r <= 'x;
            outInstrs_r.valid <= 0;
        end
        else if (ifetchEn) begin
            
            // Output fetched package (or fault) to pre-dec
            if (en1) begin
                outInstrs_r.valid <= 1;
                outInstrs_r.pc <= pcLast[30:3];
                outInstrs_r.fetchID <= fetchID;
                outInstrs_r.fetchFault <= fault;
                outInstrs_r.predTaken <= infoLast.taken;
                outInstrs_r.predPos <= infoLast.predicted ? branchPosLast : 3'b111;
                outInstrs_r.firstValid <= pcLast[2:0];
                outInstrs_r.lastValid <= (infoLast.taken || multipleLast) ? branchPosLast : (3'b111);
                // If no branch was predicted, we use the predTarget field to store
                // the current return address. In case a unpredicted return is found
                // in decode, this is a slightly better target prediction than lateRetAddr
                // at decode time, as lateRetAddr might change until then.
                outInstrs_r.predTarget <= infoLast.taken ? pc : returnAddrPredLast;
                outInstrs_r.rIdx <= rIdxLast;
            
                fetchID <= fetchID + 1;
            end

            // Fetch package (if no fault)
            if (fault == IF_FAULT_NONE && !pageWalkRequired) begin
                // Handle Page Fault, Access Fault and Interrupts
                if (fetchIsFault) begin

                    en1 <= 1;
                    pcLast <= pc;
                    infoLast <= '0;
                    rIdxLast <= BP_rIdx;
                    multipleLast <= 1;
                    branchPosLast <= pc[2:0];
                    fault <= fault_c;
                end
                // Valid Fetch
                else begin
                    en1 <= 1;
                    infoLast <= BP_info;
                    rIdxLast <= BP_rIdx;
                    pcLast <= pc;
                    branchPosLast <= predBr.valid ? predBr.offs : 3'b111;
                    multipleLast <= BP_multipleBranches;
                    returnAddrPredLast <= BP_curRetAddr;
                    
                    if (predBr.valid) begin
                        if (predBr.isJump || BP_branchTaken) begin
                            pc <= predBr.dst;
                        end
                        // Branch found, not taken
                        else begin                    
                            // There is a second branch in this block,
                            // go there.
                            if (BP_multipleBranches && predBr.offs != 3'b111) begin
                                pc <= {pc[30:3], predBr.offs + 3'b1};
                            end
                            else begin
                                pc <= {pc[30:3] + 28'b1, 3'b000};
                            end
                        end
                    end
                    else begin
                        pc <= {pc[30:3] + 28'b1, 3'b000};
                    end

                end
            end
            else en1 <= 0;
        end
    end
end

endmodule
