module CacheReadInterface
#(parameter ADDR_BITS=10, parameter LEN_BITS=8, parameter IWIDTH=128, parameter CWIDTH=32, parameter BUF_LEN=4)
(
    input wire clk,
    input wire rst,
    
    // Set at start of transaction
    input wire IN_en,
    input wire[LEN_BITS-1:0] IN_len,
    input wire[ADDR_BITS-1:0] IN_addr,
    output wire OUT_busy,

    // Streaming
    input wire IN_valid,
    output reg OUT_valid,
    output reg[IWIDTH-1:0] OUT_data,
    

    // Cache Interface
    output reg OUT_CACHE_ce,
    output reg OUT_CACHE_we,
    output reg[ADDR_BITS-1:0] OUT_CACHE_addr,
    output reg[31:0] OUT_CACHE_data,
    input wire[31:0] IN_CACHE_data
);

localparam WNUM = IWIDTH / CWIDTH;

reg active;
assign OUT_busy = active;

reg[LEN_BITS-1:0] lenCnt;
reg[ADDR_BITS-1:0] addrCnt;

reg[1:0] readRequests;

reg[$clog2(BUF_LEN):0] readBufferCnt;
wire[$clog2(BUF_LEN):0] readBufferRqCnt = readBufferCnt + {1'b0, readRequests[0]} + {1'b0, readRequests[1]};

reg[IWIDTH-1:0] readBuffer[BUF_LEN-1:0];
reg[$clog2(BUF_LEN)-1:0] readBufferInsertIdx;
reg[$clog2(WNUM):0] readBufferInsertWordIdx;
reg[$clog2(BUF_LEN)-1:0] readBufferOutputIdx;

reg readToBuffer;
always_comb begin
    
    readToBuffer = 0;
    
    OUT_CACHE_ce = 1;
    OUT_CACHE_we = 'x;
    OUT_CACHE_addr = 'x;
    OUT_CACHE_data = 'x;
    
    OUT_valid = 0;
    OUT_data = 'x;
    
    if (active) begin
        if (IN_valid && readBufferCnt != 0) begin
            OUT_data = readBuffer[readBufferOutputIdx];
            OUT_valid = 1;
        end
        
        if ((readBufferCnt < (BUF_LEN-1) || IN_valid) && lenCnt != 0) begin
            OUT_CACHE_ce = 0;
            OUT_CACHE_we = 1;
            OUT_CACHE_addr = addrCnt;
            readToBuffer = 1;
        end
    end
end

always_ff@(posedge clk) begin
    if (rst) begin
        active <= 0;
    end
    else begin
        
        readRequests <= {readRequests[0], 1'b0};
        
        if (!active && IN_en) begin
            active <= 1;
            lenCnt <= IN_len;
            addrCnt <= IN_addr;
            readBufferInsertIdx = 0;
            readBufferOutputIdx = 0;
            readBufferCnt = 0;
            readRequests <= 0;
        end
        else if (active) begin   

            // Output from FIFO     
            if (OUT_valid) begin         
                readBufferOutputIdx = readBufferOutputIdx + 1;
                readBufferCnt = readBufferCnt - 1;
            end
            
            // Write into FIFO from cache
            if (readRequests[1]) begin

                reg[$clog2(WNUM):0] nextWordIdx = readBufferInsertWordIdx + 1;

                readBuffer[readBufferInsertIdx][readBufferInsertWordIdx*CWIDTH +: CWIDTH] <= IN_CACHE_data;
                
                readBufferInsertWordIdx <= nextWordIdx;
                if (nextWordIdx[$clog2(WNUM)]) begin
                    readBufferInsertWordIdx <= 0;
                    readBufferCnt = readBufferCnt + 1;
                    readBufferInsertIdx = readBufferInsertIdx + 1;
                end
            end
            
            // Read new data from cache into buffer if space is available
            if (readToBuffer) begin
                readRequests <= {readRequests[0], 1'b1}; 
                addrCnt[`CLSIZE_E-3:0] <= addrCnt[`CLSIZE_E-3:0] + 1;
                lenCnt <= lenCnt - 1;
            end
        end
    end
end




endmodule
