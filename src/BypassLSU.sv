module BypassLSU#(parameter RQ_ID = 2)
(
    input wire clk,
    input wire rst,

    input BranchProv IN_branch,
    
    input wire IN_uopLdEn,
    output wire OUT_ldStall,
    input LD_UOp IN_uopLd,

    input wire IN_uopStEn,
    output wire OUT_stStall,
    input ST_UOp IN_uopSt,

    input wire IN_ldStall,
    output LD_UOp OUT_uopLd,
    output reg[31:0] OUT_ldData,

    output CTRL_MemC OUT_memc,
    input STAT_MemC IN_memc
);

reg[31:0] result;

LD_UOp activeLd;

wire invalidateActiveLd = !(activeLd.external || !IN_branch.taken || $signed(activeLd.sqN - IN_branch.sqN) <= 0);

enum logic[2:0]
{
    IDLE,
    LOAD_RQ,
    LOAD_ACTIVE,
    LOAD_DONE,
    STORE_RQ,
    STORE_ACTIVE
} state;

always_comb begin
    OUT_ldStall = IN_uopLd.valid && IN_uopLdEn && state != IDLE;

    OUT_uopLd = 'x;
    OUT_uopLd.valid = 0;
    OUT_ldData = 'x;

    if (state == LOAD_DONE && !invalidateActiveLd) begin
        OUT_uopLd = activeLd;
        OUT_ldData = result;
    end
end

always_comb begin
    OUT_stStall = (IN_uopSt.valid && IN_uopStEn && state != IDLE) || (IN_uopLdEn && !OUT_ldStall);
end

always_ff@(posedge clk) begin
    
    if (rst) begin
        activeLd.valid <= 0;
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
                if (IN_uopLd.valid && IN_uopLdEn && !OUT_ldStall && 
                    (IN_uopLd.external || !IN_branch.taken || $signed(IN_uopLd.sqN - IN_branch.sqN) <= 0)
                ) begin
                    activeLd <= IN_uopLd;

                    OUT_memc.cmd <= MEMC_READ_SINGLE;
                    OUT_memc.sramAddr <= 'x;
                    OUT_memc.extAddr <= IN_uopLd.addr[31:2];
                    OUT_memc.cacheID <= 'x;
                    OUT_memc.rqID <= RQ_ID;

                    state <= LOAD_RQ;
                end
                else if (IN_uopSt.valid && IN_uopStEn && !OUT_stStall) begin
                    OUT_memc.cmd <= MEMC_WRITE_SINGLE;
                    OUT_memc.sramAddr <= 'x;
                    OUT_memc.extAddr <= IN_uopSt.addr[31:2];
                    OUT_memc.cacheID <= 'x;
                    OUT_memc.rqID <= RQ_ID;
                    OUT_memc.data <= IN_uopSt.data;

                    state <= STORE_RQ;
                end
            end
            LOAD_RQ: begin
                if (IN_memc.busy && IN_memc.rqID == RQ_ID) begin
                    OUT_memc.cmd <= MEMC_NONE;
                    state <= LOAD_ACTIVE;
                end
            end
            LOAD_ACTIVE: begin
                if (IN_memc.resultValid) begin
                    result <= IN_memc.result;
                    state <= LOAD_DONE;
                    if (invalidateActiveLd)
                        state <= IDLE;
                end
            end
            LOAD_DONE: begin
                if (!IN_ldStall || invalidateActiveLd) begin
                    state <= IDLE;
                    activeLd <= 'x;
                    activeLd.valid <= 0;
                end
            end

            STORE_RQ: begin
                if (IN_memc.busy && IN_memc.rqID == RQ_ID) begin
                    OUT_memc.cmd <= MEMC_NONE;
                    state <= STORE_ACTIVE;
                end
            end
            STORE_ACTIVE: begin
                if (!IN_memc.busy) begin
                    state <= IDLE;
                end
            end
        endcase
    end

end

endmodule
