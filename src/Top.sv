
module Top#(parameter WIDTH=`AXI_WIDTH, parameter ADDR_LEN=32)
(
    input wire clk,
    input wire rst,
    input wire en,

    output wire OUT_halt
);

wire SOC_poweroff;
wire SOC_reboot;
assign OUT_halt = SOC_poweroff || SOC_reboot;

wire soomrv_busOE;
wire extmem_busOE;
wire[31:0] busOut;
wire[31:0] busIn;
wire busValid;
wire busReady;

ExternalBusMem extMem
(
    .clk(clk),
    .rst(rst),

    .OUT_busOE(extmem_busOE),
    .OUT_bus(busIn),
    .IN_bus(busOut),
    .OUT_busReady(busReady),
    .IN_busValid(busValid)
);

SoC soc
(
    .clk(clk),
    .rst(rst),
    .en(en),

    .IN_irq(1'b0),

    .OUT_powerOff(SOC_poweroff),
    .OUT_reboot(SOC_reboot),

    .OUT_busOE(soomrv_busOE),
    .OUT_bus(busOut),
    .IN_bus(busIn),
    .OUT_busValid(busValid),
    .IN_busReady(busReady),

    .OUT_dbg(),
    .OUT_dbgMemC()
);

endmodule
