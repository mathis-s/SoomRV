

module ICacheTable#(parameter ASSOC=`CASSOC, parameter NUM_ICACHE_LINES=(1<<(`CACHE_SIZE_E-`CLSIZE_E)), parameter RQ_ID=0, parameter FIFO_SIZE=4)
(
    input logic clk,
    input logic rst,

    input wire IN_MEM_busy,

    input logic IN_mispr,
    input FetchID_t IN_misprFetchID,

    input FetchID_t IN_ROB_curFetchID,
    input FetchLimit IN_BP_fetchLimit,
    
    // first cycle
    input IFetchOp IN_ifetchOp,
    output logic OUT_stall,
    
    // second cycle
    input PredBranch IN_predBranch,
    input RetStackIdx_t IN_rIdx,
    input FetchOff_t IN_lastValid,
    
    // bp file write (data to write is in BP,
    // we only provide the address)
    output logic OUT_bpFileWE,
    output FetchID_t OUT_bpFileAddr,

    // pc file write
    output logic OUT_pcFileWE,
    output FetchID_t OUT_pcFileAddr,
    output PCFileEntry OUT_pcFileEntry,

    // branch mispredict handling
    output DecodeBranchProv OUT_decBranch,
    output BTUpdate OUT_btUpdate,
    output ReturnDecUpdate OUT_retUpdate,

    input wire[30:0] IN_lateRetAddr,

    IF_ICache.HOST IF_icache,
    IF_ICTable.HOST IF_ict,

    input logic IN_ready,
    output IF_Instr OUT_instrs,
    
    input wire IN_clearICache,
    input wire IN_flushTLB,
    input VirtMemState IN_vmem,
    output PageWalk_Req OUT_pw,
    input PageWalk_Res IN_pw,

    output MemController_Req OUT_memc,
    input MemController_Res IN_memc
);

logic BH_endOffsetValid;
FetchOff_t BH_endOffset;

