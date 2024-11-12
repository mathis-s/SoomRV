module SoC#(parameter WIDTH=128, parameter ADDR_LEN=32)
(
    input wire clk,
    input wire rst,
    input wire en,

    input wire IN_irq,

    output wire OUT_powerOff,
    output wire OUT_reboot,

    // write request
    output[`AXI_ID_LEN-1:0]  s_axi_awid,
    output[ADDR_LEN-1:0] s_axi_awaddr,
    output[7:0] s_axi_awlen,
    output[2:0] s_axi_awsize,
    output[1:0] s_axi_awburst,
    output[0:0] s_axi_awlock,
    output[3:0] s_axi_awcache,
    output s_axi_awvalid,
    input s_axi_awready,

    // write stream
    output[WIDTH-1:0] s_axi_wdata,
    output[(WIDTH/8)-1:0] s_axi_wstrb,
    output s_axi_wlast,
    output s_axi_wvalid,
    input s_axi_wready,

    // write response
    output s_axi_bready,
    input[`AXI_ID_LEN-1:0] s_axi_bid,
    input s_axi_bvalid,

    // read request
    output[`AXI_ID_LEN-1:0] s_axi_arid,
    output[ADDR_LEN-1:0] s_axi_araddr,
    output[7:0] s_axi_arlen,
    output[2:0] s_axi_arsize,
    output[1:0] s_axi_arburst,
    output[0:0] s_axi_arlock,
    output[3:0] s_axi_arcache,
    output s_axi_arvalid,
    input s_axi_arready,

    // read stream
    output s_axi_rready,
    input[`AXI_ID_LEN-1:0] s_axi_rid,
    input[WIDTH-1:0] s_axi_rdata,
    input s_axi_rlast,
    input s_axi_rvalid,

    output DebugInfo OUT_dbg,
    output DebugInfoMemC OUT_dbgMemC
);

ICacheIF MC_IC_wr;

CacheIF MC_DC_rd;
CacheIF MC_DC_wr;

logic MC_DC_rd_ready;

MemController_Req MemC_ctrl[2:0] /* verilator public */;
MemController_Res MemC_stat /* verilator public */;
MemoryController memc
(
    .clk(clk),
    .rst(rst),

    .IN_ctrl(MemC_ctrl),
    .OUT_stat(MemC_stat),

    .OUT_icacheW(MC_IC_wr),
    .OUT_dcacheW(MC_DC_wr),

    .IN_dcacheRReady(MC_DC_rd_ready),
    .OUT_dcacheR(MC_DC_rd),
    .IN_dcacheR(DC_dataOut),

    .s_axi_awid(s_axi_awid),
    .s_axi_awaddr(s_axi_awaddr),
    .s_axi_awlen(s_axi_awlen),
    .s_axi_awsize(s_axi_awsize),
    .s_axi_awburst(s_axi_awburst),
    .s_axi_awlock(s_axi_awlock),
    .s_axi_awcache(s_axi_awcache),
    .s_axi_awvalid(s_axi_awvalid),
    .s_axi_awready(s_axi_awready),
    .s_axi_wdata(s_axi_wdata),
    .s_axi_wstrb(s_axi_wstrb),
    .s_axi_wlast(s_axi_wlast),
    .s_axi_wvalid(s_axi_wvalid),
    .s_axi_wready(s_axi_wready),
    .s_axi_bready(s_axi_bready),
    .s_axi_bid(s_axi_bid),
    .s_axi_bvalid(s_axi_bvalid),
    .s_axi_arid(s_axi_arid),
    .s_axi_araddr(s_axi_araddr),
    .s_axi_arlen(s_axi_arlen),
    .s_axi_arsize(s_axi_arsize),
    .s_axi_arburst(s_axi_arburst),
    .s_axi_arlock(s_axi_arlock),
    .s_axi_arcache(s_axi_arcache),
    .s_axi_arvalid(s_axi_arvalid),
    .s_axi_arready(s_axi_arready),
    .s_axi_rready(s_axi_rready),
    .s_axi_rid(s_axi_rid),
    .s_axi_rdata(s_axi_rdata),
    .s_axi_rlast(s_axi_rlast),
    .s_axi_rvalid(s_axi_rvalid),

    .OUT_dbg(OUT_dbgMemC)
);

IF_Cache IF_cache();
IF_CTable IF_ct();
IF_MMIO IF_mmio();
IF_CSR_MMIO IF_csr_mmio();

