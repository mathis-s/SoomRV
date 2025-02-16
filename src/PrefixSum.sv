module PrefixSum#(parameter N = 32)
(
    input logic[N-1:0] IN_data,
    output logic[$clog2(N+1)-1:0] OUT_psum[N-1:0]
);

always_comb begin
    logic[$clog2(N+1)-1:0] sum = 0;
    for (integer i = 0; i < N; i=i+1) begin
        // verilator lint_off WIDTHEXPAND
        sum = sum + IN_data[i];
        // verilator lint_on WIDTHEXPAND
        OUT_psum[i] = sum;
    end
end

endmodule
