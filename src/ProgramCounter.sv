module ProgramCounter
#(
    parameter NUM_UOPS=2
)
(
    input wire clk,
    input wire en0,
    input wire en1,
    input wire rst,

    input wire[31:0] IN_pc,
    input wire IN_write,

    input wire[63:0] IN_instr,

    output wire[28:0] OUT_instrAddr,

    output reg[31:0] OUT_pc[NUM_UOPS-1:0],
    output reg[31:0] OUT_instr[NUM_UOPS-1:0],
    output reg OUT_instrValid[NUM_UOPS-1:0]
);

integer i;

reg[30:0] pc;
reg[30:0] pcLast;
assign OUT_instrAddr = pc[30:2];

always_comb begin
    OUT_instr[0] = IN_instr[31:0];
    OUT_instr[1] = IN_instr[63:32];
end


always_ff@(posedge clk) begin
    if (rst) begin
        pc <= 0;
    end
    else if (IN_write) begin
        pc <= IN_pc[31:1];
    end
    else begin
        if (en1) begin
            for (i = 0; i < NUM_UOPS; i=i+1) begin
                OUT_pc[i] <= {{pcLast[30:2], 2'b00} + 31'd2 * i[30:0], 1'b0};
                OUT_instrValid[i] <= (i[0] >= pcLast[1]);
            end
        end

        if (en0) begin
            case (pc[1])
                1'b1: pc <= pc + 2;
                1'b0: pc <= pc + 4;
            endcase
            pcLast <= pc;
        end
    end
end

endmodule
