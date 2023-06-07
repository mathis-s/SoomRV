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
    
    output wire OUT_instrReadEnable,
    output wire[27:0] OUT_instrAddr,
    input wire[127:0] IN_instrRaw,
    
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
    input BTUpdate IN_btUpdates[NUM_BP_UPD-1:0],
    input BPUpdate IN_bpUpdate,
    
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
BHist_t BP_branchHistory;
BranchPredInfo BP_info;
wire BP_multipleBranches;

PredBranch predBr;
BranchPredictor#(.NUM_IN(NUM_BP_UPD)) bp
(
    .clk(clk),
    .rst(rst),
    
    .IN_clearICache(IN_clearICache),
    
    .IN_mispredFlush(IN_mispredFlush),
    .IN_mispr(OUT_branch.taken || IN_decBranch.taken),
    .IN_misprHist(OUT_branch.taken ? OUT_branch.history : IN_decBranch.history),
    .IN_misprRIdx(OUT_branch.taken ? OUT_branch.rIdx : IN_decBranch.rIdx),
    
    .IN_pcValid(ifetchEn && fault == IF_FAULT_NONE && !pageWalkRequired),
    .IN_pc({pc, 1'b0}),
    .OUT_branchTaken(BP_branchTaken),
    .OUT_branchHistory(BP_branchHistory),
    .OUT_branchInfo(BP_info),
    .OUT_multipleBranches(BP_multipleBranches),
    .OUT_lateRetAddr(OUT_lateRetAddr),
    
    .OUT_predBr(predBr),

    .IN_retDecUpd(IN_retDecUpd),
    .IN_btUpdates(IN_btUpdates),
    .IN_bpUpdate(IN_bpUpdate)
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

wire baseEn = IN_en && 
    (IN_ROB_curFetchID != fetchID);

wire tryReadICache = 
    baseEn &&
    fault == IF_FAULT_NONE &&
    !fetchIsFault &&
    !pageWalkRequired;

// When first encountering a fault, we output a single fake fault instruction.
// Thus ifetch is still enabled during this first fault cycle.
wire ifetchEn = 
    baseEn &&
    (!icacheStall || fetchIsFault);

assign OUT_instrReadEnable = !(tryReadICache && !icacheStall);

wire icacheStall;
ICacheTable ict
(
    .clk(clk),
    .rst(rst || IN_clearICache),
    .IN_lookupValid(tryReadICache),
    .IN_lookupPC(phyPCFull),
    
    .OUT_lookupAddress(OUT_instrAddr),
    .OUT_stall(icacheStall),
    
    .OUT_memc(OUT_memc),
    .IN_memc(IN_memc)
);

reg[127:0] instrRawBackup;
reg useInstrRawBackup;
always_ff@(posedge clk) begin
    if (rst)
        useInstrRawBackup <= 0;
    else if (!ifetchEn) begin
        instrRawBackup <= instrRaw;
        useInstrRawBackup <= 1;
    end
    else useInstrRawBackup <= 0;
end
wire[127:0] instrRaw = useInstrRawBackup ? instrRawBackup : IN_instrRaw;


IF_Instr outInstrs_r;
always_comb begin
    OUT_instrs = outInstrs_r;
    for (integer i = 0; i < NUM_BLOCKS; i=i+1)
        OUT_instrs.instrs[i] = (outInstrs_r.fetchFault != IF_FAULT_NONE) ? 16'b0 : instrRaw[(16*i)+:16];
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

FetchID_t fetchID;
FetchID_t fetchIDlast;
BHist_t histLast;
BranchPredInfo infoLast;
reg[2:0] branchPosLast;
reg multipleLast;

PCFileEntry PCF_writeData;
assign PCF_writeData.pc = pcLast;
assign PCF_writeData.hist = histLast;
assign PCF_writeData.bpi = infoLast;
assign PCF_writeData.branchPos = branchPosLast;
PCFile#($bits(PCFileEntry)) pcFile
(
    .clk(clk),
    
    .wen0(ifetchEn && en1),
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
reg[19:0] pageWalkVPN;

reg en1;
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
    end
    else begin
        
        if (IN_clearICache) begin
            lastVPN_valid <= 0;
            pageWalkAccepted <= 0;
            pageWalkActive <= 0;
        end

        if (IN_en) begin
            outInstrs_r <= 'x;
            outInstrs_r.valid <= 0;
        end

        // Page Walk request was accepted
        if (!pageWalkAccepted && pageWalkActive) begin
            if (IN_pw.busy && IN_pw.rqID == 0)
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
        // Start Page Walk
        else if (pageWalkRequired && IN_en && !(OUT_branch.taken || IN_decBranch.taken) && fault == IF_FAULT_NONE) begin
            en1 <= 0;
            if (!pageWalkActive && !IN_pw.busy) begin
                pageWalkActive <= 1;
                pageWalkAccepted <= 0;
                pageWalkVPN <= pcVPN;
            end
        end
    
        if (OUT_branch.taken || IN_decBranch.taken) begin
            if (OUT_branch.taken) begin
                pc <= OUT_branch.dstPC[31:1];
                fetchID <= OUT_branch.fetchID + 1;
            end
            else if (IN_decBranch.taken) begin
                pc <= IN_decBranch.dst;
                fetchID <= IN_decBranch.fetchID + 1;
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
                outInstrs_r.predTarget <= infoLast.taken ? pc : 'x;
                outInstrs_r.history <= histLast;
                outInstrs_r.rIdx <= infoLast.rIdx;
            
                fetchID <= fetchID + 1;
            end

            // Fetch package (if no fault)
            if (fault == IF_FAULT_NONE && !pageWalkRequired) begin
                // Handle Page Fault, Access Fault and Interrupts
                if (fetchIsFault) begin

                    en1 <= 1;
                    pcLast <= pc;
                    // this might be polluted with predictions from squashed insts
                    histLast <= BP_branchHistory;
                    infoLast <= 0;
                    multipleLast <= 1;
                    branchPosLast <= pc[2:0];

                    fault <= fault_c;
                end
                // Valid Fetch
                else begin
                    en1 <= 1;
                    histLast <= BP_branchHistory;
                    infoLast <= BP_info;
                    pcLast <= pc;
                    branchPosLast <= predBr.offs;
                    multipleLast <= BP_multipleBranches;
                    
                    if (predBr.valid) begin
                        if (predBr.isJump || BP_branchTaken) begin
                            pc <= predBr.dst;
                        end
                        // Branch found, not taken
                        else begin                    
                            // There is a second branch in this block,
                            // go there.
                            if (BP_multipleBranches && predBr.offs != 3'b111) begin
                                pc <=  {pc[30:3], predBr.offs + 3'b1};
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
