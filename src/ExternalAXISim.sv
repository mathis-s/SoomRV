
// Address for the simulated 8250 UART stub
// This must be between EXT_MMIO_START_ADDR and EXT_MMIO_END_ADDR!
`define SERIAL_ADDR 32'h1000_0000

module ExternalAXISim
#(parameter ID_LEN=2, parameter WIDTH=128, parameter ADDR_LEN=32)
(
    input wire clk,
    
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


localparam NUM_TFS = 4;
localparam BWIDTH = WIDTH / 8;
localparam MADDR_LEN = 29 - $clog2(WIDTH / 8);
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

// RTL sim input
logic inputAvail /*verilator public*/ = 0;
logic[7:0] inputByte /*verilator public*/;

// Read Data Output
logic readDataIdxValid;
logic[ID_LEN-1:0] readDataIdx;
always_comb begin
    // could select index randomly to 
    // simulate memory heterogeneity
    readDataIdxValid = 0;
    readDataIdx = 'x;
    for (integer i = 0; i < NUM_TFS; i=i+1) begin
        if (reads[i].valid) begin
            readDataIdxValid = 1;
            readDataIdx = i[ID_LEN-1:0];
        end
    end
end
always_ff@(posedge clk) begin
    if (!(s_axi_rvalid && !s_axi_rready)) begin
        s_axi_rid <= 'x;
        s_axi_rdata <= 'x;
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
// TODO: buffer input before processing
// in case write transfer does not exist yet
reg[NUM_TFS-1:0] writeDone;
always_comb begin
    s_axi_wready = fifoAWValid[0];
end
always_ff@(posedge clk) begin
    reg[ID_LEN-1:0] idx = fifoAW[0];

    if (s_axi_wready && s_axi_wvalid) begin
        Transfer w = writes[idx];
        reg last = w.cur == w.len;
        reg[ADDR_LEN-1:0] addr = GetCurAddr(w);
        assert(fifoAWValid[0]);
        assert(w.valid);
        assert(s_axi_wlast == last);

        if (addr[31]) begin
            // Memory
            assert((addr & ($clog2(BWIDTH) - 1)) == 0);
            for (integer i = 0; i < BWIDTH; i=i+1) begin
                if (s_axi_wstrb[i])
                    mem[addr[$clog2(BWIDTH) +: MADDR_LEN]][8*i +: 8] <= s_axi_wdata[8*i +: 8];
            end
        end
        else begin
            // MMIO
            case (addr)
                `SERIAL_ADDR: begin
                    if (s_axi_wstrb[0]) begin
                        $write("%c", s_axi_wdata[7:0] & 8'd127);
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
always_ff@(posedge clk) begin
    reg[ID_LEN-1:0] idx = fifoAW[0];

    if (s_axi_awready && s_axi_awvalid) begin
        fifoAWValid[fifoAWInsIdx] <= 1;
        fifoAW[fifoAWInsIdx] <= s_axi_awid;
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

            if (s_axi_awready && s_axi_awvalid) begin
                fifoAWValid[fifoAWInsIdx-1] <= 1;
                fifoAW[fifoAWInsIdx-1] <= s_axi_awid;
            end

            tfs[1][idx] <= 'x;
            tfs[1][idx].valid <= 0;
        end
    end
end

// Requests
always_comb begin
    s_axi_arready = !tfs[0][s_axi_arid].valid;
    s_axi_awready = !tfs[1][s_axi_awid].valid;
end
always_ff@(posedge clk) begin
    if (s_axi_arready && s_axi_arvalid) begin
        tfs[0][s_axi_arid].valid <= 1;
        tfs[0][s_axi_arid].addr <= s_axi_araddr;
        tfs[0][s_axi_arid].btype <= BurstType'(s_axi_arburst);
        tfs[0][s_axi_arid].len <= s_axi_arlen;
        tfs[0][s_axi_arid].cur <= 0;
    end
    if (s_axi_awready && s_axi_awvalid) begin
        tfs[1][s_axi_awid].valid <= 1;
        tfs[1][s_axi_awid].addr <= s_axi_awaddr;
        tfs[1][s_axi_awid].btype <= BurstType'(s_axi_awburst);
        tfs[1][s_axi_awid].len <= s_axi_awlen;
        tfs[1][s_axi_awid].cur <= 0;
        writeDone[s_axi_awid] <= 0;
    end
end
endmodule
