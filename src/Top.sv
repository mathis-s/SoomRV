typedef struct packed
{
    logic ce;
    logic we;
    logic[3:0] wm;
    logic[29:0] addr;
    logic[31:0] data;
} CacheIF;

module Top
(
    input wire clk,
    input wire rst,
    input wire en,
    output wire OUT_halt
);

wire[1:0] MC_DC_used = {!MC_DC_if[1].ce, !MC_DC_if[0].ce};
CacheIF MC_DC_if[1:0];

CTRL_MemC MemC_ctrl;
STAT_MemC MemC_stat;
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
    
    .OUT_EXT_oen(EXTMEM_oen),
    .OUT_EXT_en(EXTMEM_en),
    .OUT_EXT_bus(EXTMEM_busOut),
    .IN_EXT_bus(EXTMEM_bus)
);

assign MC_DC_if[0].addr[29:10] = 0;

wire EXTMEM_oen;
wire[31:0] EXTMEM_busOut;
wire[31:0] EXTMEM_bus = EXTMEM_oen ? EXTMEM_busOut : 32'bz;
wire EXTMEM_en;
ExternalMemorySim extMem
(
    .clk(clk),
    .en(EXTMEM_en && !rst),
    .bus(EXTMEM_bus)
);

IF_Mem IF_mem();
IF_Mem IF_mmio();
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
    
    .OUT_halt(OUT_halt),
    
    .OUT_memc(MemC_ctrl),
    .IN_memc(MemC_stat)
);

wire[31:0] DC_dataOut;

CacheIF DC_if;
assign DC_if = MC_DC_used[0] ? MC_DC_if[0] : CORE_DC_if;
MemRTL dcache
(
    .clk(clk),
    .IN_nce(!(!DC_if.ce && DC_if.addr < 1024)),
    .IN_nwe(DC_if.we),
    .IN_addr(DC_if.addr[9:0]),
    .IN_data(DC_if.data),
    .IN_wm(DC_if.wm),
    .OUT_data(DC_dataOut),
    
    .IN_nce1(!(!IF_mem.re)),
    .IN_addr1(IF_mem.raddr[9:0]),
    .OUT_data1(IF_mem.rdata)
);
assign IF_mem.rbusy = 1'b0;
assign IF_mem.wbusy = MC_DC_used[0];

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

    .OUT_SPI_cs(),
    .OUT_SPI_clk(),
    .OUT_SPI_mosi(),
    .IN_SPI_miso(1'b0),
    
    .OUT_csrIf(IF_csr_mmio.MMIO)
);

endmodule
