
module Multiply
#
(
    parameter NUM_STAGES=2,

    parameter BITS=(32/NUM_STAGES)
)
(
    input wire clk,
    input wire rst,
    input wire en,

    output wire OUT_busy,

    input BranchProv IN_branch,

    input EX_UOp IN_uop,
    output RES_UOp OUT_uop
);

typedef struct packed
{
    logic[31:0] srcA;
    logic[31:0] srcB;
    logic[63:0] res;
    logic invert;
    logic high;

    Tag tagDst;
    RegNm rd;
    SqN sqN;
    logic valid;
} MulPS;



MulPS pl[NUM_STAGES:0];
assign OUT_busy = 0;

always_ff@(posedge clk) begin

    for (integer i = 0; i < NUM_STAGES+1; i=i+1) begin
        pl[i] <= 'x;
        pl[i].valid <= 0;
    end
    OUT_uop <= 'x;
    OUT_uop.valid <= 0;

    if (!rst) begin

        if (en && IN_uop.valid && (!IN_branch.taken || $signed(IN_uop.sqN - IN_branch.sqN) <= 0)) begin
            pl[0].valid <= 1;
            pl[0].tagDst <= IN_uop.tagDst;
            pl[0].sqN <= IN_uop.sqN;
            pl[0].res <= 0;

            case (IN_uop.opcode)

                MUL_MULH: begin
                    pl[0].invert <= IN_uop.srcA[31] ^ IN_uop.srcB[31];
                    pl[0].srcA <= IN_uop.srcA[31] ? (-IN_uop.srcA) : IN_uop.srcA;
                    pl[0].srcB <= IN_uop.srcB[31] ? (-IN_uop.srcB) : IN_uop.srcB;
                end
                MUL_MULSU: begin
                    pl[0].invert <= IN_uop.srcA[31];
                    pl[0].srcA <= IN_uop.srcA[31] ? (-IN_uop.srcA) : IN_uop.srcA;
                    pl[0].srcB <= IN_uop.srcB;
                end
                MUL_MUL,
                MUL_MULU: begin
                    pl[0].invert <= 0;
                    pl[0].srcA <= IN_uop.srcA;
                    pl[0].srcB <= IN_uop.srcB;
                end
                default: begin end
            endcase
            pl[0].high <= IN_uop.opcode != MUL_MUL;
        end
        else
            pl[0].valid <= 0;

        begin
            for (integer i = 0; i < NUM_STAGES; i=i+1) begin

                if (pl[i].valid && (!IN_branch.taken || $signed(pl[i].sqN - IN_branch.sqN) <= 0)) begin

                    pl[i+1] <= pl[i];
                    pl[i+1].res <= pl[i].res + ((pl[i].srcA * pl[i].srcB[(BITS*i)+:BITS]) << (BITS*i));
                end
                else
                    pl[i+1].valid <= 0;
            end

            if (pl[NUM_STAGES].valid && (!IN_branch.taken || $signed(pl[NUM_STAGES].sqN - IN_branch.sqN) <= 0)) begin

                OUT_uop.valid <= 1;
                OUT_uop.tagDst <= pl[NUM_STAGES].tagDst;
                OUT_uop.sqN <= pl[NUM_STAGES].sqN;
                OUT_uop.flags <= FLAGS_NONE;
                OUT_uop.doNotCommit <= 0;

                if (pl[NUM_STAGES].high)
                    OUT_uop.result <= pl[NUM_STAGES].invert ? (~pl[NUM_STAGES].res[63:32] + ((pl[NUM_STAGES].res[31:0] == 0) ? 1 : 0)) : pl[NUM_STAGES].res[63:32];
                else
                    OUT_uop.result <= pl[NUM_STAGES].res[31:0];
            end
        end
    end
end
endmodule
