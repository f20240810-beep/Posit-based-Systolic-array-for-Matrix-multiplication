// =============================================================================
// fixed_to_posit8.v
//
// Converts the wide signed fixed-point accumulator value (Q*.FRAC) back
// into a Posit(8,0) bit pattern. This is the drain-time output stage of
// each PE: it normalizes the accumulator (leading-one detect) and hands
// off to posit8_pack, which does the actual round-to-nearest-even and
// range saturation. This is the SECOND (and last) place any rounding
// happens in the whole datapath - the multiply-accumulate itself was
// exact.
// =============================================================================
`timescale 1ns/1ps

module fixed_to_posit8 #(
    parameter ACC_WIDTH = 48,
    parameter FRAC       = 24
) (
    input  wire signed [ACC_WIDTH-1:0] acc_i,
    output wire [7:0]                  posit_o
);

    wire               sign_w   = acc_i[ACC_WIDTH-1];
    wire [ACC_WIDTH-1:0] magnitude = sign_w ? (~acc_i + 1'b1) : acc_i;
    wire               is_zero  = (acc_i == {ACC_WIDTH{1'b0}});

    // Priority encoder: leading-one position over the magnitude.
    reg [$clog2(ACC_WIDTH)-1:0] msb_pos;
    reg                          found;
    integer                      idx;
    always @* begin
        msb_pos = 0;
        found   = 1'b0;
        for (idx = ACC_WIDTH-1; idx >= 0; idx = idx - 1) begin
            if (!found && magnitude[idx]) begin
                msb_pos = idx[$clog2(ACC_WIDTH)-1:0];
                found   = 1'b1;
            end
        end
    end

    // k = (bit position of the leading one) - FRAC, since magnitude's
    // true value is magnitude_int / 2^FRAC, and a leading one at bit
    // `msb_pos` means magnitude_int = 2^msb_pos * (1.something).
    wire signed [15:0] k_wide = {6'b0, msb_pos} - FRAC;

    // Left-justify so the leading one sits at the very top bit, then take
    // the next 11 bits as the fraction for posit8_pack, plus an explicit
    // sticky bit for everything further down (so no precision is lost
    // even though only 11 bits are passed on - see posit8_pack.v).
    wire [ACC_WIDTH-1:0] shifted = magnitude << (ACC_WIDTH-1-msb_pos);
    wire [11:0] sig12 = {shifted[ACC_WIDTH-1 -: 12]};
    wire        sticky = |shifted[ACC_WIDTH-13:0];

    posit8_pack u_pack (
        .sign_i   (sign_w),
        .k_i      (k_wide[7:0]),
        .sig_i    (sig12),
        .sticky_i (sticky),
        .zero_i   (is_zero),
        .posit_o  (posit_o)
    );

endmodule
