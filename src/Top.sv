
module Top#(parameter WIDTH=128, parameter ID_LEN=2, parameter ADDR_LEN=32)
(
    input wire clk,
    input wire rst,
    input wire en,

    output wire OUT_halt
);

wire SOC_poweroff;
wire SOC_reboot;
assign OUT_halt = SOC_poweroff || SOC_reboot;

logic[ID_LEN-1:0]  s_axi_awid;
logic[ADDR_LEN-1:0] s_axi_awaddr;
logic[7:0] s_axi_awlen;
logic[2:0] s_axi_awsize;
logic[1:0] s_axi_awburst;
logic[0:0] s_axi_awlock;
logic[3:0] s_axi_awcache;
logic s_axi_awvalid;
logic s_axi_awready;
logic[WIDTH-1:0] s_axi_wdata;
logic[(WIDTH/8)-1:0] s_axi_wstrb;
logic s_axi_wlast;
logic s_axi_wvalid;
logic s_axi_wready;
logic s_axi_bready;
logic[ID_LEN-1:0] s_axi_bid;
logic s_axi_bvalid;
logic[ID_LEN-1:0] s_axi_arid;
logic[ADDR_LEN-1:0] s_axi_araddr;
logic[7:0] s_axi_arlen;
logic[2:0] s_axi_arsize;
logic[1:0] s_axi_arburst;
logic[0:0] s_axi_arlock;
logic[3:0] s_axi_arcache;
logic s_axi_arvalid;
logic s_axi_arready;
logic s_axi_rready;
logic[ID_LEN-1:0] s_axi_rid;
logic[WIDTH-1:0] s_axi_rdata;
logic s_axi_rlast;
logic s_axi_rvalid;

ExternalAXISim extMem
(
    .clk(clk),

    .s_axi_awid(s_axi_awid),
    .s_axi_awaddr(s_axi_awaddr),
    .s_axi_awlen(s_axi_awlen),
    .s_axi_awsize(s_axi_awsize),
    .s_axi_awburst(s_axi_awburst),
    .s_axi_awlock(s_axi_awlock),
    .s_axi_awcache(s_axi_awcache),
    .s_axi_awvalid(s_axi_awvalid),
    .s_axi_awready(s_axi_awready),
    .s_axi_wdata(s_axi_wdata),
    .s_axi_wstrb(s_axi_wstrb),
    .s_axi_wlast(s_axi_wlast),
    .s_axi_wvalid(s_axi_wvalid),
    .s_axi_wready(s_axi_wready),
    .s_axi_bready(s_axi_bready),
    .s_axi_bid(s_axi_bid),
    .s_axi_bvalid(s_axi_bvalid),
    .s_axi_arid(s_axi_arid),
    .s_axi_araddr(s_axi_araddr),
    .s_axi_arlen(s_axi_arlen),
    .s_axi_arsize(s_axi_arsize),
    .s_axi_arburst(s_axi_arburst),
    .s_axi_arlock(s_axi_arlock),
    .s_axi_arcache(s_axi_arcache),
    .s_axi_arvalid(s_axi_arvalid),
    .s_axi_arready(s_axi_arready),
    .s_axi_rready(s_axi_rready),
    .s_axi_rid(s_axi_rid),
    .s_axi_rdata(s_axi_rdata),
    .s_axi_rlast(s_axi_rlast),
    .s_axi_rvalid(s_axi_rvalid)
);

SoC soc
(
    .clk(clk),
    .rst(rst),
    .en(en),
    
    .OUT_powerOff(SOC_poweroff),
    .OUT_reboot(SOC_reboot),

    .s_axi_awid(s_axi_awid),
    .s_axi_awaddr(s_axi_awaddr),
    .s_axi_awlen(s_axi_awlen),
    .s_axi_awsize(s_axi_awsize),
    .s_axi_awburst(s_axi_awburst),
    .s_axi_awlock(s_axi_awlock),
    .s_axi_awcache(s_axi_awcache),
    .s_axi_awvalid(s_axi_awvalid),
    .s_axi_awready(s_axi_awready),
    .s_axi_wdata(s_axi_wdata),
    .s_axi_wstrb(s_axi_wstrb),
    .s_axi_wlast(s_axi_wlast),
    .s_axi_wvalid(s_axi_wvalid),
    .s_axi_wready(s_axi_wready),
    .s_axi_bready(s_axi_bready),
    .s_axi_bid(s_axi_bid),
    .s_axi_bvalid(s_axi_bvalid),
    .s_axi_arid(s_axi_arid),
    .s_axi_araddr(s_axi_araddr),
    .s_axi_arlen(s_axi_arlen),
    .s_axi_arsize(s_axi_arsize),
    .s_axi_arburst(s_axi_arburst),
    .s_axi_arlock(s_axi_arlock),
    .s_axi_arcache(s_axi_arcache),
    .s_axi_arvalid(s_axi_arvalid),
    .s_axi_arready(s_axi_arready),
    .s_axi_rready(s_axi_rready),
    .s_axi_rid(s_axi_rid),
    .s_axi_rdata(s_axi_rdata),
    .s_axi_rlast(s_axi_rlast),
    .s_axi_rvalid(s_axi_rvalid)
);

endmodule
