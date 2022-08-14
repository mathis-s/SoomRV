module ProgramCounter
(
    input wire clk,
    input wire en,
    input wire rst,
    output wire[31:0] OUT_pc
);

assign OUT_pc = {pc, 1'b0};

reg[30:0] pc;

always@(posedge clk) begin
    if (rst) begin
        pc <= 0;
    end
    else if (en) begin
        pc <= pc + 2;
    end
end

endmodule