IF_ICache IF_icache();
IF_ICTable IF_ict();

Core core
(
    .clk(clk),
    .rst(rst),
    .en(en),

    .IN_irq(IN_irq),

    .IF_cache(IF_cache),
    .IF_ct(IF_ct),
    .IF_mmio(IF_mmio),
    .IF_csr_mmio(IF_csr_mmio),

    .IF_icache(IF_icache),
    .IF_ict(IF_ict),

    .OUT_memc(MemC_ctrl),
    .IN_memc(MemC_stat),

    .OUT_dbg(OUT_dbg)
);


localparam NUM_CACHE_PORTS = 1;
localparam IN_PORTS = 4;

CacheIF cacheIFs[IN_PORTS-1:0];
always_comb begin
    cacheIFs[0] = MC_DC_wr;
    cacheIFs[1] = MC_DC_rd;
    cacheIFs[2] = CacheIF'{
        ce:   IF_cache.re[0],
        we:   IF_cache.we[0],
        wm:   IF_cache.wmask[0],
        data: {IF_cache.wdata[0]},
        addr: {IF_cache.wassoc[0], IF_cache.addr[0][11:2]}
    };
    cacheIFs[3] = CacheIF'{
        ce:   IF_cache.re[1],
        we:   IF_cache.we[1],
        wm:   IF_cache.wmask[1],
        data: {IF_cache.wdata[1]},
        addr: {IF_cache.wassoc[1], IF_cache.addr[1][11:2]}
    };
end

always_comb begin
    MC_DC_rd_ready = cacheReady[1];
    IF_cache.busy[0] = !cacheReady[2];
    IF_cache.busy[1] = !cacheReady[3];
end

logic cacheReady[IN_PORTS-1:0];
logic[`CASSOC-1:0][`CWIDTH-1:0][31:0] cacheRData[IN_PORTS-1:0];

CacheIF bankIFs[`CBANKS-1:0][NUM_CACHE_PORTS-1:0];
logic[`CASSOC-1:0][`CWIDTH-1:0][31:0] bankRData[`CBANKS-1:0][NUM_CACHE_PORTS-1:0];

CacheArbiter#(IN_PORTS, NUM_CACHE_PORTS, `CBANKS, $clog2(`CWIDTH), `CASSOC * `CWIDTH * 32) dcacheArb
(
    .clk(clk),
    .IN_ports(cacheIFs),
    .OUT_portReady(cacheReady),
    .OUT_portRData(cacheRData),

    .OUT_ports(bankIFs),
    .IN_portRData(bankRData)
);

generate
    // todo: compare CWIDTH=2 and CBANKS=2 vs CWIDTH=1 and CBANKS=4
