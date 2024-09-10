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

logic[`CWIDTH*32-1:0] DC_dataOut;
// R/W port
CacheIF[`CBANKS-1:0] bankIFs;
always_comb begin
    for (integer i = 0; i < `CBANKS; i=i+1)
        bankIFs[i] = CacheIF'{ce: 1, we: 1, default: 'x};
    IF_cache.busy[0] = 0;
    IF_cache.rbusyBank[0] = 'x;

    if (!IF_cache.re[0]) begin
        bankIFs[IF_cache.addr[0][2+$clog2(`CWIDTH) +:$clog2(`CBANKS)]].ce = IF_cache.re[0];
        bankIFs[IF_cache.addr[0][2+$clog2(`CWIDTH) +:$clog2(`CBANKS)]].we = IF_cache.we[0];
        bankIFs[IF_cache.addr[0][2+$clog2(`CWIDTH) +:$clog2(`CBANKS)]].wm = IF_cache.wmask[0];
        bankIFs[IF_cache.addr[0][2+$clog2(`CWIDTH) +:$clog2(`CBANKS)]].data = {IF_cache.wdata[0]};
        bankIFs[IF_cache.addr[0][2+$clog2(`CWIDTH) +:$clog2(`CBANKS)]].addr = {IF_cache.wassoc[0], IF_cache.addr[0][11:2]};
    end

    if (!MC_DC_wr.ce) begin
        bankIFs[MC_DC_wr.addr[$clog2(`CWIDTH) +: $clog2(`CBANKS)]] = MC_DC_wr;
        IF_cache.busy[0] = 1;
        IF_cache.rbusyBank[0] = MC_DC_wr.addr[$clog2(`CWIDTH) +: $clog2(`CBANKS)];
    end
end

// R port
CacheIF[`CBANKS-1:0] bankIFs_1;
always_comb begin
    for (integer i = 0; i < `CBANKS; i=i+1)
        bankIFs_1[i] = CacheIF'{ce: 1, we: 1, default: 'x};

    IF_cache.busy[1] = 0;
    IF_cache.rbusyBank[1] = 'x;

    if (!IF_cache.re[1]) begin
        bankIFs_1[IF_cache.addr[1][2+$clog2(`CWIDTH) +:$clog2(`CBANKS)]].ce = IF_cache.re[1];
        bankIFs_1[IF_cache.addr[1][2+$clog2(`CWIDTH) +:$clog2(`CBANKS)]].we = IF_cache.we[1];
        bankIFs_1[IF_cache.addr[1][2+$clog2(`CWIDTH) +:$clog2(`CBANKS)]].wm = IF_cache.wmask[1];
        bankIFs_1[IF_cache.addr[1][2+$clog2(`CWIDTH) +:$clog2(`CBANKS)]].data = {IF_cache.wdata[1]};
        bankIFs_1[IF_cache.addr[1][2+$clog2(`CWIDTH) +:$clog2(`CBANKS)]].addr = {IF_cache.wassoc[1], IF_cache.addr[1][11:2]};
    end
    if (!MC_DC_rd.ce) begin
        bankIFs_1[MC_DC_rd.addr[$clog2(`CWIDTH) +: $clog2(`CBANKS)]] = MC_DC_rd;
        IF_cache.busy[1] = 1;
        IF_cache.rbusyBank[1] = MC_DC_rd.addr[$clog2(`CWIDTH) +: $clog2(`CBANKS)];
    end
end
// Read Address Shift Registers
logic[9:0] CORE_raddr_0[1:0];
logic[9:0] CORE_raddr_1[1:0];
logic[`CACHE_SIZE_E-3:0] MEMC_raddr[1:0];
always_ff@(posedge clk) begin
    CORE_raddr_0 <= {CORE_raddr_0[0], IF_cache.addr[0][11:2]};
    CORE_raddr_1 <= {CORE_raddr_1[0], IF_cache.addr[1][11:2]};
    MEMC_raddr <= {MEMC_raddr[0], MC_DC_rd.addr};
end

