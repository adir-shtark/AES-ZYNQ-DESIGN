`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/23/2025 07:01:32 PM
// Design Name: 
// Module Name: last_round_core
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


module last_round_core (
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

    assign state_out = {
        shifted[ 0], shifted[ 1], shifted[ 2], shifted[ 3],
        shifted[ 4], shifted[ 5], shifted[ 6], shifted[ 7],
        shifted[ 8], shifted[ 9], shifted[10], shifted[11],
        shifted[12], shifted[13], shifted[14], shifted[15]
    };
endmodule

