

module ExternalMemorySim#(parameter SIZE=1048576)
(
    input wire clk,
    input wire en,
    inout wire[31:0] bus
);

integer i;

reg oen = 0;
reg[31:0] outBus;
assign bus = oen ? outBus : 32'bz;

reg[31:0] mem[SIZE-1:0] /*verilator public*/;
reg[31:0] addr;
reg[1:0] state = 2'b00;

initial state = 0;

reg[2:0] waitCycles;

always_ff@(posedge clk) begin
    case (state)
        
        // lookup
        0: begin
            if (en) begin
                addr <= bus;
                waitCycles <= 3;
                state <= 1;
            end
            oen <= 0;
        end
        
        // wait cycles
        1: begin
            if (waitCycles == 0) state <= addr[31] ? 2 : 3;
            waitCycles <= waitCycles - 1;
        end
        
        // write
        2: begin
            if (en) begin
                mem[addr[19:0]] <= bus;
                addr[29:0] <= addr[29:0] + 1;
            end
            else state <= 0;
        end
        
        // read
        3: begin
            if (en) begin
                outBus <= mem[addr[19:0]];
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

wire[31:0] data = mem[4096];

endmodule
