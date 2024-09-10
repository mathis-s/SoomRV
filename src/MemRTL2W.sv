module MemRTL2W
#(
    parameter WORD_SIZE=32*4*2,
    parameter NUM_WORDS=512,
    parameter WRITE_SIZE=8
)
(
    input wire clk,

    input wire IN_nce,
    input wire IN_nwe,
    input wire[$clog2(NUM_WORDS)-1:0] IN_addr,
    input wire[WORD_SIZE-1:0] IN_data,
    input wire[(WORD_SIZE/WRITE_SIZE)-1:0] IN_wm,
    output reg[WORD_SIZE-1:0] OUT_data,

    input wire IN_nce1,
    input wire IN_nwe1,
    input wire[$clog2(NUM_WORDS)-1:0] IN_addr1,
    input wire[WORD_SIZE-1:0] IN_data1,
    input wire[(WORD_SIZE/WRITE_SIZE)-1:0] IN_wm1,
    output reg[WORD_SIZE-1:0] OUT_data1
);

(* ram_style = "block" *)
reg[WORD_SIZE-1:0] mem[NUM_WORDS-1:0];

reg ce_reg = 1;
reg ce1_reg = 1;
reg we_reg;
reg we1_reg;
reg[$clog2(NUM_WORDS)-1:0] addr_reg;
reg[$clog2(NUM_WORDS)-1:0] addr1_reg;
reg[WORD_SIZE-1:0] data_reg;
reg[WORD_SIZE-1:0] data1_reg;
reg[(WORD_SIZE/WRITE_SIZE)-1:0] wm_reg;
reg[(WORD_SIZE/WRITE_SIZE)-1:0] wm1_reg;

reg dbgMultiple;

initial begin
    for (integer i = 0; i < NUM_WORDS; i=i+1)
        mem[i] = 0;
end

always@(posedge clk) begin

    dbgMultiple <= 0;

    ce_reg <= IN_nce;
    we_reg <= IN_nwe;
    addr_reg <= IN_addr;
    data_reg <= IN_data;
    wm_reg <= IN_wm;

    if (!ce_reg) begin
        if (!we_reg) begin
            for (integer i = 0; i < WORD_SIZE/WRITE_SIZE; i=i+1) begin
                if (wm_reg[i])
                    mem[addr_reg][(WRITE_SIZE*i)+:WRITE_SIZE] <= data_reg[(WRITE_SIZE*i)+:WRITE_SIZE];
            end
            //if (addr_reg == {32'h0A0}[$clog2(NUM_WORDS)-1:0] && WORD_SIZE == 128)
            //    $display("[%d] %m: write %x to %x (%b)", $time(), data_reg, addr_reg, wm_reg);
        end
        //else begin
            OUT_data <= mem[addr_reg];
        //end
    end

    if (!ce1_reg && !ce_reg && addr1_reg == addr_reg && we_reg && !we1_reg) begin
        for (integer i = 0; i < WORD_SIZE/WRITE_SIZE; i=i+1) begin
            if (wm1_reg[i])
                OUT_data[(WRITE_SIZE*i)+:WRITE_SIZE] <= data1_reg[(WRITE_SIZE*i)+:WRITE_SIZE];
        end
    end
end

always@(posedge clk) begin

    ce1_reg <= IN_nce1;
    we1_reg <= IN_nwe1;
    addr1_reg <= IN_addr1;
    data1_reg <= IN_data1;
    wm1_reg <= IN_wm1;

    if (!ce1_reg) begin
        if (!we1_reg) begin
            for (integer i = 0; i < WORD_SIZE/WRITE_SIZE; i=i+1) begin
                if (wm1_reg[i])
                    mem[addr1_reg][(WRITE_SIZE*i)+:WRITE_SIZE] <= data1_reg[(WRITE_SIZE*i)+:WRITE_SIZE];
            end
        end
        //else begin
            OUT_data1 <= mem[addr1_reg];
        //end
        //if (addr1_reg == {32'h0A0}[$clog2(NUM_WORDS)-1:0] && WORD_SIZE == 128)
        //    $display("[%d] %m: read %x from %x", $time(), mem[addr1_reg], addr1_reg);
    end

    if (!ce1_reg && !ce_reg && addr1_reg == addr_reg && !we_reg) begin
        for (integer i = 0; i < WORD_SIZE/WRITE_SIZE; i=i+1) begin
            if (wm_reg[i])
                OUT_data1[(WRITE_SIZE*i)+:WRITE_SIZE] <= data_reg[(WRITE_SIZE*i)+:WRITE_SIZE];
        end
    end
end

endmodule
