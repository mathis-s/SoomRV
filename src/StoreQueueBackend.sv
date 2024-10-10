module StoreQueueBackend#(parameter NUM_IN = 2, parameter NUM_EVICTED = 4)
(
    input wire clk,
    input wire rst,

    output reg OUT_busy,

    input LD_UOp IN_uopLd[NUM_AGUS-1:0],
    output StFwdResult OUT_fwd[NUM_AGUS-1:0],

    input SQ_UOp IN_uop[NUM_IN-1:0],
    output logic OUT_stall[NUM_IN-1:0],

    input wire IN_stallSt,
    output ST_UOp OUT_uopSt,
    input ST_Ack IN_stAck
);
localparam AXI_BWIDTH = `AXI_WIDTH/8;
localparam AXI_BWIDTH_E = $clog2(`AXI_WIDTH/8);

typedef struct packed
{
    logic[`AXI_WIDTH-1:0] data;
    logic[29:0] addr;
    logic[`AXI_WIDTH/8-1:0] wmask;
    logic isMgmt;

    logic issued;
    StNonce_t nonce;
    logic valid;
} EQEntry;

EQEntry evicted[NUM_EVICTED-1:0];

typedef struct packed
{
    StID_t idx;
    logic valid;
} IdxN;

always_comb begin
    OUT_busy = 0;
    for (integer i = 0; i < NUM_EVICTED; i=i+1)
        if (evicted[i].valid) OUT_busy = 1;

    if (fusedUOp_r.valid) OUT_busy = 1;

    for (integer i = 0; i < NUM_IN; i=i+1)
        if (IN_uop[i].valid) OUT_busy = 1;
end

EQEntry fusedUOp_r;
EQEntry fusedUOp_c;
always_ff@(posedge clk)
    fusedUOp_r <= rst ? EQEntry'{valid: 0, default: 'x} : fusedUOp_c;

