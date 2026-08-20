// =============================================================================
// fp32_adder.v
//
// Standard IEEE-754 binary32 adder: unpack both operands, align the
// smaller-magnitude one to the larger one's exponent (tracking guard
// and sticky bits for correct rounding), add or subtract significands
// depending on sign, renormalize (shift right on a same-sign carry-out,
// or shift left on cross-sign cancellation), and round to nearest-even.
//
// This is the ONLY place rounding happens in the FP16 datapath's
// accumulation path (mirroring Posit8's "round exactly once" design):
// fp16_multiplier.v is exact, this adder rounds once per accumulate
// step (as real FP32 accumulation genuinely does - unlike Posit8/INT8,
// FP32 accumulation is not bit-exact across multiple adds, which is a
// real, reportable difference between the formats), and
// fp32_to_fp16.v rounds once more at final read-out.
//
// Documented simplifications (consistent with the rest of the
// project): subnormal inputs are treated as zero (FTZ); Inf/NaN
// encodings are not specially propagated; on exact cancellation
// (a + (-a)) the result's sign follows the larger-magnitude operand
// rather than IEEE's stricter +0 rule - immaterial to magnitude
// accuracy, documented here for completeness.
// =============================================================================
`timescale 1ns/1ps

module fp32_adder (
    input  wire [31:0] a,
    input  wire [31:0] b,
    output reg  [31:0] sum
);

    // ---- Unpack ----
    wire        signA = a[31];
    wire [7:0]  expA_f = a[30:23];
    wire        zeroA = (expA_f == 8'd0);
    wire [23:0] sigA  = {1'b1, a[22:0]};
    wire signed [9:0] expA = {2'b0, expA_f} - 10'sd127;

    wire        signB = b[31];
    wire [7:0]  expB_f = b[30:23];
    wire        zeroB = (expB_f == 8'd0);
    wire [23:0] sigB  = {1'b1, b[22:0]};
    wire signed [9:0] expB = {2'b0, expB_f} - 10'sd127;

    // ---- Determine which operand has the larger magnitude ----
    wire a_ge_b = (expA > expB) || (expA == expB && sigA >= sigB);

    wire        bigSign   = a_ge_b ? signA : signB;
    wire signed [9:0] bigExp = a_ge_b ? expA : expB;
    wire [23:0] bigSig    = a_ge_b ? sigA  : sigB;

    wire        smallSign = a_ge_b ? signB : signA;
    wire signed [9:0] smallExp = a_ge_b ? expB : expA;
    wire [23:0] smallSig  = a_ge_b ? sigB  : sigA;

    wire [9:0] exp_diff_u = bigExp - smallExp; // >=0 by construction

    // ---- Align: shift the smaller operand right, tracking guard+sticky ----
    // 3 extra low bits (round/sticky tracking) appended to every
    // significand for the whole pipeline, matching the same
    // guard/round/sticky technique used in posit8_pack.v.
    wire [26:0] bigSig_ext   = {bigSig, 3'b000};
    wire [26:0] smallSig_ext = {smallSig, 3'b000};

    localparam PAD = 32;
    wire [26+PAD:0] wide_small = {smallSig_ext, {PAD{1'b0}}};
    wire [9:0] shamt = (exp_diff_u > (26+PAD)) ? (26+PAD) : exp_diff_u;
    wire [26+PAD:0] shifted_wide = wide_small >> shamt;

    wire [26:0] aligned_ext = shifted_wide[26+PAD -: 27];
    wire        shift_lost_bits = |shifted_wide[PAD-1:0];
    wire        shift_overflow_sticky = (exp_diff_u > (26+PAD)) && (smallSig != 24'b0);
    wire        sticky_total = shift_lost_bits | shift_overflow_sticky;

    wire same_sign = (bigSign == smallSign);

    // ---- Same sign: add ----
    wire [27:0] sum28 = {1'b0, bigSig_ext} + {1'b0, aligned_ext};
    wire signed [9:0] add_exp   = sum28[27] ? (bigExp + 10'sd1) : bigExp;
    wire [26:0]       add_ext27 = sum28[27] ? sum28[27:1] : sum28[26:0];
    wire              add_sticky_extra = sticky_total | (sum28[27] & sum28[0]);

    // ---- Different sign: subtract (bigSig_ext/aligned_ext - already
    // ordered so big >= small in true magnitude) ----
    wire [27:0] big_full28   = {bigSig_ext, 1'b0};
    wire [27:0] small_full28 = {aligned_ext, sticky_total};
    wire [28:0] diff29_raw   = {1'b0, big_full28} - {1'b0, small_full28};
    // Defensive clamp: the sticky-as-a-bit approximation can, in a rare
    // exact-equality-plus-sticky edge case, make the subtrahend look
    // very slightly larger than the minuend - clamp instead of wrapping
    // negative (affects at most 1 ULP of an intermediate, invisible
    // after the final FP16 rounding).
    wire [27:0] diff28 = diff29_raw[28] ? 28'b0 : diff29_raw[27:0];

    // Leading-one detector for renormalizing after cancellation.
    reg [4:0] msb_pos;
    reg       found;
    integer   idx;
    always @* begin
        msb_pos = 5'd0;
        found   = 1'b0;
        for (idx = 27; idx >= 0; idx = idx - 1) begin
            if (!found && diff28[idx]) begin
                msb_pos = idx[4:0];
                found   = 1'b1;
            end
        end
    end

    wire        sub_is_zero  = ~found;
    wire [4:0]  sub_shift    = 5'd27 - msb_pos; // 0 when no cancellation occurred
    wire [27:0] sub_shifted  = diff28 << sub_shift;
    wire signed [9:0] sub_exp   = bigExp - {5'b0, sub_shift};
    wire [26:0]       sub_ext27 = sub_shifted[27:1];

    // ---- Select add vs subtract result ----
    wire        result_sign;
    wire signed [9:0] result_exp;
    wire [26:0]       result_ext27;
    wire              extra_sticky;
    wire              is_exact_zero;

    assign result_sign   = bigSign; // documented simplification (see header)
    assign result_exp    = same_sign ? add_exp  : sub_exp;
    assign result_ext27  = same_sign ? add_ext27 : sub_ext27;
    assign extra_sticky  = same_sign ? add_sticky_extra : sub_shifted[0];
    assign is_exact_zero = (~same_sign) && sub_is_zero;

    // ---- Round to nearest, ties to even ----
    wire [23:0] pre_sig24  = result_ext27[26:3];
    wire        round_bit  = result_ext27[2];
    wire        sticky_lo  = |result_ext27[1:0];
    wire        final_sticky = sticky_lo | extra_sticky;
    wire        round_up   = round_bit & (final_sticky | pre_sig24[0]);

    wire [24:0] rounded25 = {1'b0, pre_sig24} + round_up;

    wire signed [9:0] final_exp_pre = rounded25[24] ? (result_exp + 10'sd1) : result_exp;
    wire [22:0]       final_frac    = rounded25[24] ? 23'b0 : rounded25[22:0];

    // ---- Exponent range clamp (documented simplification: saturate on
    // overflow, flush to zero on underflow - see header) ----
    wire ovf = (final_exp_pre > 10'sd127);
    wire unf = (final_exp_pre < -10'sd126);

    wire [7:0] final_exp_biased = ovf ? 8'd254 : final_exp_pre[7:0] + 8'd127;

    always @* begin
        if (zeroA)
            sum = b;
        else if (zeroB)
            sum = a;
        else if (is_exact_zero)
            sum = 32'b0;
        else if (unf)
            sum = 32'b0;
        else
            sum = {result_sign, final_exp_biased, final_frac};
    end

endmodule
