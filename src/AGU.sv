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
    output PageWalkRq OUT_pw,
    input PageWalkRes IN_pw,
    
    input EX_UOp IN_uop,
    output AGU_UOp OUT_aguOp,
    output RES_UOp OUT_uop
);


reg pageWalkActive;
reg pageWalkAccepted;
assign OUT_stall = IN_stall || pageWalkActive;

wire[31:0] addr = IN_uop.srcA + ((IN_uop.opcode >= ATOMIC_AMOSWAP_W) ? 0 : {{20{IN_uop.imm[11]}}, IN_uop.imm[11:0]});

Flags exceptFlags;
AGU_Exception except;
always_comb begin
    except = AGU_NO_EXCEPTION;
    exceptFlags = FLAGS_NONE;
    
    if (!`IS_LEGAL_ADDR(addr) && !IN_vmem.sv32en) begin
        except = AGU_ACCESS_FAULT;
        if (!LOAD_AGU) exceptFlags = FLAGS_ST_AF;
    end

    // Misalign has higher priority than access fault
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
end

always_ff@(posedge clk) begin
    
    OUT_pw.valid <= 0;
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
                    if (IN_pw.busy && IN_pw.rqID == RQ_ID) pageWalkAccepted <= 1;
                    else begin
                        OUT_pw.valid <= 1;
                        OUT_pw.rootPPN <= IN_vmem.rootPPN;
                        OUT_pw.addr <= OUT_aguOp.addr;
                    end
                end
                else if (IN_pw.valid) begin
                    if (LOAD_AGU) begin
                        case (IN_pw.result[3:1])
                            /*inv*/ 3'b000,
                            /*rfu*/ 3'b010,
                            /*rfu*/ 3'b110: OUT_aguOp.exception <= AGU_PAGE_FAULT;
                            /*xo*/  3'b100: begin
                                if (!IN_vmem.makeExecReadable) 
                                    OUT_aguOp.exception <= AGU_PAGE_FAULT;
                            end
                            /*ro*/  3'b001,
                            /*rw*/  3'b011,
                            /*rx*/  3'b101,
                            /*rwx*/ 3'b111: begin end
                        endcase
                    end
                    else begin // StoreAGU
                        case (IN_pw.result[3:1])
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
                    
                    if (IN_pw.isSuperPage) begin
                        OUT_aguOp.addr[31:22] <= IN_pw.result[29:20];
                        if (IN_pw.result[19:10] != 0) begin // misaligned superpage
                            OUT_aguOp.exception <= AGU_PAGE_FAULT;
                            if (!LOAD_AGU) OUT_uop.flags <= FLAGS_ST_PF;
                        end
                    end
                    else
                        OUT_aguOp.addr[31:12] <= IN_pw.result[29:10];

                    if (!IN_pw.result[0] ||
                        (IN_vmem.priv == PRIV_USER && !IN_pw.result[4]) ||
                        (IN_vmem.priv == PRIV_SUPERVISOR && IN_pw.result[4] && !IN_vmem.supervUserMemory) ||
                        (!IN_pw.result[6]) || // access but accessed not set
                        (!LOAD_AGU && !IN_pw.result[7]) // write but dirty not set
                    ) begin
                        OUT_aguOp.exception <= AGU_PAGE_FAULT;
                        if (!LOAD_AGU) OUT_uop.flags <= FLAGS_ST_PF;
                    end
                    
                    if (IN_pw.result[31:30] != 2'b0 || !`IS_LEGAL_ADDR({IN_pw.result[29:10], 12'b0})) begin
                        OUT_aguOp.exception <= AGU_ACCESS_FAULT;
                        if (!LOAD_AGU) OUT_uop.flags <= FLAGS_ST_AF;
                    end
                    
                    OUT_aguOp.valid <= 1;
                    OUT_uop.valid <= !LOAD_AGU;
                    
                    pageWalkActive <= 0;
                    OUT_pw.valid <= 0;
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
            OUT_aguOp.sqN <= IN_uop.sqN;
            OUT_aguOp.storeSqN <= IN_uop.storeSqN;
            OUT_aguOp.loadSqN <= IN_uop.loadSqN;
            OUT_aguOp.fetchID <= IN_uop.fetchID;
            OUT_aguOp.compressed <= IN_uop.compressed;
            OUT_aguOp.history <= IN_uop.history;
            OUT_aguOp.rIdx <= IN_uop.bpi.rIdx;
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
                        OUT_aguOp.size <= 0;
                        OUT_aguOp.signExtend <= 1;
                    end
                    LSU_LH: begin
                        OUT_aguOp.size <= 1;
                        OUT_aguOp.signExtend <= 1;
                    end
                    LSU_LR_W,
                    ATOMIC_AMOSWAP_W, ATOMIC_AMOADD_W, ATOMIC_AMOXOR_W, 
                    ATOMIC_AMOAND_W, ATOMIC_AMOOR_W, ATOMIC_AMOMIN_W, 
                    ATOMIC_AMOMAX_W, ATOMIC_AMOMINU_W, ATOMIC_AMOMAXU_W,
                    LSU_LW: begin
                        OUT_aguOp.size <= 2;
                        OUT_aguOp.signExtend <= 0;
                    end
                    LSU_LBU: begin
                        OUT_aguOp.size <= 0;
                        OUT_aguOp.signExtend <= 0;
                    end
                    LSU_LHU: begin
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
                OUT_uop.sqN <= IN_uop.sqN;
                OUT_uop.result <= addr;
                OUT_uop.doNotCommit <= 0;
                
                // HACKY: Successful SC return value has already been handled
                // in rename; thus outputting a result here again might cause problems, so redirect to zero register.
                if (IN_uop.opcode == LSU_SC_W) begin
                    OUT_uop.tagDst <= 7'h40;
                end
                
                // default
                OUT_aguOp.wmask <= 4'b1111;
                OUT_aguOp.size <= 2;
                
                OUT_uop.flags <= exceptFlags;
                
                case (IN_uop.opcode)
                    LSU_SB, LSU_SB_I: begin
                        OUT_aguOp.size <= 0;
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
                        OUT_aguOp.size <= 1;
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
                        OUT_aguOp.data <= {30'bx, 2'd0};

                        if (!IN_vmem.cbcfe) begin
                            OUT_uop.flags <= FLAGS_ILLEGAL_INSTR;
                            OUT_aguOp.valid <= 0;
                        end
                    end
                    
                    LSU_CBO_INVAL: begin
                        OUT_aguOp.wmask <= 0;

                        OUT_aguOp.data <= {30'bx, (IN_vmem.cbie == 3) ? 2'd1 : 2'd2};

                        if (exceptFlags == FLAGS_NONE)
                            OUT_uop.flags <= FLAGS_ORDERING;

                        if (IN_vmem.cbie == 2'b00) begin
                            OUT_uop.flags <= FLAGS_ILLEGAL_INSTR;
                            OUT_aguOp.valid <= 0;
                        end
                    end
                    
                    LSU_CBO_FLUSH: begin
                        OUT_aguOp.wmask <= 0;
                        OUT_aguOp.data <= {30'bx, 2'd2};
                        if (exceptFlags == FLAGS_NONE)
                            OUT_uop.flags <= FLAGS_ORDERING;

                        if (!IN_vmem.cbcfe) begin
                            OUT_uop.flags <= FLAGS_ILLEGAL_INSTR;
                            OUT_aguOp.valid <= 0;
                        end
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
