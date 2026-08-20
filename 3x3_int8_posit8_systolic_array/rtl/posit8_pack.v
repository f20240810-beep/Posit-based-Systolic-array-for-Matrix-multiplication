// =============================================================================
// posit8_pack.v
//
// Encodes a normalized {sign, k, significand} value into the nearest
// Posit(8,0) bit pattern. This is the ONLY place in the whole design that
// performs rounding - every other module (multiplier, accumulator) works
// with exact values, and only converts to Posit8 once, here, at the
// system/PE output boundary. This matches a "wide exact accumulator"
// architecture: precision is preserved internally, and Posit8's coarse
// quantization is applied exactly once at the very end.
//
// Inputs:
//   sign_i   : sign of the value (ignored if zero_i)
//   k_i      : regime value, WIDE signed input (deliberately not clamped
//              by the caller) - this module clamps/saturates internally,
//              so it can be fed directly from producers whose natural
//              exponent range exceeds Posit(8,0)'s +-6 (e.g. a wide
//              fixed-point accumulator).
//   sig_i    : 12-bit normalized significand, format 1.fffffffffff
//              (bit[11] = implicit hidden 1, bits[10:0] = 11 fraction
//              bits, left-justified / zero-padded by the caller if it
//              has fewer real bits).
//   sticky_i : OR of any additional (lower-precision) bits the caller
//              knows about that are NOT represented in sig_i[10:0]. Lets
//              wide producers (e.g. the fixed-point-to-posit converter)
//              feed in an exact sticky bit instead of losing information.
//   zero_i   : true value is exactly zero.
//
// Output:
//   posit_o  : nearest Posit(8,0) encoding, round-to-nearest-even,
//              saturating to +-maxpos (64) on overflow, flushing to 0 on
//              underflow below representable range (documented
//              simplification - see README).
// =============================================================================
`timescale 1ns/1ps

module posit8_pack (
    input  wire        sign_i,
    input  wire signed [7:0] k_i,
    input  wire [11:0] sig_i,
    input  wire        sticky_i,
    input  wire        zero_i,
    output reg  [7:0]  posit_o
);

    // Regime template lookup: for each valid (clamped) k in [-6,6], the
    // fixed high bits of the 7-bit magnitude field (regime+terminator)
    // and how many low bits are available for the fraction.
    function [9:0] regime_lut; // {frac_width[2:0], regime_tmpl[6:0]}
        input signed [3:0] k;
        begin
            case (k)
                -4'sd6:  regime_lut = {3'd0, 7'b0000001};
                -4'sd5:  regime_lut = {3'd1, 7'b0000010};
                -4'sd4:  regime_lut = {3'd2, 7'b0000100};
                -4'sd3:  regime_lut = {3'd3, 7'b0001000};
                -4'sd2:  regime_lut = {3'd4, 7'b0010000};
                -4'sd1:  regime_lut = {3'd5, 7'b0100000};
                 4'sd0:  regime_lut = {3'd5, 7'b1000000};
                 4'sd1:  regime_lut = {3'd4, 7'b1100000};
                 4'sd2:  regime_lut = {3'd3, 7'b1110000};
                 4'sd3:  regime_lut = {3'd2, 7'b1111000};
                 4'sd4:  regime_lut = {3'd1, 7'b1111100};
                 4'sd5:  regime_lut = {3'd0, 7'b1111110};
                 4'sd6:  regime_lut = {3'd0, 7'b1111111};
                default: regime_lut = {3'd0, 7'b1000000};
            endcase
        end
    endfunction

    reg signed [7:0] k_clamped;
    reg              sat_hi, flush_zero;
    reg [2:0]        frac_width;
    reg [6:0]        regime_tmpl;
    reg [4:0]        frac_out;      // up to 5 fraction bits, right-justified
    reg              round_bit, sticky, lsb_for_tie, round_up;
    reg [5:0]        frac_rounded;  // 1 extra bit to catch carry-out
    reg signed [3:0] k_final;
    reg [6:0]        mag7;
    reg [7:0]        mag8_unsigned;

    always @* begin
        // ---- Step 1: clamp/saturate k into representable range ----
        sat_hi      = (k_i > 8'sd6);
        flush_zero  = (k_i < -8'sd6);
        k_clamped   = sat_hi ? 8'sd6 : (flush_zero ? -8'sd6 : k_i);

        {frac_width, regime_tmpl} = regime_lut(k_clamped[3:0]);

        // ---- Step 2: extract fraction / round / sticky bits from sig_i ----
        // sig_i[10:0] holds 11 fraction bits, most-significant first.
        // We keep the top `frac_width` of them; bit right after that is
        // the round bit; everything below (plus caller's sticky_i) is OR'd
        // into sticky.
        case (frac_width)
            3'd0: begin
                frac_out    = 5'd0;
                round_bit   = sig_i[10];
                sticky      = (|sig_i[9:0]) | sticky_i;
                // No fraction field exists at this regime length, so
                // "even" is determined by the LSB of the regime pattern
                // itself (the full 7-bit magnitude IS the candidate when
                // we don't round up). This is NOT always 0 - e.g. k=-6's
                // pattern 0000001 has LSB=1 (odd), while k=+5's pattern
                // 1111110 has LSB=0 (even). Using a fixed 0 here was a
                // bug: it silently broke exact ties at k=-6 (and would
                // have at k=+6, were that path not already forced to
                // saturate regardless).
                lsb_for_tie = regime_tmpl[0];
            end
            3'd1: begin
                frac_out    = {4'd0, sig_i[10]};
                round_bit   = sig_i[9];
                sticky      = (|sig_i[8:0]) | sticky_i;
                lsb_for_tie = sig_i[10];
            end
            3'd2: begin
                frac_out    = {3'd0, sig_i[10:9]};
                round_bit   = sig_i[8];
                sticky      = (|sig_i[7:0]) | sticky_i;
                lsb_for_tie = sig_i[9];
            end
            3'd3: begin
                frac_out    = {2'd0, sig_i[10:8]};
                round_bit   = sig_i[7];
                sticky      = (|sig_i[6:0]) | sticky_i;
                lsb_for_tie = sig_i[8];
            end
            3'd4: begin
                frac_out    = {1'd0, sig_i[10:7]};
                round_bit   = sig_i[6];
                sticky      = (|sig_i[5:0]) | sticky_i;
                lsb_for_tie = sig_i[7];
            end
            3'd5: begin
                frac_out    = sig_i[10:6];
                round_bit   = sig_i[5];
                sticky      = (|sig_i[4:0]) | sticky_i;
                lsb_for_tie = sig_i[6];
            end
            default: begin
                frac_out    = 5'd0;
                round_bit   = 1'b0;
                sticky      = sticky_i;
                lsb_for_tie = 1'b0;
            end
        endcase

        // ---- Step 3: round to nearest, ties to even ----
        round_up     = round_bit & (sticky | lsb_for_tie);
        frac_rounded = {1'b0, frac_out} + round_up; // 6 bits, frac_out's unused
                                                      // upper bits are always 0
        // ---- Step 4: handle mantissa carry-out (bumps k by 1) ----
        // Overflow happens when the rounded fraction no longer fits in the
        // *actual* frac_width-bit field for this regime - NOT always bit[5].
        // e.g. with frac_width=3 the field is only 3 bits wide, so a carry
        // shows up in frac_rounded[3], not frac_rounded[5]. Using a fixed
        // bit[5] check here was a bug: it silently missed carries whenever
        // frac_width < 5 (i.e. for every k with |k| >= 1), pointing the
        // regime to the wrong bucket entirely for values whose fraction was
        // close to the next power of two. Checking the width-dependent bit
        // fixes it.
        if (frac_rounded[frac_width]) begin
            // Fraction overflowed (e.g. 1.11111 rounded up to 10.00000).
            // New fraction is exactly 0 regardless of the new k's width.
            k_final = (k_clamped == 4'sd6) ? 4'sd6 : (k_clamped[3:0] + 4'sd1);
            if (k_clamped == 4'sd6)
                mag7 = 7'b1111111; // already saturated at maxpos
            else begin
                {frac_width, regime_tmpl} = regime_lut(k_final);
                mag7 = regime_tmpl; // frac bits are 0, template already has them zeroed
            end
        end else begin
            // Place the rounded fraction bits into the low `frac_width` bits
            // of the template (which are already zero there).
            case (frac_width)
                3'd0: mag7 = regime_tmpl;
                3'd1: mag7 = regime_tmpl | {6'b0, frac_rounded[0]};
                3'd2: mag7 = regime_tmpl | {5'b0, frac_rounded[1:0]};
                3'd3: mag7 = regime_tmpl | {4'b0, frac_rounded[2:0]};
                3'd4: mag7 = regime_tmpl | {3'b0, frac_rounded[3:0]};
                3'd5: mag7 = regime_tmpl | {2'b0, frac_rounded[4:0]};
                default: mag7 = regime_tmpl;
            endcase
        end

        // ---- Step 5: assemble result ----
        if (zero_i)
            posit_o = 8'b0;
        else if (flush_zero)
            posit_o = 8'b0; // underflow below minPos region -> flush to zero
        else if (sat_hi)
            posit_o = sign_i ? 8'b10000001 : 8'b01111111; // -maxpos / +maxpos
        else begin
            mag8_unsigned = {1'b0, mag7};
            posit_o = sign_i ? (~mag8_unsigned + 8'd1) : mag8_unsigned;
        end
    end

endmodule