for (genvar i = 0; i < `CBANKS; i=i+1)
    MemRTL1RW#(32 * `CASSOC * `CWIDTH, (1 << (`CACHE_SIZE_E - 2 - $clog2(`CASSOC) - $clog2(`CWIDTH) - $clog2(`CBANKS)))) dcache
    (
        .clk(clk),
        .IN_nce(bankIFs[i][0].ce),
        .IN_nwe(bankIFs[i][0].we),
        .IN_addr(bankIFs[i][0].addr[(`CACHE_SIZE_E-3-$clog2(`CASSOC)):$clog2(`CWIDTH)+$clog2(`CBANKS)]),
        .IN_data({`CASSOC{bankIFs[i][0].data[`CWIDTH*32-1:0]}}),
        .IN_wm((4 * `CASSOC * `CWIDTH)'(bankIFs[i][0].wm[`CWIDTH*4-1:0]) << (bankIFs[i][0].addr[`CACHE_SIZE_E-3-:$clog2(`CASSOC)] * `CWIDTH * 4)),
        .OUT_data(bankRData[i][0])//,

        //.IN_nce1(bankIFs[i][1].ce),
        //.IN_addr1(bankIFs[i][1].addr[(`CACHE_SIZE_E-3-$clog2(`CASSOC)):$clog2(`CWIDTH)+$clog2(`CBANKS)]),
        //.OUT_data1(bankRData[i][1])
    );
endgenerate

// Read Address Shift Registers
logic[9:0] CORE_raddr[NUM_AGUS-1:0][1:0];
logic[`CACHE_SIZE_E-3:0] MEMC_raddr[1:0];
always_ff@(posedge clk) begin
    for (integer i = 0; i < NUM_AGUS; i=i+1)
        CORE_raddr[i] <= {CORE_raddr[i][0], IF_cache.addr[i][11:2]};
    MEMC_raddr <= {MEMC_raddr[0], MC_DC_rd.addr};
end

wire logic[`CWIDTH*32-1:0] DC_dataOut = cacheRData[1] [MEMC_raddr[1][`CACHE_SIZE_E-3 -: $clog2(`CASSOC)]];

logic[`CWIDTH-1:0][`CASSOC-1:0][31:0] cacheRData_t[IN_PORTS-1:0];
always_comb begin
    for (integer p = 0; p < IN_PORTS; p=p+1)
        for (integer a = 0; a < `CASSOC; a=a+1)
            for (integer w = 0; w < `CWIDTH; w=w+1)
                cacheRData_t[p][w][a] = cacheRData[p][a][w];
end

generate for (genvar i = 0; i < NUM_AGUS; i=i+1) begin
if (`CWIDTH == 1) assign IF_cache.rdata[i] = cacheRData_t[2+i];
else              assign IF_cache.rdata[i] = cacheRData_t[2+i] [CORE_raddr[i][1][0 +: $clog2(`CWIDTH)]];
end endgenerate

wire[11:0] dctAddr = IF_ct.we ? IF_ct.waddr : IF_ct.raddr[1];
MemRTL#($bits(CTEntry) * `CASSOC, 1 << (`CACHE_SIZE_E - `CLSIZE_E - $clog2(`CASSOC)), $bits(CTEntry)) dctable
(
    .clk(clk),
    .IN_nce(!(IF_ct.re[1] || IF_ct.we)),
    .IN_nwe(!IF_ct.we),
    .IN_addr(dctAddr[11-:(`CACHE_SIZE_E - `CLSIZE_E - $clog2(`CASSOC))]),
    .IN_data({`CASSOC{IF_ct.wdata}}),
    .IN_wm(1 << IF_ct.wassoc),
    .OUT_data(IF_ct.rdata[1]),

    .IN_nce1(!IF_ct.re[0]),
    .IN_addr1(IF_ct.raddr[0][11-:(`CACHE_SIZE_E - `CLSIZE_E - $clog2(`CASSOC))]),
    .OUT_data1(IF_ct.rdata[0])
);

MemRTL#($bits(CTEntry) * `CASSOC, 1 << (`CACHE_SIZE_E - `CLSIZE_E - $clog2(`CASSOC)), $bits(CTEntry)) ictable
(
    .clk(clk),
    .IN_nce(!IF_ict.we),
    .IN_nwe(!IF_ict.we),
    .IN_addr(IF_ict.waddr[11-:(`CACHE_SIZE_E - `CLSIZE_E - $clog2(`CASSOC))]),
    .IN_data({`CASSOC{IF_ict.wdata}}),
    .IN_wm(1 << IF_ict.wassoc),
    .OUT_data(),

    .IN_nce1(!IF_ict.re),
    .IN_addr1(IF_ict.raddr[11-:(`CACHE_SIZE_E - `CLSIZE_E - $clog2(`CASSOC))]),
    .OUT_data1(IF_ict.rdata)
);

MemRTL#(128 * `CASSOC, (1 << (`CACHE_SIZE_E - 4 - $clog2(`CASSOC))), 128) icache
(
    .clk(clk),
    .IN_nce(MC_IC_wr.ce),
    .IN_nwe(MC_IC_wr.we),
    .IN_addr(MC_IC_wr.addr[(`CACHE_SIZE_E-3-$clog2(`CASSOC)):2]),
    .IN_data({`CASSOC{MC_IC_wr.data}}),
    .IN_wm(1 << (MC_IC_wr.addr[`CACHE_SIZE_E-3 -: $clog2(`CASSOC)])),
    .OUT_data(),

    .IN_nce1(!IF_icache.re),
    .IN_addr1(IF_icache.raddr[11:4]),
    .OUT_data1(IF_icache.rdata)
);
assign IF_icache.busy = 0;

MMIO mmio
(
    .clk(clk),
    .rst(rst),

    .IF_mem(IF_mmio),

    .OUT_powerOff(OUT_powerOff),
    .OUT_reboot(OUT_reboot),

    .OUT_csrIf(IF_csr_mmio.MMIO)
);

endmodule
