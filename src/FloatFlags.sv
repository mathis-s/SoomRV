module FloatFlags#(parameter NUM_FLOAT_FLAG_UPD = 2, parameter SIZE=4)
(
    input wire clk,
    input wire rst,
    
    input FloatFlagsUpdate IN_floatFlagsUpdates[NUM_FLOAT_FLAG_UPD-1:0],
    
    input BranchProv IN_branch,
    input wire IN_writeEnable,
    input wire[4:0] IN_writeFlags,
    
    output wire[4:0] OUT_flags
);

integer i;

typedef struct
{
    enum logic[2:0] 
    {
        INVALID,
        NX,
        UF,
        OF,
        DZ,
        NV
    } setFlag;
    SqN sqN;
} updBuf[SIZE-1:0];

reg[4:0] committedFlags;

always_ff@(posedge clk) begin
    
    if (rst) begin
        committedFlags <= 0;
        for (i = 0; i < SIZE; i=i+1) begin
            committedFlags[i].setFlag = INVALID;
        end
    end
    else if (IN_writeEnable) begin
        
    end

end

endmodule
