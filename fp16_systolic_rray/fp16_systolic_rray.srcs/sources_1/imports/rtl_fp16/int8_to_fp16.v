// =============================================================================
// int8_to_fp16.v
//
// Converts a plain signed 8-bit integer to FP16. Unlike
// int8_to_posit8.v, this conversion is ALWAYS EXACT: FP16's 11-bit
// significand (1 hidden + 10 fraction) can represent any integer up
// to 2048 exactly, and int8's range [-128,127] is far inside that -
// so there is no rounding logic here at all, just a leading-one
// detector and a direct field assembly. This asymmetry (FP16's input
// conversion is exact where Posit8's is not) is itself a fair,
// reportable difference between the formats for the benchmark: it
// stems directly from FP16 spending more bits on precision than
// Posit8 does at magnitudes in the +-128 range, where Posit8's
// tapered precision has already started trading accuracy for range.
// =============================================================================
`timescale 1ns/1ps

module int8_to_fp16 (
    input  wire signed [7:0] int_i,
    output wire [15:0]       fp16_o
);

    wire        sign_w = int_i[7];
    wire signed [8:0] ext_in = {int_i[7], int_i};
    wire signed [8:0] mag9_s = ext_in[8] ? -ext_in : ext_in;
    wire [8:0]        mag9   = mag9_s[8:0];
    wire               is_zero = (mag9 == 9'd0);

    reg [3:0] msb_pos;
    reg       found;
    integer   idx;
    always @* begin
        msb_pos = 4'd0;
        found   = 1'b0;
        for (idx = 8; idx >= 0; idx = idx - 1) begin
            if (!found && mag9[idx]) begin
                msb_pos = idx[3:0];
                found   = 1'b1;
            end
        end
    end

    // Left-justify so the leading one sits at bit8, giving up to 8
    // fraction bits below it - well within FP16's 10-bit field, so
    // this is always an exact (zero-padded) placement.
    wire [8:0] shifted = mag9 << (4'd8 - msb_pos);
    wire [9:0] frac10  = {shifted[7:0], 2'b00};

    wire [4:0] exp5_biased = {1'b0, msb_pos} + 5'd15;

    assign fp16_o = is_zero ? 16'b0 : {sign_w, exp5_biased, frac10};

endmodule
