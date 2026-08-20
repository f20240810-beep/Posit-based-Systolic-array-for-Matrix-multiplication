// =============================================================================
// int8_to_posit8.v
//
// System-boundary ENCODER. Converts a plain signed 8-bit integer (the
// "user readable value") into its nearest Posit(8,0) representation.
// This sits outside the systolic array, at the matrix-input side.
//
// Method: take the absolute value, find the position of its leading '1'
// bit (a small priority encoder), which directly gives the posit regime
// value k (an integer has an implicit binary point at position 0, so
// value = 2^k * 1.fraction with k = index of the leading one). The
// fraction bits below the leading one are passed to posit8_pack, which
// performs the actual regime-length-dependent rounding.
// =============================================================================
`timescale 1ns/1ps

module int8_to_posit8 (
    input  wire signed [7:0] int_i,
    output wire [7:0]        posit_o
);

    wire               sign_w;
    wire signed [8:0]  ext_in;
    wire signed [8:0]  mag9_s;
    wire [8:0]         mag9;
    wire               is_zero;

    assign sign_w  = int_i[7];
    assign ext_in  = {int_i[7], int_i};          // sign-extend to 9 bits
    assign mag9_s  = ext_in[8] ? -ext_in : ext_in; // absolute value (handles -128 -> 128 exactly)
    assign mag9    = mag9_s[8:0];
    assign is_zero = (mag9 == 9'd0);

    // Priority encoder: leading-one position of a 9-bit magnitude (0..8)
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

    // Left-justify so the leading one sits at the top, then take the next
    // bits as the fraction (exact - integers have no rounding at this step).
    reg [8:0] shifted;
    always @* begin
        shifted = mag9 << (4'd8 - msb_pos);
    end

    wire [11:0] sig12 = {shifted[8:0], 3'b000}; // hidden bit + 8 frac bits + 3 zero pad

    posit8_pack u_pack (
        .sign_i   (sign_w),
        .k_i      ({4'b0, msb_pos}),  // k = msb_pos, zero-extended (always >= 0 here)
        .sig_i    (sig12),
        .sticky_i (1'b0),
        .zero_i   (is_zero),
        .posit_o  (posit_o)
    );

endmodule
