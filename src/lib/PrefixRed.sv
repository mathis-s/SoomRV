module PrefixRed#(parameter N = 32, parameter FUNC = 0, parameter START = 0)
(
    input logic[N-1:0] IN_data,
    output logic[N-1:0] OUT_pval
);

always_comb begin
    logic red = START;
    for (integer i = 0; i < N; i=i+1) begin
        // verilator lint_off WIDTHEXPAND
        case (FUNC)
            0: red = red | IN_data[i];
            1: red = red & IN_data[i];
            2: red = red ^ IN_data[i];
        endcase
        // verilator lint_on WIDTHEXPAND
        OUT_pval[i] = red;
    end
end

endmodule
