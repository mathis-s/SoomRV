module FIFO#(parameter WIDTH=32, parameter NUM=4, parameter FORWARD1 = 1, parameter FORWARD0 = 1)
(
    input logic clk,
    input logic rst,

    output logic[$clog2(NUM):0] free,

    input logic IN_valid,
    input logic[WIDTH-1:0] IN_data,
    output logic OUT_ready,

    output logic OUT_valid,
    input logic IN_ready,
    output logic[WIDTH-1:0] OUT_data
);

logic[WIDTH-1:0] mem[NUM-1:0];

logic[$clog2(NUM)-1:0] indexIn;
logic[$clog2(NUM)-1:0] indexOut;
logic fullCond;

wire equal = (indexIn == indexOut);
wire empty = !fullCond && equal;
wire full = fullCond && equal;

wire outputReady = !outValidReg || IN_ready;
wire doExtract = !empty && outputReady;
wire doInsert = IN_valid && OUT_ready;
assign OUT_ready = !full || doExtract;

always_comb begin
    if (empty) free = NUM;
    else free = (indexOut - indexIn) % NUM;
end

logic[WIDTH-1:0] outDataReg;
logic outValidReg;
logic combPassthru;
always_comb begin
    OUT_valid = outValidReg;
    OUT_data = outDataReg;
    combPassthru = 0;

    if (!OUT_valid && empty && FORWARD0) begin
        OUT_valid = IN_valid;
        OUT_data = IN_data;
        combPassthru = 1;
    end
end

always_ff@(posedge clk /*or posedge rst*/) begin
    if (rst) begin
        fullCond <= 0;
        indexIn <= 0;
        indexOut <= 0;
        outDataReg <= '0;
        outValidReg <= 0;
    end
    else begin

        if (outputReady)
            outDataReg <= 'x;
        if (IN_ready)
            outValidReg <= 0;

        if (combPassthru && IN_ready) begin
            // Nothing to do, purely comb
        end
        else if (empty && doInsert && outputReady && FORWARD1) begin
            outDataReg <= IN_data;
            outValidReg <= 1;
        end
        else begin
            // Insert
            if (doInsert) begin
                mem[indexIn] <= IN_data;

                // verilator lint_off WIDTHEXPAND
                // verilator lint_off WIDTHTRUNC
                indexIn <= (indexIn + 1) % NUM;
                // verilator lint_on WIDTHTRUNC
                // verilator lint_on WIDTHEXPAND
            end

            // Extract
            if (doExtract) begin
                // verilator lint_off WIDTHEXPAND
                // verilator lint_off WIDTHTRUNC
                indexOut <= (indexOut + 1) % NUM;
                // verilator lint_on WIDTHTRUNC
                // verilator lint_on WIDTHEXPAND
                outDataReg <= mem[indexOut];
                outValidReg <= 1;
            end

            // When pointers equal: full if last action was insert,
            // empty if last action was extract
            if (doInsert != doExtract)
                fullCond <= doInsert;
        end
    end
end
/*
// remove path from IN_valid to we.
always_ff@(posedge clk) begin
    // Insert
    if (!full) begin
        mem[indexIn] <= IN_data;
    end
end
*/
endmodule
