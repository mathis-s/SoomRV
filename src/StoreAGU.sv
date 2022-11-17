 
module StoreAGU
(
    input wire clk,
    input wire rst,
    input wire en,
    input wire stall,
    
    input BranchProv IN_branch,
    
    output ZCForward OUT_zcFwd,
    
    input EX_UOp IN_uop,
    output RES_UOp OUT_uop,
    output AGU_UOp OUT_aguOp
    
);

integer i;

wire[31:0] dataRes = IN_uop.srcB + {{20{IN_uop.imm[31]}}, IN_uop.imm[31:20]};

assign OUT_zcFwd.valid = IN_uop.valid && IN_uop.nmDst != 0;
assign OUT_zcFwd.tag = IN_uop.tagDst;
assign OUT_zcFwd.result = dataRes;

wire[31:0] addr = IN_uop.srcA + {{20{IN_uop.imm[11]}}, IN_uop.imm[11:0]};

reg except;
always_comb begin
    // Exception fires on Null pointer or unaligned access
    // (Unaligned is handled in software)
    case (IN_uop.opcode)
        LSU_SB: except = (addr == 0);
        LSU_SH: except = (addr == 0) || (addr[0]);
        LSU_F_ADDI_SW,
        LSU_SW: except = (addr == 0) || (addr[0] || addr[1]);
        default: except = 0;
    endcase
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
            OUT_uop.flags <= except ? FLAGS_EXCEPT : FLAGS_NONE;
            OUT_uop.compressed <= IN_uop.compressed;
            OUT_uop.valid <= 1;
            
            case (IN_uop.opcode)
                LSU_SB: begin
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

                LSU_SH: begin
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
                
                LSU_F_ADDI_SW: begin
                    OUT_aguOp.isLoad <= 0;
                    OUT_aguOp.wmask <= 4'b1111;
                    OUT_aguOp.data <= dataRes;
                    OUT_uop.result <= dataRes;
                end
                
                LSU_SW: begin
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
                
                default: begin end
            endcase
            
        end
        else if (!stall || (OUT_aguOp.valid && IN_branch.taken && $signed(OUT_aguOp.sqN - IN_branch.sqN) > 0))
            OUT_aguOp.valid <= 0;
    end
    
end



endmodule
