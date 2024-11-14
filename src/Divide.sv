module Divide
(
    input wire clk,
    input wire rst,
    input wire en,

    output wire OUT_busy,

    input BranchProv IN_branch,

    input EX_UOp IN_uop,
    output RES_UOp OUT_uop
);


EX_UOp uop;
reg[5:0] cnt;
reg[64:0] r;
reg[31:0] d;
reg invert;

wire[32:0] d_inv = -{1'b0, d};
wire[31:0] q = r[31:0];

reg running;

assign OUT_busy = running && (cnt != 0 && cnt != 63);

always_ff@(posedge clk or posedge rst) begin

    running <= 0;
    OUT_uop <= 'x;
    OUT_uop.valid <= 0;

    if (!rst) begin
        if (en && IN_uop.valid && (!IN_branch.taken || $signed(IN_uop.sqN - IN_branch.sqN) <= 0)) begin
            running <= 1;
            uop <= IN_uop;
            cnt <= 31;

            if (IN_uop.opcode == DIV_DIV) begin
                invert <= (IN_uop.srcA[31] ^ IN_uop.srcB[31]) && (IN_uop.srcB != 0);
                r <= {33'b0, (IN_uop.srcA[31] ? (-IN_uop.srcA) : IN_uop.srcA)};
                d <= IN_uop.srcB[31] ? (-IN_uop.srcB) : IN_uop.srcB;
            end
            else if (IN_uop.opcode == DIV_REM) begin
                invert <= IN_uop.srcA[31];
                r <= {33'b0, (IN_uop.srcA[31] ? (-IN_uop.srcA) : IN_uop.srcA)};
                d <= IN_uop.srcB[31] ? (-IN_uop.srcB) : IN_uop.srcB;
            end
            else begin
                invert <= 0;
                r <= {33'b0, IN_uop.srcA};
                d <= IN_uop.srcB;
            end
            OUT_uop.valid <= 0;

        end
        else if (running) begin

            if (IN_branch.taken && $signed(IN_branch.sqN - uop.sqN) < 0) begin
                running <= 0;
                uop.valid <= 0;
                OUT_uop.valid <= 0;
            end
            else if (cnt != 63) begin
                running <= 1;
                r <= (r << 1) + {r[64] ? {1'b0, d} : d_inv, 31'b0, !r[64]};
                cnt <= cnt - 1;
                OUT_uop.valid <= 0;
            end
            else begin
                reg[31:0] qRestored = (q - (~q)) - (r[64] ? 1 : 0);
                reg[31:0] remainder = (r[64] ? (r[63:32] + d) : r[63:32]);

                running <= 0;

                OUT_uop.sqN <= uop.sqN;
                OUT_uop.tagDst <= uop.tagDst;
                OUT_uop.doNotCommit <= 0;

                OUT_uop.flags <= FLAGS_NONE;
                OUT_uop.valid <= 1;
                if (uop.opcode == DIV_REM || uop.opcode == DIV_REMU)
                    OUT_uop.result <= invert ? (-remainder) : remainder;
                else
                    OUT_uop.result <= invert ? (-qRestored) : qRestored;
            end
        end
    end
end



endmodule
