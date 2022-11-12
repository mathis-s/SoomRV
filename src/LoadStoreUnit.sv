module LoadStoreUnit
(
    input wire clk,
    input wire rst,
    input BranchProv IN_branch,
    
    input AGU_UOp IN_uopLd,
    input ST_UOp IN_uopSt,
    
    
    output reg OUT_MEM_re,
    output reg[29:0] OUT_MEM_readAddr,
    input wire[31:0] IN_MEM_readData,
    
    output reg OUT_MEM_we,
    output reg[29:0] OUT_MEM_writeAddr,
    output reg[31:0] OUT_MEM_writeData,
    output reg[3:0] OUT_MEM_wm,
    
    // Forwarded data from store queue
    input wire[3:0] IN_SQ_lookupMask,
    input wire[31:0] IN_SQ_lookupData,
    
    // CSRs can share most ports with regular memory except these
    input wire[31:0] IN_CSR_data,
    output reg OUT_CSR_we,
    
    output RES_UOp OUT_uopLd,
    
    output wire OUT_loadFwdValid,
    output Tag OUT_loadFwdTag
);

integer i;
integer j;

AGU_UOp uopLd_0;
AGU_UOp uopLd_1;

assign OUT_loadFwdValid = uopLd_0.valid || (IN_uopLd.valid && IN_SQ_lookupMask == 4'b1111);
assign OUT_loadFwdTag = uopLd_0.valid ? uopLd_0.tagDst : IN_uopLd.tagDst;

reg isCSRread_1;

always_comb begin
    
    OUT_MEM_readAddr = IN_uopLd.addr[31:2];
    OUT_MEM_writeAddr = IN_uopSt.addr[31:2];
    OUT_MEM_writeData = IN_uopSt.data;
    OUT_MEM_wm = IN_uopSt.wmask;
        
    // Load
    if (IN_uopLd.valid && (!IN_branch.taken || $signed(IN_uopLd.sqN - IN_branch.sqN) <= 0) && IN_SQ_lookupMask != 4'b1111) begin
        OUT_MEM_re = 0;
    end
    else OUT_MEM_re = 1;
    
    // Store
    if (IN_uopSt.valid) begin
        
        if (IN_uopSt.addr[31:24] == 8'hFF) begin
            OUT_MEM_we = 1;
            OUT_CSR_we = 0;
        end
        else begin
            OUT_MEM_we = 0;
            OUT_CSR_we = 1;
        end
    end
    else begin
        OUT_MEM_we = 1;
        OUT_CSR_we = 1;
    end
end

always_comb begin
    reg[31:0] result = 32'bx;
    reg[31:0] data;
    data[31:24] = uopLd_1.wmask[3] ? uopLd_1.data[31:24] : 
        (isCSRread_1 ?  IN_CSR_data[31:24] : IN_MEM_readData[31:24]);
    data[23:16] = uopLd_1.wmask[2] ? uopLd_1.data[23:16] : 
        (isCSRread_1 ? IN_CSR_data[23:16] : IN_MEM_readData[23:16]);
    data[15:8] = uopLd_1.wmask[1] ? uopLd_1.data[15:8] : 
        (isCSRread_1 ? IN_CSR_data[15:8] : IN_MEM_readData[15:8]);
    data[7:0] = uopLd_1.wmask[0] ? uopLd_1.data[7:0] : 
        (isCSRread_1 ? IN_CSR_data[7:0] : IN_MEM_readData[7:0]);
    
    case (uopLd_1.size)
        
        0: begin
            case (uopLd_1.shamt)
                0: result[7:0] = data[7:0];
                1: result[7:0] = data[15:8];
                2: result[7:0] = data[23:16];
                3: result[7:0] = data[31:24];
            endcase
            
            result[31:8] = {24{uopLd_1.signExtend ? result[7] : 1'b0}};
        end
        
        1: begin
            case (uopLd_1.shamt)
                default: result[15:0] = data[15:0];
                2: result[15:0] = data[31:16];
            endcase
            
            result[31:16] = {16{uopLd_1.signExtend ? result[15] : 1'b0}};
        end
        
        default: result = data;
    endcase

    OUT_uopLd.result = result;
    OUT_uopLd.tagDst = uopLd_1.tagDst;
    OUT_uopLd.nmDst = /*uopLd_1.exception ? uopLd_1.addr[25:20] : */uopLd_1.nmDst;
    OUT_uopLd.sqN = uopLd_1.sqN;
    OUT_uopLd.pc = uopLd_1.pc;
    OUT_uopLd.valid = uopLd_1.valid;
    OUT_uopLd.flags = uopLd_1.exception ? FLAGS_EXCEPT : FLAGS_NONE;
    OUT_uopLd.compressed = uopLd_1.compressed;//uopLd_1.addr[18:11];
end

always_ff@(posedge clk) begin
    
    if (rst) begin
        uopLd_0.valid <= 0;
        uopLd_1.valid <= 0;
    end
    else begin
        uopLd_0.valid <= 0;
        uopLd_1.valid <= 0;
        
        if (uopLd_0.valid && (!IN_branch.taken || $signed(uopLd_0.sqN - IN_branch.sqN) <= 0)) begin
            uopLd_1 <= uopLd_0;
            isCSRread_1 <= uopLd_0.addr[31:24] == 8'hFF;
        end
        
        if (IN_uopLd.valid && (!IN_branch.taken || $signed(IN_uopLd.sqN - IN_branch.sqN) <= 0)) begin
            
            // Loads that are entirely forwarded from the store queue can be written back one cycle earlier.
            if (IN_SQ_lookupMask == 4'b1111 && !(uopLd_0.valid && (!IN_branch.taken || $signed(uopLd_0.sqN - IN_branch.sqN) <= 0))) begin
                uopLd_1 <= IN_uopLd;
                uopLd_1.wmask <= IN_SQ_lookupMask;
                uopLd_1.data <= IN_SQ_lookupData;
            end
            else begin
                uopLd_0 <= IN_uopLd;
                uopLd_0.wmask <= IN_SQ_lookupMask;
                uopLd_0.data <= IN_SQ_lookupData;
            end
        end
    end

end

endmodule
