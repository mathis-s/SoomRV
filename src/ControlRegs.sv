
module ControlRegs
#
(
    parameter NUM_UOPS=4,
    parameter NUM_WBS=4
)
(
    input wire clk,
    input wire rst,
    input wire IN_mispredFlush,
    
    input wire IN_we,
    input wire[3:0] IN_wm,
    input wire[6:0] IN_writeAddr,
    input wire[31:0] IN_data,
    
    input wire IN_re,
    input wire[6:0] IN_readAddr,
    output reg[31:0] OUT_data,
    
    
    // Various Signals to update perf counters
    input wire[NUM_UOPS-1:0] IN_comValid,
    input wire IN_branchMispred,
    input wire IN_wbValid[NUM_WBS-1:0],
    input wire[NUM_UOPS-1:0] IN_ifValid,
    input wire IN_comBranch[NUM_UOPS-1:0],
    
    output reg OUT_SPI_cs,
    output reg OUT_SPI_clk,
    output reg OUT_SPI_mosi,
    input wire IN_SPI_miso,
    
    output ModeFlags OUT_mode,
    output wire[63:0] OUT_wmask,
    output wire[63:0] OUT_rmask,
    
    output reg OUT_tmrIRQ,
    output wire OUT_IO_busy
);

integer i;

// Registered Inputs
reg reReg;
reg weReg;
reg[3:0] wmReg;
reg[6:0] writeAddrReg;
reg[6:0] readAddrReg;
reg[31:0] dataReg;


// 64-bit Regs
// 0 CR_cycles 80
// 1 CR_decInstrs 88
// 2 CR_exeInstrs 90
// 3 CR_comInstrs 98
// 4 CR_invalids a0
// 5 CR_branches a8
reg[63:0] cRegs64[5:0];


// 32-bit Control Regs
//  0 SPI out/in
//  1 IRQ handler (4)
//  2 IRQ src (8)
//  3 8 mode (15) | 8 IRQ flags (14) | 16 TIMER IRQ count (12) 
//  4 rmask0
//  5 rmask1
//  6 wmask2
//  7 wmask3

reg[31:0] cRegs[15:0];

// Nonzero during SPI transfer
reg[5:0] spiCnt;
reg[25:0] tmrCnt;

assign OUT_IO_busy = (spiCnt > 0) || (!IN_we) || !weReg;
reg[3:0] ifetchValidReg;

assign OUT_rmask = {cRegs[5], cRegs[4]};
assign OUT_wmask = {cRegs[7], cRegs[6]};
assign OUT_mode = cRegs[3][31:24];

always_ff@(posedge clk) begin
    
    OUT_tmrIRQ <= 0;
    ifetchValidReg <= IN_ifValid;
    
    if (rst) begin
        weReg <= 1;
        for (i = 0; i < 6; i=i+1)
            cRegs64[i] <= 0;
            
        for (i = 0; i < 8; i=i+1)
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
                
                // No need to have perf counters writeable for now
                
                // Upper
                /*if (addrReg[0]) begin
                    if (wmReg[0]) cRegs64[addrReg[3:1]][39:32] <= dataReg[7:0];
                    if (wmReg[1]) cRegs64[addrReg[3:1]][47:40] <= dataReg[15:8];
                    if (wmReg[2]) cRegs64[addrReg[3:1]][55:48] <= dataReg[23:16];
                    if (wmReg[3]) cRegs64[addrReg[3:1]][63:56] <= dataReg[31:24];
                end
                // Lower
                else begin
                    if (wmReg[0]) cRegs64[addrReg[3:1]][7:0] <= dataReg[7:0];
                    if (wmReg[1]) cRegs64[addrReg[3:1]][15:8] <= dataReg[15:8];
                    if (wmReg[2]) cRegs64[addrReg[3:1]][23:16] <= dataReg[23:16];
                    if (wmReg[3]) cRegs64[addrReg[3:1]][31:24] <= dataReg[31:24];
                end*/
            end
            else begin
                if (wmReg[0]) cRegs[writeAddrReg[3:0]][7:0] <= dataReg[7:0];
                if (wmReg[1]) cRegs[writeAddrReg[3:0]][15:8] <= dataReg[15:8];
                if (wmReg[2]) cRegs[writeAddrReg[3:0]][23:16] <= dataReg[23:16];
                if (wmReg[3]) cRegs[writeAddrReg[3:0]][31:24] <= dataReg[31:24];
                
                if (writeAddrReg[3:0] == 4'd3 && (|wmReg[1:0]))
                    tmrCnt <= 0;
                    
                if (writeAddrReg[4:0] == 0) begin
                    case (wmReg)
                        4'b1111: spiCnt <= 32;
                        4'b1100: spiCnt <= 16;
                        4'b1000: spiCnt <= 8;
                        default: begin end
                    endcase
                    OUT_SPI_mosi <= dataReg[31];
                    OUT_SPI_cs <= 0;
                end
            end
        end
        
        if (!reReg) begin
            if (readAddrReg[5]) begin
                if (readAddrReg[0])
                    OUT_data <= cRegs64[readAddrReg[3:1]][63:32];
                else
                    OUT_data <= cRegs64[readAddrReg[3:1]][31:0];
            end
            else begin
                OUT_data <= cRegs[readAddrReg[3:0]];
            end
        end
        
        // Timer interrupt is active in user mode
        if (OUT_mode[0]) begin
            if (cRegs[3][15:0] != 0 && cRegs[3][15:0] == tmrCnt[25:10]) begin
                OUT_tmrIRQ <= 1;
                tmrCnt <= 0;
            end
            else tmrCnt <= tmrCnt + 1;
        end
        
        reReg <= IN_re;
        weReg <= IN_we;
        wmReg <= IN_wm;
        readAddrReg <= IN_readAddr;
        writeAddrReg <= IN_writeAddr;
        dataReg <= IN_data;

        // Update Perf Counters
        cRegs64[0] <= cRegs64[0] + 1;
        cRegs64[1] = cRegs64[1] + 1;
        
        for (i = 0; i < NUM_UOPS; i=i+1) begin
        
            if (ifetchValidReg[i])
                cRegs64[1] = cRegs64[1] + 1;
            if (IN_comValid[i] && !IN_mispredFlush)
                cRegs64[3] = cRegs64[3] + 1;
            if (IN_comValid[i] && !IN_mispredFlush && IN_comBranch[i])
                cRegs64[5] = cRegs64[5] + 1;
        end
        for (i = 0; i < NUM_WBS; i=i+1) begin
            if (IN_wbValid[i])
                cRegs64[2] = cRegs64[2] + 1;
        end
        if (IN_branchMispred)
            cRegs64[4] <= cRegs64[4] + 1;
        
    end

end

endmodule
