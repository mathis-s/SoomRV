module Top
(
    input wire clk,
    input wire rst,
    input wire en,
    input wire[63:0] IN_instrRaw,

    output wire[28:0] OUT_instrAddr,
    output wire OUT_instrReadEnable,
    output wire OUT_halt
);

wire[31:0] DC_dataIn;
wire[31:0] DC_dataOut;
wire[29:0] DC_addr;
wire DC_we;
wire DC_ce;
wire[3:0] DC_wm;

MemRTL dcache
(
    .clk(clk),
    .IN_nce(DC_ce),
    .IN_nwe(DC_we),
    .IN_addr(DC_addr[15:0]),
    .IN_data(DC_dataIn),
    .IN_wm(DC_wm),
    .OUT_data(DC_dataOut)
);

Core core
(
    .clk(clk),
    .rst(rst),
    .en(en),
    
    .IN_instrRaw(IN_instrRaw),
    
    .IN_MEM_readData(DC_dataOut),
    .OUT_MEM_addr(DC_addr),
    .OUT_MEM_writeData(DC_dataIn),
    .OUT_MEM_writeEnable(DC_we),
    .OUT_MEM_readEnable(DC_ce),
    .OUT_MEM_writeMask(DC_wm),
    
    .OUT_instrAddr(OUT_instrAddr),
    .OUT_instrReadEnable(OUT_instrReadEnable),
    .OUT_halt(OUT_halt),
    
    .OUT_GPIO_oe(),
    .OUT_GPIO(),
    .IN_GPIO(16'b0),
    .OUT_SPI_clk(),
    .OUT_SPI_mosi(),
    .IN_SPI_miso(1'b0),
    .OUT_instrMappingMiss(),
    .IN_instrMappingBase(32'b0),
    .IN_instrMappingHalfSize(1'b0)
);

always@(posedge clk) begin
    if (!DC_ce && !DC_we && DC_wm == 4'b0001 && DC_addr == 30'h3F800000)
        $write("%c", DC_dataIn[7:0]);
end

endmodule
