module MemoryControllerSim
(
    input wire clk,
    input wire rst,
    
    input wire IN_ce,
    input wire IN_we,
    input wire[9:0] IN_sramAddr,
    input wire[31:0] IN_extAddr,
    output reg[9:0] OUT_progress,
    output reg OUT_busy,
    
    output reg OUT_CACHE_used,
    output reg OUT_CACHE_we,
    output reg OUT_CACHE_ce,
    output wire[3:0] OUT_CACHE_wm,
    output reg[9:0] OUT_CACHE_addr,
    output reg[31:0] OUT_CACHE_data,
    input wire[31:0] IN_CACHE_data
);

localparam LEN=64;

reg[3:0] state;

reg[31:0] extRAM[65535:0] /*verilator public*/;

reg[31:0] extAddr;
reg[9:0] sramAddr;
reg[9:0] cnt;

assign OUT_CACHE_wm = 4'b1111;

always_ff@(posedge clk) begin
    
    if (rst) begin
        state <= 0;
        OUT_CACHE_used <= 0;
        OUT_CACHE_we <= 1;
        OUT_CACHE_ce <= 1;
        OUT_busy <= 0;
    end
    else begin
        
        case(state)
            
            // Idle
            0: begin
                if (IN_ce) begin
                    if (IN_we) begin
                        state <= 1;
                    end
                    else begin
                        state <= 2;
                    end
                    
                    extAddr <= IN_extAddr;
                    sramAddr <= IN_sramAddr;
                    OUT_busy <= 1;
                    OUT_CACHE_used <= 1;
                    cnt <= 0;
                    OUT_progress <= 0;
                end
                else begin
                    OUT_CACHE_used <= 0;
                    OUT_CACHE_we <= 1;
                    OUT_CACHE_ce <= 1;
                    OUT_busy <= 0;
                end
            end
            
            // Read from Cache
            1: begin
                
                cnt <= cnt + 1;
                if (cnt == LEN + 3) begin
                    OUT_CACHE_ce <= 1;
                    state <= 0;
                    OUT_busy <= 0;
                    OUT_CACHE_used <= 0;
                end
                else begin
                    if (cnt < LEN) begin
                        OUT_CACHE_ce <= 0;
                        OUT_CACHE_we <= 1;
                        OUT_CACHE_addr <= sramAddr;
                        sramAddr <= sramAddr + 1;
                    end
                    else
                        OUT_CACHE_ce <= 1;
                    
                    if (cnt > 2) begin
                        extRAM[extAddr] <= IN_CACHE_data;
                        //$display("write %x to %x", IN_CACHE_data, extAddr);
                        extAddr <= extAddr + 1;
                        OUT_progress <= OUT_progress + 1;
                    end
                end
                
            end
            
            // Write to Cache
            2: begin
                cnt <= cnt + 1;
                if (cnt == LEN) begin
                    OUT_CACHE_ce <= 1;
                    state <= 0;
                    OUT_busy <= 0;
                    OUT_CACHE_used <= 0;
                end
                else begin
                    OUT_CACHE_ce <= 0;
                    OUT_CACHE_we <= 0;
                    
                    OUT_CACHE_addr <= sramAddr;
                    OUT_CACHE_data <= extRAM[extAddr];
                    
                    sramAddr <= sramAddr + 1;
                    extAddr <= extAddr + 1;
                end
            end

        endcase
    
    end

end

endmodule
