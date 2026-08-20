// =============================================================================
// fp16_to_int8.v
//
// Converts an FP16 value back to a plain signed 8-bit integer,
// rounding to nearest (round-half-away-from-zero, matching the same
// convention chosen for posit8_to_int8.v / fixed_to_int8.v for
// consistency across the three variants) and saturating to
// [-128,127].
// =============================================================================
`timescale 1ns/1ps

module fp16_to_int8 (
    input  wire [15:0]        fp16_i,
    output reg  signed [7:0]  int_o
);

    wire        sign_w = fp16_i[15];
    wire [4:0]  exp_f  = fp16_i[14:10];
    wire [9:0]  frac   = fp16_i[9:0];
    wire        zero_w = (exp_f == 5'd0); // FTZ: subnormal treated as zero
    wire [10:0] sig11  = {1'b1, frac};    // value = sig11 * 2^(exp-15-10)
    wire signed [5:0] exp_unbiased = {1'b0, exp_f} - 6'sd15;

    reg  [21:0] mag_wide, rounded;
    reg  signed [6:0] shift_amt; // exp_unbiased - 10
    reg  [21:0] half;

    always @* begin
        shift_amt = exp_unbiased - 6'sd10;
        if (zero_w) begin
            int_o = 8'sd0;
        end else if (shift_amt >= 0) begin
            mag_wide = ({11'b0, sig11} << shift_amt);
            if (sign_w)
                int_o = (mag_wide > 22'd128) ? -8'sd128 : -$signed({1'b0, mag_wide[7:0]});
            else
                int_o = (mag_wide > 22'd127) ? 8'sd127 : mag_wide[7:0];
        end else begin
            half     = (-shift_amt > 0) ? (22'd1 << (-shift_amt - 1)) : 22'd0;
            rounded  = ({11'b0, sig11} + half) >> (-shift_amt);
            if (sign_w)
                int_o = (rounded > 22'd128) ? -8'sd128 : -$signed({1'b0, rounded[7:0]});
            else
                int_o = (rounded > 22'd127) ? 8'sd127 : rounded[7:0];
        end
    end

endmodule
