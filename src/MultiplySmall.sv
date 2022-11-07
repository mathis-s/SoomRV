
module MultiplySmall
#
(
    parameter NUM_STAGES=4,
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
    bit[31:0] srcA;
    bit[31:0] srcB;
    bit[63:0] res;
    bit invert;
    bit high;
    
    Tag tagDst;
    RegNm nmDst;
    SqN sqN;
    bit[31:0] pc;
    bit valid;
} MulPS;


integer i;

MulPS pl;
/* verilator lint_off UNSIGNED */
assign OUT_busy = pl.valid && (stage < NUM_STAGES - 1);
/* verilator lint_on UNSIGNED */

reg[63:0] result;
reg[3:0] stage;

always_ff@(posedge clk) begin
    
    OUT_uop.valid <= 0;
    
    if (rst) begin
        pl.valid <= 0;
    end
    else begin
        if (en && IN_uop.valid && (!IN_branch.taken || $signed(IN_uop.sqN - IN_branch.sqN) <= 0)) begin
            pl.valid <= 1;
            pl.tagDst <= IN_uop.tagDst;
            pl.nmDst <= IN_uop.nmDst;
            pl.sqN <= IN_uop.sqN;
            pl.pc <= IN_uop.pc;
            pl.res <= 0;
            stage <= 0;
            
            case (IN_uop.opcode)
                
                MUL_MUL,
                MUL_MULH: begin
                    pl.invert <= IN_uop.srcA[31] ^ IN_uop.srcB[31];
                    pl.srcA <= IN_uop.srcA[31] ? (-IN_uop.srcA) : IN_uop.srcA;
                    pl.srcB <= IN_uop.srcB[31] ? (-IN_uop.srcB) : IN_uop.srcB;
                end
                MUL_MULSU: begin
                    pl.invert <= IN_uop.srcA[31];
                    pl.srcA <= IN_uop.srcA[31] ? (-IN_uop.srcA) : IN_uop.srcA;
                    pl.srcB <= IN_uop.srcB;
                end
                MUL_MULU: begin
                    pl.invert <= 0;
                    pl.srcA <= IN_uop.srcA;
                    pl.srcB <= IN_uop.srcB;
                end
                default: begin end
            endcase
            pl.high <= IN_uop.opcode != MUL_MUL;
        end
        else if ((!IN_branch.taken || $signed(pl.sqN - IN_branch.sqN) <= 0)) begin
            if (pl.valid) begin
                if (stage != NUM_STAGES) begin
                    pl.res <= pl.res + ((pl.srcA * pl.srcB[(BITS*stage)+:BITS]) << (BITS*stage));
                    stage <= stage + 1;
                end
                else begin
                    pl.valid <= 0;
                    OUT_uop.valid <= 1;
                    OUT_uop.tagDst <= pl.tagDst;
                    OUT_uop.nmDst <= pl.nmDst;
                    OUT_uop.sqN <= pl.sqN;
                    OUT_uop.pc <= pl.pc;
                    OUT_uop.isBranch <= 0;
                    OUT_uop.branchTaken <= 0;
                    OUT_uop.bpi <= 0;
                    OUT_uop.flags <= FLAGS_NONE;
                    OUT_uop.compressed <= 0;
                    
                    result = (pl.invert ? (-pl.res) : pl.res);
                    
                    if (pl.high)
                        OUT_uop.result <= result[63:32];
                    else
                        OUT_uop.result <= result[31:0];
                end
            end
        end
        else begin
            pl.valid <= 0;
        end
    end
end
endmodule