always_comb begin
    fusedUOp_c = fusedUOp_r;

    if (evInsert.valid)
        fusedUOp_c = EQEntry'{valid: 0, default: 'x};

    for (integer i = 0; i < NUM_IN; i=i+1)
        OUT_stall[i] = 1;

    if ((!fusedUOp_r.valid || evInsert.valid) && IN_uop[0].valid) begin

        // Used the oldest store as base
        OUT_stall[0] = 0;
        fusedUOp_c.valid = 1;
        fusedUOp_c.nonce = 0;
        fusedUOp_c.issued = 0;
        fusedUOp_c.isMgmt = 0;

        if (`IS_MMIO_PMA(IN_uop[0].addr) || IN_uop[0].isMgmt) begin
            fusedUOp_c.wmask = AXI_BWIDTH'(IN_uop[0].wmask);
            fusedUOp_c.addr = IN_uop[0].addr[31:2];
            fusedUOp_c.data = `AXI_WIDTH'(IN_uop[0].data);
            fusedUOp_c.isMgmt = IN_uop[0].isMgmt;
        end
        else begin
            fusedUOp_c.wmask = AXI_BWIDTH'(IN_uop[0].wmask) << IN_uop[0].addr[AXI_BWIDTH_E-1:2]*4;
            fusedUOp_c.addr = {IN_uop[0].addr[31:AXI_BWIDTH_E], 2'b0};
            fusedUOp_c.data = `AXI_WIDTH'(IN_uop[0].data) << IN_uop[0].addr[AXI_BWIDTH_E-1:2]*32;

            // Try to fuse in younger stores
            for (integer i = 1; i < NUM_IN; i=i+1) begin
                if (IN_uop[i].valid &&
                    IN_uop[i].addr[31:AXI_BWIDTH_E] == fusedUOp_c.addr[29:AXI_BWIDTH_E-2] &&
                    !`IS_MMIO_PMA(IN_uop[i].addr)
                ) begin
                    OUT_stall[i] = 0;
                    for (integer j = 0; j < AXI_BWIDTH; j=j+1) begin
                        if (IN_uop[i].addr[AXI_BWIDTH_E-1:2] == j[AXI_BWIDTH_E-1:2] &&
                            IN_uop[i].wmask[j[1:0]]
                        ) begin
                            fusedUOp_c.data[j*8+:8] = IN_uop[i].data[j[1:0]*8+:8];
                            fusedUOp_c.wmask[j] = 1;
                        end
                    end
                end
            end
        end
    end
end

EQEntry evictedV[NUM_EVICTED:0];
always_comb begin
    for (integer i = 0; i < NUM_EVICTED; i=i+1)
        evictedV[i] = evicted[i];
    evictedV[NUM_EVICTED] = fusedUOp_r;
end

reg[3:0] lookupMask[NUM_AGUS-1:0];
reg[31:0] lookupData[NUM_AGUS-1:0];
// Store queue lookup
for (genvar h = 0; h < NUM_AGUS; h=h+1)
always_comb begin

    reg[AXI_BWIDTH_E-3:0] shift = IN_uopLd[h].addr[2+:AXI_BWIDTH_E-2];
    reg[31:0] data = 'x;
    reg[3:0] mask = 'x;

    lookupMask[h] = 0;
    lookupData[h] = 32'bx;

    for (integer i = 0; i < NUM_EVICTED+1; i=i+1) begin

        data = evictedV[i].data[32*shift+:32];
        mask = evictedV[i].wmask[4*shift+:4];

        if (evictedV[i].valid &&
            evictedV[i].addr[29:AXI_BWIDTH_E-2] == IN_uopLd[h].addr[31:AXI_BWIDTH_E] &&
            !`IS_MMIO_PMA_W(evictedV[i].addr)
        ) begin
            for (integer j = 0; j < 4; j=j+1)
                if (mask[j])
                    lookupData[h][j*8 +: 8] = data[j*8 +: 8];
            lookupMask[h] = lookupMask[h] | mask;
        end
    end
end

logic mmioOpInEv;
logic mgmtOpInEv;
logic anyInEv;
always_comb begin
    mmioOpInEv = 0;
    mgmtOpInEv = 0;
    anyInEv = 0;
    for (integer i = 0; i < NUM_EVICTED; i=i+1)
        if (evicted[i].valid) begin
            anyInEv = 1;
            if (`IS_MMIO_PMA_W(evicted[i].addr))
                mmioOpInEv = 1;
            if (evicted[i].isMgmt)
                mgmtOpInEv = 1;
        end
end

// Find unused index for insertion
IdxN evInsert;
always_comb begin
    evInsert = IdxN'{valid: 0, default: 'x};

    if (!(mmioOpInEv && `IS_MMIO_PMA_W(fusedUOp_r.addr)) && !mgmtOpInEv)
        for (integer i = 0; i < NUM_EVICTED; i=i+1) begin
            if ((evicted[i].valid &&
                 evicted[i].addr[29:AXI_BWIDTH_E-2] == fusedUOp_r.addr[29:AXI_BWIDTH_E-2]) ||
                (!evicted[i].valid && !evInsert.valid)
            ) begin
                evInsert.valid = 1;
                evInsert.idx = i[$bits(evInsert.idx)-1:0];
            end
        end
end

// Select evicted entry to re-issue
IdxN reIssue;
always_comb begin
    reIssue = IdxN'{valid: 0, default: 'x};
    for (integer i = NUM_EVICTED - 1; i >= 0; i=i-1) begin
        if (evicted[i].valid && !evicted[i].issued) begin
            reIssue.valid = 1;
            reIssue.idx = i[$clog2(NUM_EVICTED)-1:0];
        end
    end
end

ST_Ack stAck_r;
always_ff@(posedge clk) begin
    if (!rst) stAck_r <= IN_stAck;
    else begin
        stAck_r <= 'x;
        stAck_r.valid <= 0;
    end
end

always_ff@(posedge clk) begin

    for (integer i = 0; i < NUM_AGUS; i=i+1) begin
        OUT_fwd[i] <= 'x;
        OUT_fwd[i].valid <= 0;
    end

    if (rst) begin
        for (integer i = 0; i < NUM_EVICTED; i=i+1)
            evicted[i].valid <= 0;
        OUT_uopSt.valid <= 0;
    end
    else begin

        if (OUT_uopSt.valid) begin
            OUT_uopSt <= ST_UOp'{valid: 0, default: 'x};
            if (IN_stallSt)
                evicted[OUT_uopSt.id].issued <= 0;
        end

        if (stAck_r.valid && stAck_r.nonce == evicted[stAck_r.idx].nonce) begin
            // delete if store ack has most recent nonce and successful
            if (evicted[stAck_r.idx].nonce == stAck_r.nonce) begin
                evicted[stAck_r.idx].issued <= 0;
                if (!stAck_r.fail) begin
                    evicted[stAck_r.idx] <= 'x;
                    evicted[stAck_r.idx].wmask <= 0;
                    evicted[stAck_r.idx].valid <= 0;
                end
            end
        end

        // Issue op from evicted
        if (reIssue.valid) begin
            evicted[reIssue.idx].issued <= 1;

            OUT_uopSt.valid <= 1;
            OUT_uopSt.id <= reIssue.idx;
            OUT_uopSt.nonce <= evicted[reIssue.idx].nonce;
            OUT_uopSt.addr <= {evicted[reIssue.idx].addr, 2'b0};
            OUT_uopSt.data <= evicted[reIssue.idx].data;
            OUT_uopSt.wmask <= evicted[reIssue.idx].wmask;
            OUT_uopSt.isMgmt <= evicted[reIssue.idx].isMgmt;
            OUT_uopSt.isMMIO <= `IS_MMIO_PMA_W(evicted[reIssue.idx].addr);
        end

        // Enqueue into evicted
        if (fusedUOp_r.valid && evInsert.valid) begin
            reg[`AXI_WIDTH-1:0] data = 'x;
            reg[`AXI_WIDTH/8-1:0] mask = 'x;
            StNonce_t newNonce = evicted[evInsert.idx].nonce + 1;

            mask = evicted[evInsert.idx].wmask | fusedUOp_r.wmask;
            data = evicted[evInsert.idx].data;
            for (integer i = 0; i < AXI_BWIDTH; i=i+1)
                if (fusedUOp_r.wmask[i] || fusedUOp_r.wmask == 0)
                    data[i*8+:8] = fusedUOp_r.data[i*8+:8];

            evicted[evInsert.idx].data <= data;
            evicted[evInsert.idx].wmask <= mask;
            evicted[evInsert.idx].addr <= fusedUOp_r.addr;
            evicted[evInsert.idx].issued <= 0;
            evicted[evInsert.idx].nonce <= newNonce;
            evicted[evInsert.idx].valid <= 1;

            if (!reIssue.valid) begin
                evicted[evInsert.idx].issued <= 1;

                OUT_uopSt.valid <= 1;
                OUT_uopSt.id <= evInsert.idx;
                OUT_uopSt.nonce <= newNonce;
                OUT_uopSt.addr <= {fusedUOp_r.addr, 2'b0};
                OUT_uopSt.data <= data;
                OUT_uopSt.wmask <= mask;
                OUT_uopSt.isMgmt <= fusedUOp_r.isMgmt;
                OUT_uopSt.isMMIO <= `IS_MMIO_PMA_W(fusedUOp_r.addr);
            end

        end

        for (integer i = 0; i < NUM_AGUS; i=i+1)
            if (IN_uopLd[i].valid) begin
                OUT_fwd[i].valid <= 1;
                OUT_fwd[i].data <= lookupData[i];
                OUT_fwd[i].mask <= lookupMask[i];
                OUT_fwd[i].conflict <= 0;
            end
    end
end

endmodule
