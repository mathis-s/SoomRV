module PageWalker#(parameter NUM_RQS=3)
(
    input wire clk,
    input wire rst,
    
    input PageWalk_Req IN_rqs[NUM_RQS-1:0],
    output PageWalk_Res OUT_res,
    
    input wire IN_ldStall,
    output PW_LD_UOp OUT_ldUOp,
    input PW_LD_RES_UOp IN_ldResUOp
);


reg[0:0] pageWalkIter;
reg[31:0] pageWalkAddr;
reg[1:0] rqID;

enum logic[1:0] 
{
    IDLE, WAIT_FOR_LOAD
} state;

wire[31:0] nextLookup = {IN_ldResUOp.data[29:10], pageWalkAddr[21:12], 2'b0};

reg pageFault_c;
reg isSuperPage_c;
reg[21:0] ppn_c;
reg[2:0] rwx_c;
reg[3:0] dagu_c;
always_comb begin
    reg[31:0] pte = IN_ldResUOp.data;
    isSuperPage_c = pageWalkIter;
    pageFault_c = 0;
    ppn_c = pte[31:10];
    rwx_c = 'x;
    dagu_c = 'x;
    
    // We can already do a few simple checks for
    // page faults here. Checks involving permissions
    // are done later though, as permissions might chance.
    if (!pte[0] || // not valid
        !pte[6]    // accessed not set
    ) begin
        pageFault_c = 1;
    end
    
    // misaligned super page
    if (isSuperPage_c && pte[19:10] != 0) begin
        pageFault_c = 1;
    end

    case (pte[3:1])
        default: ;
        /*inv*/ 3'b000,
        /*rfu*/ 3'b010,
        /*rfu*/ 3'b110: pageFault_c = 1;
    endcase

    if (!pageFault_c) begin
        // allow write only if dirty
        rwx_c = {pte[1], pte[2] && pte[7], pte[3]};
        dagu_c = pte[7:4];
    end
end

always_ff@(posedge clk) begin
    
    OUT_res.valid <= 0;

    if (rst) begin
        OUT_ldUOp.valid <= 0;
        state <= IDLE;
        OUT_res.busy <= 0;
    end
    else begin

        case (state)
            default: begin
                OUT_res.busy <= 0;
                for (integer i = 0; i < NUM_RQS; i=i+1) begin
                    if (IN_rqs[i].valid) begin
                        
                        state <= WAIT_FOR_LOAD;
                        pageWalkIter <= 1;
                        pageWalkAddr <= IN_rqs[i].addr;
                        rqID <= i[1:0];

                        OUT_ldUOp.valid <= 1;
                        OUT_ldUOp.addr <= {IN_rqs[i].rootPPN[19:0], IN_rqs[i].addr[31:22], 2'b0};

                        OUT_res <= 'x;
                        OUT_res.rqID <= i[1:0];
                        OUT_res.busy <= 1;
                        OUT_res.valid <= 0;
                    end
                end
            end

            WAIT_FOR_LOAD: begin
                if (OUT_ldUOp.valid) begin
                    if (!IN_ldStall) OUT_ldUOp.valid <= 0;
                end
                else if (IN_ldResUOp.valid) begin
                    // Pointer to next page
                    
                    if (IN_ldResUOp.data[3:0] == 4'b0001 && IN_ldResUOp.data[31:30] == 0 && pageWalkIter == 1 && `IS_LEGAL_ADDR(nextLookup)) begin
                        
                        OUT_ldUOp.valid <= 1;
                        OUT_ldUOp.addr <= nextLookup;

                        pageWalkIter <= 0;

                        state <= WAIT_FOR_LOAD;
                    end
                    else begin
                        // this really doesn't need a delay cycle...
                        OUT_res.busy <= 0;
                        OUT_res.valid <= 1;
                        OUT_res.isSuperPage <= isSuperPage_c;
                        OUT_res.pageFault <= pageFault_c;
                        OUT_res.ppn <= ppn_c;
                        OUT_res.vpn <= pageWalkAddr[31:12];
                        OUT_res.rwx <= rwx_c;

                        OUT_res.globl <= dagu_c[1];
                        OUT_res.user <= dagu_c[0];
                        state <= IDLE;
                    end
                end
            end
        endcase


    end
end

endmodule
