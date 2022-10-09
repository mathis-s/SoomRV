 
module AGU
(
    input wire clk,
    input wire rst,
    input wire en,
    input wire stall,
    
    input BranchProv IN_branch,
    
    input EX_UOp IN_uop,
    output AGU_UOp OUT_uop
);

integer i;

wire[31:0] addr = IN_uop.srcA + {{20{IN_uop.imm[11]}}, IN_uop.imm[11:0]};

always_ff@(posedge clk) begin
    
    if (rst) begin
        OUT_uop.valid <= 0;
    end
    else begin
        
        if (!stall && en && IN_uop.valid && (!IN_branch.taken || $signed(IN_uop.sqN - IN_branch.sqN) <= 0)) begin
            

            OUT_uop.addr <= addr;
            
            //OUT_uop.wmask <= IN_uop.wmask;
            //OUT_uop.signExtend <= IN_uop.signExtend;
            //OUT_uop.shamt <= IN_uop.shamt;
            OUT_uop.pc <= IN_uop.pc;
            OUT_uop.tagDst <= IN_uop.tagDst;
            OUT_uop.nmDst <= IN_uop.nmDst;
            OUT_uop.sqN <= IN_uop.sqN;
            OUT_uop.storeSqN <= IN_uop.storeSqN;
            OUT_uop.loadSqN <= IN_uop.loadSqN;
            OUT_uop.compressed <= IN_uop.compressed;
            OUT_uop.valid <= 1;
            
            // Exception fires on Null pointer or unaligned access
            // (Unaligned is handled in software)
            case (IN_uop.opcode)
                LSU_LB,
                LSU_LBU,
                LSU_SB: OUT_uop.exception <= (addr == 0);
                
                LSU_LH,
                LSU_LHU,
                LSU_SH: OUT_uop.exception <= (addr == 0) || (addr[0]);
                
                LSU_LW,
                LSU_SW: OUT_uop.exception <= (addr == 0) || (addr[0] || addr[1]);
                
                default: begin end
            endcase
            OUT_uop.exception <= 0;
            
            
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
                LSU_FLW,
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

                LSU_SB: begin
                    OUT_uop.isLoad <= 0;
                    case (addr[1:0]) 
                        0: begin
                            OUT_uop.wmask <= 4'b0001;
                            OUT_uop.data <= IN_uop.srcB;
                        end
                        1: begin 
                            OUT_uop.wmask <= 4'b0010;
                            OUT_uop.data <= IN_uop.srcB << 8;
                        end
                        2: begin
                            OUT_uop.wmask <= 4'b0100;
                            OUT_uop.data <= IN_uop.srcB << 16;
                        end 
                        3: begin
                            OUT_uop.wmask <= 4'b1000;
                            OUT_uop.data <= IN_uop.srcB << 24;
                        end 
                    endcase
                end

                LSU_SH: begin
                    OUT_uop.isLoad <= 0;
                    case (addr[1]) 
                        0: begin
                            OUT_uop.wmask <= 4'b0011;
                            OUT_uop.data <= IN_uop.srcB;
                        end
                        1: begin 
                            OUT_uop.wmask <= 4'b1100;
                            OUT_uop.data <= IN_uop.srcB << 16;
                        end
                    endcase
                end
                
                LSU_FSW,
                LSU_SW: begin
                    OUT_uop.isLoad <= 0;
                    OUT_uop.wmask <= 4'b1111;
                    OUT_uop.data <= IN_uop.srcB;
                end
                
                default: begin end
            endcase
            
        end
        else if (!stall || (OUT_uop.valid && IN_branch.taken && $signed(OUT_uop.sqN - IN_branch.sqN) > 0))
            OUT_uop.valid <= 0;
    end
    
end



endmodule
