 
module StoreAGU
(
    input wire clk,
    input wire rst,
    input wire en,
    input wire stall,
    
    input ModeFlags IN_mode,
    input wire[63:0] IN_wmask,
    
    input BranchProv IN_branch,
    output ZCForward OUT_zcFwd,
    
    input EX_UOp IN_uop,
    output RES_UOp OUT_uop,
    output AGU_UOp OUT_aguOp
    
);

integer i;

// wire[31:0] dataRes = IN_uop.srcB + {{20{IN_uop.imm[31]}}, IN_uop.imm[31:20]};
// 
// assign OUT_zcFwd.valid = IN_uop.valid && IN_uop.nmDst != 0;
// assign OUT_zcFwd.tag = IN_uop.tagDst;
// assign OUT_zcFwd.result = dataRes;

wire[31:0] addrSum = IN_uop.srcA + {{20{IN_uop.imm[11]}}, IN_uop.imm[11:0]};
wire[31:0] addr = (IN_uop.opcode >= LSU_SB_I) ? IN_uop.srcA : addrSum;

reg except;
always_comb begin
    // Exception fires on Null pointer or unaligned access
    // (Unaligned is handled in software)
    case (IN_uop.opcode)
        LSU_SB_I, LSU_SB: except = (addr == 0);
        LSU_SH_I, LSU_SH: except = (addr == 0) || (addr[0]);
        default: except = (addr == 0) || (addr[0] || addr[1]);
    endcase
    
    if (addr[31:24] == 8'hFF && IN_mode[MODE_NO_CREGS_WR]) except = 1;
    
    if (!IN_wmask[addr[31:26]] && IN_mode[MODE_WMASK]) except = 1;
end

always_ff@(posedge clk) begin
    
    OUT_uop.valid <= 0;
    
    if (rst) begin
        OUT_aguOp.valid <= 0;
    end
    else begin
        if (!stall && en && IN_uop.valid && (!IN_branch.taken || $signed(IN_uop.sqN - IN_branch.sqN) <= 0)) begin
            
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
            OUT_aguOp.valid <= 1;
            
            OUT_uop.tagDst <= IN_uop.tagDst;
            OUT_uop.nmDst <= IN_uop.nmDst;
            OUT_uop.sqN <= IN_uop.sqN;
            OUT_uop.pc <= IN_uop.pc;
            OUT_uop.flags <= except ? FLAGS_ACCESS_FAULT : FLAGS_NONE;
            OUT_uop.compressed <= IN_uop.compressed;
            OUT_uop.result <= addrSum;
            OUT_uop.doNotCommit <= 0;
            OUT_uop.valid <= 1;
            
            // HACKY: Successful SC return value has already been handled
            // in rename; thus outputting a result here again might cause problems, so redirect to zero register.
            if (IN_uop.opcode == LSU_SC_W) begin
                OUT_uop.nmDst <= 0;
                OUT_uop.tagDst <= 7'h40;
            end
                
            
            case (IN_uop.opcode)
                LSU_SB, LSU_SB_I: begin
                    OUT_aguOp.isLoad <= 0;
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
                    OUT_aguOp.isLoad <= 0;
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
                    OUT_aguOp.isLoad <= 0;
                    OUT_aguOp.wmask <= 4'b1111;
                    OUT_aguOp.data <= IN_uop.srcB;
                end
                
                LSU_CBO_CLEAN: begin
                    OUT_aguOp.isLoad <= 0;
                    OUT_aguOp.wmask <= 0;
                    OUT_aguOp.data[1:0] <= 0;
                end
                
                LSU_CBO_INVAL: begin
                    OUT_aguOp.isLoad <= 0;
                    OUT_aguOp.wmask <= 0;
                    OUT_aguOp.data[1:0] <= 1;
                    OUT_uop.flags <= FLAGS_ORDERING;
                end
                
                LSU_CBO_FLUSH: begin
                    OUT_aguOp.isLoad <= 0;
                    OUT_aguOp.wmask <= 0;
                    OUT_aguOp.data[1:0] <= 2;
                    OUT_uop.flags <= FLAGS_ORDERING;
                end
                
                
                ATOMIC_AMOSWAP_W: begin
                    OUT_aguOp.isLoad <= 0;
                    OUT_aguOp.wmask <= 4'b1111;
                    OUT_aguOp.data <= IN_uop.srcB;
                end
                
                ATOMIC_AMOADD_W: begin
                    OUT_aguOp.isLoad <= 0;
                    OUT_aguOp.wmask <= 4'b1111;
                    OUT_aguOp.data <= IN_uop.srcB + IN_uop.srcC;
                end
                
                ATOMIC_AMOXOR_W: begin
                    OUT_aguOp.isLoad <= 0;
                    OUT_aguOp.wmask <= 4'b1111;
                    OUT_aguOp.data <= IN_uop.srcB ^ IN_uop.srcC;
                end
                
                ATOMIC_AMOAND_W: begin
                    OUT_aguOp.isLoad <= 0;
                    OUT_aguOp.wmask <= 4'b1111;
                    OUT_aguOp.data <= IN_uop.srcB & IN_uop.srcC;
                end
                
                ATOMIC_AMOOR_W: begin
                    OUT_aguOp.isLoad <= 0;
                    OUT_aguOp.wmask <= 4'b1111;
                    OUT_aguOp.data <= IN_uop.srcB | IN_uop.srcC;
                end
                
                ATOMIC_AMOMIN_W: begin
                    OUT_aguOp.isLoad <= 0;
                    OUT_aguOp.wmask <= 4'b1111;
                    OUT_aguOp.data <= ($signed(IN_uop.srcB) < $signed(IN_uop.srcC)) ? IN_uop.srcB : IN_uop.srcC;
                end
                
                ATOMIC_AMOMAX_W: begin
                    OUT_aguOp.isLoad <= 0;
                    OUT_aguOp.wmask <= 4'b1111;
                    OUT_aguOp.data <= !($signed(IN_uop.srcB) < $signed(IN_uop.srcC)) ? IN_uop.srcB : IN_uop.srcC;
                end
                
                ATOMIC_AMOMINU_W: begin
                    OUT_aguOp.isLoad <= 0;
                    OUT_aguOp.wmask <= 4'b1111;
                    OUT_aguOp.data <= (IN_uop.srcB < IN_uop.srcC) ? IN_uop.srcB : IN_uop.srcC;
                end
                
                ATOMIC_AMOMAXU_W: begin
                    OUT_aguOp.isLoad <= 0;
                    OUT_aguOp.wmask <= 4'b1111;
                    OUT_aguOp.data <= !(IN_uop.srcB < IN_uop.srcC) ? IN_uop.srcB : IN_uop.srcC;
                end
                
                
                default: begin end
            endcase
            
        end
        else if (!stall || (OUT_aguOp.valid && IN_branch.taken && $signed(OUT_aguOp.sqN - IN_branch.sqN) > 0))
            OUT_aguOp.valid <= 0;
    end
    
end



endmodule
