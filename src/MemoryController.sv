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
reg[2:0] returnState;

assign OUT_CACHE_wm[0] = 4'b1111;
assign OUT_CACHE_wm[1] = 4'b1111;

wire[31:0] outDataCacheIF;
wire[0:0] idCacheIF;

// Generate control signals for cache and external memory interfaces
reg[7:0] accessLength;
reg enableCache;
reg enableExt;
reg[29:0] extAddr;

always_comb begin
    
    enableCache = 0;
    enableExt = 0;
    accessLength = 'x;
    extAddr = 'x;
    
    if (!rst && state == 0) begin
        if (IN_ctrl.cmd == MEMC_CP_CACHE_TO_EXT || IN_ctrl.cmd == MEMC_CP_EXT_TO_CACHE) begin
            enableCache = 1;
            enableExt = 1;
            extAddr = IN_ctrl.extAddr;
            accessLength = IN_ctrl.cacheID ? 128 : 32;
        end
    end
end

wire CACHEIF_busy;
CacheInterface cacheIF
(
    .clk(clk),
    .rst(rst),
    
    .IN_en(state == 0 && enableCache),
    .IN_write(IN_ctrl.cmd == MEMC_CP_EXT_TO_CACHE),
    .IN_cacheID(IN_ctrl.cacheID),
    .IN_len(accessLength),
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
    .IN_len(accessLength),
    .IN_addr(extAddr),
    .OUT_busy(MEMIF_busy),
    
    .OUT_advance(MEM_IF_advance),
    .IN_data(outDataCacheIF),
    .OUT_data(memoryIFdata),
    
    .OUT_EXT_oen(OUT_EXT_oen),
    .OUT_EXT_en(OUT_EXT_en),
    .OUT_EXT_bus(OUT_EXT_bus),
    .IN_EXT_bus(IN_EXT_bus)
);

reg[3:0] lastProgress;
always_ff@(posedge clk) begin
    
    OUT_stat.resultValid <= 0;
    
    if (rst) begin
        state <= 0;
        OUT_stat.busy <= 0;
        OUT_stat.progress <= 0;
    end
    else begin
        
        case(state)
            
            // Idle
            0: begin
                if (IN_ctrl.cmd != MEMC_NONE) begin
                    
                    // Interface
                    case (IN_ctrl.cmd)
                    
                        MEMC_CP_CACHE_TO_EXT,
                        MEMC_CP_EXT_TO_CACHE: begin
                            state <= 1;
                        end
                        
                        default: assert(0);
                    endcase
                    OUT_stat.rqID <= IN_ctrl.rqID;
                    OUT_stat.busy <= 1;
                    OUT_stat.progress <= 0;
                    lastProgress <= 0;
                end
                else begin
                    OUT_stat.busy <= 0;
                end
            end
            
            
            // Wait until transaction is done
            1: begin
                if (!MEMIF_busy && !CACHEIF_busy) begin
                    state <= 0;
                    OUT_stat.result <= 'x;
                end
                
                //lastProgress <= {lastProgress[$bits(lastProgress)-2:0], MEM_IF_advance};
                //if (lastProgress[$bits(lastProgress)-1])
                if (MEM_IF_advance)
                    OUT_stat.progress <= OUT_stat.progress + 1;
            end
        endcase
    
    end

end

endmodule