logic BH_newPredTaken;
FetchOff_t BH_newPredPos;
DecodeBranchProv BH_decBranch;
BranchHandler branchHandler
(
    .clk(clk),
    .rst(rst),

    .IN_lateRetAddr({IN_lateRetAddr, 1'b0}),

    .IN_clear(IN_mispr),
    .IN_accept(packet.valid),
    .IN_op(fetch1),
    .IN_instrs(IF_icache.rdata[assocHit]),

    .OUT_decBranch(BH_decBranch),
    .OUT_btUpdate(OUT_btUpdate),
    .OUT_retUpdate(OUT_retUpdate),
    .OUT_endOffsValid(BH_endOffsetValid),
    .OUT_endOffs(BH_endOffset),

    .OUT_newPredTaken(BH_newPredTaken),
    .OUT_newPredPos(BH_newPredPos)
);

always_ff@(posedge clk) begin
    OUT_pcFileWE <= 0;
    OUT_pcFileEntry <= 'x;
    if (rst) ;
    else if (fetch1.valid) begin
        OUT_pcFileWE <= 1;
        OUT_pcFileAddr <= fetch1.fetchID;
        OUT_pcFileEntry.pc <= fetch1.pc[31:1];
        OUT_pcFileEntry.branchPos <= packetRePred.predPos;
        OUT_pcFileEntry.bpi.predicted <= fetch1.bpi.predicted; // todo: set if late pred?
        OUT_pcFileEntry.bpi.taken <= packetRePred.predTaken;
    end
end

always_comb begin
    OUT_bpFileWE = fetch0.valid;
    OUT_bpFileAddr = fetchID;
end

wire FetchID_t fetchLimit = (IN_BP_fetchLimit.valid ? IN_BP_fetchLimit.fetchID : IN_ROB_curFetchID);
always_comb begin
    OUT_stall = 0;
    if (IN_pw.busy && IN_pw.rqID == RQ_ID)
        OUT_stall = 1;

    if ($signed(FIFO_free - $clog2(FIFO_SIZE)'(fetch0.valid) - $clog2(FIFO_SIZE)'(fetch1.valid) - 1) <= -1)
        OUT_stall = 1;

    if (fetchLimit == (fetchID + FetchID_t'(fetch0.valid)))
        OUT_stall = 1;

    if (flushState != FLUSH_IDLE)
        OUT_stall = 1;

    if (IF_icache.busy)
        OUT_stall = 1;

    // Could possibly check if cache line at PC is currently
    // being loaded. This will be caught later anyways, but
    // it would save us a flush if we stall here.
end

// Read ICache at current PC
always_comb begin
    
    IF_icache.re = 0;
    IF_icache.raddr = 'x;

    IF_ict.re = 0;
    IF_ict.raddr = 'x;

    if (IN_ifetchOp.valid && !OUT_stall) begin
        IF_icache.re = 1;
        IF_icache.raddr = IN_ifetchOp.pc[`VIRT_IDX_LEN-1:0];
        IF_ict.re = 1;
        IF_ict.raddr = IN_ifetchOp.pc[`VIRT_IDX_LEN-1:0];
    end
end

// Address Translation
TLB_Req TLB_req;
always_comb begin
    TLB_req.vpn = fetch0.pc[31:12];
    TLB_req.valid = fetch0.valid && !IN_mispr && !cacheMiss;
end
TLB_Res TLB_res_c;
TLB_Res TLB_res;
TLB#(1, `ITLB_SIZE, `ITLB_ASSOC, 1) itlb
(
    .clk(clk),
    .rst(rst),
    .clear(IN_clearICache || IN_flushTLB),
    .IN_pw(IN_pw),
    .IN_rqs('{TLB_req}),
    .OUT_res('{TLB_res_c})
);
always_ff@(posedge clk) TLB_res <= TLB_res_c;


logic[$clog2(`CASSOC)-1:0] assocCnt;
logic tlbMiss;
logic cacheHit;
logic cacheMiss;
logic doCacheLoad;
logic[$clog2(`CASSOC)-1:0] assocHit;
logic[31:0] phyPC;

// Check Tags
IF_Instr packet;
always_comb begin
    logic transferExists = 'x;
    logic allowPassThru = 'x;

    phyPC = 'x;

    packet = IF_Instr'{valid: 0, default: 'x};
    packet.fetchFault = fetch1.fetchFault;
    
    tlbMiss = 0;
    cacheHit = 0;
    cacheMiss = 0;
    assocHit = 'x;
    doCacheLoad = 1;

    if (fetch1.valid) begin

        // Check TLB
        if (IN_vmem.sv32en_ifetch && packet.fetchFault == IF_FAULT_NONE) begin
            if (TLB_res.hit) begin
                if ((TLB_res.pageFault) || 
                    (!TLB_res.rwx[0]) || 
                    (IN_vmem.priv == PRIV_USER && !TLB_res.user) ||
                    (IN_vmem.priv == PRIV_SUPERVISOR && TLB_res.user && !IN_vmem.supervUserMemory)
                ) begin
                    packet.fetchFault = IF_PAGE_FAULT;
                end
                else phyPC = {TLB_res.isSuper ? {TLB_res.ppn[19:10], fetch1.pc[21:12]} : TLB_res.ppn, fetch1.pc[11:0]};
            end
            else tlbMiss = 1;
        end
        else phyPC = fetch1.pc;
        
        // Check PMAs
        if (!tlbMiss && packet.fetchFault == IF_FAULT_NONE) begin
            if (!`IS_LEGAL_ADDR(phyPC) || `IS_MMIO_PMA(phyPC))
                packet.fetchFault = IF_ACCESS_FAULT;
        end

        // Check cache tags
        if (!tlbMiss && packet.fetchFault == IF_FAULT_NONE) begin
            for (integer i = 0; i < `CASSOC; i=i+1) begin
                if (IF_ict.rdata[i].valid && IF_ict.rdata[i].addr == phyPC[31:`VIRT_IDX_LEN]) begin
                    assert(!cacheHit);
                    cacheHit = 1;
                    doCacheLoad = 0;
                    assocHit = i[$clog2(`CASSOC)-1:0];
                    packet.instrs = IF_icache.rdata[i];
                end
            end
            begin
                {allowPassThru, transferExists} = CheckTransfers(OUT_memc, IN_memc, 1, phyPC, 0);
                if (transferExists) begin
                    doCacheLoad = 0;
                    cacheHit &= allowPassThru;
                end
            end

            cacheMiss = !cacheHit;
        end
        
        if (packet.fetchFault != IF_FAULT_NONE) begin
            packet.pc = fetch1.pc[31:`FSIZE_E];
            packet.firstValid = fetch1.pc[1+:$bits(FetchOff_t)];
            packet.lastValid = fetch1.pc[1+:$bits(FetchOff_t)];
            packet.predPos = {$bits(FetchOff_t){1'b1}};
            packet.predTaken = 0;
            packet.predTarget = 'x;
            packet.rIdx = fetch1.rIdx;
            packet.fetchID = fetch1.fetchID;
            packet.instrs = '0;
            packet.valid = 1;
        end
        else if (!tlbMiss && cacheHit) begin
            packet.pc = fetch1.pc[31:`FSIZE_E];
            packet.firstValid = fetch1.pc[1+:$bits(FetchOff_t)];
            packet.lastValid = fetch1.lastValid;
            packet.predPos = fetch1.predPos;
            packet.predTaken = fetch1.bpi.taken;
            packet.predTarget = fetch1.predTarget;
            packet.rIdx = fetch1.rIdx;
            packet.fetchID = fetch1.fetchID;
            packet.valid = 1;
        end
    end
end

// Apply post-BranchHandler corrected branch pred metadata
// to the fetch package.
IF_Instr packetRePred /*verilator public*/;
always_comb begin
    packetRePred = packet;
    
    if (packetRePred.fetchFault != IF_FAULT_NONE) ;
    else begin
        if (BH_endOffsetValid) begin
            if (BH_endOffset == 0) begin
                packetRePred = 'x;
                packetRePred.valid = 0;
            end
            else begin
                packetRePred.lastValid = BH_endOffset - 1;
            end

            if (packetRePred.firstValid > packetRePred.lastValid) begin
                packetRePred = 'x;
                packetRePred.valid = 0;
            end
        end

        if (BH_decBranch.taken) begin
            packetRePred.predTarget = BH_decBranch.dst;
            packetRePred.predPos = BH_newPredPos;
            packetRePred.predTaken = BH_newPredTaken;
        end
    end
end

// TLB Miss Handling
PageWalk_Req OUT_pw_c;
always_comb begin
    OUT_pw_c = PageWalk_Req'{valid: 0, default: 'x};
    
    if (rst) begin
    end
    else if (OUT_pw.valid && IN_pw.busy) begin
        OUT_pw_c = OUT_pw;
    end
    else if (tlbMiss) begin
        OUT_pw_c.addr = fetch1.pc;
        OUT_pw_c.rootPPN = IN_vmem.rootPPN;
        OUT_pw_c.valid = 1;
    end
end
always_ff@(posedge clk) OUT_pw <= OUT_pw_c;

// Cache Miss Handling
MemController_Req OUT_memc_c;
logic handlingMiss;
always_comb begin
    OUT_memc_c = 'x;
    OUT_memc_c.cmd = MEMC_NONE;
    handlingMiss = 0;
    
    if (rst) begin
    end
    else if (OUT_memc.cmd != MEMC_NONE && IN_memc.stall[0]) begin
        OUT_memc_c = OUT_memc;
    end
    else if (cacheMiss && doCacheLoad && !IN_mispr) begin
        OUT_memc_c.cmd = MEMC_CP_EXT_TO_CACHE;
        OUT_memc_c.cacheAddr = {assocCnt, phyPC[`VIRT_IDX_LEN-1:4], 2'b0};
        OUT_memc_c.readAddr = {phyPC[31:4], 4'b0}; // todo: adjust alignment based on AXI width
        OUT_memc_c.cacheID = 1;
        OUT_memc_c.data = 0;
        OUT_memc_c.mask = 0;
        handlingMiss = 1;
    end
end
always_comb begin
    IF_ict.wdata = 'x;
    IF_ict.wassoc = 'x;
    IF_ict.waddr = 'x;
    IF_ict.we = 0;
    
    if (flushState == FLUSH_ACTIVE) begin
        IF_ict.wdata.valid = 0;
        IF_ict.wdata.addr = '0;
        IF_ict.wassoc = flushAssocIter;
        IF_ict.waddr = {flushAddrIter, {`CLSIZE_E{1'b0}}};
        IF_ict.we = 1;
    end
    else if (handlingMiss) begin
        IF_ict.wdata.valid = 1;
        IF_ict.wdata.addr = phyPC[31:`VIRT_IDX_LEN];
        IF_ict.wassoc = assocCnt;
        IF_ict.waddr = phyPC[`VIRT_IDX_LEN-1:0];
        IF_ict.we = 1;
    end
end

always_ff@(posedge clk) OUT_memc <= rst ? MemController_Req'{cmd: MEMC_NONE, default: 'x} : OUT_memc_c;

always_comb begin
    OUT_decBranch = BH_decBranch;

    if (cacheMiss || tlbMiss) begin
        OUT_decBranch = DecodeBranchProv'{
            taken: 1,
            fetchID: fetch1.fetchID,
            fetchOffs: fetch1.pc[1+:$bits(FetchOff_t)],
            dst: fetch1.pc[31:1],
            tgtSpec: BR_TGT_MANUAL,
            default: '0
        };
    end
end

// Output Buffering
wire FIFO_outValid;
IF_Instr FIFO_out;
wire[$clog2(FIFO_SIZE):0] FIFO_free;
wire FIFO_ready;
FIFO#($bits(IF_Instr), FIFO_SIZE, 1, 1) outFIFO
(
    .clk(clk),
    .rst(rst || IN_mispr),
    .free(FIFO_free),

    .IN_valid(packetRePred.valid),
    .IN_data(packetRePred),
    .OUT_ready(FIFO_ready),

    .OUT_valid(FIFO_outValid),
    .IN_ready(IN_ready),
    .OUT_data(FIFO_out)
);
always_comb begin
    OUT_instrs = 'x;
    OUT_instrs.valid = 0;
    if (FIFO_outValid)
        OUT_instrs = FIFO_out;
end

always_ff@(posedge clk) begin
    if (!(rst || IN_mispr) && packetRePred.valid)
        assert(FIFO_ready);
end

FetchID_t fetchID /* verilator public */;

// pipeline
FetchID_t fetchID_c;
IFetchOp fetch0 /* verilator public */;
IFetchOp fetch1 /* verilator public */;

typedef enum logic[1:0]
{
    FLUSH_IDLE,
    FLUSH_QUEUED,
    FLUSH_ACTIVE,
    FLUSH_FINALIZE
} FlushState;
FlushState flushState;
logic[$clog2(`CASSOC)-1:0] flushAssocIter;
logic[`CACHE_SIZE_E-`CLSIZE_E-$clog2(`CASSOC)-1:0] flushAddrIter;

always_ff@(posedge clk) begin
    fetch0 <= IFetchOp'{valid: 0, default: 'x};
    fetch1 <= IFetchOp'{valid: 0, default: 'x};

    if (rst) begin
        fetchID <= 0;
        flushState <= FLUSH_QUEUED;
    end
    else if (IN_mispr) begin
        fetchID <= IN_misprFetchID + 1;
    end
    else if (BH_decBranch.taken) begin
        fetchID <= BH_decBranch.fetchID + 1;
    end
    else begin
        if (cacheMiss || tlbMiss) begin
            // miss, flush pipeline
            fetchID <= fetch1.fetchID;
        end
        else begin
            if (IN_ifetchOp.valid && !OUT_stall) begin
                fetch0 <= IN_ifetchOp;
            end
            if (fetch0.valid) begin
                fetch1 <= fetch0;
                fetch1.fetchID <= fetchID;
                fetch1.lastValid <= IN_lastValid;
                fetch1.predPos <= IN_predBranch.valid ? IN_predBranch.offs : {$bits(FetchOff_t){1'b1}};
                fetch1.predDirOnly <= IN_predBranch.dirOnly;
                fetch1.bpi.predicted <= IN_predBranch.valid;
                fetch1.bpi.taken <= IN_predBranch.taken;
                fetch1.predTarget <= IN_predBranch.dst;
                fetch1.rIdx <= IN_rIdx;

                fetchID <= fetchID + 1;
            end
        end

        if (handlingMiss)
            assocCnt <= assocCnt + 1;
    end

    if (!rst) begin
        case (flushState)
            default: begin
                flushState <= FLUSH_IDLE;
                if (IN_clearICache)
                    flushState <= FLUSH_QUEUED;
                flushAssocIter <= 0;
                flushAddrIter <= 0;
            end
            FLUSH_QUEUED: begin
                flushState <= FLUSH_ACTIVE;
                if (fetch0.valid || fetch1.valid)
                    flushState <= FLUSH_QUEUED;
                flushAssocIter <= 0;
                flushAddrIter <= 0;
            end
            FLUSH_ACTIVE: begin
                reg flushDone;
                reg[$bits(flushAssocIter)-1:0] nextFlushAssoc;
                reg[$bits(flushAddrIter)-1:0] nextFlushAddr;
                {flushDone, nextFlushAssoc, nextFlushAddr} = {flushAssocIter, flushAddrIter} + 1;
                
                flushAssocIter <= nextFlushAssoc;
                flushAddrIter <= nextFlushAddr;
                if (flushDone) flushState <= IN_MEM_busy ? FLUSH_FINALIZE : FLUSH_IDLE;
            end
            FLUSH_FINALIZE: begin
                if (!IN_MEM_busy) flushState <= FLUSH_IDLE;
            end
        endcase
    end
end

endmodule
