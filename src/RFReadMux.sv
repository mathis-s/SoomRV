module RFReadMux
#(
    parameter VIRT_READS = 4,
    parameter PHY_READS = 3
)
(
    input wire clk,

    input  RF_ReadReq[VIRT_READS-1:0] IN_read,
    output logic[VIRT_READS-1:0] OUT_readReady,
    output RegT[VIRT_READS-1:0] OUT_readData,

    output logic[PHY_READS-1:0] OUT_readEnable,
    output RFTag[PHY_READS-1:0] OUT_readAddress,
    input  RegT[PHY_READS-1:0]  IN_readData
);

localparam COMP_READS = VIRT_READS - PHY_READS;

logic[PHY_READS-1:0] staticReadEnable;
always_comb begin
    for (integer i = 0; i < PHY_READS; i=i+1)
        staticReadEnable[i] = IN_read[i].valid;
end

if (COMP_READS > 0) begin
    always_comb begin
        for (integer i = 0; i < PHY_READS; i=i+1) begin
            OUT_readData[i] = IN_readData[i];
        end
        for (integer i = 0; i < COMP_READS; i=i+1) begin
            OUT_readData[i+PHY_READS] = IN_readData[compReadIdx_r[i]];
        end
    end

    logic[$clog2(PHY_READS)-1:0] compReadIdx_c[COMP_READS-1:0];
    logic compReadValid_c[COMP_READS-1:0];
    PriorityEncoder#(PHY_READS, COMP_READS) penc(~staticReadEnable, compReadIdx_c, compReadValid_c);

    logic[$clog2(PHY_READS)-1:0] compReadIdx_r[COMP_READS-1:0];
    always_ff@(posedge clk)
        compReadIdx_r <= compReadIdx_c;

    always_comb begin
        for (integer i = 0; i < PHY_READS; i=i+1) begin
            OUT_readEnable[i] = staticReadEnable[i];
            OUT_readAddress[i] = IN_read[i].tag;
            OUT_readReady[i] = 1;
        end

        for (integer i = 0; i < COMP_READS; i=i+1) begin
            OUT_readReady[PHY_READS + i] = 0;
            if (compReadValid_c[i] && IN_read[PHY_READS + i].valid) begin
                OUT_readReady[PHY_READS + i] = 1;
                OUT_readEnable[compReadIdx_c[i]] = 1;
                OUT_readAddress[compReadIdx_c[i]] = IN_read[PHY_READS + i].tag;
            end
        end
    end
end
else begin
    always_comb begin
        for (integer i = 0; i < PHY_READS; i=i+1) begin
            OUT_readData[i] = IN_readData[i];
        end
    end

    always_comb begin
        for (integer i = 0; i < PHY_READS; i=i+1) begin
            OUT_readEnable[i] = staticReadEnable[i];
            OUT_readAddress[i] = IN_read[i].tag;
            OUT_readReady[i] = 1;
        end
    end
end

endmodule
