
module MMIO
(
    input wire clk,
    input wire rst,
    
    IF_Mem.MEM IF_mem,
    
    output reg OUT_SPI_cs,
    output reg OUT_SPI_clk,
    output reg OUT_SPI_mosi,
    input wire IN_SPI_miso,
    
    output reg OUT_powerOff,
    output reg OUT_reboot,
    
    IF_CSR_MMIO.MMIO OUT_csrIf
);

integer i;

integer spiCntI = 0;
reg[7:0] spiByte = 0;
always@(posedge OUT_SPI_clk) begin
    spiByte = {spiByte[6:0], OUT_SPI_mosi};
    spiCntI = spiCntI + 1;
    if (spiCntI == 8) begin
        $write("%c", spiByte);
        spiCntI = 0;
    end
end

// Registered Inputs
reg reReg;
reg weReg;
reg[3:0] wmReg;
reg[6:0] writeAddrReg;
reg[6:0] readAddrReg;
reg[31:0] dataReg;


// 64-bit Memory Mapped Regs
// 0 mtime 80
// 1 mtimecmp 88
reg[63:0] cRegs64[1:0];


// 32-bit Memory Mapped Regs
//  0 SPI out/in
//  1 unused
//  2 unused
//  3 unused

reg[31:0] cRegs[3:0];

// Nonzero during SPI transfer
reg[5:0] spiCnt;

wire ioWriteBusy = (spiCnt > 0) || (!IF_mem.we) || !weReg;
assign IF_mem.rbusy = 0;
assign IF_mem.wbusy = ioWriteBusy;

assign OUT_csrIf.mtime = cRegs64[0];
assign OUT_csrIf.mtimecmp = cRegs64[1];

always_ff@(posedge clk) begin
    
    cRegs64[0] <= cRegs64[0] + 1;
    OUT_powerOff <= 0;
    OUT_reboot <= 0;
    
    if (rst) begin
        weReg <= 1;
        for (i = 0; i < 2; i=i+1)
            cRegs64[i] <= 0;
            
        for (i = 0; i < 4; i=i+1)
            cRegs[i] <= 0; 
        
        OUT_SPI_clk <= 0;
        spiCnt <= 0;
        OUT_SPI_cs <= 1;
        OUT_SPI_mosi <= 0;
    end
    else begin
        
        if (OUT_SPI_clk == 1) begin
            OUT_SPI_clk <= 0;
            OUT_SPI_mosi <= cRegs[0][31];
        end
        else if (spiCnt != 0) begin
            OUT_SPI_clk <= 1;
            spiCnt <= spiCnt - 1;
            cRegs[0] <= {cRegs[0][30:0], IN_SPI_miso};
        end
        if (spiCnt == 0)
            OUT_SPI_cs <= 1;
        

        if (!weReg) begin
            // 64-bit
            if (writeAddrReg[5]) begin
                // Upper
                if (writeAddrReg[0]) begin
                    if (wmReg[0]) cRegs64[writeAddrReg[1:1]][39:32] <= dataReg[7:0];
                    if (wmReg[1]) cRegs64[writeAddrReg[1:1]][47:40] <= dataReg[15:8];
                    if (wmReg[2]) cRegs64[writeAddrReg[1:1]][55:48] <= dataReg[23:16];
                    if (wmReg[3]) cRegs64[writeAddrReg[1:1]][63:56] <= dataReg[31:24];
                end
                // Lower
                else begin
                    if (wmReg[0]) cRegs64[writeAddrReg[1:1]][7:0] <= dataReg[7:0];
                    if (wmReg[1]) cRegs64[writeAddrReg[1:1]][15:8] <= dataReg[15:8];
                    if (wmReg[2]) cRegs64[writeAddrReg[1:1]][23:16] <= dataReg[23:16];
                    if (wmReg[3]) cRegs64[writeAddrReg[1:1]][31:24] <= dataReg[31:24];
                end
            end
            // 32-bit
            else begin
                if (wmReg[0]) cRegs[writeAddrReg[1:0]][7:0] <= dataReg[7:0];
                if (wmReg[1]) cRegs[writeAddrReg[1:0]][15:8] <= dataReg[15:8];
                if (wmReg[2]) cRegs[writeAddrReg[1:0]][23:16] <= dataReg[23:16];
                if (wmReg[3]) cRegs[writeAddrReg[1:0]][31:24] <= dataReg[31:24];
                
                // SPI
                if (writeAddrReg[1:0] == 0) begin
                    case (wmReg)
                        4'b1111: spiCnt <= 32;
                        4'b1100: spiCnt <= 16;
                        4'b1000: spiCnt <= 8;
                        default: begin end
                    endcase
                    OUT_SPI_mosi <= dataReg[31];
                    OUT_SPI_cs <= 0;
                end
                
                // SysCon
                if (writeAddrReg[1:0] == 1 && wmReg[0]) begin
                    if (dataReg[7:0] == 8'h77) OUT_reboot <= 1;
                    if (dataReg[7:0] == 8'h55) OUT_powerOff <= 1;
                end
            end
        end
        
        if (!reReg) begin
            if (readAddrReg[5]) begin
                if (readAddrReg[0])
                    IF_mem.rdata <= cRegs64[readAddrReg[1:1]][63:32];
                else
                    IF_mem.rdata <= cRegs64[readAddrReg[1:1]][31:0];
            end
            else begin
                IF_mem.rdata <= cRegs[readAddrReg[1:0]];
            end
        end
        
        reReg <= IF_mem.re;
        weReg <= IF_mem.we;
        wmReg <= IF_mem.wmask;
        readAddrReg <= IF_mem.raddr[6:0];
        writeAddrReg <= IF_mem.waddr[6:0];
        dataReg <= IF_mem.wdata;
    end

end

endmodule
