module BypassLSU#(parameter RQ_ID = 2)
(
    input wire clk,
    input wire rst,

    input BranchProv IN_branch,
    
    input wire IN_uopLdEn,
    output wire OUT_ldStall,
    input LD_UOp IN_uopLd,

    input wire IN_stall,
    output LD_UOp OUT_uopLd,
    output reg[31:0] OUT_ldData,

    output CTRL_MemC OUT_memc,
    input STAT_MemC IN_memc
);

// We need to be extremely careful that bypassing load/stores aren't cached (and no transaction to cache them is currently)
// starting or in progress

reg[31:0] result;
LD_UOp activeLd;

wire invalidateActiveLd = !(activeLd.external || !IN_branch.taken || $signed(activeLd.sqN - IN_branch.sqN) <= 0);

enum logic[1:0]
{
    IDLE,
    LOAD_RQ,
    LOAD_ACTIVE,
    LOAD_DONE
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
            IDLE: begin
                if (IN_uopLdEn && !OUT_ldStall && 
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
                if (!IN_stall || invalidateActiveLd) begin
                    state <= IDLE;
                    activeLd <= 'x;
                    activeLd.valid <= 0;
                end
            end

        endcase
    end

end

endmodule
