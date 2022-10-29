module MemoryController
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
    input wire[31:0] IN_CACHE_data,
    
    output reg OUT_EXT_oen,
    output reg OUT_EXT_en,
    output reg[31:0] OUT_EXT_bus,
    input wire[31:0] IN_EXT_bus
    
);

localparam LEN=64;

reg[2:0] state;
reg isExtWrite;

reg[9:0] sramAddr;
reg[9:0] cnt;

reg[2:0] waitCycles;

assign OUT_CACHE_wm = 4'b1111;

always_ff@(posedge clk) begin
    
    if (rst) begin
        state <= 0;
        OUT_CACHE_used <= 0;
        OUT_CACHE_we <= 1;
        OUT_CACHE_ce <= 1;
        OUT_busy <= 0;
        OUT_EXT_oen <= 1;
    end
    else begin
        
        case(state)
            
            // Idle
            0: begin
                if (IN_ce) begin
                    
                    // Next state
                    if (IN_we) begin
                        isExtWrite <= 1;
                        waitCycles <= 0;
                    end
                    else begin
                        isExtWrite <= 0;
                        waitCycles <= 5;
                    end
                    
                    state <= 1;
                    
                    // SRAM 
                    sramAddr <= IN_sramAddr;
                    cnt <= 0;
                    
                    // External RAM
                    OUT_EXT_en <= 1;
                    OUT_EXT_bus <= {IN_we, 1'b0, IN_extAddr[29:0]};
                    OUT_EXT_oen <= 1;
                    
                    // Interface
                    OUT_busy <= 1;
                    OUT_CACHE_used <= 1;
                    OUT_progress <= 0;
                end
                else begin
                    OUT_CACHE_used <= 0;
                    OUT_CACHE_we <= 1;
                    OUT_CACHE_ce <= 1;
                    OUT_busy <= 0;
                    OUT_EXT_en <= 0;
                end
                
                OUT_EXT_oen <= 1;
            end
            
            
            // Wait for external memory
            1: begin
                if (waitCycles == 0) begin
                    if (isExtWrite) state <= 2;
                    else begin
                        state <= 3;
                        OUT_EXT_oen <= 0;
                    end
                end
                waitCycles <= waitCycles - 1;
            end
            
            // Write to External
            2: begin
                // Read from SRAM
                OUT_CACHE_ce <= !(cnt < LEN);
                OUT_CACHE_we <= 1;
                OUT_CACHE_addr <= sramAddr;
                if (cnt < LEN) sramAddr <= sramAddr + 1;
                else OUT_CACHE_used <= 0;
                
                cnt <= cnt + 1;
                
                if (cnt == LEN + 3) begin
                    OUT_EXT_en <= 0;
                    state <= 0;
                    OUT_busy <= 0;
                end
                else if (cnt > 2) begin
                    OUT_EXT_bus <= IN_CACHE_data;
                end
            end
            
            // Read from External
            3: begin
                cnt <= cnt + 1;
                if (cnt < LEN) begin
                    OUT_CACHE_ce <= 0;
                    OUT_CACHE_we <= 0;
                    OUT_CACHE_addr <= sramAddr;
                    sramAddr <= sramAddr + 1;
                    OUT_CACHE_data <= IN_EXT_bus;
                end
                else begin
                    OUT_CACHE_ce <= 1;
                    OUT_CACHE_we <= 1;
                    OUT_CACHE_used <= 0;
                    OUT_busy <= 0;
                    state <= 0;
                    OUT_EXT_en <= 0;
                end
            end

        endcase
    
    end

end

endmodule
