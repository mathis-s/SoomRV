module FIFO#(parameter WIDTH=32, parameter NUM=4)
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

wire doExtract = !empty && (!OUT_valid || IN_ready);
wire doInsert = IN_valid && OUT_ready;
assign OUT_ready = !full || doExtract;

always_comb begin
    if (empty) free = NUM;
    else free = (indexOut - indexIn) % NUM;
end

always_ff@(posedge clk) begin
    if (rst) begin
        fullCond <= 0;
        indexIn <= 0;
        indexOut <= 0;
        OUT_data <= 'x;
        OUT_valid <= 0;
    end
    else begin

        if (!OUT_valid || IN_ready)
            OUT_data <= 'x;
        if (IN_ready)
            OUT_valid <= 0;

        // Insert
        if (doInsert) begin
            mem[indexIn] <= IN_data;
            // verilator lint_off WIDTHEXPAND
            // verilator lint_off WIDTHTRUNC
            indexIn <= (indexIn + 2'b1) % NUM;
            // verilator lint_on WIDTHTRUNC
            // verilator lint_on WIDTHEXPAND
        end

        // Extract
        if (doExtract) begin
            // verilator lint_off WIDTHEXPAND
            // verilator lint_off WIDTHTRUNC
            indexOut <= (indexOut + 2'b1) % NUM;
            // verilator lint_on WIDTHTRUNC
            // verilator lint_on WIDTHEXPAND
            OUT_data <= mem[indexOut];
            OUT_valid <= 1;
        end
        
        // When pointers equal: full if last action was insert,
        // empty if last action was extract
        if (doInsert != doExtract)
            fullCond <= doInsert;
    end
end
endmodule
