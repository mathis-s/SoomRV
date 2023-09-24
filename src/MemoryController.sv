module MemoryController
#(parameter NUM_CACHES=2, parameter NUM_TFS=4, parameter NUM_TFS_IN=3, parameter ID_LEN=2, parameter ADDR_LEN=32, parameter WIDTH=128)
(
    input wire clk,
    input wire rst,
    
    input MemController_Req IN_ctrl[NUM_TFS_IN-1:0],
    output MemController_Res OUT_stat,
    
    output reg OUT_CACHE_we[NUM_CACHES-1:0],
    output reg OUT_CACHE_ce[NUM_CACHES-1:0],
    output reg[(WIDTH/8)-1:0] OUT_CACHE_wm[NUM_CACHES-1:0],
    output reg[`CACHE_SIZE_E-3:0] OUT_CACHE_addr[NUM_CACHES-1:0],
    output reg[WIDTH-1:0] OUT_CACHE_data[NUM_CACHES-1:0],
    input wire[WIDTH-1:0] IN_CACHE_data[NUM_CACHES-1:0],

    output[ID_LEN-1:0]  s_axi_awid, // write req id
    output[ADDR_LEN-1:0] s_axi_awaddr, // write addr
    output[7:0] s_axi_awlen, // write len
    output[2:0] s_axi_awsize, // word size
    output[1:0] s_axi_awburst, // FIXED, INCR, WRAP, RESERVED
    output[0:0] s_axi_awlock, // exclusive access
    output[3:0] s_axi_awcache, // {allocate, other allocate, modifiable, bufferable}
    output s_axi_awvalid,
    input s_axi_awready,
    
    // write stream
    output[WIDTH-1:0] s_axi_wdata,
    output[(WIDTH/8)-1:0] s_axi_wstrb,
    output s_axi_wlast,
    output s_axi_wvalid,
    input s_axi_wready,
    
    // write response
    output s_axi_bready,
    input[ID_LEN-1:0] s_axi_bid,
    //input[1:0] s_axi_bresp,
    input s_axi_bvalid,
    
    // read request
    output[ID_LEN-1:0] s_axi_arid,
    output[ADDR_LEN-1:0] s_axi_araddr,
    output[7:0] s_axi_arlen,
    output[2:0] s_axi_arsize,
    output[1:0] s_axi_arburst,
    output[0:0] s_axi_arlock,
    output[3:0] s_axi_arcache, // {other allocate, allocate, modifiable, bufferable}
    output s_axi_arvalid,
    input s_axi_arready,
    
    // read stream
    output s_axi_rready,
    input[ID_LEN-1:0] s_axi_rid,
    input[WIDTH-1:0] s_axi_rdata,
    //input logic[1:0] s_axi_rresp,
    input s_axi_rlast,
    input s_axi_rvalid
);

always_comb begin
    OUT_CACHE_we[0] = 1;
    OUT_CACHE_ce[0] = 1;
    OUT_CACHE_addr[0] = 'x;
    DCR_CACHE_ready = 0;
    DCW_CACHE_ready = 0;
    
    // read has higher priority than write
    if (!DCR_CACHE_ce) begin
        OUT_CACHE_we[0] = DCR_CACHE_we;
        OUT_CACHE_ce[0] = DCR_CACHE_ce;
        OUT_CACHE_addr[0] = DCR_CACHE_addr;
        DCR_CACHE_ready = 1;
    end
    else if (!DCW_CACHE_ce) begin
        OUT_CACHE_we[0] = DCW_CACHE_we;
        OUT_CACHE_ce[0] = DCW_CACHE_ce;
        OUT_CACHE_addr[0] = DCW_CACHE_addr;
        DCW_CACHE_ready = 1;
    end
end

typedef enum logic[1:0]
{
    FIXED, INCR, WRAP
} BurstType;

typedef struct packed
{
    logic[`CLSIZE_E-2:0] evictProgress;
    logic[`CLSIZE_E-2:0] progress;
    logic[`CLSIZE_E-2:0] addrCounter;
    logic[`CACHE_SIZE_E-3:0] cacheAddr;
    logic[31:0] readAddr;
    logic[31:0] writeAddr;

    // r/w from AXI perspective
    logic needReadRq;
    logic[1:0] needWriteRq; // 0: cache, 1: AXI
    
    CacheID_t cacheID;
    MemC_Cmd cmd;
    logic valid;
} Transfer;

Transfer transfers[NUM_TFS-1:0];

logic[3:0] isMMIO;
always_comb begin
    for (integer i = 0; i < NUM_TFS; i=i+1) begin
        case(transfers[i].cmd)
            MEMC_READ_BYTE, MEMC_READ_HALF, MEMC_READ_WORD,
            MEMC_WRITE_BYTE, MEMC_WRITE_HALF, MEMC_WRITE_WORD:
                isMMIO[i] = transfers[i].valid;
            default:
                isMMIO[i] = 0;
        endcase
    end
end

MemController_SglLdRes sglLdRes;
MemController_SglStRes sglStRes;

// Find enqueue index
logic[$clog2(NUM_TFS)-1:0] enqIdx;
logic enqIdxValid;
always_comb begin
    enqIdx = 'x;
    enqIdxValid = 0;
    for (integer i = 0; i < NUM_TFS; i=i+1) begin
        if (!enqIdxValid && transfers[i].cmd == MEMC_NONE) begin
            enqIdx = i[$clog2(NUM_TFS)-1:0];
            enqIdxValid = 1;
        end
    end
end

// Select Incoming Transfer
MemController_Req selReq;
always_comb begin
    OUT_stat.stall = '1;
    selReq = 'x;
    selReq.cmd = MEMC_NONE;

    if (enqIdxValid) begin
        for (integer i = 0; i < NUM_TFS_IN; i=i+1) begin
            if (selReq.cmd == MEMC_NONE && IN_ctrl[i].cmd != MEMC_NONE) begin
                selReq = IN_ctrl[i];
                OUT_stat.stall[i] = 1'b0;
            end
        end
    end
end

// AXI read control signals
reg[$clog2(NUM_TFS)-1:0] arIdx;
reg arIdxValid;
wire readReqSuccess = arIdxValid && s_axi_arready;
always_comb begin
    
    // Default AXI read rq bus state
    s_axi_arid = '0;
    s_axi_araddr = '0;
    s_axi_arlen = '0;
    s_axi_arburst = '0;
    s_axi_arlock = '0;
    s_axi_arcache = '0;
    s_axi_arvalid = '0;
    s_axi_arsize = '0;
    
    // Find Op that requires read request
    arIdx = 'x;
    arIdxValid = 0;
    for (integer i = 0; i < NUM_TFS; i=i+1) begin
        if (!arIdxValid && transfers[i].valid && transfers[i].needReadRq && transfers[i].needWriteRq == 0) begin
            arIdx = i[$clog2(NUM_TFS)-1:0];
            arIdxValid = 1;
        end
    end

    // Reads only have to be requested on AXI. The MemoryWriteInterface
    // handles data as it comes in, no setup required.
    if (arIdxValid) begin
        s_axi_arvalid = 1;
        s_axi_arburst = WRAP;
        s_axi_arlen = isMMIO[arIdx] ? 0 : ((1 << (`CLSIZE_E - 4)) - 1);
        s_axi_araddr = transfers[arIdx].readAddr;
        s_axi_arid = arIdx;

        case (transfers[arIdx].cmd)
            MEMC_WRITE_BYTE: s_axi_arsize = 0;
            MEMC_WRITE_HALF: s_axi_arsize = 1;
            MEMC_WRITE_WORD: s_axi_arsize = 2;
            default: s_axi_arsize = 3'($clog2(WIDTH/8));
        endcase
    end
