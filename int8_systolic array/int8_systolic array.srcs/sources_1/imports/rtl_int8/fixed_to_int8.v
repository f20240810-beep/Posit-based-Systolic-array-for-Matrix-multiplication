// =============================================================================
// fixed_to_int8.v
//
// Converts the wide, EXACT integer accumulator value back down to a
// saturated signed 8-bit result. Unlike fixed_to_posit8.v (which must
// round a fractional fixed-point value) or fp32_to_fp16.v (which must
// round a floating mantissa), integer accumulation is always exact -
// there is no fractional information to round away. The only thing
// this stage does is CLIP values that overflow the INT8 range
// [-128,127], which is the direct fixed-point analog of Posit8's
// saturate-to-maxpos behavior (and is exactly what real INT8 GEMM
// accelerators do when requantizing an INT32 accumulator back to
// INT8).
// =============================================================================
`timescale 1ns/1ps

module fixed_to_int8 #(
    parameter ACC_WIDTH = 32
) (
    input  wire signed [ACC_WIDTH-1:0] acc_i,
    output wire signed [7:0]           int8_o
);

    localparam signed [ACC_WIDTH-1:0] INT8_MAX = 127;
    localparam signed [ACC_WIDTH-1:0] INT8_MIN = -128;

    wire overflow_pos = (acc_i > INT8_MAX);
    wire overflow_neg = (acc_i < INT8_MIN);

    assign int8_o = overflow_pos ? 8'sd127 :
                     overflow_neg ? -8'sd128 :
                     acc_i[7:0];

endmodule
