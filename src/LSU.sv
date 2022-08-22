module LSU
(
    input wire clk,
    input wire rst,

    input wire IN_valid,
    input EX_UOp IN_uop,
    
    input wire IN_invalidate,
    input wire[5:0] IN_invalidateSqN,


    input wire[31:0] IN_MEM_readData,
    output reg[31:0] OUT_MEM_addr,
    output reg[31:0] OUT_MEM_writeData,
    output reg OUT_MEM_writeEnable,
    output reg OUT_MEM_readEnable,
    output reg[3:0] OUT_MEM_writeMask,

    output wire OUT_wbReq,

    output reg OUT_valid,
    output RES_UOp OUT_uop
);

reg iValid;
reg[5:0] iOpcode;
reg[5:0] iTagDst;
reg[4:0] iNmDst;
reg[5:0] iSqN;
reg[1:0] iByteIndex;

wire[31:0] addr = IN_uop.srcA + IN_uop.imm;

assign OUT_wbReq = iValid;


// TODO: Forward stored values from intermediate cycle
always@(posedge clk) begin
    if (rst) begin
        iValid <= 0;
    end
    else if (IN_valid && (!IN_invalidate || $signed(IN_uop.sqN - IN_invalidateSqN) <= 0)) begin

        iValid <= 1;
        iOpcode <= IN_uop.opcode;
        iTagDst <= IN_uop.tagDst;
        iNmDst <= IN_uop.nmDst;
        iSqN <= IN_uop.sqN;
        iByteIndex <= addr[1:0];
        OUT_MEM_addr <= {2'b00, addr[31:2]};

        case (IN_uop.opcode)
            LSU_LB,
            LSU_LH,
            LSU_LW,
            LSU_LBU,
            LSU_LHU: begin
                OUT_MEM_readEnable <= 1;
                OUT_MEM_writeEnable <= 0;
                iByteIndex <= addr[1:0];
            end

            LSU_SB: begin
                OUT_MEM_readEnable <= 0;
                OUT_MEM_writeEnable <= 1;
                case (addr[1:0]) 
                    0: begin
                        OUT_MEM_writeMask <= 4'b0001;
                        OUT_MEM_writeData <= IN_uop.srcB;
                    end
                    1: begin 
                        OUT_MEM_writeMask <= 4'b0010;
                        OUT_MEM_writeData <= IN_uop.srcB << 8;
                    end
                    2: begin
                        OUT_MEM_writeMask <= 4'b0100;
                        OUT_MEM_writeData <= IN_uop.srcB << 16;
                    end 
                    3: begin
                        OUT_MEM_writeMask <= 4'b1000;
                        OUT_MEM_writeData <= IN_uop.srcB << 24;
                    end 
                endcase
            end

            LSU_SH: begin
                OUT_MEM_readEnable <= 0;
                OUT_MEM_writeEnable <= 1;
                case (addr[1]) 
                    0: begin
                        OUT_MEM_writeMask <= 4'b0011;
                        OUT_MEM_writeData <= IN_uop.srcB;
                    end
                    1: begin 
                        OUT_MEM_writeMask <= 4'b1100;
                        OUT_MEM_writeData <= IN_uop.srcB << 16;
                    end
                endcase
            end

            LSU_SW: begin
                OUT_MEM_readEnable <= 0;
                OUT_MEM_writeEnable <= 1;
                OUT_MEM_writeMask <= 4'b1111;
                OUT_MEM_writeData <= IN_uop.srcB;
            end
            default: begin end
        endcase
    end
    else begin
        iValid <= 0;
        OUT_MEM_readEnable <= 0;
        OUT_MEM_writeEnable <= 0;
    end

    if (iValid && (!IN_invalidate || $signed(iSqN - IN_invalidateSqN) <= 0)) begin
        OUT_uop.tagDst <= iTagDst;
        OUT_uop.nmDst <= iNmDst;
        OUT_uop.sqN <= iSqN;
        OUT_valid <= 1;

        case (iOpcode)
            LSU_LBU,
            LSU_LB: begin
                reg[7:0] temp;
                case (iByteIndex)
                    0: temp = IN_MEM_readData[7:0];
                    1: temp = IN_MEM_readData[15:8];
                    2: temp = IN_MEM_readData[23:16];
                    3: temp = IN_MEM_readData[31:24];
                endcase
                OUT_uop.result <= (iOpcode == LSU_LBU) ? {24'b0, temp} : {{24{temp[7]}}, temp};
            end

            LSU_LHU,
            LSU_LH: begin
                reg[15:0] temp;
                case (iByteIndex[1])
                    0: temp = IN_MEM_readData[15:0];
                    1: temp = IN_MEM_readData[31:16];
                endcase
                OUT_uop.result <= (iOpcode == LSU_LBU) ? {16'b0, temp} : {{16{temp[15]}}, temp};
            end

            LSU_LW: OUT_uop.result <= IN_MEM_readData;
            default: OUT_uop.result <= 32'bx;
        endcase
    end
    else
        OUT_valid <= 0;
    

end


endmodule
