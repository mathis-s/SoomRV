module CacheInterface
#(parameter ADDR_BITS=10, parameter LEN_BITS=8, parameter ID_BITS=1)
(
    input wire clk,
    input wire rst,

    // Set at start of transaction
    input wire IN_en,
    input wire IN_write,
    input wire[ID_BITS-1:0] IN_cacheID,
    input wire[LEN_BITS-1:0] IN_len,
    input wire[ADDR_BITS-1:0] IN_addr,
    output wire OUT_busy,

    // Streaming
    input wire IN_valid,
    input wire[31:0] IN_data,
    output reg OUT_valid,
    output reg[31:0] OUT_data,


    // Cache Interface
    output reg[ID_BITS-1:0] OUT_CACHE_id,
    output reg OUT_CACHE_ce,
    output reg OUT_CACHE_we,
    output reg[ADDR_BITS-1:0] OUT_CACHE_addr,
    output reg[31:0] OUT_CACHE_data,
    input wire[31:0] IN_CACHE_data
);


reg active;
assign OUT_busy = active;
reg isWrite;

reg[ID_BITS-1:0] cacheID;
reg[LEN_BITS-1:0] lenCnt;
reg[ADDR_BITS-1:0] addrCnt;

reg[1:0] readRequests;

reg[1:0] readBufferCnt;
wire[1:0] readBufferRqCnt = readBufferCnt + {1'b0, readRequests[0]} + {1'b0, readRequests[1]};

reg[0:0] readBufferInsertIdx;
reg[0:0] readBufferOutputIdx;

reg[31:0] readBuffer[1:0];

reg progress;
reg readToBuffer;
reg readFromBuffer;

always_comb begin

    OUT_CACHE_id = cacheID;

    progress = 0;
    readToBuffer = 0;
    readFromBuffer = 0;

    OUT_CACHE_ce = 1;
    OUT_CACHE_we = 'x;
    OUT_CACHE_addr = 'x;
    OUT_CACHE_data = 'x;

    OUT_valid = 0;
    OUT_data = 'x;

    if (active) begin

        // Writes are bufferless, the write is just forwarded
        // to cache when ready
        if (isWrite && IN_valid) begin
            OUT_CACHE_ce = 0;
            OUT_CACHE_we = 0;
            OUT_CACHE_addr = addrCnt;
            OUT_CACHE_data = IN_data;
            progress = 1;
        end

        if (!isWrite && IN_valid) begin
            readFromBuffer = (readBufferCnt != 0);
            OUT_data = readFromBuffer ? readBuffer[readBufferOutputIdx] : IN_CACHE_data;
            OUT_valid = 1;
        end

        // Reads are buffered, fill buffer if not full
        if (!isWrite && (readBufferRqCnt != 2 || IN_valid) && lenCnt != 0) begin
            OUT_CACHE_ce = 0;
            OUT_CACHE_we = 1;
            OUT_CACHE_addr = addrCnt;
            readToBuffer = 1;
        end
    end
end

always_ff@(posedge clk or posedge rst) begin
    if (rst) begin
        active <= 0;
    end
    else begin

        readRequests <= {readRequests[0], 1'b0};

        if (!active && IN_en) begin
            active <= 1;
            isWrite <= IN_write;
            lenCnt <= IN_len;
            addrCnt <= IN_addr;
            cacheID <= IN_cacheID;
            readBufferInsertIdx = 0;
            readBufferOutputIdx = 0;
            readBufferCnt = 0;
            readRequests <= 0;
        end
        else if (active) begin
            if (isWrite && progress) begin
                if (lenCnt == 1) active <= 0;
                addrCnt[`CLSIZE_E-3:0] <= addrCnt[`CLSIZE_E-3:0] + 1;
                lenCnt <= lenCnt - 1;

                readBufferInsertIdx = 0;
                readBufferOutputIdx = 0;
                readRequests <= 0;
            end
            else if (!isWrite) begin

                // Read incoming cache data or from buffer
                if (IN_valid) begin

                    if (lenCnt == 0 && readBufferRqCnt == 1) active <= 0;

                    if (readFromBuffer) begin
                        readBufferOutputIdx = readBufferOutputIdx + 1;
                        readBufferCnt = readBufferCnt - 1;
                    end
                end

                // Write incoming data from cache into buffer
                if (readRequests[1] && (!IN_valid || readFromBuffer)) begin
                    readBuffer[readBufferInsertIdx] <= IN_CACHE_data;
                    readBufferCnt = readBufferCnt + 1;
                    readBufferInsertIdx = readBufferInsertIdx + 1;
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
end




endmodule
