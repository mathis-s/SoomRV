
module ICacheTable#(parameter ASSOC=`CASSOC, parameter NUM_ICACHE_LINES=(1<<(`CACHE_SIZE_E-`CLSIZE_E)))
(
    input logic clk,
    input logic rst,
    input logic IN_mispr,

    input logic IN_lookupValid,
    input logic[31:0] IN_lookupPC,
    output logic OUT_stall,
    output logic OUT_icacheMiss,

    IF_ICache.HOST IF_icache,
    IF_ICTable.HOST IF_ict,

    input logic IN_dataReady,
    output logic[127:0] OUT_instrData,

    output MemController_Req OUT_memc,
    input MemController_Res IN_memc
);

typedef struct packed
{
    logic[31:0] pc;
    logic valid;
} IFetch;

// Read ICache at current PC
always_comb begin
    OUT_stall = 0;
    
    IF_icache.re = 0;
    IF_icache.raddr = 'x;

    IF_ict.re = 0;
    IF_ict.raddr = 'x;

    if (IN_lookupValid) begin
        IF_icache.re = 1;
        IF_icache.raddr = IN_lookupPC[11:0];
        IF_ict.re = 1;
        IF_ict.raddr = IN_lookupPC[11:0];
    end
end


reg[$clog2(`CASSOC)-1:0] assocCnt;
reg cacheHit;
reg doCacheLoad;
reg[$clog2(`CASSOC)-1:0] assocHit;

reg[127:0] instrData;

wire FIFO_outValid;
// todo: just one entry is required
FIFO#(128, 2, 1, 1) outFIFO
(
    .clk(clk),
    .rst(rst),
    .free(),

    .IN_valid(cacheHit),
    .IN_data(instrData),
    .OUT_ready(),

    .OUT_valid(FIFO_outValid),
    .IN_ready(FIFO_outValid && IN_dataReady),
    .OUT_data(OUT_instrData)
);

// Check Tags
always_comb begin
    // TODO: vmem
    cacheHit = 0;
    instrData = 'x;
    assocHit = 'x;
    doCacheLoad = 0;

    if (fetch1.valid) begin
        for (integer i = 0; i < `CASSOC; i=i+1) begin
            if (IF_ict.rdata[i].valid && IF_ict.rdata[i].addr == fetch1.pc[31:12]) begin
                assert(!cacheHit);
                cacheHit = 1;
                assocHit = i[$clog2(`CASSOC)-1:0];
                instrData = IF_icache.rdata[i];
            end
        end

        doCacheLoad = !cacheHit;
        for (integer i = 0; i < `AXI_NUM_TRANS; i=i+1) begin
            if (IN_memc.transfers[i].valid &&
                IN_memc.transfers[i].cacheID == 1 &&
                IN_memc.transfers[i].readAddr[31:`CLSIZE_E] == fetch1.pc[31:`CLSIZE_E]
            ) begin
                cacheHit = 0;
                doCacheLoad = 0;
            end
        end

        if (OUT_memc.cmd != MEMC_NONE && OUT_memc.readAddr[31:`CLSIZE_E] == fetch1.pc[31:`CLSIZE_E]) begin
            cacheHit = 0;
            doCacheLoad = 0;
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
    else if (fetch1.valid && !cacheHit && doCacheLoad) begin
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
// todo: don't forward on IN_mispr
always_ff@(posedge clk) OUT_memc <= OUT_memc_c;

assign OUT_icacheMiss = fetch1.valid && !cacheHit;

IFetch fetch0;
IFetch fetch1;
always_ff@(posedge clk) begin
    fetch0 <= IFetch'{valid: 0, default: 'x};
    fetch1 <= IFetch'{valid: 0, default: 'x};

    if (rst) begin
        
    end
    else if (IN_mispr) begin

    end
    else begin
        if (fetch1.valid && !cacheHit) begin
            // miss, flush pipeline
        end
        else begin
            if (IN_lookupValid) begin
                fetch0.valid <= 1;
                fetch0.pc <= IN_lookupPC;
            end
            if (fetch0.valid) begin
                fetch1 <= fetch0;
            end
        end

        if (handlingMiss)
            assocCnt <= assocCnt + 1;
    end
end

endmodule
