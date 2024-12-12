
module CacheArbiter
#(
    parameter INPUT_READS = 4,
    parameter INPUT_WRITES = 4,

    parameter OUTPUT_PORTS = 2,
    parameter OUTPUT_BANKS = 4,
    parameter BANK_OFFSET = 0,
    parameter DATA_WIDTH = 32,
    parameter type IF_t,

    parameter OUTPUT_R = 1,
    parameter OUTPUT_RW = 1,
    parameter OUTPUT_W = OUTPUT_PORTS - OUTPUT_R - OUTPUT_RW
)
(
    input wire clk,

    input IF_t IN_reads[INPUT_READS-1:0],
    input IF_t IN_writes[INPUT_WRITES-1:0],

    output logic OUT_readReady[INPUT_READS-1:0],
    output logic OUT_writeReady[INPUT_WRITES-1:0],
    output logic[DATA_WIDTH-1:0] OUT_portRData[INPUT_READS-1:0],

    output IF_t OUT_ports[OUTPUT_BANKS-1:0][OUTPUT_PORTS-1:0],
    input logic[DATA_WIDTH-1:0] IN_portRData[OUTPUT_BANKS-1:0][OUTPUT_PORTS-1:0]
);

localparam OUT_R_CANDIDATES = OUTPUT_R + OUTPUT_RW;
localparam OUT_W_CANDIDATES = OUTPUT_W + OUTPUT_RW;

typedef logic[$clog2(INPUT_READS)-1:0] InReadIdx;
typedef logic[$clog2(INPUT_WRITES)-1:0] InWriteIdx;
typedef logic[OUTPUT_PORTS == 1 ? 0 : $clog2(OUTPUT_PORTS)-1:0] OutPortIdx;
typedef logic[OUTPUT_BANKS == 1 ? 0 : $clog2(OUTPUT_BANKS)-1:0] BankIdx;

OutPortIdx outPortIdx[INPUT_READS-1:0];

InReadIdx reqIdx_r[OUTPUT_BANKS-1:0][OUT_R_CANDIDATES-1:0];
logic reqIdxValid_r[OUTPUT_BANKS-1:0][OUT_R_CANDIDATES-1:0];

InWriteIdx reqIdx_w[OUTPUT_BANKS-1:0][OUT_W_CANDIDATES-1:0];
logic reqIdxValid_w[OUTPUT_BANKS-1:0][OUT_W_CANDIDATES-1:0];

generate for (genvar bank = 0; bank < OUTPUT_BANKS; bank=bank+1) begin : gen_banks
    logic[INPUT_READS-1:0] reqUnary_r;
    logic[INPUT_WRITES-1:0] reqUnary_w;

    if (OUTPUT_BANKS > 1)
    always_comb
        for (integer i = 0; i < INPUT_READS; i=i+1)
            reqUnary_r[i] = !IN_reads[i].ce && IN_reads[i].addr[BANK_OFFSET+:$clog2(OUTPUT_BANKS)] == BankIdx'(bank);
    else
    always_comb
        for (integer i = 0; i < INPUT_READS; i=i+1)
            reqUnary_r[i] = !IN_reads[i].ce;

    if (OUTPUT_BANKS > 1)
    always_comb
        for (integer i = 0; i < INPUT_WRITES; i=i+1)
            reqUnary_w[i] = !IN_writes[i].ce && IN_writes[i].addr[BANK_OFFSET+:$clog2(OUTPUT_BANKS)] == BankIdx'(bank);
    else
    always_comb
        for (integer i = 0; i < INPUT_WRITES; i=i+1)
            reqUnary_w[i] = !IN_writes[i].ce;

    PriorityEncoder#(INPUT_READS, OUT_R_CANDIDATES) penc_r(reqUnary_r, reqIdx_r[bank], reqIdxValid_r[bank]);
    PriorityEncoder#(INPUT_WRITES, OUT_W_CANDIDATES) penc_w(reqUnary_w, reqIdx_w[bank], reqIdxValid_w[bank]);
end endgenerate

always_comb begin
    for (integer i = 0; i < INPUT_READS; i=i+1) begin
        OUT_readReady[i] = 0;
        outPortIdx[i] = 'x;
    end

    for (integer i = 0; i < INPUT_WRITES; i=i+1) begin
        OUT_writeReady[i] = 0;
    end

    for (integer bank = 0; bank < OUTPUT_BANKS; bank=bank+1) begin

        // read-only ports
        for (integer i = 0; i < OUTPUT_R; i=i+1) begin
            OUT_ports[bank][i] = IN_reads[reqIdx_r[bank][i]];
            OUT_ports[bank][i].ce = !reqIdxValid_r[bank][i];
            OUT_readReady[reqIdx_r[bank][i]] |= reqIdxValid_r[bank][i];
            outPortIdx[reqIdx_r[bank][i]] = OutPortIdx'(i);
        end

        // write-only ports
        for (integer i = 0; i < OUTPUT_W; i=i+1) begin
            integer idx = i + OUTPUT_R;
            OUT_ports[bank][idx] = IN_writes[reqIdx_w[bank][i]];
            OUT_ports[bank][idx].ce = !reqIdxValid_w[bank][i];
            OUT_writeReady[reqIdx_w[bank][i]] |= reqIdxValid_w[bank][i];
            //outPortIdx[reqIdx_w[bank][idx]] = OutPortIdx'(i);
        end

        // read/write ports
        if (OUTPUT_RW == 1) begin
            integer idx = OUTPUT_R + OUTPUT_W;

            if (reqIdxValid_w[bank][OUT_W_CANDIDATES - 1]) begin
                localparam i = OUT_W_CANDIDATES - 1;
                OUT_ports[bank][idx] = IN_writes[reqIdx_w[bank][i]];
                OUT_ports[bank][idx].ce = !reqIdxValid_w[bank][i];
                OUT_writeReady[reqIdx_w[bank][i]] |= reqIdxValid_w[bank][i];
                //outPortIdx[reqIdx_w[bank][idx]] = OutPortIdx'(i);
            end
            else begin
                localparam i = OUT_R_CANDIDATES - 1;
                OUT_ports[bank][idx] = IN_reads[reqIdx_r[bank][i]];
                OUT_ports[bank][idx].ce = !reqIdxValid_r[bank][i];
                OUT_readReady[reqIdx_r[bank][i]] |= reqIdxValid_r[bank][i];
                outPortIdx[reqIdx_r[bank][i]] = OutPortIdx'(i);
            end
        end
    end
end

typedef struct packed
{
    BankIdx bank;
    OutPortIdx port;
} Read;

Read readIdxs[1:0][INPUT_READS-1:0];
always_ff@(posedge clk) begin
    for (integer i = 0; i < INPUT_READS; i=i+1) begin
        readIdxs[0][i] <= Read'{bank: IN_reads[i].addr[BANK_OFFSET+:OUTPUT_BANKS == 1 ? 1 : $clog2(OUTPUT_BANKS)], port: outPortIdx[i]};

        if (OUTPUT_BANKS == 1) readIdxs[0][i].bank <= 0;
        if (OUTPUT_PORTS == 1) readIdxs[0][i].port <= 0;
    end
    readIdxs[1] <= readIdxs[0];
end

always_comb begin
    for (integer i = 0; i < INPUT_READS; i=i+1) begin
        OUT_portRData[i] = IN_portRData[readIdxs[1][i].bank][readIdxs[1][i].port];
    end
end

endmodule
