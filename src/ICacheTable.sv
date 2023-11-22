
module ICacheTable#(parameter ASSOC=`CASSOC, parameter NUM_ICACHE_LINES=(1<<(`CACHE_SIZE_E-`CLSIZE_E)), parameter RQ_ID=0, parameter FIFO_SIZE=4)
(
    input logic clk,
    input logic rst,

    input wire IN_MEM_busy,

    input logic IN_mispr,
    input FetchID_t IN_misprFetchID,

    input FetchID_t IN_ROB_curFetchID,
    
    // first cycle
    input IFetchOp IN_ifetchOp,
    output logic OUT_stall,
    
    // second cycle
    input PredBranch IN_predBranch,
    input RetStackIdx_t IN_rIdx,
    input FetchOff_t IN_lastValid,
    
    // pc file write
    output FetchID_t OUT_fetchID,
    output logic OUT_pcFileWE,
    output PCFileEntry OUT_pcFileEntry,
    
    // miss
    output logic OUT_icacheMiss,
    output FetchID_t OUT_icacheMissFetchID,
    output logic[31:0] OUT_icacheMissPC,

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

always_comb begin
    OUT_pcFileWE = 0;
    OUT_pcFileEntry = 'x;
    if (fetch0.valid) begin
        OUT_pcFileWE = 1;
        OUT_pcFileEntry.pc = fetch0.pc[31:1];
        OUT_pcFileEntry.branchPos = IN_predBranch.offs;
        OUT_pcFileEntry.bpi.predicted = IN_predBranch.valid;
        OUT_pcFileEntry.bpi.taken = IN_predBranch.taken;
        OUT_pcFileEntry.bpi.isJump = IN_predBranch.isJump;
    end
end

always_comb begin
    OUT_stall = 0;
    if (IN_pw.busy && IN_pw.rqID == RQ_ID)
        OUT_stall = 1;

    if ($signed(FIFO_free - $clog2(FIFO_SIZE)'(fetch0.valid) - $clog2(FIFO_SIZE)'(fetch1.valid) - 1) <= -1)
        OUT_stall = 1;

    if (IN_ROB_curFetchID == (OUT_fetchID + FetchID_t'(fetch0.valid)))
        OUT_stall = 1;

    if (flushState != FLUSH_IDLE)
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
        IF_icache.raddr = IN_ifetchOp.pc[11:0];
        IF_ict.re = 1;
        IF_ict.raddr = IN_ifetchOp.pc[11:0];
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
                if (IF_ict.rdata[i].valid && IF_ict.rdata[i].addr == phyPC[31:12]) begin
                    assert(!cacheHit);
                    cacheHit = 1;
                    doCacheLoad = 0;
                    assocHit = i[$clog2(`CASSOC)-1:0];
                    packet.instrs = IF_icache.rdata[i];
                end
            end
            begin
                {allowPassThru, transferExists} = CheckTransfers(OUT_memc, IN_memc, 1, phyPC);
                if (transferExists) begin
                    doCacheLoad = 0;
                    cacheHit &= allowPassThru;
                end
            end

            cacheMiss = !cacheHit;
        end
        
        if (packet.fetchFault != IF_FAULT_NONE) begin
            packet.pc = fetch1.pc[31:4];
            packet.firstValid = fetch1.pc[3:1];
            packet.lastValid = fetch1.pc[3:1];
            packet.predPos = 3'b111;
            packet.predTaken = 0;
            packet.predTarget = 'x;
            packet.rIdx = fetch1.rIdx;
            packet.fetchID = fetch1.fetchID;
            packet.instrs = '0;
            packet.valid = 1;
        end
        else if (!tlbMiss && cacheHit) begin
            packet.pc = fetch1.pc[31:4];
            packet.firstValid = fetch1.pc[3:1];
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
        OUT_memc_c.cacheAddr = {assocCnt, phyPC[11:4], 2'b0};
        OUT_memc_c.readAddr = {phyPC[31:4], 4'b0};
        OUT_memc_c.cacheID = 1;
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
        IF_ict.wdata.addr = phyPC[31:12];
        IF_ict.wassoc = assocCnt;
        IF_ict.waddr = phyPC[11:0];
        IF_ict.we = 1;
    end
end

always_ff@(posedge clk) OUT_memc <= rst ? MemController_Req'{cmd: MEMC_NONE, default: 'x} : OUT_memc_c;

always_comb begin
    OUT_icacheMissFetchID = 'x;
    OUT_icacheMissPC = 'x;
    OUT_icacheMiss = cacheMiss || tlbMiss;
    if (OUT_icacheMiss) begin
        OUT_icacheMissPC = fetch1.pc;
        OUT_icacheMissFetchID = fetch1.fetchID;
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

    .IN_valid(packet.valid),
    .IN_data(packet),
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
    if (!(rst || IN_mispr) && packet.valid)
        assert(FIFO_ready);
end

FetchID_t fetchID /* verilator public */;
assign OUT_fetchID = fetchID;

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
                fetch1.predPos <= IN_predBranch.valid ? IN_predBranch.offs : 3'b111;
                fetch1.bpi.predicted <= IN_predBranch.valid;
                fetch1.bpi.taken <= IN_predBranch.taken;
                fetch1.bpi.isJump <= IN_predBranch.isJump;
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
