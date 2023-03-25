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
    input wire[31:0] IN_EXT_bus
);

reg active;
reg isWrite;

reg[LEN_BITS-1:0] lenCnt;
reg[2:0] waitCycles;

assign OUT_busy = active;

always_comb begin

    OUT_advance = !rst && active && waitCycles == 0;
    OUT_data = 'x;
    
    if (OUT_advance && !isWrite)
        OUT_data = IN_EXT_bus;
end

always_ff@(posedge clk) begin
    
    OUT_EXT_en <= 0;
    
    if (rst) begin
        OUT_EXT_oen <= 1;
        active <= 0;
    end
    else begin
        
        if (!active && IN_en) begin
            OUT_EXT_oen <= 1;
            OUT_EXT_bus <= {IN_write, 1'b0, IN_addr};
            
            lenCnt <= IN_len;
            isWrite <= IN_write;
            
            active <= 1;
            
            OUT_EXT_en <= 1;
            
            if (IN_write)
                waitCycles <= 2;
            else
                waitCycles <= 4;
        end
        else if (active) begin
            
            OUT_EXT_en <= 1;

            if (waitCycles != 0) begin
                waitCycles <= waitCycles - 1;
                if (waitCycles == 1) begin
                    OUT_EXT_oen <= isWrite;
                    if (lenCnt <= 2) OUT_EXT_en <= 0;
                end
            end
            else begin
                
                if (isWrite) begin
                    OUT_EXT_bus <= IN_data;
                    if (lenCnt == 1) active <= 0;
                    else lenCnt <= lenCnt - 1;
                end
                else begin
                    if (lenCnt <= 2) OUT_EXT_en <= 0;
                    
                    if (lenCnt == 1) active <= 0;
                    else lenCnt <= lenCnt - 1;
                end
            end
        end
    end
end

endmodule
