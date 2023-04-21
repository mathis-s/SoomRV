module PageWalker#(parameter NUM_RQS=3)
(
    input wire clk,
    input wire rst,
    
    input PageWalkRq IN_rqs[NUM_RQS-1:0],
    output PageWalkRes OUT_res,
    
    input wire IN_ldStall,
    output PW_LD_UOp OUT_ldUOp,
    input PW_LD_RES_UOp IN_ldResUOp
);


reg[0:0] pageWalkIter;
reg[31:0] pageWalkAddr;

enum logic[1:0] 
{
    IDLE, WAIT_FOR_LOAD
} state;

always_ff@(posedge clk) begin
    
    OUT_res.valid <= 0;

    if (rst) begin
        OUT_ldUOp.valid <= 0;
        state <= IDLE;
    end
    else begin

        case (state)
            default: begin
                for (integer i = 0; i < NUM_RQS; i=i+1) begin
                    if (IN_rqs[i].valid) begin
                        
                        state <= WAIT_FOR_LOAD;
                        pageWalkIter <= 1;
                        pageWalkAddr <= IN_rqs[i].addr;

                        OUT_ldUOp.valid <= 1;
                        OUT_ldUOp.addr <= {IN_rqs[i].rootPPN[19:0], IN_rqs[i].addr[31:22], 2'b0};
                        OUT_res.rqID <= i[1:0];
                        OUT_res.busy <= 1;
                    end
                end
            end

            WAIT_FOR_LOAD: begin
                if (OUT_ldUOp.valid) begin
                    if (!IN_ldStall) OUT_ldUOp.valid <= 0;
                end
                else if (IN_ldResUOp.valid) begin
                    // Pointer to next page
                    reg[31:0] nextLookup = {IN_ldResUOp.data[29:10], pageWalkAddr[21:12], 2'b0};
                    if (IN_ldResUOp.data[3:0] == 4'b0001 && IN_ldResUOp.data[31:30] == 0 && pageWalkIter == 1 && `IS_LEGAL_ADDR(nextLookup)) begin
                        
                        OUT_ldUOp.valid <= 1;
                        OUT_ldUOp.addr <= nextLookup;

                        pageWalkIter <= 0;

                        state <= WAIT_FOR_LOAD;
                    end
                    else begin
                        // this really doesn't need a delay cycle...
                        OUT_res.valid <= 1;
                        OUT_res.busy <= 0;
                        OUT_res.result <= IN_ldResUOp.data;
                        OUT_res.isSuperPage <= pageWalkIter;

                        state <= IDLE;
                    end
                end
            end
        endcase


    end
end

endmodule
