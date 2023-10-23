module BranchPredictionTable
(
    input wire clk,
    input wire rst,
    
    input wire IN_readValid,
    input wire[`BP_BASEP_ID_LEN-1:0] IN_readAddr,
    output reg OUT_taken,
    
    input wire IN_writeEn,
    input wire[`BP_BASEP_ID_LEN-1:0] IN_writeAddr,
    input wire IN_writeTaken
);

localparam NUM_COUNTERS = (1 << `BP_BASEP_ID_LEN);

reg pred[NUM_COUNTERS-1:0];
reg hist[NUM_COUNTERS-1:0];

always_ff@(posedge clk) begin
    if (IN_readValid)
        OUT_taken <= pred[IN_readAddr];
end

typedef struct packed
{
    logic[`BP_BASEP_ID_LEN-1:0] addr;
    logic taken;
    logic valid;
} Write;

reg[1:0] writeTempReg;

Write write_c;
Write write_r;
always_comb begin
    write_c.valid = IN_writeEn;
    write_c.addr = IN_writeAddr;
    write_c.taken = IN_writeTaken;
end

always_ff@(posedge clk) begin
    
    if (rst) begin
    
    end
    else begin
        write_r <= write_c;
        if (write_c.valid) begin
            writeTempReg <= {pred[write_c.addr], hist[write_c.addr]};
        end
        if (write_r.valid) begin
            if (writeTempReg != 2'b11 && write_r.taken)
                {pred[write_r.addr], hist[write_r.addr]} <= writeTempReg + 1'b1;
            if (writeTempReg != 2'b00 && !write_r.taken)
                {pred[write_r.addr], hist[write_r.addr]} <= writeTempReg - 1'b1;
        end
    end
end

endmodule
