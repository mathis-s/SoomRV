module RF
#(
    parameter NUM_READ = 6,
    parameter NUM_WRITE = 3,
    parameter SIZE=64
)
(
    input wire clk,
    input wire rst,

    input wire IN_readEnable[NUM_READ-1:0],
    input wire[5:0] IN_readAddress[NUM_READ-1:0],
    output reg[31:0] OUT_readData[NUM_READ-1:0],

    input wire IN_writeEnable[NUM_WRITE-1:0],
    input wire[5:0] IN_writeAddress[NUM_WRITE-1:0],
    input wire[31:0] IN_writeData[NUM_WRITE-1:0]
);

integer i;
reg[31:0] mem[SIZE-1:0];

always_comb begin
    for (i = 0; i < NUM_READ; i=i+1) begin
        if (IN_readEnable[i]) begin
            OUT_readData[i] = mem[IN_readAddress[i]];
        end
        else
            OUT_readData[i] = 32'bx;
    end
end

always_ff@(posedge clk) begin

    if (rst) begin
        
    end
    else begin
        for (i = 0; i < NUM_WRITE; i=i+1) begin
            if (IN_writeEnable[i]) begin
                mem[IN_writeAddress[i]] <= IN_writeData[i];
            end
        end
    end
end

endmodule
