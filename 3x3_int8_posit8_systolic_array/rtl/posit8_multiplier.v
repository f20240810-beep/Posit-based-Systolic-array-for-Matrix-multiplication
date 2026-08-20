// =============================================================================
// posit8_multiplier.v
//
// Multiplies two Posit(8,0) operands DIRECTLY on their bit patterns (via
// posit8_unpack) and produces an EXACT product in a wide signed
// fixed-point format - deliberately NOT rounded back to Posit8 here.
//
// Why: the PE accumulates several of these products (one per systolic
// step) before the result is ever read out. Rounding to Posit8 after
// every single multiply, then again after every add, would compound
// error at every step. Instead this design keeps a wide, exact
// fixed-point running sum inside the PE (see fixed_accumulator.v) and
// only rounds back to Posit8 once, at the very end (fixed_to_posit8.v).
//
// Fixed-point format of the output: signed Q(ACC_WIDTH-1-FRAC).FRAC,
// i.e. fixed_o represents the real value (fixed_o / 2^FRAC).
//
// Derivation of the exact conversion (see project notes for the full
// derivation): unpacking gives each operand as sign, k (regime, -6..6),
// and a 6-bit significand sig = 32*(1.fraction) (so sig in [32,63]).
// The product magnitude is:
//     value = (siga * sigb / 2^10) * 2^(ka+kb)
// siga*sigb is an exact 12-bit unsigned integer (max 63*63=3969), so no
// precision is lost - we just need to shift it into the accumulator's
// fixed-point frame:
//     fixed = (siga*sigb) << (ka + kb - 10 + FRAC)
// With FRAC=24 and ka,kb in [-6,6] (so ka+kb in [-12,12]), the shift
// amount (ka+kb+14) is always in [2,26] - i.e. always a LEFT shift, so
// this is always exact (no bits are ever discarded).
// =============================================================================
`timescale 1ns/1ps

module posit8_multiplier #(
    parameter ACC_WIDTH = 48,
    parameter FRAC       = 24
) (
    input  wire [7:0] posit_a,
    input  wire [7:0] posit_b,
    output wire signed [ACC_WIDTH-1:0] fixed_o
);

    wire sign_a, sign_b, zero_a, zero_b, nar_a, nar_b;
    wire signed [4:0] k_a, k_b;
    wire [5:0] sig_a, sig_b;

    posit8_unpack u_a (.posit_i(posit_a), .sign_o(sign_a), .k_o(k_a),
                        .sig_o(sig_a), .zero_o(zero_a), .nar_o(nar_a));
    posit8_unpack u_b (.posit_i(posit_b), .sign_o(sign_b), .k_o(k_b),
                        .sig_o(sig_b), .zero_o(zero_b), .nar_o(nar_b));

    wire        prod_sign = sign_a ^ sign_b;
    wire signed [6:0] k_sum = k_a + k_b;                 // range -12..12
    wire [11:0] sig_prod   = sig_a * sig_b;               // exact, <=3969

    // Shift amount to place sig_prod (Q2.10-ish exact integer) into the
    // accumulator's Q(*).FRAC frame. Always a left shift by construction
    // (see derivation above), so this is exact - no rounding here.
    wire signed [7:0] shamt = k_sum + (FRAC - 10);

    wire [ACC_WIDTH-1:0] mag_shifted = ({{(ACC_WIDTH-12){1'b0}}, sig_prod} << shamt);

    wire is_zero_prod = zero_a | zero_b | nar_a | nar_b; // NaR treated as 0 (documented limitation)

    assign fixed_o = is_zero_prod ? {ACC_WIDTH{1'b0}} :
                      (prod_sign ? (~mag_shifted + 1'b1) : mag_shifted);

endmodule
