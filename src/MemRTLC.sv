module MemRTLC
#(
    parameter WORD_SIZE=32*4*2,
    parameter NUM_WORDS=128,
    parameter WRITE_SIZE=8,
    parameter PORTS=1
)
(
    input wire clk,

    input wire[PORTS-1:0] IN_nce,
    input wire[PORTS-1:0] IN_nwe,
    input wire[PORTS-1:0][$clog2(NUM_WORDS)-1:0] IN_addr,
    input wire[PORTS-1:0][WORD_SIZE-1:0] IN_data,
    input wire[PORTS-1:0][(WORD_SIZE/WRITE_SIZE)-1:0] IN_wm,
    output reg[PORTS-1:0][WORD_SIZE-1:0] OUT_data
);

(* ram_style = "block" *)
reg[WORD_SIZE-1:0] mem[NUM_WORDS-1:0] /* verilator public */;

reg[PORTS-1:0] ce_reg;
reg[PORTS-1:0] ce1_reg;
reg[PORTS-1:0] we_reg;
reg[PORTS-1:0][$clog2(NUM_WORDS)-1:0] addr_reg;
reg[PORTS-1:0][$clog2(NUM_WORDS)-1:0] addr1_reg;
reg[PORTS-1:0][WORD_SIZE-1:0] data_reg;
reg[PORTS-1:0][(WORD_SIZE/WRITE_SIZE)-1:0] wm_reg;

initial begin
    for (integer i = 0; i < NUM_WORDS; i=i+1)
        mem[i] = 0;
end

always_ff@(posedge clk) begin

    ce_reg <= IN_nce;
    we_reg <= IN_nwe;
    addr_reg <= IN_addr;
    data_reg <= IN_data;
    wm_reg <= IN_wm;

    for (integer port = 0; port < PORTS; port++) begin
        if (!ce_reg[port]) begin
            if (!we_reg[port]) begin
                for (integer i = 0; i < WORD_SIZE/WRITE_SIZE; i=i+1) begin
                    if (wm_reg[port][i])
                        mem[addr_reg[port]][(WRITE_SIZE*i)+:WRITE_SIZE] <= data_reg[port][(WRITE_SIZE*i)+:WRITE_SIZE];
                end
            end
            else begin
                OUT_data[port] <= mem[addr_reg[port]];
            end
        end
    end
end

endmodule
