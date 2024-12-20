module MemRTL1RW
#(
    parameter WORD_SIZE=32*4*2,
    parameter NUM_WORDS=128,
    parameter WRITE_SIZE=8
)
(
    input wire clk,

    input wire IN_nce,
    input wire IN_nwe,
    input wire[$clog2(NUM_WORDS)-1:0] IN_addr,
    input wire[WORD_SIZE-1:0] IN_data,
    input wire[(WORD_SIZE/WRITE_SIZE)-1:0] IN_wm,
    output logic[WORD_SIZE-1:0] OUT_data
);

(* ram_style = "block" *)
reg[WORD_SIZE-1:0] mem[NUM_WORDS-1:0] /* verilator public */;

reg ce_reg = 1;
reg we_reg;
reg[$clog2(NUM_WORDS)-1:0] addr_reg;
reg[WORD_SIZE-1:0] data_reg;
reg[(WORD_SIZE/WRITE_SIZE)-1:0] wm_reg;

always@(posedge clk) begin

    ce_reg <= IN_nce;
    we_reg <= IN_nwe;
    addr_reg <= IN_addr;
    data_reg <= IN_data;
    wm_reg <= IN_wm;
end

initial begin
    for (integer i = 0; i < NUM_WORDS; i=i+1)
        mem[i] = 0;
end

always@(posedge clk) begin
    if (!ce_reg) begin
        if (!we_reg) begin
            for (integer i = 0; i < WORD_SIZE/WRITE_SIZE; i=i+1) begin
                if (wm_reg[i])
                    mem[addr_reg][(WRITE_SIZE*i)+:WRITE_SIZE] <= data_reg[(WRITE_SIZE*i)+:WRITE_SIZE];
            end
            //if (addr_reg == {32'h0A0}[$clog2(NUM_WORDS)-1:0] && WORD_SIZE == 128)
            //    $display("[%d] %m: write %x to %x (%b)", $time(), data_reg, addr_reg, wm_reg);
        end
        else begin
            OUT_data <= mem[addr_reg];
        end
    end
end

endmodule
