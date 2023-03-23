
module AGU
#(parameter LOAD_AGU=1, parameter RQ_ID=2)
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
    output AGU_UOp OUT_aguOp,
    output RES_UOp OUT_uop
);

integer i;

reg pageWalkActive;
reg pageWalkAccepted;
assign OUT_stall = IN_stall || pageWalkActive;

wire[31:0] addr = IN_uop.srcA + ((IN_uop.opcode >= ATOMIC_AMOSWAP_W) ? 0 : {{20{IN_uop.imm[11]}}, IN_uop.imm[11:0]});

Flags exceptFlags;
AGU_Exception except;
always_comb begin
    except = AGU_NO_EXCEPTION;
    exceptFlags = FLAGS_NONE;
    
    if (LOAD_AGU) begin
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
    end
    else begin
        case (IN_uop.opcode)
        LSU_SB_I, LSU_SB: begin end
        LSU_SH_I, LSU_SH: begin
            if (addr[0]) begin
                except = AGU_ADDR_MISALIGN;
                exceptFlags = FLAGS_ST_MA;
            end
        end
        default: begin
            if (addr[0] || addr[1]) begin
                except = AGU_ADDR_MISALIGN;
                exceptFlags = FLAGS_ST_MA;
            end
        end
        endcase
    end
        
    if (addr == 0) begin
        except = AGU_ACCESS_FAULT;
        if (!LOAD_AGU) exceptFlags = FLAGS_ST_AF;
    end
end

