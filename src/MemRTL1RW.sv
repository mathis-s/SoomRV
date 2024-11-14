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

`ifdef SYNTHESIS

localparam NUM_RAMS = (WORD_SIZE + 63) / 64;
localparam WORD_SIZE_POW2 = 1 << $clog2(WORD_SIZE);
wire[WORD_SIZE_POW2-1:0] data_reg_pad = {{WORD_SIZE_POW2-WORD_SIZE{1'bx}}, data_reg};
wire[WORD_SIZE_POW2-1:0] data_out_pad;
assign OUT_data = data_out_pad[0 +: WORD_SIZE];

logic[WORD_SIZE_POW2-1:0] wmask;
always_comb begin
    for (integer i = 0; i < WORD_SIZE; i=i+1)
        wmask[i] = wm_reg[i / WRITE_SIZE];
end

generate for (genvar i = 0; i < NUM_RAMS; i=i+1) begin : gen
    if (NUM_WORDS == 64) RM_IHPSG13_1P_64x64_c2_bm_bist ram
    (
        .A_CLK(clk),
        .A_MEN(1'b1),
        .A_WEN(1'b0),
        .A_REN(!ce_reg),
        .A_ADDR(addr_reg),
        .A_DIN(64'b0),
        .A_DLY(1'b0),
        .A_DOUT(data_out_pad[i * 64 +: 64]),
        .A_BM(64'b0),

        .A_BIST_CLK(clk),
        .A_BIST_EN(!we_reg),
        .A_BIST_MEN(1'b1),
        .A_BIST_WEN(!ce_reg),
        .A_BIST_REN(1'b0),
        .A_BIST_ADDR(addr_reg),
        .A_BIST_DIN(data_reg_pad[i * 64 +: 64]),
        .A_BIST_BM(wmask[i * 64 +: 64])
    );
    if (NUM_WORDS == 256) RM_IHPSG13_1P_256x64_c2_bm_bist ram
    (
        .A_CLK(clk),
        .A_MEN(1'b1),
        .A_WEN(1'b0),
        .A_REN(!ce_reg),
        .A_ADDR(addr_reg),
        .A_DIN(64'b0),
        .A_DLY(1'b0),
        .A_DOUT(data_out_pad[i * 64 +: 64]),
        .A_BM(64'b0),

        .A_BIST_CLK(clk),
        .A_BIST_EN(!we_reg),
        .A_BIST_MEN(1'b1),
        .A_BIST_WEN(!ce_reg),
        .A_BIST_REN(1'b0),
        .A_BIST_ADDR(addr_reg),
        .A_BIST_DIN(data_reg_pad[i * 64 +: 64]),
        .A_BIST_BM(wmask[i * 64 +: 64])
    );
    if (NUM_WORDS == 512) RM_IHPSG13_1P_512x64_c2_bm_bist ram
    (
        .A_CLK(clk),
        .A_MEN(1'b1),
        .A_WEN(1'b0),
        .A_REN(!ce_reg),
        .A_ADDR(addr_reg),
        .A_DIN(64'b0),
        .A_DLY(1'b0),
        .A_DOUT(data_out_pad[i * 64 +: 64]),
        .A_BM(64'b0),

        .A_BIST_CLK(clk),
        .A_BIST_EN(!we_reg),
        .A_BIST_MEN(1'b1),
        .A_BIST_WEN(!ce_reg),
        .A_BIST_REN(1'b0),
        .A_BIST_ADDR(addr_reg),
        .A_BIST_DIN(data_reg_pad[i * 64 +: 64]),
        .A_BIST_BM(wmask[i * 64 +: 64])
    );
    if (NUM_WORDS == 1024) RM_IHPSG13_1P_1024x64_c2_bm_bist ram
    (
        .A_CLK(clk),
        .A_MEN(1'b1),
        .A_WEN(1'b0),
        .A_REN(!ce_reg),
        .A_ADDR(addr_reg),
        .A_DIN(64'b0),
        .A_DLY(1'b0),
        .A_DOUT(data_out_pad[i * 64 +: 64]),
        .A_BM(64'b0),

        .A_BIST_CLK(clk),
        .A_BIST_EN(!we_reg),
        .A_BIST_MEN(1'b1),
        .A_BIST_WEN(!ce_reg),
        .A_BIST_REN(1'b0),
        .A_BIST_ADDR(addr_reg),
        .A_BIST_DIN(data_reg_pad[i * 64 +: 64]),
        .A_BIST_BM(wmask[i * 64 +: 64])
    );
end endgenerate
`else

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
`endif

endmodule
