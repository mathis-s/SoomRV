module LoadResultBuffer#(parameter SIZE=4)
(
    input wire clk,
    input wire rst,
    
    input BranchProv IN_branch,
    input MemController_Res IN_memc,
    
    input LoadResUOp IN_uop,
    output wire OUT_ready,

    output RES_UOp OUT_uop
);

typedef struct packed
{
    logic[$clog2(SIZE)-1:0] idx;
    logic valid;
} IdxN;

LoadResUOp entries[SIZE-1:0];

// Select load to write back
LoadResUOp outLMQ_c;
LoadResUOp enqLMQ_c;

IdxN deq_c;
always_comb begin
    outLMQ_c = LoadResUOp'{valid: 0, default: 'x};
    deq_c = IdxN'{valid: 0, default: 'x};
    enqLMQ_c = IN_uop;

    // TODO: build compare tree manually
    for (integer i = 0; i < SIZE; i=i+1) begin
        if (entries[i].valid && entries[i].dataAvail &&
            (!outLMQ_c.valid || outLMQ_c.external || $signed(entries[i].sqN - outLMQ_c.sqN) <= 0)
        ) begin
            outLMQ_c = entries[i];
            deq_c.valid = 1;
            deq_c.idx = i[$clog2(SIZE)-1:0];
        end
    end
    
    // immediately pass through incoming load if older
    if (IN_uop.valid && IN_uop.dataAvail &&
        (!outLMQ_c.valid || outLMQ_c.external || $signed(IN_uop.sqN - outLMQ_c.sqN) <= 0)
    ) begin
        outLMQ_c = IN_uop;
        deq_c = IdxN'{valid: 0, default: 'x};
        enqLMQ_c = LoadResUOp'{valid: 0, default: 'x};
    end
end

// Get enqueue index
IdxN enq;
assign OUT_ready = enq.valid;
always_comb begin
    enq = IdxN'{valid: 0, default: 'x};

    if (rst) ;
    else begin
        // TODO: optimize
        for (integer i = 0; i < SIZE; i=i+1) begin
            if (!entries[i].valid) begin
                enq.valid = 1;
                enq.idx = i[$clog2(SIZE)-1:0];
            end
        end
    end
end

always_ff@(posedge clk) begin
    if (rst) begin
        for (integer i = 0; i < SIZE; i=i+1) begin
            entries[i] <= LoadResUOp'{valid: 0, default: 'x};
        end
    end
    else begin
        
        // Invalidate
        if (IN_branch.taken)
            for (integer i = 0; i < SIZE; i=i+1) begin
                if (entries[i].valid && !entries[i].external && 
                    $signed(entries[i].sqN - IN_branch.sqN) > 0
                ) begin
                    entries[i] <= LoadResUOp'{valid: 0, default: 'x};
                end
            end

        // Dequeue
        if (deq_c.valid)
            entries[deq_c.idx] <= LoadResUOp'{valid: 0, default: 'x};

        // Enqueue
        if (enqLMQ_c.valid && enq.valid &&
            (!IN_branch.taken || enqLMQ_c.external || $signed(enqLMQ_c.sqN - IN_branch.sqN) <= 0)) begin
            entries[enq.idx] <= enqLMQ_c;
        end
    end
end

always_ff@(posedge clk) begin
    if (rst) ;
    else begin
        for (integer i = 0; i < SIZE; i=i+1) begin
            if (entries[i].valid && !entries[i].dataAvail && 
                entries[i].addr[31:$clog2(`AXI_WIDTH/8)] == 
                    IN_memc.ldDataFwd.addr[31:$clog2(`AXI_WIDTH/8)]
            ) begin
                entries[i].dataAvail <= 1;
                for (integer j = 0; j < 4; j=j+1)
                    if (!entries[i].fwdMask[j])
                        entries[i].data[8*j+:8] <= IN_memc.ldDataFwd.data[{entries[i].addr[$clog2(`AXI_WIDTH/8)-1:2], j[1:0]}*8+:8];
            end
        end
    end
end

// Shift/Mask raw loaded data to produce final result uop
always_comb begin
    OUT_uop = RES_UOp'{valid: 0, default: 'x};
    if (outLMQ_c.valid) begin
        OUT_uop.valid = 1;
        OUT_uop.flags = FLAGS_NONE;
        OUT_uop.doNotCommit = outLMQ_c.doNotCommit;
        OUT_uop.tagDst = outLMQ_c.tagDst;
        OUT_uop.sqN = outLMQ_c.sqN;
        
        case (outLMQ_c.exception)
            AGU_NO_EXCEPTION: OUT_uop.flags = FLAGS_NONE;
            AGU_ADDR_MISALIGN: OUT_uop.flags = FLAGS_LD_MA;
            AGU_ACCESS_FAULT: OUT_uop.flags = FLAGS_LD_AF;
            AGU_PAGE_FAULT: OUT_uop.flags = FLAGS_LD_PF;
        endcase

        case (outLMQ_c.size)
            0: OUT_uop.result = 
                {{24{outLMQ_c.sext ? outLMQ_c.data[8*(outLMQ_c.addr[1:0])+7] : 1'b0}},
                outLMQ_c.data[8*(outLMQ_c.addr[1:0])+:8]};

            1: OUT_uop.result = 
                {{16{outLMQ_c.sext ? outLMQ_c.data[16*(outLMQ_c.addr[1])+15] : 1'b0}},
                outLMQ_c.data[16*(outLMQ_c.addr[1])+:16]};

            2: OUT_uop.result = outLMQ_c.data;
            default: assert(0);
        endcase
    end
end

endmodule
