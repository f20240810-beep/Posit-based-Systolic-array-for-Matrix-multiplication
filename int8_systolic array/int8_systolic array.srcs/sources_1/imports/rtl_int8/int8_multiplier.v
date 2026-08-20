// =============================================================================
// int8_multiplier.v
//
// Multiplies two signed 8-bit fixed-point (plain two's complement)
// operands. Unlike posit8_multiplier.v, there is no bit-pattern
// decoding step - a fixed-point multiply is just a multiply. The
// result is exact (16 bits is always enough for an 8x8 signed
// product), sign-extended to ACC_WIDTH so it can feed the SAME
// fixed_accumulator.v module used by the Posit8 PE - by design, this
// is the only difference in the datapath the accumulator/control
// microarchitecture is 100% shared across the Posit8 and INT8
// variants, isolating "numeric format" as the sole independent
// variable for the benchmark comparison.
// =============================================================================
`timescale 1ns/1ps

module int8_multiplier #(
    parameter ACC_WIDTH = 32
) (
    input  wire signed [7:0] a,
    input  wire signed [7:0] b,
    output wire signed [ACC_WIDTH-1:0] fixed_o
);

    wire signed [15:0] product = a * b; // exact, no rounding possible/needed

    assign fixed_o = {{(ACC_WIDTH-16){product[15]}}, product}; // sign-extend

endmodule