always_ff@(posedge clk) begin
    
    OUT_memc.cmd <= MEMC_NONE;
    OUT_uop.valid <= 0;
    
    if (rst) begin
        OUT_aguOp.valid <= 0;
        OUT_uop.valid <= 0;
        pageWalkActive <= 0;
    end
    else begin
        if (pageWalkActive) begin
            if ((!IN_branch.taken || $signed(OUT_aguOp.sqN - IN_branch.sqN) <= 0)) begin
                
                if (!pageWalkAccepted) begin
                    if (IN_memc.busy && IN_memc.rqID == RQ_ID) pageWalkAccepted <= 1;
                    else begin
                        OUT_memc.cmd <= MEMC_PAGE_WALK;
                        OUT_memc.rootPPN <= IN_vmem.rootPPN;
                        OUT_memc.extAddr <= OUT_aguOp.addr[31:2];
                        OUT_memc.cacheID <= 'x;
                        OUT_memc.sramAddr <= 'x;
                        OUT_memc.rqID <= RQ_ID;
                    end
                end
                else if (IN_memc.resultValid) begin
                    if (LOAD_AGU) begin
                        case (IN_memc.result[3:1])
                            /*xo*/  3'b100,
                            /*inv*/ 3'b000,
                            /*rfu*/ 3'b010,
                            /*rfu*/ 3'b110: OUT_aguOp.exception <= AGU_PAGE_FAULT;
                            /*ro*/  3'b001,
                            /*rw*/  3'b011,
                            /*rx*/  3'b101,
                            /*rwx*/ 3'b111: begin end
                        endcase
                    end
                    else begin // StoreAGU
                        case (IN_memc.result[3:1])
                            /*ro*/  3'b001,
                            /*xo*/  3'b100,
                            /*rx*/  3'b101,
                            /*inv*/ 3'b000,
                            /*rfu*/ 3'b010,
                            /*rfu*/ 3'b110: begin
                                OUT_aguOp.exception <= AGU_PAGE_FAULT;
                                OUT_uop.flags <= FLAGS_ST_PF;
                            end
                            /*rw*/  3'b011,
                            /*rwx*/ 3'b111: begin end
                        endcase
                    end
                    
                    if (IN_memc.isSuperPage) begin
                        OUT_aguOp.addr[31:22] <= IN_memc.result[29:20];
                        if (IN_memc.result[19:10] != 0) begin // misaligned superpage
                            OUT_aguOp.exception <= AGU_PAGE_FAULT;
                            if (!LOAD_AGU) OUT_uop.flags <= FLAGS_ST_PF;
                        end
                    end
                    else
                        OUT_aguOp.addr[31:12] <= IN_memc.result[29:10];
                    
                    if (!IN_memc.result[0]) begin
                        OUT_aguOp.exception <= AGU_PAGE_FAULT;
                        if (!LOAD_AGU) OUT_uop.flags <= FLAGS_ST_PF;
                    end
                    
                    OUT_aguOp.valid <= 1;
                    OUT_uop.valid <= !LOAD_AGU;
                    
                    pageWalkActive <= 0;
                    OUT_memc.cmd <= MEMC_NONE;
                end
            end
            else begin
                pageWalkActive <= 0;
            end
        end
        else if (!IN_stall && en && IN_uop.valid && (!IN_branch.taken || $signed(IN_uop.sqN - IN_branch.sqN) <= 0)) begin
            
            OUT_aguOp.addr <= addr;
            OUT_aguOp.pc <= IN_uop.pc;
            OUT_aguOp.tagDst <= IN_uop.tagDst;
            OUT_aguOp.nmDst <= IN_uop.nmDst;
            OUT_aguOp.sqN <= IN_uop.sqN;
            OUT_aguOp.storeSqN <= IN_uop.storeSqN;
            OUT_aguOp.loadSqN <= IN_uop.loadSqN;
            OUT_aguOp.fetchID <= IN_uop.fetchID;
            OUT_aguOp.compressed <= IN_uop.compressed;
            OUT_aguOp.history <= IN_uop.history;
            OUT_aguOp.exception <= except;
            
            if (IN_vmem.sv32en && except == AGU_NO_EXCEPTION) begin
                OUT_aguOp.valid <= 0;
                OUT_uop.valid <= 0;
                pageWalkActive <= 1;
                pageWalkAccepted <= 0;
            end 
            else begin
                OUT_aguOp.valid <= 1;
                OUT_uop.valid <= !LOAD_AGU;
            end
                
            if (LOAD_AGU) begin
                OUT_aguOp.isLoad <= 1;
                OUT_aguOp.doNotCommit <= IN_uop.opcode >= ATOMIC_AMOSWAP_W;
                
                OUT_uop <= 'x;
                OUT_uop.valid <= 0;
                
                // Exception fires on Null pointer or unaligned access
                // (Unaligned is handled in software)
                case (IN_uop.opcode)
                    LSU_LB: begin
                        OUT_aguOp.shamt <= addr[1:0];
                        OUT_aguOp.size <= 0;
                        OUT_aguOp.signExtend <= 1;
                    end
                    LSU_LH: begin
                        OUT_aguOp.shamt <= {addr[1], 1'b0};
                        OUT_aguOp.size <= 1;
                        OUT_aguOp.signExtend <= 1;
                    end
                    LSU_LR_W,
                    ATOMIC_AMOSWAP_W, ATOMIC_AMOADD_W, ATOMIC_AMOXOR_W, 
                    ATOMIC_AMOAND_W, ATOMIC_AMOOR_W, ATOMIC_AMOMIN_W, 
                    ATOMIC_AMOMAX_W, ATOMIC_AMOMINU_W, ATOMIC_AMOMAXU_W,
                    LSU_LW: begin
                        OUT_aguOp.shamt <= 2'b0;
                        OUT_aguOp.size <= 2;
                        OUT_aguOp.signExtend <= 0;
                    end
                    LSU_LBU: begin
                        OUT_aguOp.shamt <= addr[1:0];
                        OUT_aguOp.size <= 0;
                        OUT_aguOp.signExtend <= 0;
                    end
                    LSU_LHU: begin
                        OUT_aguOp.shamt <= {addr[1], 1'b0};
                        OUT_aguOp.size <= 1;
                        OUT_aguOp.signExtend <= 0;
                    end
                    default: assert(0);
                endcase
            end
            else begin // StoreAGU
                OUT_aguOp.isLoad <= 0;
                OUT_aguOp.doNotCommit <= 0;
                
                OUT_uop.tagDst <= IN_uop.tagDst;
                OUT_uop.nmDst <= IN_uop.nmDst;
                OUT_uop.sqN <= IN_uop.sqN;
                OUT_uop.pc <= IN_uop.pc;
                OUT_uop.flags <= FLAGS_NONE;
                OUT_uop.compressed <= IN_uop.compressed;
                OUT_uop.result <= addr;
                OUT_uop.doNotCommit <= 0;
                
                // HACKY: Successful SC return value has already been handled
                // in rename; thus outputting a result here again might cause problems, so redirect to zero register.
                if (IN_uop.opcode == LSU_SC_W) begin
                    OUT_uop.nmDst <= 0;
                    OUT_uop.tagDst <= 7'h40;
                end
                
                // default
                OUT_aguOp.wmask <= 4'b1111;
                
                case (IN_uop.opcode)
                    LSU_SB, LSU_SB_I: begin
                        case (addr[1:0]) 
                            0: begin
                                OUT_aguOp.wmask <= 4'b0001;
                                OUT_aguOp.data <= IN_uop.srcB;
                            end
                            1: begin 
                                OUT_aguOp.wmask <= 4'b0010;
                                OUT_aguOp.data <= IN_uop.srcB << 8;
                            end
                            2: begin
                                OUT_aguOp.wmask <= 4'b0100;
                                OUT_aguOp.data <= IN_uop.srcB << 16;
                            end 
                            3: begin
                                OUT_aguOp.wmask <= 4'b1000;
                                OUT_aguOp.data <= IN_uop.srcB << 24;
                            end 
                        endcase
                    end

                    LSU_SH, LSU_SH_I: begin
                        case (addr[1]) 
                            0: begin
                                OUT_aguOp.wmask <= 4'b0011;
                                OUT_aguOp.data <= IN_uop.srcB;
                            end
                            1: begin 
                                OUT_aguOp.wmask <= 4'b1100;
                                OUT_aguOp.data <= IN_uop.srcB << 16;
                            end
                        endcase
                    end
                    
                    LSU_SC_W, LSU_SW, LSU_SW_I: begin
                        OUT_aguOp.wmask <= 4'b1111;
                        OUT_aguOp.data <= IN_uop.srcB;
                    end
                    
                    LSU_CBO_CLEAN: begin
                        OUT_aguOp.wmask <= 0;
                        OUT_aguOp.data[1:0] <= 0;
                    end
                    
                    LSU_CBO_INVAL: begin
                        OUT_aguOp.wmask <= 0;
                        OUT_aguOp.data[1:0] <= 1;
                        // FIXME: exception flags for CBO ops
                        OUT_uop.flags <= FLAGS_ORDERING;
                    end
                    
                    LSU_CBO_FLUSH: begin
                        OUT_aguOp.wmask <= 0;
                        OUT_aguOp.data[1:0] <= 2;
                        OUT_uop.flags <= FLAGS_ORDERING;
                    end
                    
                    ATOMIC_AMOSWAP_W: OUT_aguOp.data <= IN_uop.srcB;
                    ATOMIC_AMOADD_W:  OUT_aguOp.data <= IN_uop.srcB + IN_uop.srcC;
                    ATOMIC_AMOXOR_W:  OUT_aguOp.data <= IN_uop.srcB ^ IN_uop.srcC;
                    ATOMIC_AMOAND_W:  OUT_aguOp.data <= IN_uop.srcB & IN_uop.srcC;
                    ATOMIC_AMOOR_W:   OUT_aguOp.data <= IN_uop.srcB | IN_uop.srcC;
                    ATOMIC_AMOMIN_W:  OUT_aguOp.data <= ($signed(IN_uop.srcB) < $signed(IN_uop.srcC)) ? IN_uop.srcB : IN_uop.srcC;
                    ATOMIC_AMOMAX_W:  OUT_aguOp.data <= !($signed(IN_uop.srcB) < $signed(IN_uop.srcC)) ? IN_uop.srcB : IN_uop.srcC;
                    ATOMIC_AMOMINU_W: OUT_aguOp.data <= (IN_uop.srcB < IN_uop.srcC) ? IN_uop.srcB : IN_uop.srcC;
                    ATOMIC_AMOMAXU_W: OUT_aguOp.data <= !(IN_uop.srcB < IN_uop.srcC) ? IN_uop.srcB : IN_uop.srcC;
                    default: assert(0);
                endcase
            end
        end
        else if (!IN_stall || (OUT_aguOp.valid && IN_branch.taken && $signed(OUT_aguOp.sqN - IN_branch.sqN) > 0))
            OUT_aguOp.valid <= 0;
    end
end



endmodule
