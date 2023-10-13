
module ICacheTable#(parameter ASSOC=`CASSOC, parameter NUM_ICACHE_LINES=(1<<(`CACHE_SIZE_E-`CLSIZE_E)))
(
    input logic clk,
    input logic rst,

    input logic IN_mispr,
    input FetchID_t IN_misprFetchID,
    
    input IFetchOp IN_ifetchOp,
    output logic OUT_stall,

    output FetchID_t OUT_fetchID,
    output logic OUT_pcFileWE,
    output PCFileEntry OUT_pcFileEntry,

    output logic OUT_icacheMiss,
    output logic[31:0] OUT_icacheMissPC,

    IF_ICache.HOST IF_icache,
    IF_ICTable.HOST IF_ict,

    input logic IN_ready,
    output IF_Instr OUT_instrs, 

    output MemController_Req OUT_memc,
    input MemController_Res IN_memc
);

always_comb begin
    OUT_pcFileWE = 0;
    OUT_pcFileEntry = 'x;
    if (fetch0.valid) begin
        OUT_pcFileWE = 1;
        OUT_pcFileEntry.pc = fetch0.pc[31:1];
        OUT_pcFileEntry.branchPos = fetch0.predPos;
        OUT_pcFileEntry.bpi = fetch0.bpi;
    end
end

// Read ICache at current PC
always_comb begin
    OUT_stall = 0;
    
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

reg[$clog2(`CASSOC)-1:0] assocCnt;
reg cacheHit;
reg doCacheLoad;
reg[$clog2(`CASSOC)-1:0] assocHit;

wire FIFO_outValid;
IF_Instr FIFO_out;
// todo: just one entry is required
FIFO#($bits(IF_Instr), 2, 1, 1) outFIFO
(
    .clk(clk),
    .rst(rst || IN_mispr),
    .free(),

    .IN_valid(packet.valid),
    .IN_data(packet),
    .OUT_ready(),

    .OUT_valid(FIFO_outValid),
    .IN_ready(FIFO_outValid && IN_ready),
    .OUT_data(FIFO_out)
);
always_comb begin
    OUT_instrs = 'x;
    OUT_instrs.valid = 0;
    if (FIFO_outValid)
        OUT_instrs = FIFO_out;
end

// Check Tags
IF_Instr packet;
always_comb begin
    logic transferExists = 'x;
    logic allowPassThru = 'x;

    packet = IF_Instr'{valid: 0, default: 'x};

    cacheHit = 0;
    assocHit = 'x;
    doCacheLoad = 1;

    if (fetch1.valid) begin
        // TODO: vmem

        // Check cache tags
        for (integer i = 0; i < `CASSOC; i=i+1) begin
            if (IF_ict.rdata[i].valid && IF_ict.rdata[i].addr == fetch1.pc[31:12]) begin
                assert(!cacheHit);
                cacheHit = 1;
                doCacheLoad = 0;
                assocHit = i[$clog2(`CASSOC)-1:0];
                packet.instrs = IF_icache.rdata[i];
            end
        end
        begin
            {allowPassThru, transferExists} = CheckTransfers(OUT_memc, IN_memc, 1, fetch1.pc);
            if (transferExists) begin
                doCacheLoad = 0;
                cacheHit &= allowPassThru;
            end
        end

        if (cacheHit) begin
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
    else if (fetch1.valid && !cacheHit && doCacheLoad && !IN_mispr) begin
        OUT_memc_c.cmd = MEMC_CP_EXT_TO_CACHE;
        OUT_memc_c.cacheAddr = {assocCnt, fetch1.pc[11:4], 2'b0};
        OUT_memc_c.readAddr = {fetch1.pc[31:4], 4'b0};
        OUT_memc_c.cacheID = 1;
        handlingMiss = 1;
    end
end
always_comb begin
    IF_ict.wdata = 'x;
    IF_ict.wassoc = 'x;
    IF_ict.waddr = 'x;
    IF_ict.we = 0;

    if (handlingMiss) begin
        IF_ict.wdata.valid = 1;
        IF_ict.wdata.addr = fetch1.pc[31:12];
        IF_ict.wassoc = assocCnt;
        IF_ict.waddr = fetch1.pc[11:0];
        IF_ict.we = 1;
    end
end

always_ff@(posedge clk) OUT_memc <= OUT_memc_c;

always_comb begin
    OUT_icacheMissPC = 'x;
    OUT_icacheMiss = fetch1.valid && !cacheHit;
    if (OUT_icacheMiss) begin
        OUT_icacheMissPC = fetch1.pc;
    end
end

FetchID_t fetchID;
assign OUT_fetchID = fetchID;

IFetchOp fetch0;
IFetchOp fetch1;
always_ff@(posedge clk) begin
    fetch0 <= IFetchOp'{valid: 0, default: 'x};
    fetch1 <= IFetchOp'{valid: 0, default: 'x};

    if (rst) begin
        fetchID <= 0;
    end
    else if (IN_mispr) begin
        fetchID <= IN_misprFetchID + 1;
    end
    else begin
        if (fetch1.valid && !cacheHit) begin
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
                fetchID <= fetchID + 1;
            end
        end

        if (handlingMiss)
            assocCnt <= assocCnt + 1;
    end
end

endmodule
