module SoC
(
    input wire clk,
    input wire rst,
    input wire en,

    output wire OUT_busOEn,
    output wire OUT_busEn,
    output wire[31:0] OUT_bus,
    input wire IN_busStall,
    input wire[31:0] IN_bus,

    output wire OUT_powerOff,
    output wire OUT_reboot
);

typedef struct packed
{
    logic ce;
    logic we;
    logic[3:0] wm;
    logic[29:0] addr;
    logic[31:0] data;
} CacheIF;

wire[1:0] MC_DC_used = {!MC_DC_if[1].ce, !MC_DC_if[0].ce};
CacheIF MC_DC_if[1:0];

MemController_Req MemC_ctrl;
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
    .OUT_CACHE_addr('{MC_DC_if[1].addr[9:0], MC_DC_if[0].addr[9:0]}),
    .OUT_CACHE_data('{MC_DC_if[1].data, MC_DC_if[0].data}),
    .IN_CACHE_data('{32'bx, DC_dataOut}),
    
    .OUT_EXT_oen(OUT_busOEn),
    .OUT_EXT_en(OUT_busEn),
    .OUT_EXT_bus(OUT_bus),
    .IN_EXT_stall(IN_busStall),
    .IN_EXT_bus(IN_bus)
);

assign MC_DC_if[0].addr[29:10] = 0;

IF_Mem IF_mem();
IF_MMIO IF_mmio();
IF_CSR_MMIO IF_csr_mmio();

CacheIF CORE_DC_if;
always_comb begin
    CORE_DC_if.ce = IF_mem.we;
    CORE_DC_if.we = IF_mem.we;
    CORE_DC_if.wm = IF_mem.wmask;
    CORE_DC_if.addr = IF_mem.waddr;
    CORE_DC_if.data = IF_mem.wdata;
end

wire CORE_instrReadEnable;
wire[27:0] CORE_instrReadAddress;
wire[127:0] CORE_instrReadData;

Core core
(
    .clk(clk),
    .rst(rst),
    .en(en),
    
    .IF_mem(IF_mem),
    .IF_mmio(IF_mmio),
    .IF_csr_mmio(IF_csr_mmio),
    
    .OUT_instrAddr(CORE_instrReadAddress),
    .OUT_instrReadEnable(CORE_instrReadEnable),
    .IN_instrRaw(CORE_instrReadData),
    
    .OUT_memc(MemC_ctrl),
    .IN_memc(MemC_stat)
);


wire[31:0] DC_dataOut;

wire CacheIF DC_if0 = (MC_DC_used[0] && MC_DC_if[0].addr[0] == 0) ? MC_DC_if[0] : CORE_DC_if;
wire CacheIF DC_if1 = (MC_DC_used[0] && MC_DC_if[0].addr[0] == 1) ? MC_DC_if[0] : CORE_DC_if;

reg[1:0] dcache_readSelect0;
reg[1:0] dcache_readSelect1;
always_ff@(posedge clk) begin
    dcache_readSelect0 <= {dcache_readSelect0[0], MC_DC_if[0].addr[0]};
    dcache_readSelect1 <= {dcache_readSelect1[0], IF_mem.raddr[0]};
end

wire[31:0] dcache_out0 = dcache_readSelect0[1] ? dcache1_out0 : dcache0_out0;
wire[31:0] dcache_out1 = dcache_readSelect1[1] ? dcache1_out1 : dcache0_out1;

wire[31:0] dcache0_out0;
wire[31:0] dcache0_out1;
MemRTL#(32, 512) dcache0
(
    .clk(clk),
    .IN_nce(!(!DC_if0.ce && DC_if0.addr[0] == 1'b0)),
    .IN_nwe(DC_if0.we),
    .IN_addr(DC_if0.addr[9:1]),
    .IN_data(DC_if0.data),
    .IN_wm(DC_if0.wm),
    .OUT_data(dcache0_out0),
    
    .IN_nce1(!(!IF_mem.re && IF_mem.raddr[0] == 0)),
    .IN_addr1(IF_mem.raddr[9:1]),
    .OUT_data1(dcache0_out1)
);

wire[31:0] dcache1_out0;
wire[31:0] dcache1_out1;
MemRTL#(32, 512) dcache1
(
    .clk(clk),
    .IN_nce(!(!DC_if1.ce && DC_if1.addr[0] == 1'b1)),
    .IN_nwe(DC_if1.we),
    .IN_addr(DC_if1.addr[9:1]),
    .IN_data(DC_if1.data),
    .IN_wm(DC_if1.wm),
    .OUT_data(dcache1_out0),
    
    .IN_nce1(!(!IF_mem.re && IF_mem.raddr[0] == 1)),
    .IN_addr1(IF_mem.raddr[9:1]),
    .OUT_data1(dcache1_out1)
);


assign DC_dataOut = dcache_out0;
assign IF_mem.rdata = dcache_out1;

assign IF_mem.rbusy = 1'b0;
assign IF_mem.wbusy = MC_DC_used[0] && MC_DC_if[0].addr[0] == CORE_DC_if.addr[0];

MemRTL#(64, 512) icache
(
    .clk(clk),
    .IN_nce(MC_DC_used[1] ? MC_DC_if[1].ce : CORE_instrReadEnable),
    .IN_nwe(MC_DC_used[1] ? MC_DC_if[1].we : 1'b1),
    .IN_addr(MC_DC_used[1] ? MC_DC_if[1].addr[9:1] : {CORE_instrReadAddress[7:0], 1'b1}),
    .IN_data({MC_DC_if[1].data, MC_DC_if[1].data}),
    .IN_wm({{4{MC_DC_if[1].addr[0]}}, {4{~MC_DC_if[1].addr[0]}}}),
    .OUT_data(CORE_instrReadData[127:64]),
    
    .IN_nce1(CORE_instrReadEnable),
    .IN_addr1({CORE_instrReadAddress[7:0], 1'b0}),
    .OUT_data1(CORE_instrReadData[63:0])
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
