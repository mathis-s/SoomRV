 
module LZCnt
(
    input wire[31:0] in,
    output reg[5:0] out
);

integer i;

reg[1:0] s0[15:0];
reg[2:0] s1[7:0];
reg[3:0] s2[3:0];
reg[4:0] s3[1:0];

always_comb begin
    for (i = 0; i < 16; i=i+1) begin
        case (in[2*i+:2])
            2'b00: s0[15-i] = 2'b10;
            2'b01: s0[15-i] = 2'b01;
            2'b10: s0[15-i] = 2'b00;
            2'b11: s0[15-i] = 2'b00;
        endcase
    end
    
    for (i = 0; i < 8; i=i+1) begin
        
        if (s0[2*i+0][1] && s0[2*i+1][1])
            s1[i] = 3'b100;
        else if (s0[2*i][1] == 1'b0)
            s1[i] = {1'b0, s0[2*i]};
        else //if (s0[i][1] == 1'b1)
            s1[i] = {2'b01, s0[2*i+1][0]};
    end
    
    for (i = 0; i < 4; i=i+1) begin
        
        if (s1[2*i+0][2] && s1[2*i+1][2])
            s2[i] = 4'b1000;
        else if (s1[2*i][2] == 1'b0)
            s2[i] = {1'b0, s1[2*i]};
        else //if (s1[2*i][2] == 1'b1)
            s2[i] = {2'b01, s1[2*i+1][1:0]};
    end
    
    for (i = 0; i < 2; i=i+1) begin
    
        if (s2[2*i+0][3] && s2[2*i+1][3])
            s3[i] = 5'b10000;
        else if (s2[2*i][3] == 1'b0)
            s3[i] = {1'b0, s2[2*i]};
        else //if (s2[2*i][3] == 1'b1)
            s3[i] = {2'b01, s2[2*i+1][2:0]};
    end
    
    if (s3[0][4] && s3[1][4])
        out = 6'b100000;
    else if (s3[0][4] == 1'b0)
        out = {1'b0, s3[0]};
    else //if (s3[0][4] == 1'b1)
        out = {2'b01, s3[1][3:0]};
end

endmodule
