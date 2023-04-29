module ACLINT
(
    input wire clk,
    input wire rst,

    input wire IN_re,
    input wire[29:0] IN_raddr,
    output reg[31:0] OUT_rdata,
    output wire OUT_rbusy,
    output reg OUT_rvalid,

    input wire IN_we,
    input wire[3:0] IN_wmask,
    input wire[29:0] IN_waddr,
    input wire[31:0] IN_wdata,

    output wire[63:0] OUT_mtime,
    output wire[63:0] OUT_mtimecmp
    
);

`define WRITE(x) \
    begin \
        if (IN_wmask[0]) x[7:0] <= IN_wdata[7:0]; \
        if (IN_wmask[1]) x[15:8] <= IN_wdata[15:8]; \
        if (IN_wmask[2]) x[23:16] <= IN_wdata[23:16]; \
        if (IN_wmask[3]) x[31:24] <= IN_wdata[31:24]; \
    end

`define WRITE_L32(x) \
    begin \
        if (IN_wmask[0]) x[7:0] <= IN_wdata[7:0]; \
        if (IN_wmask[1]) x[15:8] <= IN_wdata[15:8]; \
        if (IN_wmask[2]) x[23:16] <= IN_wdata[23:16]; \
        if (IN_wmask[3]) x[31:24] <= IN_wdata[31:24]; \
    end

`define WRITE_H32(x) \
    begin \
        if (IN_wmask[0]) x[39:32] <= IN_wdata[7:0]; \
        if (IN_wmask[1]) x[47:40] <= IN_wdata[15:8]; \
        if (IN_wmask[2]) x[55:48] <= IN_wdata[23:16]; \
        if (IN_wmask[3]) x[63:56] <= IN_wdata[31:24]; \
    end
    
`define READ(x) \
    begin \
        OUT_rdata <= x; \
        OUT_rvalid <= 1; \
    end


assign OUT_rbusy = 0;

reg[63:0] mtime;
reg[63:0] mtimecmp;

reg[19:0] divCnt;

assign OUT_mtime = mtime;
assign OUT_mtimecmp = mtimecmp;

