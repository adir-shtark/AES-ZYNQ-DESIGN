`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/23/2025 06:30:17 PM
// Design Name: 
// Module Name: mix_column
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module mix_column (
    input  wire [7:0] s0, s1, s2, s3,
    output wire [7:0] m0, m1, m2, m3
);

    // Multiply by 2 in GF(2^8)
    function [7:0] xtime;
        input [7:0] b;
        begin
            xtime = (b << 1) ^ (8'h1b & {8{b[7]}});
        end
    endfunction

    // Multiply by 3 in GF(2^8) = xtime(b) ^ b
    function [7:0] mul_by_3;
        input [7:0] b;
        begin
            mul_by_3 = xtime(b) ^ b;
        end
    endfunction

    assign m0 = xtime(s0) ^ mul_by_3(s1) ^ s2 ^ s3;
    assign m1 = s0 ^ xtime(s1) ^ mul_by_3(s2) ^ s3;
    assign m2 = s0 ^ s1 ^ xtime(s2) ^ mul_by_3(s3);
    assign m3 = mul_by_3(s0) ^ s1 ^ s2 ^ xtime(s3);

endmodule

