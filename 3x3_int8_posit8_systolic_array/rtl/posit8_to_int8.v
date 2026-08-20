// =============================================================================
// posit8_to_int8.v
//
// System-boundary DECODER. Converts a Posit(8,0) bit pattern back into a
// plain signed 8-bit integer ("user readable value"), rounding to the
// nearest integer (round-half-up on magnitude) and saturating to the
// int8 range [-128,127] (Posit8,0's own range, +-64, never actually
// reaches that limit, so saturation is a safety net rather than a
// commonly-hit path).
//
// This sits outside the systolic array, at the matrix-output side.
// NaR input is treated as 0 (documented limitation - see README).
// =============================================================================
`timescale 1ns/1ps

module posit8_to_int8 (
    input  wire [7:0]        posit_i,
    output reg  signed [7:0] int_o
);

    wire        sign_w, zero_w, nar_w;
    wire signed [4:0] k_w;
    wire [5:0]  sig_w; // {hidden, frac[4:0]} = value*32, i.e. true value = sig_w * 2^(k-5)

    posit8_unpack u_unpack (
        .posit_i(posit_i), .sign_o(sign_w), .k_o(k_w),
        .sig_o(sig_w), .zero_o(zero_w), .nar_o(nar_w)
    );

    reg  [15:0] mag_wide;      // sig_w scaled up, room for left or right shift
    reg  [15:0] rounded;
    reg  signed [8:0] shift_amt; // k - 5
    reg  [15:0] half;

    always @* begin
        shift_amt = k_w - 5'sd5;
        if (zero_w || nar_w) begin
            int_o = 8'sd0;
        end else if (shift_amt >= 0) begin
            // Exact - integer values, no rounding needed.
            mag_wide = ({10'b0, sig_w} << shift_amt);
            int_o = (mag_wide > 16'd127) ? 8'sd127 : mag_wide[7:0];
            if (sign_w)
                int_o = (mag_wide > 16'd128) ? -8'sd128 : -$signed({1'b0,mag_wide[7:0]});
        end else begin
            // Fractional - round to nearest (round-half-up on magnitude).
            half     = (-shift_amt > 0) ? (16'd1 << (-shift_amt - 1)) : 16'd0;
            rounded  = ({10'b0, sig_w} + half) >> (-shift_amt);
            int_o    = sign_w ? -$signed({1'b0,rounded[7:0]}) : rounded[7:0];
        end
    end

endmodule
