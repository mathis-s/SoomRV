
// Address for the simulated 8250 UART stub
// This must be between EXT_MMIO_START_ADDR and EXT_MMIO_END_ADDR!
`define SERIAL_ADDR 32'h1000_0000

module ExternalAXISim
#(parameter ID_LEN=`AXI_ID_LEN, parameter WIDTH=`AXI_WIDTH, parameter ADDR_LEN=32)
(
    input wire clk,
    input wire rst,

    // write request
    input[ID_LEN-1:0]  s_axi_awid, // write req id
    input[ADDR_LEN-1:0] s_axi_awaddr, // write addr
    input[7:0] s_axi_awlen, // write len
    input[2:0] s_axi_awsize, // word size
    input[1:0] s_axi_awburst, // FIXED, INCR, WRAP, RESERVED
    input[0:0] s_axi_awlock, // exclusive access
    input[3:0] s_axi_awcache, // {allocate, other allocate, modifiable, bufferable}
    input s_axi_awvalid,
    output logic s_axi_awready,

    // write stream
    input[WIDTH-1:0] s_axi_wdata,
    input[(WIDTH/8)-1:0] s_axi_wstrb,
    input s_axi_wlast,
    input s_axi_wvalid,
    output logic s_axi_wready,

    // write response
    input s_axi_bready,
    output logic[ID_LEN-1:0] s_axi_bid,
    //output[1:0] s_axi_bresp,
    output logic s_axi_bvalid,

    // read request
    input[ID_LEN-1:0] s_axi_arid,
    input[ADDR_LEN-1:0] s_axi_araddr,
    input[7:0] s_axi_arlen,
    input[2:0] s_axi_arsize,
    input[1:0] s_axi_arburst,
    input[0:0] s_axi_arlock,
    input[3:0] s_axi_arcache, // {other allocate, allocate, modifiable, bufferable}
    input s_axi_arvalid,
    output logic s_axi_arready,

    // read stream
    input s_axi_rready,
    output logic[ID_LEN-1:0] s_axi_rid,
    output logic[WIDTH-1:0] s_axi_rdata,
    //output logic[1:0] s_axi_rresp,
    output logic s_axi_rlast,
    output logic s_axi_rvalid
);


localparam NUM_TFS = 1<<ID_LEN;
localparam BWIDTH = WIDTH / 8;
localparam MADDR_LEN = 28 - $clog2(WIDTH / 8);
localparam MEM_LEN = (1 << MADDR_LEN);

reg[WIDTH-1:0] mem[MEM_LEN-1:0] /*verilator public*/;

typedef enum logic[1:0]
{
    FIXED, INCR, WRAP
} BurstType;

typedef struct packed
{
    logic[7:0] cur;
    logic[7:0] len;
    BurstType btype;
    logic[ADDR_LEN-1:0] addr;
    logic valid;
} Transfer;

function logic[ADDR_LEN-1:0] GetCurAddr(Transfer t);
    case (t.btype)
    FIXED: return t.addr;
    INCR: return t.addr + (t.cur * BWIDTH);
    WRAP: return ((t.addr + (t.cur * BWIDTH)) & (t.len * BWIDTH)) | (t.addr & ~(t.len * BWIDTH));
    default: assert(0);
    endcase
    return -1;
endfunction

Transfer[NUM_TFS-1:0] tfs[1:0];
wire Transfer[NUM_TFS-1:0] reads = tfs[0];
wire Transfer[NUM_TFS-1:0] writes = tfs[1];
initial begin
    tfs[0] = '0;
    tfs[1] = '0;
end

// RTL sim input
logic inputAvail /*verilator public*/ = 0;
logic[7:0] inputByte /*verilator public*/;

// Read Data Output
logic readDataIdxValid;
logic[ID_LEN-1:0] readDataIdx;
always_comb begin
    readDataIdxValid = 0;
    readDataIdx = 'x;
    // could select index randomly to
    // simulate memory heterogeneity
    for (integer i = NUM_TFS - 1; i >= 0; i=i-1) begin
        if (reads[i].valid) begin
            readDataIdxValid = 1;
            readDataIdx = ID_LEN'(i);
        end
    end
end

always_ff@(posedge clk ) begin
    if (rst) ;
    else if (!(s_axi_rvalid && !s_axi_rready)) begin
        s_axi_rid <= 'x;
        //s_axi_rdata <= 'x;
        s_axi_rlast <= 'x;
        s_axi_rvalid <= 0;
        if (readDataIdxValid) begin
            reg last = (reads[readDataIdx].cur) == (reads[readDataIdx].len);
            reg[ADDR_LEN-1:0] addr = GetCurAddr(reads[readDataIdx]);

            s_axi_rid <= readDataIdx;
            s_axi_rlast <= last;
            s_axi_rvalid <= 1;

            if (addr[31]) begin
                // Memory
                assert((addr & ($clog2(BWIDTH) - 1)) == 0);
                s_axi_rdata <= mem[addr[$clog2(BWIDTH) +: MADDR_LEN]];
            end
            else begin
                // MMIO

                case (addr)
                    `SERIAL_ADDR: begin
                        s_axi_rdata <= 'x;
                        s_axi_rdata[7:0] <= inputByte;
                        inputAvail <= 0;
                    end
                    `SERIAL_ADDR + 5: begin
                        s_axi_rdata <= 'x;
                        s_axi_rdata[7:0] <= 8'h60 | (inputAvail ? 1 : 0);
                    end
                endcase
            end

            tfs[0][readDataIdx].cur <= reads[readDataIdx].cur + 1;
            if (last) begin
                tfs[0][readDataIdx] <= 'x;
                tfs[0][readDataIdx].valid <= 0;
            end
        end
    end
end

// Write Idx FIFO
reg[ID_LEN-1:0] fifoAW[NUM_TFS-1:0];
reg fifoAWValid[NUM_TFS-1:0]; // insert idx as unary
initial begin
    for (integer i = 0; i < NUM_TFS; i=i+1) begin
        fifoAW[i] = '0;
        fifoAWValid[i] = '0;
    end
end

logic[ID_LEN-1:0] fifoAWInsIdx;
logic fifoAWInsIdxValid;
always_comb begin
    fifoAWInsIdxValid = 0;
    fifoAWInsIdx = 'x;
    for (integer i = 0; i < 4; i=i+1) begin
        if (!fifoAWInsIdxValid && !fifoAWValid[i]) begin
            fifoAWInsIdx = i[ID_LEN-1:0];
            fifoAWInsIdxValid = 1;
        end
    end
end

// Write Data Input
localparam W_LEN = $bits(s_axi_wdata) + $bits(s_axi_wstrb) + $bits(s_axi_wlast);
logic[WIDTH-1:0] buf_wdata;
logic[(WIDTH/8)-1:0] buf_wstrb;
logic buf_wlast;
logic buf_wvalid;
logic buf_wready;
FIFO#(W_LEN, 2, 1, 1) wFIFO
(
    .clk(clk),
    .rst(rst),
    .free(),

    .IN_valid(s_axi_wvalid),
    .IN_data({s_axi_wdata, s_axi_wstrb, s_axi_wlast}),
    .OUT_ready(s_axi_wready),

    .OUT_valid(buf_wvalid),
    .IN_ready(buf_wready),
    .OUT_data({buf_wdata, buf_wstrb, buf_wlast})
);

reg[NUM_TFS-1:0] writeDone;
reg[ID_LEN-1:0] writeIdx;
reg writeIdxValid;
always_comb begin
    writeIdx = 'x;
    writeIdxValid = 0;

    for (integer i = NUM_TFS-1; i >= 0; i=i-1) begin
        if (fifoAWValid[i] && !writeDone[fifoAW[i[ID_LEN-1:0]]]) begin
            writeIdxValid = 1;
            writeIdx = fifoAW[i[ID_LEN-1:0]];
        end
    end
end
assign buf_wready = writeIdxValid;
always_ff@(posedge clk ) begin
    reg[ID_LEN-1:0] idx = writeIdx;
    if (rst) ;
    else if (buf_wready && buf_wvalid) begin
        Transfer w = writes[idx];
        reg last = w.cur == w.len;
        reg[ADDR_LEN-1:0] addr = GetCurAddr(w);
        assert(writeIdxValid);
        assert(w.valid);
        assert(buf_wlast == last);

        if (addr[31]) begin
            // Memory
            assert((addr & ($clog2(BWIDTH) - 1)) == 0);
            for (integer i = 0; i < BWIDTH; i=i+1) begin
                if (buf_wstrb[i])
                    mem[addr[$clog2(BWIDTH) +: MADDR_LEN]][8*i +: 8] <= buf_wdata[8*i +: 8];
            end
        end
        else begin
            // MMIO
            case (addr)
                `SERIAL_ADDR: begin
                    if (buf_wstrb[0]) begin
                        $write("%c", buf_wdata[7:0]);
                        $fflush(32'h80000001);
                    end
                end
            endcase
        end

        tfs[1][idx].cur <= w.cur + 1;
        if (last) begin
            writeDone[idx] <= 1;
            tfs[1][idx].cur <= 'x;
        end
    end
end

// Write Ack Output
always_ff@(posedge clk ) begin
    reg[ID_LEN-1:0] idx = fifoAW[0];

    if (rst) ;
    else begin
        if (buf_awready && buf_awvalid) begin
            fifoAWValid[fifoAWInsIdx] <= 1;
            fifoAW[fifoAWInsIdx] <= buf_awid;
        end

        if (!(s_axi_bvalid && !s_axi_bready)) begin
            s_axi_bid <= 'x;
            s_axi_bvalid <= 0;
            if (fifoAWValid[0] && writes[idx].valid && writeDone[idx]) begin

                s_axi_bid <= idx;
                s_axi_bvalid <= 1;

                for (integer i = 0; i < NUM_TFS-1; i=i+1) begin
                    fifoAW[i] <= fifoAW[i+1];
                    fifoAWValid[i] <= fifoAWValid[i+1];
                end
                fifoAW[NUM_TFS-1] <= 'x;
                fifoAWValid[NUM_TFS-1] <= 0;

                if (buf_awready && buf_awvalid) begin
                    fifoAWValid[fifoAWInsIdx-1] <= 1;
                    fifoAW[fifoAWInsIdx-1] <= buf_awid;
                end

                tfs[1][idx] <= 'x;
                tfs[1][idx].valid <= 0;
            end
        end
    end
end

// Write Request FIFO
localparam AW_LEN =
    $bits(s_axi_awid) + $bits(s_axi_awaddr) + $bits(s_axi_awsize) + $bits(s_axi_awlen) +
    $bits(s_axi_awburst) + $bits(s_axi_awlock) + $bits(s_axi_awcache);

logic[ID_LEN-1:0]  buf_awid;
logic[ADDR_LEN-1:0] buf_awaddr;
logic[7:0] buf_awlen;
logic[2:0] buf_awsize;
logic[1:0] buf_awburst;
logic[0:0] buf_awlock;
logic[3:0] buf_awcache;
logic buf_awvalid;
logic buf_awready;
FIFO#(AW_LEN, 2, 1, 1) awFIFO
(
    .clk(clk),
    .rst(rst),
    .free(),

    .IN_valid(s_axi_awvalid),
    .IN_data({s_axi_awid, s_axi_awaddr, s_axi_awsize, s_axi_awlen, s_axi_awburst, s_axi_awlock, s_axi_awcache}),
    .OUT_ready(s_axi_awready),

    .OUT_valid(buf_awvalid),
    .IN_ready(buf_awready),
    .OUT_data({buf_awid, buf_awaddr, buf_awsize, buf_awlen, buf_awburst, buf_awlock, buf_awcache})
);

// Read Request FIFO
localparam AR_LEN =
    $bits(s_axi_arid) + $bits(s_axi_araddr) + $bits(s_axi_arsize) + $bits(s_axi_arlen) +
    $bits(s_axi_arburst) + $bits(s_axi_arlock) + $bits(s_axi_arcache);

logic[ID_LEN-1:0]  buf_arid;
logic[ADDR_LEN-1:0] buf_araddr;
logic[7:0] buf_arlen;
logic[2:0] buf_arsize;
logic[1:0] buf_arburst;
logic[0:0] buf_arlock;
logic[3:0] buf_arcache;
logic buf_arvalid;
logic buf_arready;
FIFO#(AR_LEN, 2, 1, 1) arFIFO
(
    .clk(clk),
    .rst(rst),
    .free(),

    .IN_valid(s_axi_arvalid),
    .IN_data({s_axi_arid, s_axi_araddr, s_axi_arsize, s_axi_arlen, s_axi_arburst, s_axi_arlock, s_axi_arcache}),
    .OUT_ready(s_axi_arready),

    .OUT_valid(buf_arvalid),
    .IN_ready(buf_arready),
    .OUT_data({buf_arid, buf_araddr, buf_arsize, buf_arlen, buf_arburst, buf_arlock, buf_arcache})
);

// Requests
assign buf_arready = !tfs[0][buf_arid].valid && buf_arvalid;
assign buf_awready = !tfs[1][buf_awid].valid && buf_awvalid;

always_ff@(posedge clk ) begin
    if (rst) ;
    else begin
        if (buf_arready) begin
            tfs[0][buf_arid].valid <= 1;
            tfs[0][buf_arid].addr <= buf_araddr;
            tfs[0][buf_arid].btype <= BurstType'(buf_arburst);
            tfs[0][buf_arid].len <= buf_arlen;
            tfs[0][buf_arid].cur <= 0;
        end
        if (buf_awready) begin
            tfs[1][buf_awid].valid <= 1;
            tfs[1][buf_awid].addr <= buf_awaddr;
            tfs[1][buf_awid].btype <= BurstType'(buf_awburst);
            tfs[1][buf_awid].len <= buf_awlen;
            tfs[1][buf_awid].cur <= 0;
            writeDone[buf_awid] <= 0;
        end
    end
end
endmodule
