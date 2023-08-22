module AGU
#(parameter LOAD_AGU=1, parameter RQ_ID=2)
(
    input wire clk,
    input wire rst,
    input wire en,
    input wire IN_stall,
    output wire OUT_stall,
    
    input BranchProv IN_branch,
    
    input VirtMemState IN_vmem,
    output PageWalk_Req OUT_pw,
    input PageWalk_Res IN_pw,

    output TLB_Req OUT_tlb,
    input TLB_Res IN_tlb,
    
    output TValProv OUT_tvalProv,
    
    input EX_UOp IN_uop,
    output AGU_UOp OUT_aguOp,
    output ELD_UOp OUT_eldOp,
    output RES_UOp OUT_uop,
    input wire IN_isDelayLoad
);

localparam STORE_AGU = !LOAD_AGU;

function logic IsPermFault(logic[2:0] pte_rwx, logic pte_user);
    logic r;
    r = (LOAD_AGU  && !(pte_rwx[2] || (pte_rwx[0] && IN_vmem.makeExecReadable))) ||
        (STORE_AGU && !pte_rwx[1]) ||
        (IN_vmem.priv == PRIV_USER && !pte_user) ||
        (IN_vmem.priv == PRIV_SUPERVISOR && pte_user && !IN_vmem.supervUserMemory);
    return r;
endfunction

// delayed loads stay in the LoadBuffer anyways,
// so we can ignore the LSU's stall signal
wire inStallMasked = IN_stall && !IN_isDelayLoad;

reg pageWalkActive;
reg pageWalkAccepted;
reg eldIsPageWalkOp;
assign OUT_stall = inStallMasked || eldIsPageWalkOp || waitForPWComplete;


wire[31:0] addr = IN_uop.srcA + ((IN_uop.opcode >= ATOMIC_AMOSWAP_W) ? 0 : {{20{IN_uop.imm[11]}}, IN_uop.imm[11:0]});
wire[31:0] phyAddr = IN_vmem.sv32en ? {IN_tlb.ppn, addr[11:0]} : addr; // super is already handled in TLB

always_comb begin
    OUT_eldOp = 'x;

    if (eldIsPageWalkOp) begin
        OUT_eldOp.valid =
            !rst &&
            ((pageWalkAccepted && IN_pw.valid) || !pageWalkActive) &&
            (!IN_branch.taken || $signed(OUT_aguOp.sqN - IN_branch.sqN) <= 0);
        if (OUT_eldOp.valid)
            OUT_eldOp.addr = OUT_aguOp.addr[11:0];
    end
    else begin
        OUT_eldOp.valid =
            !rst &&
            !waitForPWComplete &&
            !pageWalkActive &&
            en && IN_uop.valid && (!IN_branch.taken || $signed(IN_uop.sqN - IN_branch.sqN) <= 0);
        
        if (OUT_eldOp.valid)
            OUT_eldOp.addr = addr[11:0];
    end
end

