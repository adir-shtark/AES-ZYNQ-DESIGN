`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/23/2025 06:17:15 PM
// Design Name: 
// Module Name: aes_round_core
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


module aes_round_core (
    input  wire [127:0] state_in,
    output wire [127:0] state_out
);
    wire [7:0] sbox_out [15:0];
    wire [7:0] shifted [15:0];
    wire [7:0] mixed [15:0];

    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : sbox_stage
            sbox sbox_inst (
                .in(state_in[127 - i*8 -: 8]),
                .out(sbox_out[i])
            );
        end
    endgenerate

    // ShiftRows: positions after SubBytes
    assign shifted[ 0] = sbox_out[ 0];
    assign shifted[ 1] = sbox_out[ 5];
    assign shifted[ 2] = sbox_out[10];
    assign shifted[ 3] = sbox_out[15];

    assign shifted[ 4] = sbox_out[ 4];
    assign shifted[ 5] = sbox_out[ 9];
    assign shifted[ 6] = sbox_out[14];
    assign shifted[ 7] = sbox_out[ 3];

    assign shifted[ 8] = sbox_out[ 8];
    assign shifted[ 9] = sbox_out[13];
    assign shifted[10] = sbox_out[ 2];
    assign shifted[11] = sbox_out[ 7];

    assign shifted[12] = sbox_out[12];
    assign shifted[13] = sbox_out[ 1];
    assign shifted[14] = sbox_out[ 6];
    assign shifted[15] = sbox_out[11];

    // MixColumns (column by column)
    genvar c;
    generate
        for (c = 0; c < 4; c = c + 1) begin : mix_columns
            mix_column mix (
                .s0(shifted[c*4 + 0]),
                .s1(shifted[c*4 + 1]),
                .s2(shifted[c*4 + 2]),
                .s3(shifted[c*4 + 3]),
                .m0(mixed[c*4 + 0]),
                .m1(mixed[c*4 + 1]),
                .m2(mixed[c*4 + 2]),
                .m3(mixed[c*4 + 3])
            );
        end
    endgenerate

    assign state_out = {
        mixed[ 0], mixed[ 1], mixed[ 2], mixed[ 3],
        mixed[ 4], mixed[ 5], mixed[ 6], mixed[ 7],
        mixed[ 8], mixed[ 9], mixed[10], mixed[11],
        mixed[12], mixed[13], mixed[14], mixed[15]
    };
endmodule

