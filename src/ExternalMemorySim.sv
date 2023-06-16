
// Address for the simulated 8250 UART stub
// This must be between EXT_MMIO_START_ADDR and EXT_MMIO_END_ADDR!
`define SERIAL_ADDR 32'h1000_0000

module ExternalMemorySim#(parameter SIZE=(1<<24))
(
    input wire clk,
    input wire en,
    output wire OUT_oen,
    output reg OUT_stall,
    input wire[31:0] IN_bus,
    output wire[31:0] OUT_bus
);


reg oen = 0;
reg[31:0] outBus;
assign OUT_bus = oen ? outBus : 32'bx;
wire[31:0] inBus = oen ? outBus : IN_bus;

assign OUT_oen = oen;

reg[31:0] mem[SIZE-1:0] /*verilator public*/;
reg[31:0] addr;
reg[1:0] state = 2'b00;

initial state = 0;

reg[2:0] waitCycles;
reg inputAvail /*verilator public*/ = 0;
reg[7:0] inputByte /*verilator public*/;
reg[31:0] mmioDummy;

always_ff@(posedge clk) begin
    
    OUT_stall <= 0;

    case (state)
        // lookup
        0: begin
            oen <= 0;
            if (en) begin
                addr <= inBus;
                // Write
                if (IN_bus[31] == 1) begin
                    state <= 2;
                end
                // Read
                else begin
                    if (IN_bus[29] == 0) begin // MMIO read
                        
                        reg[3:0] rmask = IN_bus[28:25];

                        if (rmask == 4'b0001 && ({IN_bus[29:0], 2'b0} & (~32'h78000000)) == ((`SERIAL_ADDR) & (~32'h78000000))) begin
                            outBus <= {24'b0, inputAvail ? inputByte : 8'b0};
                            inputAvail <= 0;
                        end
                        else if (rmask == 4'b0010 && ({IN_bus[29:0], 2'b0} & (~32'h78000000)) == ((`SERIAL_ADDR + 4) & (~32'h78000000)))
                            outBus <= 32'h6000 | (inputAvail ? 32'h0100 : 32'h0);
                        else
                            outBus <= mmioDummy;

                        OUT_stall <= 0;
                        state <= 0;
                        oen <= 1;
                    end
                    else begin
                        // Request one delay cycle such that the read isn't comb
                        OUT_stall <= 1;
                        state <= 3;
                        oen <= 1;
                    end
                end
            end
        end
        
        // wait cycles
        1: begin
            if (waitCycles == 0) state <= addr[31] ? 2 : 3;
            waitCycles <= waitCycles - 1;
        end
        
        // write
        2: begin
            if (en) begin
                // MMIO
                if (addr[29] == 0) begin

                    reg[3:0] rmask = addr[28:25];
                    if (rmask == 4'b0001 && ({addr[29:0], 2'b0} & (~32'h78000000)) == (`SERIAL_ADDR & (~32'h78000000))) begin
                        $write("%c", IN_bus[7:0] & 8'd127);
                        $fflush(32'h80000001);
                    end
                    else begin
                        for (integer i = 0; i < 4; i=i+1)
                            if (addr[29-4+i]) mmioDummy[8*i+:8] <= inBus[8*i+:8];
                    end
                end
                else begin
                    mem[addr[$clog2(SIZE)-1:0]] <= inBus;
                    addr[28:0] <= addr[28:0] + 1;
                end
            end
            else state <= 0;
        end
        
        // read
        3: begin
            if (en) begin
                outBus <= mem[addr[$clog2(SIZE)-1:0]];
                addr[28:0] <= addr[28:0] + 1;
                oen <= 1;
            end
            else begin 
                state <= 0;
                oen <= 0;
            end
        end
    endcase
end

endmodule
