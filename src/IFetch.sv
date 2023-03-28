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
    input wire en,
    
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
    
    input DecodeBranchProv IN_decBranch,
    
    input wire IN_clearICache,
    input BTUpdate IN_btUpdates[NUM_BP_UPD-1:0],
    input BPUpdate IN_bpUpdate,
    
    input FetchID_t IN_pcReadAddr[4:0],
    output PCFileEntry OUT_pcReadData[4:0],
    
    output IF_Instr OUT_instrs,
    
    input STAT_VMem IN_vmem,
    
    output CTRL_MemC OUT_memc2,
    output CTRL_MemC OUT_memc,
    input STAT_MemC IN_memc,
    
    output wire OUT_stall
);

integer i;

assign OUT_instrReadEnable = !en;

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
wire BP_isJump;
FetchOff_t BP_branchSrcOffs;
wire[31:0] BP_branchDst;
BHist_t BP_branchHistory;
BranchPredInfo BP_info;
wire BP_multipleBranches;
wire BP_branchFound;
wire BP_branchCompr;
BranchPredictor#(.NUM_IN(NUM_BP_UPD)) bp
(
    .clk(clk),
    .rst(rst),
    
    .IN_clearICache(IN_clearICache),
    
    .IN_mispredFlush(IN_mispredFlush),
    .IN_mispr(OUT_branch.taken || IN_decBranch.taken),
    .IN_misprHist(OUT_branch.taken ? OUT_branch.history : IN_decBranch.history),
    
    .IN_pcValid(en),
    .IN_pc({pc, 1'b0}),
    .OUT_branchTaken(BP_branchTaken),
    .OUT_isJump(BP_isJump),
    .OUT_branchSrcOffs(BP_branchSrcOffs),
    .OUT_branchDst(BP_branchDst),
    .OUT_branchHistory(BP_branchHistory),
    .OUT_branchInfo(BP_info),
    .OUT_multipleBranches(BP_multipleBranches),
    .OUT_branchFound(BP_branchFound),
    .OUT_branchCompr(BP_branchCompr),
    
    .IN_btUpdates(IN_btUpdates),
    .IN_bpUpdate(IN_bpUpdate)
);

wire pageWalkRequired = IN_vmem.sv32en_ifetch && 
    ((pcPPNsuperpage ? (pcVPN[19:10] != lastVPN[19:10]) : (pcVPN != lastVPN)) || !lastVPN_valid);

wire[30:0] physicalPC = IN_vmem.sv32en_ifetch ? {pcPPN[19:10], (pcPPNsuperpage ? pc[20:11] : pcPPN[9:0]), pc[10:0]} : pc;

wire icacheStall;
ICacheTable ict
(
    .clk(clk),
    .rst(rst || IN_clearICache),
    .IN_lookupValid(en && !pageWalkRequired && fault == IF_FAULT_NONE && !(IN_vmem.sv32en_ifetch && pcPPNfault != IF_FAULT_NONE)),
    .IN_lookupPC(physicalPC),
    
    .OUT_lookupAddress(OUT_instrAddr),
    .OUT_stall(icacheStall),
    
    .OUT_memc(OUT_memc),
    .IN_memc(IN_memc)
);

assign OUT_stall = (IN_ROB_curFetchID == fetchID) || (icacheStall && fault == IF_FAULT_NONE);


reg[127:0] instrRawBackup;
reg useInstrRawBackup;
always_ff@(posedge clk) begin
    if (rst)
        useInstrRawBackup <= 0;
    else if (!en) begin
        instrRawBackup <= instrRaw;
        useInstrRawBackup <= 1;
    end
    else useInstrRawBackup <= 0;
end
wire[127:0] instrRaw = useInstrRawBackup ? instrRawBackup : IN_instrRaw;


IF_Instr outInstrs_r;
always_comb begin
    OUT_instrs = outInstrs_r;
    for (i = 0; i < NUM_BLOCKS; i=i+1)
        OUT_instrs.instrs[i] = instrRaw[(16*i)+:16];
end

// these are virtual addresses when address translation is active
reg[30:0] pc;
reg[30:0] pcLast;
wire[31:0] pcFull = {pc, 1'b0};

// virtual page number
// If this has changed, we do a page walk to find the new PPN
wire[19:0] pcVPN = pc[30:11];
reg lastVPN_valid;
reg[19:0] lastVPN;

// physical page number
// used for instruction lookup
reg[19:0] pcPPN;
reg pcPPNsuperpage;
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
    
    .wen0(en && en1),
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
    
    OUT_memc2.cmd <= MEMC_NONE;
    if (rst) begin
        pc <= 0;
        fetchID <= 0;
        en1 <= 0;
        outInstrs_r <= 'x;
        outInstrs_r.valid <= 0;
        lastVPN_valid <= 0;
        pageWalkActive <= 0;
        fault <= IF_FAULT_NONE;
        pcPPNfault <= IF_FAULT_NONE;
    end
    else begin
    
        if (!pageWalkAccepted && pageWalkActive) begin
            if (IN_memc.busy && IN_memc.rqID == 4)
                pageWalkAccepted <= 1;
            else begin
                OUT_memc2.cmd <= MEMC_PAGE_WALK;
                OUT_memc2.rootPPN <= IN_vmem.rootPPN;
                OUT_memc2.extAddr[29:10] <= pageWalkVPN;
                OUT_memc2.cacheID <= 'x;
                OUT_memc2.sramAddr <= 'x;
                OUT_memc2.rqID <= 4;
            end
        end
        else if (IN_memc.resultValid && pageWalkActive) begin
            pageWalkActive <= 0;
            pageWalkAccepted <= 'x;
            lastVPN <= pageWalkVPN;
            
            pcPPN <= IN_memc.result[29:10];
            pcPPNsuperpage <= IN_memc.isSuperPage;
            lastVPN_valid <= 1;
            
            pcPPNfault <= IF_FAULT_NONE;
            
            case (IN_memc.result[3:1])
                    /*inv*/ 3'b000,
                    /*ro*/  3'b001,
                    /*rfu*/ 3'b010,
                    /*rw*/  3'b011,
                    /*rfu*/ 3'b110: pcPPNfault <= IF_PAGE_FAULT;
                    
                    /*xo*/  3'b100,
                    /*rx*/  3'b101,
                    /*rwx*/ 3'b111: begin end
            endcase
            
            if ((IN_memc.isSuperPage && IN_memc.result[19:10] != 0) ||
                (!IN_memc.result[0]) ||
                (IN_vmem.priv == PRIV_USER && !IN_memc.result[4]) ||
                (IN_vmem.priv == PRIV_SUPERVISOR && IN_memc.result[4]) ||
                (!IN_memc.result[6])) 
                
                pcPPNfault <= IF_PAGE_FAULT;
        end
        
        if (IN_clearICache) begin
            lastVPN_valid <= 0;
            pageWalkAccepted <= 0;
            pageWalkActive <= 0;
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
        else if (en) begin
            
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
            
                fetchID <= fetchID + 1;
            end
            else begin
                outInstrs_r <= 'x;
                outInstrs_r.valid <= 0;
            end
            
            // Fetch package (if no fault)
            if (fault == IF_FAULT_NONE) begin
                if (`IS_MMIO_PMA(pcFull)) begin
                    fault <= IF_ACCESS_FAULT;
                end else
                if (pageWalkRequired) begin
                    if (!pageWalkActive && !IN_memc.busy) begin
                        pageWalkActive <= 1;
                        pageWalkAccepted <= 0;
                        pageWalkVPN <= pcVPN;
                    end
                end
                else begin
                    en1 <= 1;
                    histLast <= BP_branchHistory;
                    infoLast <= BP_info;
                    pcLast <= pc;
                    branchPosLast <= BP_branchSrcOffs;
                    multipleLast <= BP_multipleBranches;
                    
                    if (IN_vmem.sv32en_ifetch && pcPPNfault != IF_FAULT_NONE) begin
                        fault <= pcPPNfault;
                    end
                    else if (BP_branchFound) begin
                        if (BP_isJump || BP_branchTaken) begin
                            pc <= BP_branchDst[31:1];
                            
                            //if (BP_branchSrc[31:4] != pc[30:3]) begin
                                //$display("BTB PC Misspeculation: spec=%x, actual=%x\n", BP_branchSrc, pc << 1);
                            //    dbgMisspec <= 1;
                            //end
                        end
                        // Branch found, not taken
                        else begin                    
                            // There is a second branch in this block,
                            // go there.
                            if (BP_multipleBranches && BP_branchSrcOffs != 3'b111) begin
                                pc <=  {pc[30:3], BP_branchSrcOffs + 3'b1};
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
        end
    end
end

endmodule
