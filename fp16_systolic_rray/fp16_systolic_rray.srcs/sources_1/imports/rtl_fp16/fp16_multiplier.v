// =============================================================================
// fp16_multiplier.v
//
// Multiplies two IEEE-754 binary16 (FP16) operands and produces an
// EXACT IEEE-754 binary32 (FP32) product - no rounding at all. This
// works because an FP16 significand is only 11 bits (1 hidden + 10
// fraction), so the exact product of two of them needs at most 22
// bits - which fits comfortably inside FP32's 24-bit significand.
// This is exactly why real mixed-precision hardware (e.g. NVIDIA
// Tensor Cores) multiplies in FP16 and accumulates in FP32: the
// multiply is free of rounding error by construction, so all of
// FP16 matmul's numerical error comes from the FINAL FP32->FP16
// rounding at read-out (fp32_to_fp16.v), not from the per-term
// products - unlike Posit8/INT8, where the entire pipeline (aside
// from final read-out) is separately exact by design regardless of
// intermediate magnitude.
//
// Documented simplification (consistent with Posit8's NaR handling):
// subnormal FP16 inputs are flushed to zero (FTZ), and Inf/NaN
// encodings are not specially propagated - out of scope for this
// systolic-array comparison, matching the same scoping decision made
// for Posit8's NaR.
// =============================================================================
`timescale 1ns/1ps

module fp16_multiplier (
    input  wire [15:0] a,
    input  wire [15:0] b,
    output wire [31:0] fp32_o
);

    wire        sign_a = a[15];
    wire [4:0]  exp_a  = a[14:10];
    wire [9:0]  frac_a = a[9:0];
    wire        zero_a = (exp_a == 5'd0); // FTZ: subnormal treated as zero too
    wire [10:0] sig_a  = {1'b1, frac_a};  // 1.frac * 1024, in [1024,2047]

    wire        sign_b = b[15];
    wire [4:0]  exp_b  = b[14:10];
    wire [9:0]  frac_b = b[9:0];
    wire        zero_b = (exp_b == 5'd0);
    wire [10:0] sig_b  = {1'b1, frac_b};

    wire        sign_p = sign_a ^ sign_b;
    wire signed [6:0] exp_sum = $signed({2'b0, exp_a}) - 5'sd15 + $signed({2'b0, exp_b}) - 5'sd15; // unbiased sum

    wire [21:0] sig_prod = sig_a * sig_b; // exact, 2^20 .. just under 2^22

    // Leading one is at bit 21 or bit 20 (only two possibilities, given
    // both operands are in [1024,2047)).
    wire        norm_hi = sig_prod[21];
    wire signed [7:0] fp32_exp_unbiased = norm_hi ? (exp_sum + 8'sd1) : exp_sum;

    // Left-justify the 22-bit product's fractional part into FP32's
    // 23-bit fraction field (exact - always <=21 real bits, so this is
    // zero-padded, never truncated).
    wire [22:0] fp32_frac = norm_hi ? {sig_prod[20:0], 2'b00} : {sig_prod[19:0], 3'b000};

    wire is_zero = zero_a | zero_b;

    wire [7:0] fp32_exp_biased = fp32_exp_unbiased[7:0] + 8'd127;

    assign fp32_o = is_zero ? 32'b0 : {sign_p, fp32_exp_biased, fp32_frac};

endmodule
