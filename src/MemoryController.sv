module MemoryController#(parameter NUM_CACHES=2)
(
    input wire clk,
    input wire rst,
    
    input CTRL_MemC IN_ctrl,
    output STAT_MemC OUT_stat,
    
    //output reg[NUM_CACHES-1:0] OUT_CACHE_used,
    output reg OUT_CACHE_we[NUM_CACHES-1:0],
    output reg OUT_CACHE_ce[NUM_CACHES-1:0],
    output reg[3:0] OUT_CACHE_wm[NUM_CACHES-1:0],
    output reg[9:0] OUT_CACHE_addr[NUM_CACHES-1:0],
    output reg[31:0] OUT_CACHE_data[NUM_CACHES-1:0],
    input wire[31:0] IN_CACHE_data[NUM_CACHES-1:0],
    
    output wire OUT_EXT_oen,
    output wire OUT_EXT_en,
    output wire[31:0] OUT_EXT_bus,
    input wire[31:0] IN_EXT_bus
    
);

integer i;

reg[2:0] state;

assign OUT_CACHE_wm[0] = 4'b1111;
assign OUT_CACHE_wm[1] = 4'b1111;

wire[31:0] outDataCacheIF;
wire[0:0] idCacheIF;

wire CACHEIF_busy;
CacheInterface cacheIF
(
    .clk(clk),
    .rst(rst),
    
    .IN_en(state == 0 && IN_ctrl.cmd != MEMC_NONE),
    .IN_write(IN_ctrl.cmd == MEMC_CP_EXT_TO_CACHE),
    .IN_cacheID(IN_ctrl.cacheID),
    .IN_len(IN_ctrl.cacheID ? 128 : 64),
    .IN_addr(IN_ctrl.sramAddr),
    .OUT_busy(CACHEIF_busy),
    
    .IN_valid(MEM_IF_advance),
    .IN_data(memoryIFdata),
    .OUT_data(outDataCacheIF),
    
    .OUT_CACHE_id(idCacheIF),
    .OUT_CACHE_ce(OUT_CACHE_ce[idCacheIF]),
    .OUT_CACHE_we(OUT_CACHE_we[idCacheIF]),
    .OUT_CACHE_addr(OUT_CACHE_addr[idCacheIF]),
    .OUT_CACHE_data(OUT_CACHE_data[idCacheIF]),
    .IN_CACHE_data(IN_CACHE_data[idCacheIF])
);

wire MEM_IF_advance;
wire[31:0] memoryIFdata;
wire MEMIF_busy;
MemoryInterface memoryIF
(
    .clk(clk),
    .rst(rst),
    
    .IN_en(state == 0 && IN_ctrl.cmd != MEMC_NONE),
    .IN_write(IN_ctrl.cmd == MEMC_CP_CACHE_TO_EXT),
    .IN_len(IN_ctrl.cacheID ? 128 : 64),
    .IN_addr(IN_ctrl.extAddr),
    .OUT_busy(MEMIF_busy),
    
    .OUT_advance(MEM_IF_advance),
    .IN_data(outDataCacheIF),
    .OUT_data(memoryIFdata),
    
    .OUT_EXT_oen(OUT_EXT_oen),
    .OUT_EXT_en(OUT_EXT_en),
    .OUT_EXT_bus(OUT_EXT_bus),
    .IN_EXT_bus(IN_EXT_bus)
);

always_ff@(posedge clk) begin
    
    if (rst) begin
        state <= 0;
        //for (i = 0; i < NUM_CACHES; i=i+1) begin
        //    OUT_CACHE_used[i] <= 0;
        //end
        OUT_stat.busy <= 0;
        OUT_stat.progress <= 0;
    end
    else begin
        
        case(state)
            
            // Idle
            0: begin
                //for (i = 0; i < NUM_CACHES; i=i+1)
                //    OUT_CACHE_used[i] <= 0;
                    
                if (IN_ctrl.cmd != MEMC_NONE) begin
                    
                    //OUT_CACHE_used[IN_ctrl.cacheID] <= 1;
                    
                    // Interface
                    OUT_stat.busy <= 1;
                    OUT_stat.progress <= 0;
                    OUT_stat.cacheID <= IN_ctrl.cacheID;
                    
                    state <= 1;
                end
                else begin
                    OUT_stat.busy <= 0;
                    OUT_stat.progress <= 0;
                end
            end
            
            
            // Wait until transaction is done
            1: begin
                if (!MEMIF_busy && !CACHEIF_busy) 
                    state <= 0;
            end

        endcase
    
    end

end

endmodule