end

// Output status to clients
always_comb begin
    OUT_stat = '0;
    OUT_stat.busy = 1; // make old clients stall
    
    // Cache Line Transfer Status
    for (integer i = 0; i < NUM_TFS; i=i+1) begin
        OUT_stat.transfers[i] = 'x;
        OUT_stat.transfers[i].valid = 0;
        
        if (transfers[i].valid && !isMMIO[i]) begin
            OUT_stat.transfers[i].valid = 1;
            OUT_stat.transfers[i].cacheID = transfers[i].cacheID;
            OUT_stat.transfers[i].progress = transfers[i].progress[`CLSIZE_E-2:0];
            OUT_stat.transfers[i].writeAddr = transfers[i].writeAddr;
            OUT_stat.transfers[i].readAddr = transfers[i].readAddr;
        end
    end
    
    // MMIO
    OUT_stat.sglLdRes = sglLdRes;
    OUT_stat.sglStRes = sglStRes;
end

logic ICW_ready;
logic ICW_valid;
logic[`CACHE_SIZE_E-3:0] ICW_addr;
logic[127:0] ICW_data;
logic[ID_LEN-1:0] ICW_id;

logic ICW_ackValid;
logic[ID_LEN-1:0] ICW_ackId;

CacheWriteInterface#(`CACHE_SIZE_E-2, 8, WIDTH, 128) icacheWriteIF
(
    .clk(clk),
    .rst(rst),

    .OUT_ready(ICW_ready),
    .IN_valid(ICW_valid),
    .IN_addr(ICW_addr),
    .IN_data(ICW_data),
    .IN_id(ICW_id),

    .OUT_ackValid(ICW_ackValid),
    .OUT_ackId(ICW_ackId),

    .IN_CACHE_ready(1'b1),
    .OUT_CACHE_ce(OUT_CACHE_ce[1]),
    .OUT_CACHE_we(OUT_CACHE_we[1]),
    .OUT_CACHE_addr(OUT_CACHE_addr[1]),
    .OUT_CACHE_data(OUT_CACHE_data[1])
);

logic DCW_ready;
logic DCW_valid;
logic[`CACHE_SIZE_E-3:0] DCW_addr;
logic[127:0] DCW_data;
logic[ID_LEN-1:0] DCW_id;

logic DCW_ackValid;
logic[ID_LEN-1:0] DCW_ackId;


logic DCW_CACHE_ready;
logic DCW_CACHE_ce;
logic DCW_CACHE_we;
logic[`CACHE_SIZE_E-3:0] DCW_CACHE_addr;
CacheWriteInterface#(`CACHE_SIZE_E-2, 8, WIDTH, 32) dcacheWriteIF
(
    .clk(clk),
    .rst(rst),

    .OUT_ready(DCW_ready),
    .IN_valid(DCW_valid),
    .IN_addr(DCW_addr),
    .IN_data(DCW_data),
    .IN_id(DCW_id),

    .OUT_ackValid(DCW_ackValid),
    .OUT_ackId(DCW_ackId),

    .IN_CACHE_ready(DCW_CACHE_ready),
    .OUT_CACHE_ce(DCW_CACHE_ce),
    .OUT_CACHE_we(DCW_CACHE_we),
    .OUT_CACHE_addr(DCW_CACHE_addr),
    .OUT_CACHE_data(OUT_CACHE_data[0][31:0])
);

// temp
always_comb begin
    OUT_CACHE_wm[0] = '1;
    OUT_CACHE_wm[1] = '1;
end

function logic[`CACHE_SIZE_E-3:0] GetCacheRdAddr(Transfer t);
    case (t.cmd)
    MEMC_REPLACE, MEMC_CP_EXT_TO_CACHE:
        return {t.cacheAddr[`CACHE_SIZE_E-3:`CLSIZE_E-2], (t.cacheAddr[`CLSIZE_E-3:0] + t.addrCounter[`CLSIZE_E-3:0])};
    default:
        return t.cacheAddr;
    endcase
endfunction

// Forward AXI read data to cache
always_comb begin
    // Defaults
    s_axi_rready = 0;

    ICW_valid = 0;
    ICW_addr = 'x;
    ICW_data = 'x;
    ICW_id = 'x;
    
    DCW_valid = 0;
    DCW_addr = 'x;
    DCW_data = 'x;
    DCW_id = 'x;
    
    // todo: add fifo to remove comb path from valid to ready
    if (s_axi_rvalid) begin
        if (isMMIO[s_axi_rid]) begin
            s_axi_rready = 1;
        end
        else begin
            CacheID_t cID = transfers[s_axi_rid].cacheID;
            case (cID)
            0: if (DCW_ready && transfers[s_axi_rid].evictProgress > transfers[s_axi_rid].addrCounter) begin // dcache
                s_axi_rready = 1;
                DCW_valid = 1;
                DCW_addr = GetCacheRdAddr(transfers[s_axi_rid]);
                DCW_data = s_axi_rdata;
                DCW_id = s_axi_rid;
            end

            1: if (ICW_ready) begin // icache
                s_axi_rready = 1;
                ICW_valid = 1;
                ICW_addr = GetCacheRdAddr(transfers[s_axi_rid]);
                ICW_data = s_axi_rdata;
                ICW_id = s_axi_rid;
            end
            endcase
        end
    end
end


logic DCR_reqReady;
logic DCR_reqValid;
logic[ID_LEN-1:0] DCR_reqTId;
logic[7:0] DCR_reqLen;
logic[`CACHE_SIZE_E-3:0] DCR_reqAddr;
logic DCR_reqMMIO;
logic[31:0] DCR_reqMMIOData;

logic DCR_dataReady;
logic DCR_dataValid;
logic[WIDTH-1:0] DCR_data;
logic DCR_dataLast;
logic[ID_LEN-1:0] DCR_dataTId;

logic DCR_CACHE_ready;
logic DCR_CACHE_ce;
logic DCR_CACHE_we;
logic[`CACHE_SIZE_E-3:0] DCR_CACHE_addr;
CacheReadInterface#(`CACHE_SIZE_E-2, 8, 128, 32, 4) dcacheReadIF
(
    .clk(clk),
    .rst(rst),

    .OUT_ready(DCR_reqReady),
    .IN_valid(DCR_reqValid),
    .IN_id(DCR_reqTId),
    .IN_len(DCR_reqLen),
    .IN_addr(DCR_reqAddr),
    .IN_mmio(DCR_reqMMIO),
    .IN_mmioData(DCR_reqMMIOData),

    .IN_ready(DCR_dataReady),
    .OUT_valid(DCR_dataValid),
    .OUT_id(DCR_dataTId),
    .OUT_data(DCR_data),
    .OUT_last(DCR_dataLast),
    
    .IN_CACHE_ready(DCR_CACHE_ready),
    .OUT_CACHE_ce(DCR_CACHE_ce),
    .OUT_CACHE_we(DCR_CACHE_we),
    .OUT_CACHE_addr(DCR_CACHE_addr),
    .IN_CACHE_data(IN_CACHE_data[0][31:0])
);

// Begin Write Transactions
logic[ID_LEN-1:0] awIdx;
logic awIdxValid;
always_comb begin
    reg isExclusive = 0;
    
    // Default AXI write rq bus state
    s_axi_awaddr = '0;
    s_axi_awlen = '0;
    s_axi_awsize = '0;
    s_axi_awburst = '0;
    s_axi_awlock = '0;
    s_axi_awcache = '0;
    s_axi_awvalid = '0;
    s_axi_awid = '0;
    
    DCR_reqAddr = 'x;
    DCR_reqLen = 'x;
    DCR_reqTId = 'x;
    DCR_reqMMIOData = 'x;
    DCR_reqMMIO = 0;
    DCR_reqValid = 0;
    
    // Find Op that requires write request
    awIdx = 'x;
    awIdxValid = 0;
    for (integer i = 0; i < NUM_TFS; i=i+1) begin
        if (transfers[i].valid && transfers[i].needWriteRq != 0) begin
            if (!isExclusive) begin
                // requests to cache and AXI must be made in the same order,
                // so a request made to only one of the two so far has priority
                isExclusive = transfers[i].needWriteRq != 2'b11;
                awIdx = i[$clog2(NUM_TFS)-1:0];
                awIdxValid = 1;
            end
            else assert(transfers[i].needWriteRq != 2'b01 && transfers[i].needWriteRq != 2'b10);
        end
    end
    
    // Request to AXI
    if (awIdxValid && transfers[awIdx].needWriteRq[1]) begin
        s_axi_awvalid = 1;
        s_axi_awburst = WRAP;
        s_axi_awlen = isMMIO[awIdx] ? 0 : ((1 << (`CLSIZE_E - 4)) - 1);
        s_axi_awaddr = transfers[awIdx].writeAddr;
        s_axi_awid = awIdx;
        
        case (transfers[awIdx].cmd)
            MEMC_WRITE_BYTE: s_axi_awsize = 0;
            MEMC_WRITE_HALF: s_axi_awsize = 1;
            MEMC_WRITE_WORD: s_axi_awsize = 2;
            default: s_axi_awsize = 3'($clog2(WIDTH/8));
        endcase
    end
    
    // Request to dcache read interface
    if (awIdxValid && transfers[awIdx].needWriteRq[0]) begin
        DCR_reqValid = 1;
        DCR_reqTId = awIdx;
        DCR_reqLen = isMMIO[awIdx] ? 0 : ((1 << (`CLSIZE_E - 2)) - 1);
        DCR_reqAddr = isMMIO[awIdx] ? 'x : transfers[awIdx].cacheAddr;
        DCR_reqMMIO = isMMIO[awIdx];
        DCR_reqMMIOData = isMMIO[awIdx] ? transfers[awIdx].readAddr : 'x;
    end
end

// Write Data
always_comb begin
    // Write requests are made in the same order on cache and AXI,
    // and write data has to be sent in-order on AXI4. As such,
    // we simply forward any data that the cache interface outputs.
    
    s_axi_wdata = 'x;
    s_axi_wstrb = 'x;
    s_axi_wlast = 'x;
    s_axi_wvalid = 0;

    if (DCR_dataValid) begin
        s_axi_wvalid = 1;
        s_axi_wlast = DCR_dataLast;
        s_axi_wstrb = '1;
        s_axi_wdata = DCR_data;
    end
end
assign DCR_dataReady = s_axi_wready;

assign s_axi_bready = 1;

// Input Transfers
always_ff@(posedge clk) begin
    
    sglStRes <= MemController_SglStRes'{default: 'x, valid: 0};
    sglLdRes <= MemController_SglLdRes'{default: 'x, valid: 0};

    if (rst) begin
        for (integer i = 0; i < NUM_TFS; i=i+1) begin
            transfers[i] <= 'x;
            transfers[i].valid <= 0;
        end
    end
    else begin
        
        // Enqueue
        if (selReq.cmd != MEMC_NONE) begin
            assert(enqIdxValid);
            transfers[enqIdx].valid <= 1;
            transfers[enqIdx].cmd <= selReq.cmd;
            transfers[enqIdx].needReadRq <= '0;
            transfers[enqIdx].needWriteRq <= '0;
            transfers[enqIdx].progress <= 0;
            transfers[enqIdx].addrCounter <= 0;
            transfers[enqIdx].evictProgress <= (1 << (`CLSIZE_E - 2));
            transfers[enqIdx].cacheID <= selReq.cacheID;

            if (selReq.cmd == MEMC_REPLACE || selReq.cmd == MEMC_CP_CACHE_TO_EXT || selReq.cmd == MEMC_CP_EXT_TO_CACHE) begin
                // cache-line oriented ops use aligned addresses
                transfers[enqIdx].writeAddr <= selReq.writeAddr & ~(WIDTH/8 - 1);
                transfers[enqIdx].readAddr <= selReq.readAddr & ~(WIDTH/8 - 1);
                transfers[enqIdx].cacheAddr <= selReq.cacheAddr & ~((WIDTH/8 - 1) >> 2);
            end
            else begin
                transfers[enqIdx].writeAddr <= selReq.writeAddr;
                transfers[enqIdx].readAddr <= selReq.readAddr;
                transfers[enqIdx].cacheAddr <= selReq.cacheAddr;
            end

            case (selReq.cmd)
                MEMC_REPLACE: begin
                    transfers[enqIdx].needReadRq <= '1;
                    transfers[enqIdx].needWriteRq <= '1;
                    transfers[enqIdx].evictProgress <= 0;
                end
                MEMC_CP_EXT_TO_CACHE: begin
                    transfers[enqIdx].needReadRq <= '1;
                end
                MEMC_CP_CACHE_TO_EXT: begin
                    transfers[enqIdx].needWriteRq <= '1;
                    transfers[enqIdx].evictProgress <= 0;
                end
                MEMC_READ_BYTE, MEMC_READ_HALF, MEMC_READ_WORD: begin
                    transfers[enqIdx].needReadRq <= '1;
                end
                MEMC_WRITE_BYTE, MEMC_WRITE_HALF, MEMC_WRITE_WORD: begin
                    transfers[enqIdx].needWriteRq <= '1;
                    // readAddr field is used to store data to write
                    transfers[enqIdx].readAddr <= selReq.data;
                end
                default: assert(0);
            endcase
        end

        // Read Request
        if (readReqSuccess) begin
            transfers[arIdx].needReadRq <= 0;
        end

        // Read Data
        if (s_axi_rvalid && s_axi_rready) begin

            transfers[s_axi_rid].addrCounter <= transfers[s_axi_rid].addrCounter + 4;
            
            if (isMMIO[s_axi_rid]) begin
                transfers[s_axi_rid] <= 'x;
                transfers[s_axi_rid].valid <= 0;
                
                sglLdRes.valid <= 1;
                sglLdRes.id <= transfers[s_axi_rid].cacheAddr;
                sglLdRes.data <= s_axi_rdata[31:0];
            end
        end

        // Read ACK
        if (DCW_ackValid) begin
            transfers[DCW_ackId].progress <= transfers[DCW_ackId].progress + 4;
            if ((transfers[DCW_ackId].progress >> 2) == (1 << (`CLSIZE_E - 4)) - 1) begin
                transfers[DCW_ackId] <= 'x;
                transfers[DCW_ackId].valid <= 0;
            end
        end
        if (ICW_ackValid) begin
            transfers[ICW_ackId].progress <= transfers[ICW_ackId].progress + 4;
            if ((transfers[ICW_ackId].progress >> 2) == (1 << (`CLSIZE_E - 4)) - 1) begin
                transfers[ICW_ackId] <= 'x;
                transfers[ICW_ackId].valid <= 0;
            end
        end

        // Write Request
        if (awIdxValid) begin
            if (DCR_reqValid && DCR_reqReady) transfers[awIdx].needWriteRq[0] <= 0;
            if (s_axi_awvalid && s_axi_awready) transfers[awIdx].needWriteRq[1] <= 0;
        end

        // Write Data
        if (DCR_dataValid && s_axi_wready) begin
            transfers[DCR_dataTId].evictProgress <= transfers[DCR_dataTId].evictProgress + 4;
        end

        // Write ACK 
        if (s_axi_bvalid) begin
            if (isMMIO[s_axi_bid]) begin
                sglStRes.valid <= 1;
                sglStRes.id <= transfers[s_axi_bid].cacheAddr;
            end
            if (isMMIO[s_axi_bid] || transfers[s_axi_bid].cmd == MEMC_CP_CACHE_TO_EXT) begin
                transfers[s_axi_bid] <= 'x;
                transfers[s_axi_bid].valid <= 0;
            end
        end
    end
end

endmodule
