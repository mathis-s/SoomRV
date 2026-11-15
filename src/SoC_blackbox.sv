(* black_box *) module SoC#(parameter WIDTH=128, parameter ADDR_LEN=32)
(
    input wire clk,
    input wire rst,
    input wire en,

    input wire IN_irq,

    output wire OUT_powerOff,
    output wire OUT_reboot,

    // write request
    output[`AXI_ID_LEN-1:0]  s_axi_awid,
    output[ADDR_LEN-1:0] s_axi_awaddr,
    output[7:0] s_axi_awlen,
    output[2:0] s_axi_awsize,
    output[1:0] s_axi_awburst,
    output[0:0] s_axi_awlock,
    output[3:0] s_axi_awcache,
    output s_axi_awvalid,
    input s_axi_awready,

    // write stream
    output[WIDTH-1:0] s_axi_wdata,
    output[(WIDTH/8)-1:0] s_axi_wstrb,
    output s_axi_wlast,
    output s_axi_wvalid,
    input s_axi_wready,

    // write response
    output s_axi_bready,
    input[`AXI_ID_LEN-1:0] s_axi_bid,
    input s_axi_bvalid,

    // read request
    output[`AXI_ID_LEN-1:0] s_axi_arid,
    output[ADDR_LEN-1:0] s_axi_araddr,
    output[7:0] s_axi_arlen,
    output[2:0] s_axi_arsize,
    output[1:0] s_axi_arburst,
    output[0:0] s_axi_arlock,
    output[3:0] s_axi_arcache,
    output s_axi_arvalid,
    input s_axi_arready,

    // read stream
    output s_axi_rready,
    input[`AXI_ID_LEN-1:0] s_axi_rid,
    input[WIDTH-1:0] s_axi_rdata,
    input s_axi_rlast,
    input s_axi_rvalid,

    output DebugInfo OUT_dbg,
    output DebugInfoMemC OUT_dbgMemC
);

endmodule
