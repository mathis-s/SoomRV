
module Top
(
    input wire clk,
    input wire rst,
    input wire en,

    output wire OUT_halt
);

wire SOC_EXTMEM_oen;
wire EXTMEM_oen;

wire[31:0] EXTMEM_busOut;
wire[31:0] EXTMEM_bus;
wire EXTMEM_en;
wire EXTMEM_stall;
ExternalMemorySim extMem
(
    .clk(clk),
    .en(EXTMEM_en && !rst),

    .OUT_oen(EXTMEM_oen),
    .OUT_stall(EXTMEM_stall),
    .IN_bus(EXTMEM_busOut),
    .OUT_bus(EXTMEM_bus)
);

wire SOC_poweroff;
wire SOC_reboot;
assign OUT_halt = SOC_poweroff || SOC_reboot;

SoC soc
(
    .clk(clk),
    .rst(rst),
    .en(en),
    .OUT_busOEn(SOC_EXTMEM_oen),
    .OUT_busEn(EXTMEM_en),
    .OUT_bus(EXTMEM_busOut),
    .IN_busStall(EXTMEM_stall),
    .IN_bus(EXTMEM_bus),
    
    .OUT_powerOff(SOC_poweroff),
    .OUT_reboot(SOC_reboot)
);

endmodule