always_ff@(posedge clk) begin
    OUT_rvalid <= 0;
    
    if (rst) begin
        mtime <= 0;
        mtimecmp <= 0;
        divCnt <= 99;
    end
    else begin
        
        if (divCnt == 0) begin
            mtime <= mtime + 1;
            divCnt <= 99;
        end
        else divCnt <= divCnt - 1;
        
        if (IN_re) begin
            case ({IN_raddr, 2'b0})
                `MTIME_ADDR + 0: `READ(mtime[31:0])
                `MTIME_ADDR + 4: `READ(mtime[63:32])
                `MTIMECMP_ADDR + 0: `READ(mtimecmp[31:0])
                `MTIMECMP_ADDR + 4: `READ(mtimecmp[63:32])
            endcase
        end
        
        if (IN_we) begin
            case ({IN_waddr, 2'b0})
                `MTIME_ADDR + 0: `WRITE_L32(mtime)
                `MTIME_ADDR + 4: `WRITE_H32(mtime)
                `MTIMECMP_ADDR + 0: `WRITE_L32(mtimecmp)
                `MTIMECMP_ADDR + 4: `WRITE_H32(mtimecmp)
            endcase
        end
    end
end
endmodule

module SPI#(parameter ADDR=32'hFF000000)
(
    input wire clk,
    input wire rst,

    input wire IN_re,
    input wire[29:0] IN_raddr,
    output reg[31:0] OUT_rdata,
    output wire OUT_rbusy,
    output reg OUT_rvalid,

    input wire IN_we,
    input wire[3:0] IN_wmask,
    input wire[29:0] IN_waddr,
    input wire[31:0] IN_wdata,
    
    output reg OUT_SPI_cs,
    output reg OUT_SPI_clk,
    output reg OUT_SPI_mosi,
    input wire IN_SPI_miso
);

integer spiCntI = 0;
reg[7:0] spiByte = 0;
always@(posedge OUT_SPI_clk) begin
    spiByte = {spiByte[6:0], OUT_SPI_mosi};
    spiCntI = spiCntI + 1;
    if (spiCntI == 8) begin
        $write("%c", spiByte);
        $fflush(32'h80000001);
        spiCntI = 0;
    end
end

// Nonzero during SPI transfer
reg[5:0] spiCnt;
reg[31:0] buffer;

reg readValid /* verilator public */;
reg[7:0] readData /* verilator public */;

assign OUT_rbusy = spiCnt > 0;

always_ff@(posedge clk) begin
    
    OUT_rvalid <= 0;

    if (rst) begin
        spiCnt <= 0;
        buffer <= 0;
        readValid <= 0;
    end
    else begin            
        if (IN_re) begin
            if ({IN_raddr, 2'b0} == ADDR) begin
                OUT_rdata <= {24'b0, readData};
                readValid <= 0;
                OUT_rvalid <= 1;
            end
            if ({IN_raddr, 2'b0} == ADDR+4) begin
                OUT_rdata <= 32'h6000 | (readValid ? 32'h0100 : 32'h0);
                OUT_rvalid <= 1;
            end
        end
        if (IN_we) begin
            if ({IN_waddr, 2'b0} == ADDR) begin
                case (IN_wmask)
                    default: begin
                        spiCnt <= 32;
                        buffer <= IN_wdata;
                        OUT_SPI_mosi <= IN_wdata[31];
                    end
                    4'b0011: begin
                        spiCnt <= 16;
                        buffer <= {IN_wdata[15:0], 16'b0};
                        OUT_SPI_mosi <= IN_wdata[15];
                    end
                    4'b0001: begin
                        spiCnt <= 8;
                        buffer <= {IN_wdata[7:0], 24'b0};
                        OUT_SPI_mosi <= IN_wdata[7];
                    end
                endcase
                OUT_SPI_cs <= 0;
                OUT_SPI_clk <= 0;
            end
        end
                
        if (OUT_SPI_clk == 1) begin
            OUT_SPI_clk <= 0;
            OUT_SPI_mosi <= buffer[31];
        end
        else if (spiCnt != 0) begin
            OUT_SPI_clk <= 1;
            spiCnt <= spiCnt - 1;
            buffer <= {buffer[30:0], IN_SPI_miso};
        end
        if (spiCnt == 0)
            OUT_SPI_cs <= 1;
    end
end
endmodule

`ifdef ENABLE_UART
module UART#(parameter ADDR=32'hFF000000)
(
    input wire clk,
    input wire rst,

    input wire IN_re,
    input wire[29:0] IN_raddr,
    output reg[31:0] OUT_rdata,
    output wire OUT_rbusy,
    output reg OUT_rvalid,

    input wire IN_we,
    input wire[3:0] IN_wmask,
    input wire[29:0] IN_waddr,
    input wire[31:0] IN_wdata,
    
    output wire OUT_uartTX,
    input wire IN_uartRX
);

reg[15:0] divider = 87;

wire[7:0] UART_rdata;
wire UART_readReady;
Uart#(.CLOCK_DIVIDER_WIDTH(16)) uart
(
    .reset_i(rst),
    .clock_i(clk),
    .clock_divider_i(divider),
    .serial_i(IN_uartRX),
    .serial_o(OUT_uartTX),
    
    .data_i(IN_wdata[7:0]),
    .data_o(UART_rdata),

    .write_i(IN_we && {IN_waddr, 2'b0} == ADDR && IN_wmask[0]),
    .write_busy_o(OUT_rbusy),
    
    .read_ready_o(UART_readReady),
    .ack_i(IN_re && {IN_raddr, 2'b0} == ADDR),

    .two_stop_bits_i(0),
    .parity_bit_i(0),
    .parity_even_i()

);

always_ff@(posedge clk) begin
    
    OUT_rvalid <= 0;

    if (rst) begin
        divider <= 87; // 115200 baud @ 10MHz
    end
    else begin            
        if (IN_re) begin
            if ({IN_raddr, 2'b0} == ADDR) begin
                OUT_rdata <= {24'b0, UART_rdata};
                OUT_rvalid <= 1;
            end
            if ({IN_raddr, 2'b0} == ADDR+4) begin
                OUT_rdata <= 32'h6000 | (UART_readReady ? 32'h0100 : 32'h0);
                OUT_rvalid <= 1;
            end
        end

        if (IN_we) begin
            if ({IN_waddr, 2'b0} == ADDR + 16) begin
                if (IN_wmask[0]) divider[7:0] <= IN_wdata[7:0];
                if (IN_wmask[1]) divider[15:8] <= IN_wdata[15:8];
            end
        end
    end
end
endmodule
`endif

module SysCon#(ADDR=32'hFF000004)
(
    input wire clk,
    input wire rst,

    input wire IN_re,
    input wire[29:0] IN_raddr,
    output reg[31:0] OUT_rdata,
    output wire OUT_rbusy,
    output reg OUT_rvalid,

    input wire IN_we,
    input wire[3:0] IN_wmask,
    input wire[29:0] IN_waddr,
    input wire[31:0] IN_wdata,

    output reg OUT_powerOff,
    output reg OUT_reboot
    
);

assign OUT_rbusy = 0;
assign OUT_rdata = 0;
assign OUT_rvalid = 0;

always_ff@(posedge clk) begin
    
    OUT_powerOff <= 0;
    OUT_reboot <= 0;
    
    if (rst) begin
        
    end
    else begin
        if (IN_we) begin
            if ({IN_waddr, 2'b0} == ADDR) begin
                if (IN_wmask[0]) begin
                    if (IN_wdata[7:0] == 8'h77) OUT_reboot <= 1;
                    if (IN_wdata[7:0] == 8'h55) OUT_powerOff <= 1;
                end
            end
        end
    end
end
endmodule
