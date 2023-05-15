

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
reg[31:0] mmioDummy = 0;

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
                    //waitCycles <= 0;
                    state <= 2;
                end
                // Read
                else begin
                    if (IN_bus[29] == 0) begin // MMIO read
                        outBus <= mmioDummy;
                        mmioDummy <= mmioDummy + 1;
                        OUT_stall <= 0;
                        state <= 0;
                        oen <= 1;
                    end
                    else begin
                        // Request one delay cycle such that the read isn't comb
                        OUT_stall <= 1;
                        state <= 3;
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
                mem[addr[$clog2(SIZE)-1:0]] <= inBus;
                addr[29:0] <= addr[29:0] + 1;
            end
            else state <= 0;
        end
        
        // read
        3: begin
            if (en) begin
                outBus <= mem[addr[$clog2(SIZE)-1:0]];
                addr[29:0] <= addr[29:0] + 1;
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
