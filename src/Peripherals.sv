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

always_ff@(posedge clk or posedge rst) begin
    OUT_rvalid <= 0;

    if (rst) begin
        mtime <= 0;
        mtimecmp <= 0;
    end
    else begin
        mtime <= mtime + 1;

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

always_ff@(posedge clk or posedge rst) begin

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
