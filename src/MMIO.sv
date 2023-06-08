
module MMIO
(
    input wire clk,
    input wire rst,
    
    IF_MMIO.MEM IF_mem,
    
    output reg OUT_powerOff,
    output reg OUT_reboot,
    
    IF_CSR_MMIO.MMIO OUT_csrIf
);


// Registered Inputs
reg reReg;
reg weReg;
reg[3:0] wmReg;
reg[31:0] writeAddrReg;
reg[31:0] readAddrReg;
reg[31:0] dataReg;

assign IF_mem.rbusy = 0;
assign IF_mem.wbusy = aclintBusy || sysConBusy || weReg;

wire[31:0] aclintData;
wire aclintBusy;
wire aclintRValid;
ACLINT aclint
(
    .clk(clk),
    .rst(rst),
    
    .IN_re(reReg),
    .IN_raddr(readAddrReg[31:2]),
    .OUT_rdata(aclintData),
    .OUT_rbusy(aclintBusy),
    .OUT_rvalid(aclintRValid),
    
    .IN_we(weReg),
    .IN_wmask(wmReg),
    .IN_waddr(writeAddrReg[31:2]),
    .IN_wdata(dataReg),
    
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
    
    .IN_re(reReg),
    .IN_raddr(readAddrReg[31:2]),
    .OUT_rdata(sysConData),
    .OUT_rbusy(sysConBusy),
    .OUT_rvalid(sysConRValid),
    
    .IN_we(weReg),
    .IN_wmask(wmReg),
    .IN_waddr(writeAddrReg[31:2]),
    .IN_wdata(dataReg),
    
    .OUT_powerOff(OUT_powerOff),
    .OUT_reboot(OUT_reboot)
    
);

always_comb begin
    IF_mem.rdata = 'x;
    if (aclintRValid) IF_mem.rdata = aclintData;
    if (sysConRValid) IF_mem.rdata = sysConData;
end

always_ff@(posedge clk) begin
    
    if (rst) begin
        weReg <= 0;
        reReg <= 0;
    end
    else begin
        reReg <= !IF_mem.re;
        weReg <= !IF_mem.we;
        wmReg <= IF_mem.wmask;
        readAddrReg <= IF_mem.raddr;
        writeAddrReg <= IF_mem.waddr;
        dataReg <= IF_mem.wdata;
    end

end

endmodule
