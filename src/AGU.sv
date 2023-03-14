
module AGU
(
    input wire clk,
    input wire rst,
    input wire en,
    input wire stall,
    
    input ModeFlags IN_mode,
    input wire[63:0] IN_rmask,
    
    input BranchProv IN_branch,
    
    input EX_UOp IN_uop,
    output AGU_UOp OUT_uop
);

integer i;

wire[31:0] addr = IN_uop.srcA + ((IN_uop.opcode >= ATOMIC_AMOSWAP_W) ? 0 : {{20{IN_uop.imm[11]}}, IN_uop.imm[11:0]});

always_ff@(posedge clk) begin
    
    if (rst) begin
        OUT_uop.valid <= 0;
    end
    else begin
        
        if (!stall && en && IN_uop.valid && (!IN_branch.taken || $signed(IN_uop.sqN - IN_branch.sqN) <= 0)) begin
            
            OUT_uop.addr <= addr;
            OUT_uop.pc <= IN_uop.pc;
            OUT_uop.tagDst <= IN_uop.tagDst;
            OUT_uop.nmDst <= IN_uop.nmDst;
            OUT_uop.sqN <= IN_uop.sqN;
            OUT_uop.storeSqN <= IN_uop.storeSqN;
            OUT_uop.loadSqN <= IN_uop.loadSqN;
            OUT_uop.fetchID <= IN_uop.fetchID;
            OUT_uop.compressed <= IN_uop.compressed;
            OUT_uop.history <= IN_uop.history;
            
            OUT_uop.doNotCommit <= IN_uop.opcode >= ATOMIC_AMOSWAP_W;
            OUT_uop.valid <= 1;
            
            // Exception fires on Null pointer or unaligned access
            // (Unaligned is handled in software)
            case (IN_uop.opcode)
            
                LSU_LB,
                LSU_LBU: OUT_uop.exception <= (addr == 0);
                
                LSU_LH,
                LSU_LHU: OUT_uop.exception <= (addr == 0) || (addr[0]);
                
                default: OUT_uop.exception <= (addr == 0) || (addr[0] || addr[1]);
                
            endcase
            
            if (addr[31:24] == 8'hFF && IN_mode[MODE_NO_CREGS_RD]) OUT_uop.exception <= 1;
            if (!IN_rmask[addr[31:26]] && IN_mode[MODE_RMASK]) OUT_uop.exception <= 1;
            
            
            case (IN_uop.opcode)
                LSU_LB: begin
                    OUT_uop.isLoad <= 1;
                    OUT_uop.shamt <= addr[1:0];
                    OUT_uop.size <= 0;
                    OUT_uop.signExtend <= 1;
                end
                 LSU_LH: begin
                    OUT_uop.isLoad <= 1;
                    OUT_uop.shamt <= {addr[1], 1'b0};
                    OUT_uop.size <= 1;
                    OUT_uop.signExtend <= 1;
                end
                
                LSU_LR_W,
                ATOMIC_AMOSWAP_W, ATOMIC_AMOADD_W, ATOMIC_AMOXOR_W, 
                ATOMIC_AMOAND_W, ATOMIC_AMOOR_W, ATOMIC_AMOMIN_W, 
                ATOMIC_AMOMAX_W, ATOMIC_AMOMINU_W, ATOMIC_AMOMAXU_W,
                LSU_LW: begin
                    OUT_uop.isLoad <= 1;
                    OUT_uop.shamt <= 2'b0;
                    OUT_uop.size <= 2;
                    OUT_uop.signExtend <= 0;
                end
                LSU_LBU: begin
                    OUT_uop.isLoad <= 1;
                    OUT_uop.shamt <= addr[1:0];
                    OUT_uop.size <= 0;
                    OUT_uop.signExtend <= 0;
                end
                LSU_LHU: begin
                    OUT_uop.isLoad <= 1;
                    OUT_uop.shamt <= {addr[1], 1'b0};
                    OUT_uop.size <= 1;
                    OUT_uop.signExtend <= 0;
                end
                default: begin end
            endcase
            
        end
        else if (!stall || (OUT_uop.valid && IN_branch.taken && $signed(OUT_uop.sqN - IN_branch.sqN) > 0))
            OUT_uop.valid <= 0;
    end
    
end



endmodule
