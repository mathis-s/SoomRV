module MemoryInterface
#(parameter LEN_BITS=8)
(
    input wire clk,
    input wire rst,
    
    // Setup
    input wire IN_en,
    input wire IN_write,
    input wire[LEN_BITS-1:0] IN_len,
    input wire[29:0] IN_addr,
    output wire OUT_busy,
    
    // Stream
    output reg OUT_advance,
    input wire[31:0] IN_data,
    output reg[31:0] OUT_data,
    
    // Memory Interface
    output reg OUT_EXT_oen,
    output reg OUT_EXT_en,
    output reg[31:0] OUT_EXT_bus,
    input wire IN_EXT_stall,
    input wire[31:0] IN_EXT_bus
);

reg active;
reg isWrite;

reg[LEN_BITS-1:0] lenCnt;
reg[2:0] waitCycles;
reg[29:0] addr;

assign OUT_busy = active;

/*always_comb begin
    OUT_advance = !rst && active && waitCycles == 0;
    OUT_data = 'x;
    
    if (OUT_advance && !isWrite)
        OUT_data = IN_EXT_bus; // should probably register this...
end*/

always_ff@(posedge clk) begin
    
    OUT_EXT_en <= 0;
    OUT_advance <= 0;
    OUT_data <= 'x;
    
    if (rst) begin
        OUT_EXT_oen <= 1;
        active <= 0;
    end
    else begin
        if (!active && IN_en) begin
            
            if (!IN_write) begin
                OUT_EXT_en <= 1;
                OUT_EXT_oen <= 1;
                OUT_EXT_bus <= {IN_write, IN_len == 128, IN_addr};
            end
            
            lenCnt <= IN_len;
            isWrite <= IN_write;
            addr <= IN_addr;
            active <= 1;
            
            if (IN_write)
                waitCycles <= 2;
            else
                waitCycles <= 1;
        end
        else if (active) begin
            
            if (isWrite) begin
                if (waitCycles <= 1) begin
                    OUT_EXT_en <= 1;
                end
                if (waitCycles == 1) begin
                    OUT_EXT_oen <= 1;
                    OUT_EXT_bus <= {isWrite, IN_len == 128, addr};
                    OUT_advance <= 1;
                end
            end
            if (!isWrite) OUT_EXT_en <= 1;

            if (waitCycles != 0) begin
                waitCycles <= waitCycles - 1;
                if (waitCycles == 1) begin
                    OUT_EXT_oen <= isWrite;
                    if (lenCnt <= 2 && !isWrite) OUT_EXT_en <= 0;
                end
            end
            else begin
                // Write
                if (isWrite) begin
                    OUT_advance <= !IN_EXT_stall;
                    if (OUT_advance) begin
                        OUT_EXT_bus <= IN_data;
                        if (lenCnt == 1) active <= 0;
                        else lenCnt <= lenCnt - 1;
                    end
                end
                // Read
                else begin
                    if (!IN_EXT_stall) begin
                        OUT_advance <= 1;
                        OUT_data <= IN_EXT_bus;
                        
                        if (lenCnt <= 2) 
                            OUT_EXT_en <= 0;

                        if (lenCnt == 1) begin
                            active <= 0;
                            OUT_EXT_oen <= 1;
                        end
                        else lenCnt <= lenCnt - 1;
                    end 
                end
            end
        end
    end
end

endmodule
