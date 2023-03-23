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
reg pageWalkLevel;

reg[29:0] rqExtAddr;

// Generate control signals for cache and external memory interfaces
reg[7:0] accessLength;
reg enableCache;
reg enableExt;
reg[29:0] extAddr;

reg pageWalkNextLookup;
always_comb begin
    
    enableCache = 0;
    enableExt = 0;
    pageWalkNextLookup = 0;
    accessLength = 'x;
    extAddr = 'x;
    
    if (!rst && state == 0) begin
        if (IN_ctrl.cmd == MEMC_PAGE_WALK) begin
            extAddr = {IN_ctrl.rootPPN[19:0], IN_ctrl.extAddr[19:10]};
            accessLength = 1;
            enableExt = 1;
        end
        else if (IN_ctrl.cmd == MEMC_CP_CACHE_TO_EXT || IN_ctrl.cmd == MEMC_CP_EXT_TO_CACHE) begin
            enableCache = 1;
            enableExt = 1;
            extAddr = IN_ctrl.extAddr;
            accessLength = IN_ctrl.cacheID ? 128 : 64;
        end
    end
    
    // Page Walk Next Lookup
    if (!rst && state == 3 && !MEMIF_busy) begin
        
        pageWalkNextLookup = 1;
        accessLength = 1;
        enableExt = 1;
        // NOTE: currently ignoring the upper two bits of 34 bit phy addr
        extAddr = {OUT_stat.result[29:10], rqExtAddr[29:20]};
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
                        
                        MEMC_PAGE_WALK: begin
                            state <= 2;
                            pageWalkLevel <= 0;
                        end
                        
                        default: assert(0);
                    endcase
                    OUT_stat.rqID <= IN_ctrl.rqID;
                    rqExtAddr <= IN_ctrl.extAddr;
                    OUT_stat.busy <= 1;
                end
                else begin
                    OUT_stat.busy <= 0;
                end
            end
            
            
            // Wait until transaction is done
            1: begin
                if (!MEMIF_busy && !CACHEIF_busy) 
                    state <= 0;
            end
            
            // Page Walk: Wait for lookup
            2: begin
                if (MEM_IF_advance) begin
                    OUT_stat.result <= memoryIFdata;
                    
                    // Pointer to next page
                    if (memoryIFdata[3:1] == 3'b000 && memoryIFdata[0] && pageWalkLevel == 0) begin
                        state <= 3;
                        pageWalkLevel <= 1;
                    end
                    // Invalid or leaf page
                    else begin
                        state <= 0;
                        OUT_stat.resultValid <= 1;
                    end
                end
            end
            
            // Page Walk: Begin Next Lookup
            3: begin
                if (pageWalkNextLookup)
                    state <= 2;
            end

        endcase
    
    end

end

endmodule
