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

typedef struct packed
{
    logic ce;
    logic we;
    logic[15:0] wm;
    logic[`CACHE_SIZE_E-3:0] addr;
    logic[127:0] data;
} CacheIF;

wire[1:0] MC_DC_used = {!MC_DC_if[1].ce, !MC_DC_if[0].ce};
CacheIF MC_DC_if[1:0];

MemController_Req MemC_ctrl[2:0];
MemController_Res MemC_stat;
MemoryController memc
(
    .clk(clk),
    .rst(rst),
    
    .IN_ctrl(MemC_ctrl),
    .OUT_stat(MemC_stat),
    
    .OUT_CACHE_we('{MC_DC_if[1].we, MC_DC_if[0].we}),
    .OUT_CACHE_ce('{MC_DC_if[1].ce, MC_DC_if[0].ce}),
    .OUT_CACHE_wm('{MC_DC_if[1].wm, MC_DC_if[0].wm}),
    .OUT_CACHE_addr('{MC_DC_if[1].addr, MC_DC_if[0].addr}),
    .OUT_CACHE_data('{MC_DC_if[1].data, MC_DC_if[0].data}),
    .IN_CACHE_data('{128'bx, DC_dataOut}),
    
    .s_axi_awid(s_axi_awid),
    .s_axi_awaddr(s_axi_awaddr),
    .s_axi_awlen(s_axi_awlen),
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

CacheIF CORE_DC_if;
always_comb begin
    CORE_DC_if = '0;
    CORE_DC_if.ce = IF_cache.we;
    CORE_DC_if.we = IF_cache.we;
    CORE_DC_if.wm[3:0] = IF_cache.wmask;
    CORE_DC_if.addr = {IF_cache.wassoc, IF_cache.waddr[11:2]};
    CORE_DC_if.data[31:0] = IF_cache.wdata;
end

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


wire[9:0] CORE_raddr = IF_cache.raddr[11:2];

wire[127:0] DC_dataOut;

wire CacheIF DC_if0 = (MC_DC_used[0] && MC_DC_if[0].addr[0] == 0) ? MC_DC_if[0] : CORE_DC_if;
wire CacheIF DC_if1 = (MC_DC_used[0] && MC_DC_if[0].addr[0] == 1) ? MC_DC_if[0] : CORE_DC_if;

reg[1:0] dcache_readSelect0;
reg[1:0] dcache_readSelect1;
reg[1:0][$clog2(`CASSOC)-1:0] MEMC_readAssoc;
always_ff@(posedge clk) begin
    dcache_readSelect0 <= {dcache_readSelect0[0], MC_DC_if[0].addr[0]};
    dcache_readSelect1 <= {dcache_readSelect1[0], CORE_raddr[0]};
    MEMC_readAssoc <= {MEMC_readAssoc[0], MC_DC_if[0].addr[10+:$clog2(`CASSOC)]};
end

wire[`CASSOC-1:0][31:0] dcache_out0 = dcache_readSelect0[1] ? dcache1_out0 : dcache0_out0;
wire[`CASSOC-1:0][31:0] dcache_out1 = dcache_readSelect1[1] ? dcache1_out1 : dcache0_out1;

wire[`CASSOC-1:0][31:0] dcache0_out0;
wire[`CASSOC-1:0][31:0] dcache0_out1;
MemRTL#(32 * `CASSOC, (1 << (`CACHE_SIZE_E - 3 - $clog2(`CASSOC)))) dcache0
(
    .clk(clk),
    .IN_nce(!(!DC_if0.ce && DC_if0.addr[0] == 1'b0)),
    .IN_nwe(DC_if0.we),
    .IN_addr(DC_if0.addr[(`CACHE_SIZE_E-3-$clog2(`CASSOC)):1]),
    .IN_data({`CASSOC{DC_if0.data[31:0]}}),
    .IN_wm({{(`CASSOC-1){4'b0}}, DC_if0.wm[3:0]} << (DC_if0.addr[10+:$clog2(`CASSOC)] * 4)),
    .OUT_data(dcache0_out0),
    
    .IN_nce1(!(!IF_cache.re && CORE_raddr[0] == 0)),
    .IN_addr1(CORE_raddr[(`CACHE_SIZE_E-3-$clog2(`CASSOC)):1]),
    .OUT_data1(dcache0_out1)
);

wire[`CASSOC-1:0][31:0] dcache1_out0;
wire[`CASSOC-1:0][31:0] dcache1_out1;
MemRTL#(32 * `CASSOC, (1 << (`CACHE_SIZE_E - 3 - $clog2(`CASSOC)))) dcache1
(
    .clk(clk),
    .IN_nce(!(!DC_if1.ce && DC_if1.addr[0] == 1'b1)),
    .IN_nwe(DC_if1.we),
    .IN_addr(DC_if1.addr[(`CACHE_SIZE_E-3-$clog2(`CASSOC)):1]),
    .IN_data({`CASSOC{DC_if1.data[31:0]}}),
    .IN_wm({{(`CASSOC-1){4'b0}}, DC_if1.wm[3:0]} << (DC_if1.addr[10+:$clog2(`CASSOC)] * 4)),
    .OUT_data(dcache1_out0),
    
    .IN_nce1(!(!IF_cache.re && CORE_raddr[0] == 1)),
    .IN_addr1(CORE_raddr[(`CACHE_SIZE_E-3-$clog2(`CASSOC)):1]),
    .OUT_data1(dcache1_out1)
);

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


assign DC_dataOut = {96'bx, dcache_out0[MEMC_readAssoc[1]]};
assign IF_cache.rdata = dcache_out1;

assign IF_cache.rbusy = 1'b0;
assign IF_cache.wbusy = MC_DC_used[0] && MC_DC_if[0].addr[0] == CORE_DC_if.addr[0];

MemRTL#(128, (1 << (`CACHE_SIZE_E - 4)), 32) icache
(
    .clk(clk),
    .IN_nce(MC_DC_if[1].ce),
    .IN_nwe(MC_DC_if[1].we),
    .IN_addr(MC_DC_if[1].addr[(`CACHE_SIZE_E-3):2]),
    .IN_data({MC_DC_if[1].data}),
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
