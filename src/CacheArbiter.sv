
module CacheArbiter
#(
    parameter INPUT_PORTS = 4,
    parameter OUTPUT_PORTS = 2,
    parameter OUTPUT_BANKS = 4,
    parameter BANK_OFFSET = 0,
    parameter DATA_WIDTH = 32,
    parameter type IF_t
)
(
    input wire clk,

    input IF_t IN_ports[INPUT_PORTS-1:0],
    output logic OUT_portReady[INPUT_PORTS-1:0],
    output logic[DATA_WIDTH-1:0] OUT_portRData[INPUT_PORTS-1:0],

    output IF_t OUT_ports[OUTPUT_BANKS-1:0][OUTPUT_PORTS-1:0],
    input logic[DATA_WIDTH-1:0] IN_portRData[OUTPUT_BANKS-1:0][OUTPUT_PORTS-1:0]
);

typedef logic[$clog2(INPUT_PORTS)-1:0] InPortIdx;
typedef logic[OUTPUT_PORTS == 1 ? 0 : $clog2(OUTPUT_PORTS)-1:0] OutPortIdx;
typedef logic[OUTPUT_BANKS == 1 ? 0 : $clog2(OUTPUT_BANKS)-1:0] BankIdx;

OutPortIdx outPortIdx[INPUT_PORTS-1:0];

InPortIdx reqIdx[OUTPUT_BANKS-1:0][OUTPUT_PORTS-1:0];
logic reqIdxValid[OUTPUT_BANKS-1:0][OUTPUT_PORTS-1:0];

generate for (genvar bank = 0; bank < OUTPUT_BANKS; bank=bank+1) begin : gen_banks
    logic[INPUT_PORTS-1:0] reqUnary;
    if (OUTPUT_BANKS > 1)
    always_comb
        for (integer i = 0; i < INPUT_PORTS; i=i+1)
            reqUnary[i] = !IN_ports[i].ce && IN_ports[i].addr[BANK_OFFSET+:$clog2(OUTPUT_BANKS)] == BankIdx'(bank);
    else
    always_comb
        for (integer i = 0; i < INPUT_PORTS; i=i+1)
            reqUnary[i] = !IN_ports[i].ce;

    PriorityEncoder#(INPUT_PORTS, OUTPUT_PORTS) penc(reqUnary, reqIdx[bank], reqIdxValid[bank]);
end endgenerate

always_comb begin
    for (integer i = 0; i < INPUT_PORTS; i=i+1) begin
        OUT_portReady[i] = 0;
        outPortIdx[i] = 'x;
    end

    for (integer bank = 0; bank < OUTPUT_BANKS; bank=bank+1) begin
        for (integer i = 0; i < OUTPUT_PORTS; i=i+1) begin
            OUT_ports[bank][i] = IN_ports[reqIdx[bank][i]];
            if (!reqIdxValid[bank][i])
                OUT_ports[bank][i].ce = 1;

            OUT_portReady[reqIdx[bank][i]] |= reqIdxValid[bank][i];
            outPortIdx[reqIdx[bank][i]] = OutPortIdx'(i);
        end
    end
end

typedef struct packed
{
    BankIdx bank;
    OutPortIdx port;
} Read;

Read readIdxs[1:0][INPUT_PORTS-1:0];
always_ff@(posedge clk) begin
    for (integer i = 0; i < INPUT_PORTS; i=i+1) begin
        readIdxs[0][i] <= Read'{bank: IN_ports[i].addr[BANK_OFFSET+:OUTPUT_BANKS == 1 ? 1 : $clog2(OUTPUT_BANKS)], port: outPortIdx[i]};
    end
    readIdxs[1] <= readIdxs[0];
end

always_comb begin
    for (integer i = 0; i < INPUT_PORTS; i=i+1) begin
        OUT_portRData[i] = IN_portRData[readIdxs[1][i].bank][readIdxs[1][i].port];
    end
end

endmodule
