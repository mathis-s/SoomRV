
module ExternalBusMem#(parameter WIDTH=32, parameter LEN = 1<<24)
(
    input wire clk,
    input wire rst,

    output logic OUT_busOE,
    output logic[WIDTH-1:0] OUT_bus,
    input logic[WIDTH-1:0] IN_bus,
    output logic OUT_busReady,
    input logic IN_busValid
);
localparam COUNT_LEN = `CLSIZE_E - 2;

reg[WIDTH-1:0] mem[LEN-1:0] /* verilator public */;


enum logic[1:0]
{
    IDLE,
    READ,
    WRITE
} state;

reg[COUNT_LEN-1:0] curCnt;
reg[1:0] curSize;
reg[28:0] addr;

logic inputAvail /*verilator public*/ = 0;
logic[7:0] inputByte /*verilator public*/;

logic serialRead;
always_comb begin
    OUT_bus = 'x;
    OUT_busOE = 0;
    serialRead = 0;

    if (!rst && state == READ) begin
        OUT_busOE = 1;
        if (curSize != 3) begin
            if (addr == 29'h10000000) begin
                OUT_bus = {24'b0, inputByte};
                serialRead = 1;
            end
            if (addr == 29'h10000005) OUT_bus = 32'h60 | (inputAvail ? 32'b1 : 32'b0);
        end
        else OUT_bus = mem[addr[25:2]];
    end
end

always_ff@(posedge clk) begin
    OUT_busReady <= 1;//1'($random());
end
//assign OUT_busReady = 1;

always_ff@(posedge clk) begin
    if (rst) state <= IDLE;
    else begin

        if (serialRead)
            inputAvail <= 0;

        case (state)
            IDLE: begin
                if (OUT_busReady && IN_busValid) begin
                    curCnt <= (IN_bus[30-:2] != 2'b11) ? {COUNT_LEN{1'b1}} : {COUNT_LEN{1'b0}};
                    curSize <= IN_bus[30-:2];
                    state <= IN_bus[31] ? WRITE : READ;
                    addr <= IN_bus[28:0];
                end
            end
            WRITE: begin
                if (OUT_busReady && IN_busValid) begin

                    if (curSize != 3) begin
                        if (addr == 29'h10000000) begin
                            $write("%c", IN_bus[7:0]);
                            $fflush(32'h80000001);
                        end
                    end
                    else mem[addr[25:2]] <= IN_bus;

                    addr <= {addr[28:`CLSIZE_E], addr[`CLSIZE_E-1:2] + 1'b1, addr[1:0]};
                    curCnt <= curCnt + 1;
                    if (curCnt == {COUNT_LEN{1'b1}}) state <= IDLE;
                end
            end
            READ: begin
                if (OUT_busReady && IN_busValid) begin
                    addr <= {addr[28:`CLSIZE_E], addr[`CLSIZE_E-1:2] + 1'b1, addr[1:0]};
                    curCnt <= curCnt + 1;
                    if (curCnt == {COUNT_LEN{1'b1}}) state <= IDLE;
                end
            end
            default: state <= IDLE;
        endcase
    end
end

endmodule
