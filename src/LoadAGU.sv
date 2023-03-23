
module LoadAGU
(
    input wire clk,
    input wire rst,
    input wire en,
    input wire IN_stall,
    output wire OUT_stall,
    
    input BranchProv IN_branch,
    
    input STAT_VMem IN_vmem,
    output CTRL_MemC OUT_memc,
    input STAT_MemC IN_memc,
    
    input EX_UOp IN_uop,
    output AGU_UOp OUT_uop
);

integer i;

reg pageWalkActive;
reg pageWalkAccepted;
assign OUT_stall = IN_stall || pageWalkActive;

wire[31:0] addr = IN_uop.srcA + ((IN_uop.opcode >= ATOMIC_AMOSWAP_W) ? 0 : {{20{IN_uop.imm[11]}}, IN_uop.imm[11:0]});

AGU_Exception except;
always_comb begin
    
    except = AGU_NO_EXCEPTION;

    case (IN_uop.opcode)
        LSU_LB, LSU_LBU: begin end
        
        LSU_LH, LSU_LHU: begin
            if (addr[0])
                except = AGU_ADDR_MISALIGN;
        end
        default: begin
            if (addr[0] || addr[1])
                except = AGU_ADDR_MISALIGN;
        end
    endcase
    
    if (addr == 0)
        except = AGU_ACCESS_FAULT;
end

always_ff@(posedge clk) begin
    
    OUT_memc.cmd <= MEMC_NONE;
    
    if (rst) begin
        OUT_uop.valid <= 0;
        pageWalkActive <= 0;
    end
    else begin
        
        if (pageWalkActive) begin
            if ((!IN_branch.taken || $signed(OUT_uop.sqN - IN_branch.sqN) <= 0)) begin
                
                if (!pageWalkAccepted) begin
                    if (IN_memc.busy && IN_memc.rqID == 2) pageWalkAccepted <= 1;
                    else begin
                        OUT_memc.cmd <= MEMC_PAGE_WALK;
                        OUT_memc.rootPPN <= IN_vmem.rootPPN;
                        OUT_memc.extAddr <= OUT_uop.addr[31:2];
                        OUT_memc.cacheID <= 'x;
                        OUT_memc.sramAddr <= 'x;
                        OUT_memc.rqID <= 2;
                    end
                end
                
                // FIXME: unchecked!
                else if (IN_memc.resultValid) begin
                    
                    case (IN_memc.result[3:1])
                        3'b000,
                        3'b010,
                        3'b110: OUT_uop.exception <= AGU_PAGE_FAULT;
                        
                        3'b001,
                        3'b011,
                        3'b100,
                        3'b101,
                        3'b111: OUT_uop.addr[31:12] <= IN_memc.result[29:10];
                    endcase
                    
                    OUT_uop.valid <= 1;
                    pageWalkActive <= 0;
                    OUT_memc.cmd <= MEMC_NONE;
                end
            end
            else begin
                pageWalkActive <= 0;
            end
        end
        else if (!IN_stall && en && IN_uop.valid && (!IN_branch.taken || $signed(IN_uop.sqN - IN_branch.sqN) <= 0)) begin
            
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
            OUT_uop.exception <= except;
            
            OUT_uop.doNotCommit <= IN_uop.opcode >= ATOMIC_AMOSWAP_W;
            
            if (IN_vmem.sv32en && except == AGU_NO_EXCEPTION) begin
                OUT_uop.valid <= 0;
                pageWalkActive <= 1;
                pageWalkAccepted <= 0;
            end 
            else begin
                OUT_uop.valid <= 1;
            end
            
            // Exception fires on Null pointer or unaligned access
            // (Unaligned is handled in software)
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
        else if (!IN_stall || (OUT_uop.valid && IN_branch.taken && $signed(OUT_uop.sqN - IN_branch.sqN) > 0))
            OUT_uop.valid <= 0;
    end
    
end



endmodule
