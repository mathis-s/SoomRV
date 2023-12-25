module BypassLSU
(
    input wire clk,
    input wire rst,

    input BranchProv IN_branch,
    
    input wire IN_uopLdEn,
    output reg OUT_ldStall,
    input LD_UOp IN_uopLd,

    input wire IN_uopStEn,
    output reg OUT_stStall,
    input ST_UOp IN_uopSt,

    input wire IN_ldStall,
    output LD_UOp OUT_uopLd,
    output reg[31:0] OUT_ldData,

    output MemController_Req OUT_memc,
    input MemController_Res IN_memc
);

reg[31:0] result;

LD_UOp activeLd;

wire invalidateActiveLd = !(activeLd.external || !IN_branch.taken || $signed(activeLd.sqN - IN_branch.sqN) <= 0);

enum logic[2:0]
{
    IDLE,
    RQ_LD,
    RQ_ST,
    WAIT_LD,
    WAIT_ST,
    DONE_LD
} state;

always_comb begin
    OUT_stStall = (state != IDLE);
    OUT_ldStall = (state != IDLE || (IN_uopSt.valid && !OUT_stStall));

    OUT_uopLd = 'x;
    OUT_uopLd.valid = 0;

    if (state == DONE_LD && !invalidateActiveLd) begin // todo: invalidate check likely not required here (or just ff the output)
        OUT_uopLd = activeLd;
    end
end

always_ff@(posedge clk) begin
    
    if (rst) begin
        activeLd.valid <= 0;
        OUT_memc <= '0;
        OUT_memc.cmd <= MEMC_NONE;
        state <= IDLE;
    end
    else begin

        if (invalidateActiveLd) begin
            activeLd <= 'x;
            activeLd.valid <= 0;
        end
        case (state)

            default: begin
                state <= IDLE;
                if (IN_uopSt.valid && IN_uopStEn && !OUT_stStall) begin
                    
                    reg[1:0] addrLow;
                    for (integer i = 3; i >= 0; i=i-1)
                        if (IN_uopSt.wmask[i] == 1)
                            addrLow = i[1:0];

                    case (IN_uopSt.wmask)
                        4'b0001, 4'b0010, 4'b0100, 4'b1000:
                            OUT_memc.cmd <= MEMC_WRITE_BYTE;
                        4'b0011, 4'b1100:
                            OUT_memc.cmd <= MEMC_WRITE_HALF;
                        4'b1111:
                            OUT_memc.cmd <= MEMC_WRITE_WORD;
                        default: assert(0);
                    endcase

                    OUT_memc.cacheAddr <= 'x;
                    OUT_memc.writeAddr <= {IN_uopSt.addr[31:2], addrLow};
                    OUT_memc.cacheID <= 'x;
                    OUT_memc.data <= IN_uopSt.data;

                    state <= RQ_ST;
                end
                else if (IN_uopLd.valid && IN_uopLdEn && !OUT_ldStall && 
                    (IN_uopLd.external || !IN_branch.taken || $signed(IN_uopLd.sqN - IN_branch.sqN) <= 0)
                ) begin
                    
                    case (IN_uopLd.size)
                        0: OUT_memc.cmd <= MEMC_READ_BYTE;
                        1: OUT_memc.cmd <= MEMC_READ_HALF;
                        2: OUT_memc.cmd <= MEMC_READ_WORD;
                        default: assert(0);
                    endcase

                    OUT_memc.cacheAddr <= 'x;
                    OUT_memc.readAddr <= IN_uopLd.addr[31:0];
                    OUT_memc.cacheID <= 'x;

                    state <= RQ_LD;
                    activeLd <= IN_uopLd;
                end
            end
            RQ_LD, RQ_ST: begin
                if (!IN_memc.stall[2]) begin
                    OUT_memc <= MemController_Req'{default: 'x, cmd: MEMC_NONE};
                    state <= state == RQ_LD ? WAIT_LD : WAIT_ST;
                end
            end
            WAIT_LD: begin
                if (IN_memc.sglLdRes.valid) begin
                    state <= DONE_LD;
                    case (activeLd.size)
                        0: OUT_ldData <= {4{IN_memc.sglLdRes.data[7:0]}}; 
                        1: OUT_ldData <= {2{IN_memc.sglLdRes.data[15:0]}}; 
                        default: OUT_ldData <= IN_memc.sglLdRes.data;
                    endcase
                end
            end
            WAIT_ST: begin
                if (IN_memc.sglStRes.valid)
                    state <= IDLE;
            end
            DONE_LD: begin
                if (!IN_ldStall) begin
                    state <= IDLE;
                    activeLd <= 'x;
                    activeLd.valid <= 0;
                end
            end
        endcase
    end

end

endmodule