logic[`CASSOC-1:0][`CWIDTH-1:0][31:0] dcacheOut0[`CBANKS-1:0];
logic[`CASSOC-1:0][`CWIDTH-1:0][31:0] dcacheOut1[`CBANKS-1:0];
generate
for (genvar i = 0; i < `CBANKS; i=i+1)
    MemRTL#(32 * `CASSOC * `CWIDTH, (1 << (`CACHE_SIZE_E - 2 - $clog2(`CASSOC) - $clog2(`CWIDTH) - $clog2(`CBANKS)))) dcache
    (
        .clk(clk),
        .IN_nce(bankIFs[i].ce),
        .IN_nwe(bankIFs[i].we),
        .IN_addr(bankIFs[i].addr[(`CACHE_SIZE_E-3-$clog2(`CASSOC)):$clog2(`CWIDTH)+$clog2(`CBANKS)]),
        .IN_data({`CASSOC{bankIFs[i].data[`CWIDTH*32-1:0]}}),
        .IN_wm((4 * `CASSOC * `CWIDTH)'(bankIFs[i].wm[`CWIDTH*4-1:0]) << (bankIFs[i].addr[`CACHE_SIZE_E-3-:$clog2(`CASSOC)] * `CWIDTH * 4)),
        .OUT_data(dcacheOut0[i]),

        .IN_nce1(bankIFs_1[i].ce),
        //.IN_nwe1(bankIFs_1[i].we),
        .IN_addr1(bankIFs_1[i].addr[(`CACHE_SIZE_E-3-$clog2(`CASSOC)):$clog2(`CWIDTH)+$clog2(`CBANKS)]),
        //.IN_data1({`CASSOC{bankIFs_1[i].data[`CWIDTH*32-1:0]}}),
        //.IN_wm1((4 * `CASSOC * `CWIDTH)'(bankIFs_1[i].wm[`CWIDTH*4-1:0]) << (bankIFs_1[i].addr[`CACHE_SIZE_E-3-:$clog2(`CASSOC)] * `CWIDTH * 4)),
        .OUT_data1(dcacheOut1[i])
    );
endgenerate

logic[`CWIDTH-1:0][`CASSOC-1:0][31:0] dcacheOut0_t[`CBANKS-1:0];
always_comb begin
    for (integer i = 0; i < `CBANKS; i=i+1)
        for (integer a = 0; a < `CASSOC; a=a+1)
            for (integer w = 0; w < `CWIDTH; w=w+1)
                dcacheOut0_t[i][w][a] = dcacheOut0[i][a][w];
end

logic[`CWIDTH-1:0][`CASSOC-1:0][31:0] dcacheOut1_t[`CBANKS-1:0];
always_comb begin
    for (integer i = 0; i < `CBANKS; i=i+1)
        for (integer a = 0; a < `CASSOC; a=a+1)
            for (integer w = 0; w < `CWIDTH; w=w+1)
                dcacheOut1_t[i][w][a] = dcacheOut1[i][a][w];
end

always_comb begin
    DC_dataOut = 'x;
    DC_dataOut[`CWIDTH*32-1:0] = dcacheOut1 [MEMC_raddr[1][$clog2(`CWIDTH) +: $clog2(`CBANKS)]] [MEMC_raddr[1][`CACHE_SIZE_E-3 -: $clog2(`CASSOC)]];
end
if (`CWIDTH == 1) assign IF_cache.rdata[0] = dcacheOut0_t [CORE_raddr_0[1][$clog2(`CWIDTH) +: $clog2(`CBANKS)]];
else              assign IF_cache.rdata[0] = dcacheOut0_t [CORE_raddr_0[1][$clog2(`CWIDTH) +: $clog2(`CBANKS)]] [CORE_raddr_0[1][0 +: $clog2(`CWIDTH)]];
if (`CWIDTH == 1) assign IF_cache.rdata[1] = dcacheOut1_t [CORE_raddr_1[1][$clog2(`CWIDTH) +: $clog2(`CBANKS)]];
else              assign IF_cache.rdata[1] = dcacheOut1_t [CORE_raddr_1[1][$clog2(`CWIDTH) +: $clog2(`CBANKS)]] [CORE_raddr_1[1][0 +: $clog2(`CWIDTH)]];


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
