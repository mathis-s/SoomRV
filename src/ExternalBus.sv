
module ExternalBus#(parameter WIDTH=32, parameter ADDR_LEN=32)
(
    input logic clk,
    input logic rst,

    output logic OUT_busOE,
    output logic[WIDTH-1:0] OUT_bus,
    input logic[WIDTH-1:0] IN_bus,
    output logic OUT_busValid,
    input logic IN_busReady,

    input logic[`AXI_ID_LEN-1:0]  s_axi_awid, // write req id
    input logic[ADDR_LEN-1:0] s_axi_awaddr, // write addr
    input logic[7:0] s_axi_awlen, // write len
    input logic[2:0] s_axi_awsize, // word size
    input logic[1:0] s_axi_awburst, // FIXED, INCR, WRAP, RESERVED
    input logic[0:0] s_axi_awlock, // exclusive access
    input logic[3:0] s_axi_awcache, // {allocate, other allocate, modifiable, bufferable}
    input logic s_axi_awvalid,
    output logic s_axi_awready,

    // write stream
    input logic [WIDTH-1:0] s_axi_wdata,
    input logic [(WIDTH/8)-1:0] s_axi_wstrb,
    input logic s_axi_wlast,
    input logic s_axi_wvalid,
    output logic s_axi_wready,

    // write response
    input logic s_axi_bready,
    output logic[`AXI_ID_LEN-1:0] s_axi_bid,
    output logic s_axi_bvalid,

    // read request
    input logic[`AXI_ID_LEN-1:0] s_axi_arid,
    input logic[ADDR_LEN-1:0] s_axi_araddr,
    input logic[7:0] s_axi_arlen,
    input logic[2:0] s_axi_arsize,
    input logic[1:0] s_axi_arburst,
    input logic[0:0] s_axi_arlock,
    input logic[3:0] s_axi_arcache,
    input logic s_axi_arvalid,
    output logic s_axi_arready,

    // read stream
    input logic s_axi_rready,
    output logic[`AXI_ID_LEN-1:0] s_axi_rid,
    output logic[WIDTH-1:0] s_axi_rdata,
    //output logic[1:0] s_axi_rresp,
    output logic s_axi_rlast,
    output logic s_axi_rvalid
);

localparam COUNT_LEN = `CLSIZE_E - 2;

enum logic[2:0]
{
    IDLE,
    READ,
    WRITE,
    READ_MMIO,
    WRITE_MMIO
} state;

typedef struct packed
{
    logic isWrite;
    logic[1:0] size;
    logic[28:0] addr;
} BusAddr;

always_comb begin
    s_axi_wready = 0;
    s_axi_rvalid = 0;

    OUT_busOE = 1;
    OUT_bus = '0;
    OUT_busValid = 0;

    s_axi_rvalid = 0;
    s_axi_rid = 'x;
    s_axi_rdata = 'x;
    s_axi_rlast = 'x;

    case (state)
        IDLE: begin
            if (s_axi_arvalid) begin
                OUT_busValid = 1;
                OUT_busOE = 1;
                OUT_bus = BusAddr'{
                    isWrite: 0,
                    size: (s_axi_arlen == 0) ? s_axi_arsize[1:0] : 2'b11,
                    addr: s_axi_araddr[28:0]
                };
            end
            else if (s_axi_awvalid) begin
                OUT_busValid = 1;
                OUT_busOE = 1;
                OUT_bus = BusAddr'{
                    isWrite: 1,
                    size: (s_axi_awlen == 0) ? s_axi_awsize[1:0] : 2'b11,
                    addr: s_axi_awaddr[28:0]
                };
            end
        end

        READ,
        READ_MMIO: begin
            OUT_busValid = s_axi_rready;

            s_axi_rvalid = IN_busReady;
            s_axi_rid = curID;
            s_axi_rlast = (curCnt == {COUNT_LEN{1'b1}});
            s_axi_rdata = IN_bus;
            OUT_busOE = 0;
        end

        WRITE,
        WRITE_MMIO: begin
            s_axi_wready = IN_busReady;
            OUT_busValid = s_axi_wvalid;
            OUT_bus = s_axi_wdata;
            OUT_busOE = 1;
        end
        default: ;
    endcase
end

reg[$clog2(`AXI_NUM_TRANS)-1:0] curID;
reg[COUNT_LEN-1:0] curCnt;
always_ff@(posedge clk or posedge rst) begin

    s_axi_awready <= 0;
    s_axi_arready <= 0;
    s_axi_bvalid <= 0;
    s_axi_bid <= 'x;

    if (rst) state <= IDLE;
    else begin
        case (state)
            IDLE: begin
                if (s_axi_arvalid) begin
                    if (IN_busReady) begin
                        s_axi_arready <= 1;
                        state <= (s_axi_arlen == 0) ? READ_MMIO : READ;
                        curID <= s_axi_arid;
                        curCnt <= (s_axi_arlen == 0) ? {COUNT_LEN{1'b1}} : {COUNT_LEN{1'b0}};
                    end
                end
                else if (s_axi_awvalid) begin
                    if (IN_busReady) begin
                        s_axi_awready <= 1;
                        state <= (s_axi_awlen == 0) ? WRITE_MMIO : WRITE;
                        curID <= s_axi_awid;
                        curCnt <= (s_axi_awlen == 0) ? {COUNT_LEN{1'b1}} : {COUNT_LEN{1'b0}};
                    end
                end
            end

            READ,
            READ_MMIO: begin
                if (s_axi_rready && s_axi_rvalid) begin
                    curCnt <= curCnt + 1;
                    if (s_axi_rlast) begin
                        curCnt <= 'x;
                        state <= IDLE;
                    end
                end
            end
            WRITE,
            WRITE_MMIO: begin
                if (s_axi_wready && s_axi_wvalid) begin
                    curCnt <= curCnt + 1;
                    if (s_axi_wlast) begin
                        assert(curCnt == {COUNT_LEN{1'b1}});
                        curCnt <= 'x;
                        state <= IDLE;

                        s_axi_bvalid <= 1;
                        s_axi_bid <= curID;
                    end
                end
            end
            default: state <= IDLE;
        endcase
    end
end

endmodule
