module SoC#(parameter WIDTH=128, parameter ID_LEN=2, parameter ADDR_LEN=32)
(
    input wire clk,
    input wire rst,
    input wire en,

    output wire OUT_powerOff,
    output wire OUT_reboot,
    
    // write request
    output[ID_LEN-1:0]  s_axi_awid,
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
    input[ID_LEN-1:0] s_axi_bid,
    input s_axi_bvalid,
    
    // read request
    output[ID_LEN-1:0] s_axi_arid,
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
    input[ID_LEN-1:0] s_axi_rid,
    input[WIDTH-1:0] s_axi_rdata,
    input s_axi_rlast,
    input s_axi_rvalid
);

CacheIF unused_MC_DC_if;
CacheIF MC_IC_if;

CacheIF MC_DC_rd;
CacheIF MC_DC_wr;

MemController_Req MemC_ctrl[2:0];
MemController_Res MemC_stat;
MemoryController memc
(
    .clk(clk),
    .rst(rst),
    
    .IN_ctrl(MemC_ctrl),
    .OUT_stat(MemC_stat),
    
    .OUT_CACHE_we('{MC_IC_if.we, unused_MC_DC_if.we}),
    .OUT_CACHE_ce('{MC_IC_if.ce, unused_MC_DC_if.ce}),
    .OUT_CACHE_wm('{MC_IC_if.wm, unused_MC_DC_if.wm}),
    .OUT_CACHE_addr('{MC_IC_if.addr, unused_MC_DC_if.addr}),
    .OUT_CACHE_data('{MC_IC_if.data, unused_MC_DC_if.data}),
    .IN_CACHE_data('{128'bx, DC_dataOut}),

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
    .s_axi_rvalid(s_axi_rvalid)
);

IF_Cache IF_cache();
IF_CTable IF_ct();
IF_MMIO IF_mmio();
IF_CSR_MMIO IF_csr_mmio();

wire CORE_instrReadEnable;
wire[27:0] CORE_instrReadAddress;
wire[127:0] CORE_instrReadData;

Core core
(
    .clk(clk),
    .rst(rst),
    .en(en),
    
    .IF_cache(IF_cache),
    .IF_ct(IF_ct),
    .IF_mmio(IF_mmio),
    .IF_csr_mmio(IF_csr_mmio),
    
    .OUT_instrAddr(CORE_instrReadAddress),
    .OUT_instrReadEnable(CORE_instrReadEnable),
    .IN_instrRaw(CORE_instrReadData),
    
    .OUT_memc(MemC_ctrl),
    .IN_memc(MemC_stat)
);

CacheIF CORE_DC_if;
always_comb begin
    CORE_DC_if.ce = IF_cache.we;
    CORE_DC_if.we = IF_cache.we;
    CORE_DC_if.addr = {IF_cache.wassoc, IF_cache.waddr[11:2]};
end
if (`CWIDTH == 1) always_comb begin
    CORE_DC_if.wm = '0;
    CORE_DC_if.wm[3:0] = IF_cache.wmask;
    CORE_DC_if.data = 'x;
    CORE_DC_if.data[31:0] = IF_cache.wdata;
end
else always_comb begin
    CORE_DC_if.wm = '0;
    CORE_DC_if.wm[(IF_cache.waddr[2 +: $clog2(`CWIDTH)] * 4) +: 4] = IF_cache.wmask;

    CORE_DC_if.data = 'x;
    CORE_DC_if.data[(IF_cache.waddr[2 +: $clog2(`CWIDTH)] * 32) +: 32] = IF_cache.wdata;
end

logic[127:0] DC_dataOut;
// R port
CacheIF[`CBANKS-1:0] readIFs;
always_comb begin
    for (integer i = 0; i < `CBANKS; i=i+1)
        readIFs[i] = CacheIF'{ce: 1, we: 1, default: 'x};
    IF_cache.rbusy = 0;
    IF_cache.rbusyBank = 'x;
    
    if (!IF_cache.re) begin
        readIFs[IF_cache.raddr[2+$clog2(`CWIDTH) +:$clog2(`CBANKS)]].ce = IF_cache.re;
        readIFs[IF_cache.raddr[2+$clog2(`CWIDTH) +:$clog2(`CBANKS)]].addr = {{$clog2(`CASSOC){1'bx}}, IF_cache.raddr[11:2]};
    end
    if (!MC_DC_rd.ce) begin
        readIFs[MC_DC_rd.addr[$clog2(`CWIDTH) +: $clog2(`CBANKS)]] = MC_DC_rd;
        IF_cache.rbusy = 1;
        IF_cache.rbusyBank = MC_DC_rd.addr[$clog2(`CWIDTH) +: $clog2(`CBANKS)];
    end
end
// W port
CacheIF[`CBANKS-1:0] bankIFs;
always_comb begin
    for (integer i = 0; i < `CBANKS; i=i+1)
        bankIFs[i] = CacheIF'{ce: 1, default: 'x};

    if (!CORE_DC_if.ce)
        bankIFs[CORE_DC_if.addr[$clog2(`CWIDTH) +: $clog2(`CBANKS)]] = CORE_DC_if;
    if (!MC_DC_wr.ce)
        bankIFs[MC_DC_wr.addr[$clog2(`CWIDTH) +: $clog2(`CBANKS)]] = MC_DC_wr;

    IF_cache.wbusy = !MC_DC_wr.ce &&
        (CORE_DC_if.addr[$clog2(`CWIDTH) +: $clog2(`CBANKS)] == MC_DC_wr.addr[$clog2(`CWIDTH) +: $clog2(`CBANKS)]);
end
// Read Address Shift Registers
logic[9:0] CORE_raddr[1:0];
logic[`CACHE_SIZE_E-3:0] MEMC_raddr[1:0];
always_ff@(posedge clk) begin
    CORE_raddr <= {CORE_raddr[0], IF_cache.raddr[11:2]};
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
        
        .IN_nce1(readIFs[i].ce),
        .IN_addr1(readIFs[i].addr[(`CACHE_SIZE_E-3-$clog2(`CASSOC)):$clog2(`CWIDTH)+$clog2(`CBANKS)]),
        .OUT_data1(dcacheOut1[i])
    );
endgenerate

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
if (`CWIDTH == 1) assign IF_cache.rdata = dcacheOut1_t [CORE_raddr[1][$clog2(`CWIDTH) +: $clog2(`CBANKS)]];
else              assign IF_cache.rdata = dcacheOut1_t [CORE_raddr[1][$clog2(`CWIDTH) +: $clog2(`CBANKS)]] [CORE_raddr[1][0 +: $clog2(`CWIDTH)]];


MemRTL#($bits(CTEntry) * `CASSOC, 1 << (`CACHE_SIZE_E - `CLSIZE_E - $clog2(`CASSOC)), $bits(CTEntry)) dctable
(
    .clk(clk),
    .IN_nce(!(IF_ct.re[1] || IF_ct.we)),
    .IN_nwe(!IF_ct.we),
    .IN_addr({IF_ct.we ? IF_ct.waddr : IF_ct.raddr[1]}[11-:(`CACHE_SIZE_E - `CLSIZE_E - $clog2(`CASSOC))]),
    .IN_data({`CASSOC{IF_ct.wdata}}),
    .IN_wm(1 << IF_ct.wassoc),
    .OUT_data(IF_ct.rdata[1]),
    
    .IN_nce1(!IF_ct.re[0]),
    .IN_addr1(IF_ct.raddr[0][11-:(`CACHE_SIZE_E - `CLSIZE_E - $clog2(`CASSOC))]),
    .OUT_data1(IF_ct.rdata[0])
);

MemRTL#(128, (1 << (`CACHE_SIZE_E - 4)), 32) icache
(
    .clk(clk),
    .IN_nce(MC_IC_if.ce),
    .IN_nwe(MC_IC_if.we),
    .IN_addr(MC_IC_if.addr[(`CACHE_SIZE_E-3):2]),
    .IN_data({MC_IC_if.data}),
    .IN_wm('1),
    .OUT_data(),
    
    .IN_nce1(CORE_instrReadEnable),
    .IN_addr1(CORE_instrReadAddress[(`CACHE_SIZE_E-5):0]),
    .OUT_data1(CORE_instrReadData[127:0])
);

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
