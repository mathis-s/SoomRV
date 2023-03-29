module ACLINT#(parameter MTIME_ADDR=32'hFF000080, parameter MTIMECMP_ADDR=32'hFF000080)
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

`define READ(x) \
    begin \
        OUT_rdata <= x; \
        OUT_rvalid <= 1; \
    end


assign OUT_rbusy = 0;

reg[63:0] mtime;
reg[63:0] mtimecmp;

assign OUT_mtime = mtime;
assign OUT_mtimecmp = mtimecmp;

always_ff@(posedge clk) begin
    OUT_rvalid <= 0;
    
    if (rst) begin
        mtime <= 0;
        mtimecmp <= 0;
    end
    else begin
        
        mtime <= mtime + 1;
        
        if (IN_re) begin
            case ({IN_raddr, 2'b0})
                MTIME_ADDR + 0: `READ(mtime[31:0])
                MTIME_ADDR + 4: `READ(mtime[63:32])
                MTIMECMP_ADDR + 0: `READ(mtimecmp[31:0])
                MTIMECMP_ADDR + 4: `READ(mtimecmp[63:32])
            endcase
        end
        
        if (IN_we) begin
            case ({IN_waddr, 2'b0})
                MTIME_ADDR + 0: `WRITE(mtime[31:0])
                MTIME_ADDR + 4: `WRITE(mtime[63:32])
                MTIMECMP_ADDR + 0: `WRITE(mtimecmp[31:0])
                MTIMECMP_ADDR + 4: `WRITE(mtimecmp[63:32])
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
        spiCntI = 0;
    end
end

// Nonzero during SPI transfer
reg[5:0] spiCnt;
reg[31:0] buffer;

assign OUT_rbusy = spiCnt > 0;

always_ff@(posedge clk) begin
    
    OUT_rvalid <= 0;

    if (rst) begin
        spiCnt <= 0;
        buffer <= 0;
    end
    else begin            
        if (IN_re) begin
            if ({IN_raddr, 2'b0} == ADDR) begin
                OUT_rdata <= buffer;
                OUT_rvalid <= 1;
            end
            if ({IN_raddr, 2'b0} == ADDR+1) begin
                OUT_rdata <= 32'h60;
                OUT_rvalid <= 1;
            end
        end
        if (IN_we) begin
            if ({IN_waddr, 2'b0} == ADDR) begin
                case (IN_wmask)
                    default: begin
                        spiCnt <= 32;
                        buffer <= IN_wdata;
                    end
                    4'b0011: begin
                        spiCnt <= 16;
                        buffer <= {IN_wdata[15:0], 16'b0};
                    end
                    4'b0001: begin
                        spiCnt <= 8;
                        buffer <= {IN_wdata[7:0], 24'b0};
                    end
                endcase
                OUT_SPI_mosi <= IN_wdata[31];
                OUT_SPI_cs <= 0;
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
