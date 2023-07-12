
module MMIO
(
    input wire clk,
    input wire rst,
    
    IF_MMIO.MEM IF_mem,
    
    output reg OUT_powerOff,
    output reg OUT_reboot,
    
    IF_CSR_MMIO.MMIO OUT_csrIf
);

assign IF_mem.rbusy = 0;
assign IF_mem.wbusy = aclintBusy || sysConBusy || (!IF_mem.we);

wire[31:0] aclintData;
wire aclintBusy;
wire aclintRValid;
ACLINT aclint
(
    .clk(clk),
    .rst(rst),
    
    .IN_re(!IF_mem.re),
    .IN_raddr(IF_mem.raddr[31:2]),
    .OUT_rdata(aclintData),
    .OUT_rbusy(aclintBusy),
    .OUT_rvalid(aclintRValid),
    
    .IN_we(!IF_mem.we),
    .IN_wmask(IF_mem.wmask),
    .IN_waddr(IF_mem.waddr[31:2]),
    .IN_wdata(IF_mem.wdata),
    
    .OUT_mtime(OUT_csrIf.mtime),
    .OUT_mtimecmp(OUT_csrIf.mtimecmp)
);

wire[31:0] sysConData;
wire sysConBusy;
wire sysConRValid;
SysCon#(.ADDR(`SYSCON_ADDR)) sysCon
(
    .clk(clk),
    .rst(rst),
    
    .IN_re(!IF_mem.re),
    .IN_raddr(IF_mem.raddr[31:2]),
    .OUT_rdata(sysConData),
    .OUT_rbusy(sysConBusy),
    .OUT_rvalid(sysConRValid),
    
    .IN_we(!IF_mem.we),
    .IN_wmask(IF_mem.wmask),
    .IN_waddr(IF_mem.waddr[31:2]),
    .IN_wdata(IF_mem.wdata),
    
    .OUT_powerOff(OUT_powerOff),
    .OUT_reboot(OUT_reboot)
);

always_comb begin
    IF_mem.rdata = 'x;
    if (aclintRValid) IF_mem.rdata = aclintData;
    if (sysConRValid) IF_mem.rdata = sysConData;
end

endmodule
