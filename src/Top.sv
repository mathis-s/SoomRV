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

wire[1:0] MC_DC_used;
CacheIF MC_DC_if[1:0];

wire MC_ce;
wire MC_we;
wire[0:0] MC_cacheID;
wire[9:0] MC_sramAddr;
wire[29:0] MC_extAddr;
wire[9:0] MC_progress;
wire MC_busy;
MemoryController memc
(
    .clk(clk),
    .rst(rst),
    
    .IN_ce(MC_ce),
    .IN_we(MC_we),
    .IN_cacheID(MC_cacheID),
    .IN_sramAddr(MC_sramAddr),
    .IN_extAddr(MC_extAddr),
    .OUT_progress(MC_progress),
    .OUT_busy(MC_busy),
    
    .OUT_CACHE_used(MC_DC_used),
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

CacheIF CORE_DC_if;
always_comb begin
    CORE_DC_if.ce = CORE_writeEnable;
    CORE_DC_if.we = CORE_writeEnable;
    CORE_DC_if.wm = CORE_writeMask;
    CORE_DC_if.addr = CORE_writeAddr;
    CORE_DC_if.data = CORE_writeData;
end

wire CORE_writeEnable;
wire[31:0] CORE_writeData;
wire[29:0] CORE_writeAddr;
wire[3:0] CORE_writeMask;

wire CORE_readEnable;
wire[29:0] CORE_readAddr;
wire[31:0] CORE_readData;

wire CORE_instrReadEnable;
wire[27:0] CORE_instrReadAddress;
wire[127:0] CORE_instrReadData;

wire SPI_mosi;
wire SPI_clk;
Core core
(
    .clk(clk),
    .rst(rst),
    .en(en),
    
    .IN_instrRaw(CORE_instrReadData),
    
    .OUT_MEM_writeAddr(CORE_writeAddr),
    .OUT_MEM_writeData(CORE_writeData),
    .OUT_MEM_writeEnable(CORE_writeEnable),
    .OUT_MEM_writeMask(CORE_writeMask),
    
    .OUT_MEM_readEnable(CORE_readEnable),
    .OUT_MEM_readAddr(CORE_readAddr),
    .IN_MEM_readData(CORE_readData),
    
    .OUT_instrAddr(CORE_instrReadAddress),
    .OUT_instrReadEnable(CORE_instrReadEnable),
    .OUT_halt(OUT_halt),
    
    .OUT_SPI_clk(SPI_clk),
    .OUT_SPI_mosi(SPI_mosi),
    .IN_SPI_miso(1'b0),
    
    .OUT_MC_ce(MC_ce),
    .OUT_MC_we(MC_we),
    .OUT_MC_cacheID(MC_cacheID),
    .OUT_MC_sramAddr(MC_sramAddr),
    .OUT_MC_extAddr(MC_extAddr),
    .IN_MC_progress(MC_progress),
    .IN_MC_busy(MC_busy)
);

integer spiCnt = 0;
reg[7:0] spiByte = 0;
always@(posedge SPI_clk) begin
    spiByte = {spiByte[6:0], SPI_mosi};
    spiCnt = spiCnt + 1;
    //$display("cnt %d %x", spiCnt, mprj_io[25]);
    if (spiCnt == 8) begin
        $write("%c", spiByte);
        spiCnt = 0;
    end
end

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
    
    .IN_nce1(!(!CORE_readEnable && CORE_readAddr < 1024)),
    .IN_addr1(CORE_readAddr[9:0]),
    .OUT_data1(CORE_readData)
);

//wire[31:0] IC_dataOut;
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

always@(posedge clk) begin
    if (!CORE_DC_if.ce && !CORE_DC_if.we && CORE_DC_if.wm == 4'b0001 && CORE_DC_if.addr == 30'h3F800000)
        $write("%c", CORE_DC_if.data[7:0]);
end

endmodule
