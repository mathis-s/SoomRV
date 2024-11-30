module TLBMissQueue#(parameter SIZE=4)
(
    input wire clk,
    input wire rst,

    output reg[$clog2(SIZE):0] OUT_free,
    output wire OUT_ready,

    input BranchProv IN_branch,
    input VirtMemState IN_vmem,
    input PageWalk_Res IN_pw,
    input wire IN_pwActive,

    input wire IN_enqueue,
    input wire IN_uopReady,
    input AGU_UOp IN_uop,

    input wire IN_dequeue,
    output AGU_UOp OUT_uop
);
localparam ID_LEN = $clog2(SIZE);

AGU_UOp queue[SIZE-1:0];
reg[SIZE-1:0] ready;

// Index in
reg[ID_LEN-1:0] idxIn;
reg idxInValid;
always_comb begin
    idxInValid = 0;
    idxIn = 'x;
    for (integer i = 0; i < SIZE; i=i+1) begin
        if (!queue[i].valid) begin
            idxIn = i[ID_LEN-1:0];
            idxInValid = 1;
        end
    end
end

assign OUT_ready = idxInValid;

always_comb begin

    reg[1:0] stage0[1:0];
    stage0[0] = (!queue[0].valid) + (!queue[1].valid);
    stage0[1] = (!queue[2].valid) + (!queue[3].valid);

    OUT_free = stage0[0] + stage0[1];
    if (OUT_free != 0) OUT_free = OUT_free - $clog2(SIZE)'(OUT_uop.valid);
end

// Index out
reg[ID_LEN-1:0] idxOut;
reg idxOutValid;
always_comb begin
    idxOutValid = 0;
    idxOut = 'x;
    for (integer i = 0; i < SIZE; i=i+1) begin
        // When the page walker is not busy, we also issue non-ready
        // ops that will miss TLB and start a new page walk.
        if (queue[i].valid && (ready[i] || !IN_pwActive)) begin
            idxOut = i[ID_LEN-1:0];
            idxOutValid = 1;
        end
    end
end

always_ff@(posedge clk or posedge rst) begin
    if (rst) begin
        for (integer i = 0; i < SIZE; i=i+1) begin
            queue[i] <= AGU_UOp'{valid: 0, default: 'x};
        end
        OUT_uop <= AGU_UOp'{valid: 0, default: 'x};
        ready <= 'x;
    end
    else begin

        // Translate
        if (IN_pw.valid) begin
            for (integer i = 0; i < SIZE; i=i+1) begin
                if (queue[i].valid && !ready[i] &&
                    (IN_pw.isSuperPage ?
                        (IN_pw.vpn[19:10] == queue[i].addr[31:22]) :
                        (IN_pw.vpn == queue[i].addr[31:12]))
                ) begin
                    ready[i] <= 1;
                end
            end
        end

        // Invalidate
        if (IN_branch.taken) begin
            for (integer i = 0; i < SIZE; i=i+1) begin
                if (queue[i].valid && $signed(queue[i].sqN - IN_branch.sqN) > 0) begin
                    ready[i] <= 'x;
                    queue[i] <= 'x;
                    queue[i].valid <= 0;
                end
            end
        end

        // Enqueue
        if (IN_enqueue && IN_uop.valid && (!IN_branch.taken || $signed(IN_uop.sqN - IN_branch.sqN) <= 0)) begin
            assert(idxInValid);
            ready[idxIn] <= (!IN_vmem.sv32en) || IN_uopReady;
            queue[idxIn] <= IN_uop;
        end

        // Dequeue
        if (IN_dequeue || (IN_branch.taken && $signed(OUT_uop.sqN - IN_branch.sqN) > 0)) begin
            OUT_uop <= 'x;
            OUT_uop.valid <= 0;
        end
        if ((!OUT_uop.valid || IN_dequeue) && idxOutValid) begin
            if (queue[idxOut].valid && (!IN_branch.taken || $signed(queue[idxOut].sqN - IN_branch.sqN) <= 0)) begin
                OUT_uop <= queue[idxOut];
                ready[idxOut] <= 'x;
                queue[idxOut] <= 'x;
                queue[idxOut].valid <= 0;
            end
        end

    end
end
endmodule
