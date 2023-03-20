module MemoryController#(parameter NUM_CACHES=2)
(
    input wire clk,
    input wire rst,
    
    input wire IN_ce,
    input wire IN_we,
    input wire[$clog2(NUM_CACHES)-1:0] IN_cacheID,
    input wire[9:0] IN_sramAddr,
    input wire[29:0] IN_extAddr,
    output reg[9:0] OUT_progress,
    output reg OUT_busy,
    
    output reg[NUM_CACHES-1:0] OUT_CACHE_used,
    output reg OUT_CACHE_we[NUM_CACHES-1:0],
    output reg OUT_CACHE_ce[NUM_CACHES-1:0],
    output reg[3:0] OUT_CACHE_wm[NUM_CACHES-1:0],
    output reg[9:0] OUT_CACHE_addr[NUM_CACHES-1:0],
    output reg[31:0] OUT_CACHE_data[NUM_CACHES-1:0],
    input wire[31:0] IN_CACHE_data[NUM_CACHES-1:0],
    
    output reg OUT_EXT_oen,
    output reg OUT_EXT_en,
    output reg[31:0] OUT_EXT_bus,
    input wire[31:0] IN_EXT_bus
    
);

integer i;

reg[2:0] state;
reg isExtWrite;

reg[9:0] sramAddr;
reg[9:0] cnt;
reg[9:0] len;
reg[$clog2(NUM_CACHES)-1:0] cacheID;

reg[2:0] waitCycles;


assign OUT_CACHE_wm[0] = 4'b1111;
assign OUT_CACHE_wm[1] = 4'b1111;


always_ff@(posedge clk) begin
    
    if (rst) begin
        state <= 0;
        for (i = 0; i < NUM_CACHES; i=i+1) begin
            OUT_CACHE_used[i] <= 0;
            OUT_CACHE_we[i] <= 1;
            OUT_CACHE_ce[i] <= 1;
        end
        OUT_busy <= 0;
        OUT_EXT_oen <= 1;
        OUT_progress <= 0;
        len <= 0;
        OUT_EXT_bus <= 0;
        OUT_EXT_en <= 0;
    end
    else begin
        
        case(state)
            
            // Idle
            0: begin
                OUT_EXT_oen <= 1;
                for (i = 0; i < NUM_CACHES; i=i+1)
                    OUT_CACHE_used[i] <= 0;
                    
                if (IN_ce) begin
                    
                    
                    if (IN_we) begin
                        // Write
                        isExtWrite <= 1;
                        state <= 2;
                        OUT_CACHE_used[cacheID] <= 1;
                        
                        // Start reading from cache immediately
                        OUT_CACHE_ce[cacheID] <= 0;
                        OUT_CACHE_we[cacheID] <= 1;
                        OUT_CACHE_addr[cacheID] <= IN_sramAddr;
                        sramAddr <= IN_sramAddr + 1;
                        cnt <= 1;
                    end
                    else begin
                        // Read
                        isExtWrite <= 0;
                        waitCycles <= 3;
                        state <= 1;
                        cnt <= 0;
                        sramAddr <= IN_sramAddr;
                    end
                    
                    cacheID <= IN_cacheID;
                    
                    
                    if (IN_cacheID == 0) len <= 64;
                    else len <= 128;
                    
                    // External RAM
                    OUT_EXT_en <= 1;
                    OUT_EXT_bus <= {IN_we, IN_cacheID[0], IN_extAddr[29:0]};
                    OUT_EXT_oen <= 1;
                    
                    // Interface
                    OUT_busy <= 1;
                    OUT_progress <= 0;
                end
                else begin
                    for (i = 0; i < NUM_CACHES; i=i+1) begin
                        OUT_CACHE_we[i] <= 1;
                        OUT_CACHE_ce[i] <= 1;
                    end
                    OUT_busy <= 0;
                    OUT_EXT_en <= 0;
                    OUT_progress <= 0;
                    OUT_EXT_bus <= 0;
                end
            end
            
            
            // Wait until external memory is ready to send data
            1: begin
                if (waitCycles == 0) begin
                    state <= 3;
                    OUT_EXT_oen <= 0;
                    OUT_CACHE_used[cacheID] <= 1;
                end
                waitCycles <= waitCycles - 1;
            end
            
            // Write to External
            2: begin
                // Read from SRAM
                OUT_CACHE_ce[cacheID] <= !(cnt < len);
                OUT_CACHE_we[cacheID] <= 1;
                OUT_CACHE_addr[cacheID] <= sramAddr;
                if (cnt < len) sramAddr <= sramAddr + 1;
                else OUT_CACHE_used[cacheID] <= 0;
                
                cnt <= cnt + 1;
                
                if (cnt == len + 3) begin
                    OUT_EXT_en <= 0;
                    state <= 0;
                    OUT_busy <= 0;
                end
                else if (cnt > 2) begin
                    OUT_EXT_bus <= IN_CACHE_data[cacheID];
                end
            end
            
            // Read from External
            3: begin
                cnt <= cnt + 1;
                if (cnt < len) begin
                    OUT_CACHE_ce[cacheID] <= 0;
                    OUT_CACHE_we[cacheID] <= 0;
                    OUT_CACHE_addr[cacheID] <= sramAddr;
                    sramAddr <= sramAddr + 1;
                    OUT_CACHE_data[cacheID] <= IN_EXT_bus;
                    OUT_progress <= OUT_progress + 1;
                end
                else begin
                    OUT_CACHE_ce[cacheID] <= 1;
                    OUT_CACHE_we[cacheID] <= 1;
                    OUT_CACHE_used[cacheID] <= 0;
                    OUT_busy <= 0;
                    OUT_progress <= 0;
                    state <= 0;
                    OUT_EXT_en <= 0;
                end
            end

        endcase
    
    end

end

endmodule
