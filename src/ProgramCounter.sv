module ProgramCounter
(
    input wire clk,
    input wire en,
    input wire rst,

    input wire[31:0] IN_pc,
    input wire IN_write,
    output wire[31:0] OUT_pc
);

assign OUT_pc = {pc, 1'b0};

reg[30:0] pc;

always@(posedge clk) begin
    if (rst) begin
        pc <= 0;
    end
    else if (IN_write) begin
        pc <= IN_pc[31:1];
    end
    else if (en) begin
        pc <= pc + 2;
    end
end

endmodule