Flags exceptFlags;
AGU_Exception except;
always_comb begin
    except = AGU_NO_EXCEPTION;
    exceptFlags = FLAGS_NONE;
    
    if (IN_vmem.sv32en && IN_tlb.hit && 
        (IN_tlb.fault || IsPermFault(IN_tlb.rwx, IN_tlb.user))
    ) begin
        except = AGU_PAGE_FAULT;
        if (STORE_AGU) exceptFlags = FLAGS_ST_PF;
    end
    else if (!`IS_LEGAL_ADDR(phyAddr) && !(IN_vmem.sv32en && !IN_tlb.hit)) begin
        except = AGU_ACCESS_FAULT;
        if (STORE_AGU) exceptFlags = FLAGS_ST_AF;
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

always_comb begin
    OUT_tlb.valid = 
        (IN_vmem.sv32en) &&
        !(rst) && 
        !(waitForPWComplete) && 
        !(pageWalkActive) && 
        (!inStallMasked && en && IN_uop.valid /*&& (!IN_branch.taken || $signed(IN_uop.sqN - IN_branch.sqN) <= 0)*/);
    
    OUT_tlb.vpn = addr[31:12];
end


reg waitForPWComplete;

always_ff@(posedge clk) begin

    OUT_pw.valid <= 0;
    OUT_uop.valid <= 0;
    OUT_tvalProv <= 'x;
    OUT_tvalProv.valid <= 0;
    
    if (rst) begin
        OUT_aguOp.valid <= 0;
        OUT_uop.valid <= 0;
        pageWalkActive <= 0;
        waitForPWComplete <= 0;
        eldIsPageWalkOp <= 0;
    end
    else begin

        if (eldIsPageWalkOp && !pageWalkActive && !inStallMasked)
            eldIsPageWalkOp <= 0;

        if (waitForPWComplete) begin
            if (!IN_pw.busy || IN_pw.rqID != RQ_ID)
                waitForPWComplete <= 0;
        end
        else if (pageWalkActive) begin
            if ((!IN_branch.taken || $signed(OUT_aguOp.sqN - IN_branch.sqN) <= 0)) begin
                
                if (!pageWalkAccepted) begin
                    if (IN_pw.busy && IN_pw.rqID == RQ_ID) begin
                        pageWalkAccepted <= 1;
                    end
                    else begin
                        OUT_pw.valid <= 1;
                        OUT_pw.rootPPN <= IN_vmem.rootPPN;
                        OUT_pw.addr <= OUT_aguOp.addr;
                    end
                end
                else if (IN_pw.valid) begin

                    AGU_Exception exception_c = AGU_NO_EXCEPTION;
                    if (IN_pw.pageFault)
                        exception_c = AGU_PAGE_FAULT;
                    else if (IsPermFault(IN_pw.rwx, IN_pw.user)) begin
                        exception_c = AGU_PAGE_FAULT;
                    end
                    else if (IN_pw.ppn[21:20] != 2'b0 || 
                            !`IS_LEGAL_ADDR(IN_pw.isSuperPage ? 
                                {IN_pw.ppn[19:10], OUT_aguOp.addr[21:0]} : 
                                {IN_pw.ppn[19:0], OUT_aguOp.addr[11:0]})
                    ) begin
                        exception_c = AGU_ACCESS_FAULT;
                    end
                    else begin
                        // Register translated address
                        if (IN_pw.isSuperPage)
                            OUT_aguOp.addr[31:22] <= IN_pw.ppn[19:10];
                        else
                            OUT_aguOp.addr[31:12] <= IN_pw.ppn[19:0];
                    end
                    
                    OUT_aguOp.valid <= 1;
                    OUT_aguOp.exception <= exception_c;

                    if (STORE_AGU) begin
                        OUT_uop.valid <= 1;
                        case (exception_c)
                            AGU_NO_EXCEPTION: ;
                            AGU_ACCESS_FAULT:  OUT_uop.flags <= FLAGS_ST_AF;
                            AGU_PAGE_FAULT:    OUT_uop.flags <= FLAGS_ST_PF;
                            AGU_ADDR_MISALIGN: assert(0);
                        endcase
                    end

                    if (exception_c != AGU_NO_EXCEPTION) begin
                        OUT_tvalProv.valid <= 1;
                        OUT_tvalProv.sqN <= OUT_aguOp.sqN;
                        OUT_tvalProv.tval <= OUT_aguOp.addr;
                    end

                    pageWalkActive <= 0;
                    pageWalkAccepted <= 0;
                    OUT_pw.valid <= 0;
                    eldIsPageWalkOp <= inStallMasked;
                end
            end
            else begin
                waitForPWComplete <= pageWalkActive;
                pageWalkAccepted <= 0;
                pageWalkActive <= 0;
                eldIsPageWalkOp <= 0;
            end
        end
        else if (!inStallMasked && en && IN_uop.valid && (!IN_branch.taken || $signed(IN_uop.sqN - IN_branch.sqN) <= 0) && !eldIsPageWalkOp) begin
            
            OUT_aguOp.addr <= phyAddr;
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
            
            if (IN_vmem.sv32en && except == AGU_NO_EXCEPTION && !IN_tlb.hit) begin
                OUT_aguOp.addr <= addr;
                OUT_aguOp.valid <= 0;
                OUT_uop.valid <= 0;
                pageWalkActive <= 1;
                eldIsPageWalkOp <= 1;
                pageWalkAccepted <= 0;
            end 
            else begin
                if (except != AGU_NO_EXCEPTION) begin
                    OUT_tvalProv.valid <= 1;
                    OUT_tvalProv.sqN <= IN_uop.sqN;
                    OUT_tvalProv.tval <= addr;
                end

                OUT_aguOp.valid <= 1;
                OUT_uop.valid <= STORE_AGU;
            end
            
            if (LOAD_AGU) begin
                OUT_aguOp.isLoad <= 1;
                OUT_aguOp.doNotCommit <= IN_uop.opcode >= ATOMIC_AMOSWAP_W;
                
                OUT_uop <= 'x;
                OUT_uop.valid <= 0;
                
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
                OUT_uop.result <= phyAddr;
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
                        case (phyAddr[1:0]) 
                            0: begin
                                OUT_aguOp.wmask <= 4'b0001;
                            end
                            1: begin 
                                OUT_aguOp.wmask <= 4'b0010;
                            end
                            2: begin
                                OUT_aguOp.wmask <= 4'b0100;
                            end 
                            3: begin
                                OUT_aguOp.wmask <= 4'b1000;
                            end 
                        endcase
                    end

                    LSU_SH, LSU_SH_I: begin
                        OUT_aguOp.size <= 1;
                        case (phyAddr[1]) 
                            0: begin
                                OUT_aguOp.wmask <= 4'b0011;
                            end
                            1: begin 
                                OUT_aguOp.wmask <= 4'b1100;
                            end
                        endcase
                    end
                    
                    LSU_SC_W, LSU_SW, LSU_SW_I: begin
                        OUT_aguOp.wmask <= 4'b1111;
                    end
                    
                    LSU_CBO_CLEAN: begin
                        OUT_aguOp.wmask <= 0;

                        if (!IN_vmem.cbcfe) begin
                            OUT_uop.flags <= FLAGS_ILLEGAL_INSTR;
                            OUT_aguOp.valid <= 0;
                        end
                    end
                    
                    LSU_CBO_INVAL: begin
                        OUT_aguOp.wmask <= 0;

                        if (exceptFlags == FLAGS_NONE)
                            OUT_uop.flags <= FLAGS_ORDERING;

                        if (IN_vmem.cbie == 2'b00) begin
                            OUT_uop.flags <= FLAGS_ILLEGAL_INSTR;
                            OUT_aguOp.valid <= 0;
                        end
                    end
                    
                    LSU_CBO_FLUSH: begin
                        OUT_aguOp.wmask <= 0;
                        if (exceptFlags == FLAGS_NONE)
                            OUT_uop.flags <= FLAGS_ORDERING;

                        if (!IN_vmem.cbcfe) begin
                            OUT_uop.flags <= FLAGS_ILLEGAL_INSTR;
                            OUT_aguOp.valid <= 0;
                        end
                    end
                    
                    ATOMIC_AMOSWAP_W,
                    ATOMIC_AMOADD_W,
                    ATOMIC_AMOXOR_W,
                    ATOMIC_AMOAND_W,
                    ATOMIC_AMOOR_W,
                    ATOMIC_AMOMIN_W,
                    ATOMIC_AMOMAX_W,
                    ATOMIC_AMOMINU_W,
                    ATOMIC_AMOMAXU_W:;

                    default: assert(0);
                endcase
            end
        end
        else if ((!inStallMasked && !eldIsPageWalkOp) || (OUT_aguOp.valid && IN_branch.taken && $signed(OUT_aguOp.sqN - IN_branch.sqN) > 0))
            OUT_aguOp.valid <= 0;
    end
end



endmodule
