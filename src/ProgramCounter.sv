module ProgramCounter
#(
    parameter NUM_UOPS=2
)
(
    input wire clk,
    input wire en,
    input wire rst,

    input wire[31:0] IN_pc,
    input wire IN_write,
    output reg[31:0] OUT_pc[NUM_UOPS-1:0]
);

integer i;

reg[30:0] pc;

always_comb begin
    for (i = 0; i < NUM_UOPS; i=i+1)
        OUT_pc[i] = {({pc + 2 * i}[30:0]), 1'b0};
end

always_ff@(posedge clk) begin
    if (rst) begin
        pc <= 0;
    end
    else if (IN_write) begin
        pc <= IN_pc[31:1];
    end
    else if (en) begin
        pc <= pc + 2 * NUM_UOPS;
    end
end

endmodule
