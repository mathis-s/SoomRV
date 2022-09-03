module LSU
(
    input wire clk,
    input wire rst,

    input wire IN_valid,
    input EX_UOp IN_uop,
    
    input wire IN_invalidate,
    input wire[5:0] IN_invalidateSqN,

    
    output reg OUT_SQ_valid,
    output reg OUT_SQ_isLoad,
    output reg[29:0] OUT_SQ_addr,
    output reg[31:0] OUT_SQ_data,
    output reg[3:0] OUT_SQ_wmask,
    output reg[5:0] OUT_SQ_sqN,
    output reg[5:0] OUT_SQ_storeSqN,
    
    input wire[31:0] IN_readData,
    
    output reg OUT_LB_valid,
    output reg OUT_LB_isLoad,
    output reg[31:0] OUT_LB_addr,
    output reg[5:0] OUT_LB_sqN,
    output reg[5:0] OUT_LB_loadSqN,
    input wire IN_LB_mispred,
    
    output BranchProv OUT_branchProv,

    output wire OUT_wbReq,

    output reg OUT_valid,
    output RES_UOp OUT_uop
);

typedef struct packed
{
    bit valid;
    bit[5:0] opcode;
    bit[5:0] tagDst;
    bit[4:0] nmDst;
    bit[5:0] sqN;
    bit[5:0] loadSqN;
    bit[5:0] storeSqN;
    bit[1:0] byteIndex;
    bit[31:0] pc;
} IData;

IData i0;
IData i1;
IData i2;

wire[31:0] addr = IN_uop.srcA + IN_uop.imm;

assign OUT_wbReq = i2.valid;

always@(posedge clk) begin

    if (rst) begin
        i0.valid <= 0;
        i1.valid <= 0;
        OUT_LB_valid <= 0;
    end
    else if (IN_valid && (!IN_invalidate || $signed(IN_uop.sqN - IN_invalidateSqN) <= 0)) begin

        i0.valid <= 1;
        i0.opcode <= IN_uop.opcode;
        i0.tagDst <= IN_uop.tagDst;
        i0.nmDst <= IN_uop.nmDst;
        i0.sqN <= IN_uop.sqN;
        i0.loadSqN <= IN_uop.loadSqN;
        i0.storeSqN <= IN_uop.storeSqN;
        i0.byteIndex <= addr[1:0];
        i0.pc <= IN_uop.pc;
        
        OUT_SQ_addr <= addr[31:2];
        OUT_SQ_storeSqN <= IN_uop.storeSqN;
        OUT_SQ_sqN <= IN_uop.sqN;
        
        OUT_LB_valid <= 1;
        OUT_LB_isLoad <= !(IN_uop.opcode == LSU_SB || IN_uop.opcode == LSU_SH || IN_uop.opcode == LSU_SW);
        OUT_LB_addr <= addr;
        OUT_LB_sqN <= IN_uop.sqN;
        OUT_LB_loadSqN <= IN_uop.loadSqN;

        case (IN_uop.opcode)
            LSU_LB,
            LSU_LH,
            LSU_LW,
            LSU_LBU,
            LSU_LHU: begin
                OUT_SQ_isLoad <= 1;
                OUT_SQ_valid <= 1;
                i0.byteIndex <= addr[1:0];
            end

            LSU_SB: begin
                OUT_SQ_isLoad <= 0;
                OUT_SQ_valid <= 1;
                case (addr[1:0]) 
                    0: begin
                        OUT_SQ_wmask <= 4'b0001;
                        OUT_SQ_data <= IN_uop.srcB;
                    end
                    1: begin 
                        OUT_SQ_wmask <= 4'b0010;
                        OUT_SQ_data <= IN_uop.srcB << 8;
                    end
                    2: begin
                        OUT_SQ_wmask <= 4'b0100;
                        OUT_SQ_data <= IN_uop.srcB << 16;
                    end 
                    3: begin
                        OUT_SQ_wmask <= 4'b1000;
                        OUT_SQ_data <= IN_uop.srcB << 24;
                    end 
                endcase
            end

            LSU_SH: begin
                OUT_SQ_isLoad <= 0;
                OUT_SQ_valid <= 1;
                case (addr[1]) 
                    0: begin
                        OUT_SQ_wmask <= 4'b0011;
                        OUT_SQ_data <= IN_uop.srcB;
                    end
                    1: begin 
                        OUT_SQ_wmask <= 4'b1100;
                        OUT_SQ_data <= IN_uop.srcB << 16;
                    end
                endcase
            end

            LSU_SW: begin
                OUT_SQ_isLoad <= 0;
                OUT_SQ_valid <= 1;
                OUT_SQ_wmask <= 4'b1111;
                OUT_SQ_data <= IN_uop.srcB;
            end
            default: begin end
        endcase
    end
    else begin
        OUT_LB_valid <= 0;
        i0.valid <= 0;
        OUT_SQ_valid <= 0;
        OUT_SQ_isLoad <= 0;
    end
    
    // Forward or invalidate i0
    if (i0.valid && (!IN_invalidate || $signed(i0.sqN - IN_invalidateSqN) <= 0)) begin
        i1 <= i0;
    end
    else begin
        i1.valid <= 0;
    end
    
    if (i1.valid && (!IN_invalidate || $signed(i1.sqN - IN_invalidateSqN) <= 0)) begin
        
        if (IN_LB_mispred) begin
            OUT_branchProv.taken <= 1;
            OUT_branchProv.dstPC <= (i1.pc + 4);
            OUT_branchProv.sqN <= (i1.sqN);
            OUT_branchProv.loadSqN <= i1.loadSqN;
            OUT_branchProv.storeSqN <= i1.storeSqN;
        end
        else
            OUT_branchProv.taken <= 0;
            
        i2 <= i1;
    end
    else begin
        i2.valid <= 0;
        OUT_branchProv.taken <= 0;
    end
    

    if (i2.valid && (!IN_invalidate || $signed(i2.sqN - IN_invalidateSqN) <= 0)) begin
        OUT_uop.tagDst <= i2.tagDst;
        OUT_uop.nmDst <= i2.nmDst;
        OUT_uop.sqN <= i2.sqN;
        OUT_valid <= 1;

        case (i2.opcode)
            LSU_LBU,
            LSU_LB: begin
                reg[7:0] temp;
                case (i2.byteIndex)
                    0: temp = IN_readData[7:0];
                    1: temp = IN_readData[15:8];
                    2: temp = IN_readData[23:16];
                    3: temp = IN_readData[31:24];
                endcase
                OUT_uop.result <= (i2.opcode == LSU_LBU) ? {24'b0, temp} : {{24{temp[7]}}, temp};
            end

            LSU_LHU,
            LSU_LH: begin
                reg[15:0] temp;
                case (i2.byteIndex[1])
                    0: temp = IN_readData[15:0];
                    1: temp = IN_readData[31:16];
                endcase
                OUT_uop.result <= (i2.opcode == LSU_LBU) ? {16'b0, temp} : {{16{temp[15]}}, temp};
            end

            LSU_LW: OUT_uop.result <= IN_readData;
            default: OUT_uop.result <= 32'bx;
        endcase
    end
    else
        OUT_valid <= 0;
end


endmodule
