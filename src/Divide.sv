module Divide
(
    input wire clk,
    input wire rst,
    input wire en,
    
    input wire IN_wbStall,
    output wire OUT_wbReq,
    output reg OUT_busy,
    
    input BranchProv IN_branch,
    
    input EX_UOp IN_uop,
    output RES_UOp OUT_uop
);


EX_UOp uop;
reg[5:0] cnt;
// could use single register for r/q
reg[63:0] r;
reg[31:0] q;
reg[31:0] d;
reg invert;

assign OUT_wbReq = OUT_busy && (cnt == 0);


always_ff@(posedge clk) begin

    if (rst) begin
        OUT_uop.valid <= 0;
        OUT_busy <= 0;
    end
    else begin
        if (en && IN_uop.valid && (!IN_branch.taken || $signed(IN_uop.sqN - IN_branch.sqN) <= 0)) begin
            OUT_busy <= 1;
            uop <= IN_uop;
            cnt <= 31;
            
            if (IN_uop.opcode == DIV_DIV) begin
                invert <= IN_uop.srcA[31] ^ IN_uop.srcB[31];
                r <= {32'b0, (IN_uop.srcA[31] ? (-IN_uop.srcA) : IN_uop.srcA)};
                d <= IN_uop.srcB[31] ? (-IN_uop.srcB) : IN_uop.srcB;
            end
            else if (IN_uop.opcode == DIV_REM) begin
                invert <= IN_uop.srcA[31];
                r <= {32'b0, (IN_uop.srcA[31] ? (-IN_uop.srcA) : IN_uop.srcA)};
                d <= IN_uop.srcB[31] ? (-IN_uop.srcB) : IN_uop.srcB;
            end
            else begin
                invert <= 0;
                r <= {32'b0, IN_uop.srcA};
                d <= IN_uop.srcB;
            end
            OUT_uop.valid <= 0;
            
        end
        else if (OUT_busy) begin
            
            if (IN_branch.taken && $signed(IN_branch.sqN - uop.sqN) < 0) begin
                OUT_busy <= 0;
                uop.valid <= 0;
                OUT_uop.valid <= 0;
            end
            else if (cnt != 63) begin
                if (!r[63]) begin
                    q[cnt[4:0]] <= 1;
                    r <= 2 * r - {d, 32'b0};
                end
                else begin
                    q[cnt[4:0]] <= 0;
                    r <= 2 * r + {d, 32'b0};
                end
                cnt <= cnt - 1;
                OUT_uop.valid <= 0;
            end
            else if (!IN_wbStall)  begin
                reg[31:0] qRestored = (q - (~q)) - (r[63] ? 1 : 0);
                reg[31:0] remainder = (r[63] ? (r[63:32] + d) : r[63:32]);
                
                OUT_busy <= 0;
                
                OUT_uop.sqN <= uop.sqN;
                OUT_uop.tagDst <= uop.tagDst;
                OUT_uop.nmDst <= uop.nmDst;
                OUT_uop.pc <= uop.pc;
                OUT_uop.isBranch <= 0;
                OUT_uop.branchTaken <= 0;
                OUT_uop.branchID <= 0;
                
                OUT_uop.flags <= FLAGS_NONE;
                OUT_uop.valid <= 1;
                if (uop.opcode == DIV_REM || uop.opcode == DIV_REMU)
                    OUT_uop.result <= invert ? (-remainder) : remainder;
                else
                    OUT_uop.result <= invert ? (-qRestored) : qRestored;
            end
            else
                OUT_uop.valid <= 0;
        end
        else begin
            OUT_uop.valid <= 0;
            OUT_busy <= 0;
        end
    end
end



endmodule
