// =============================================================================
// posit8_unpack.v
//
// Decodes an 8-bit Posit(8,0) bit pattern into its arithmetic components:
//   sign_o : sign bit (1 = negative)
//   k_o    : regime value (signed). For Posit(8,0), es=0 so the *entire*
//            exponent is carried by the regime, k in [-6,+6].
//   sig_o  : 6-bit significand, format 1.fffff (bit[5] is the implicit
//            "hidden" leading 1, bits[4:0] are the stored fraction bits,
//            zero-filled if the regime used up all the fraction bits).
//   zero_o : true value is exactly 0 (all-zero pattern).
//   nar_o  : "Not a Real" pattern (1000_0000). This design does not
//            propagate NaR through the datapath (documented limitation,
//            out of scope for this systolic-array demo) - callers should
//            treat nar_o like zero if it ever appears.
//
// True value represented = (-1)^sign * 2^k * (sig_o / 32)
//
// Implementation notes:
//  - Posit uses a variable-length "regime" run (a run of equal bits
//    terminated by the opposite bit, or running to the end of the word).
//    Because n=8 is small, the regime run-length -> (k, fraction width)
//    mapping is implemented as a priority casez over the 7 magnitude
//    bits, which is the standard, cheap way to build a small posit
//    decoder (equivalent to a leading-one/leading-zero detector).
// =============================================================================
`timescale 1ns/1ps

module posit8_unpack (
    input  wire [7:0] posit_i,
    output reg         sign_o,
    output reg  signed [4:0] k_o,   // range -6..6, 5 bits signed for margin
    output reg  [5:0]  sig_o,       // {hidden, frac[4:0]}
    output reg         zero_o,
    output reg         nar_o
);

    wire [6:0] mag;          // magnitude field after removing sign
    wire [7:0] posit_mag8;   // two's complement of posit_i when negative

    assign posit_mag8 = posit_i[7] ? (~posit_i + 8'd1) : posit_i;
    assign mag        = posit_mag8[6:0];

    reg [2:0] frac_width;    // 0..5, how many low bits of `mag` are fraction

    always @* begin
        sign_o  = posit_i[7];
        zero_o  = (posit_i == 8'b0);
        nar_o   = (posit_i == 8'b1000_0000);
        k_o     = 5'sd0;
        frac_width = 3'd0;
        sig_o   = 6'b100000; // default (value 1.0) - overwritten below

        if (!zero_o && !nar_o) begin
            casez (mag)
                7'b0000001: begin k_o = -5'sd6; frac_width = 3'd0; end
                7'b000001?: begin k_o = -5'sd5; frac_width = 3'd1; end
                7'b00001??: begin k_o = -5'sd4; frac_width = 3'd2; end
                7'b0001???: begin k_o = -5'sd3; frac_width = 3'd3; end
                7'b001????: begin k_o = -5'sd2; frac_width = 3'd4; end
                7'b01?????: begin k_o = -5'sd1; frac_width = 3'd5; end
                7'b10?????: begin k_o =  5'sd0; frac_width = 3'd5; end
                7'b110????: begin k_o =  5'sd1; frac_width = 3'd4; end
                7'b1110???: begin k_o =  5'sd2; frac_width = 3'd3; end
                7'b11110??: begin k_o =  5'sd3; frac_width = 3'd2; end
                7'b111110?: begin k_o =  5'sd4; frac_width = 3'd1; end
                7'b1111110: begin k_o =  5'sd5; frac_width = 3'd0; end
                7'b1111111: begin k_o =  5'sd6; frac_width = 3'd0; end
                default:    begin k_o =  5'sd0; frac_width = 3'd0; end
            endcase

            // Extract `frac_width` low bits of `mag` as the fraction,
            // left-justify into the 5-bit fraction slot (zero pad the rest).
            case (frac_width)
                3'd0: sig_o = {1'b1, 5'b00000};
                3'd1: sig_o = {1'b1, mag[0],    4'b0000};
                3'd2: sig_o = {1'b1, mag[1:0],  3'b000};
                3'd3: sig_o = {1'b1, mag[2:0],  2'b00};
                3'd4: sig_o = {1'b1, mag[3:0],  1'b0};
                3'd5: sig_o = {1'b1, mag[4:0]};
                default: sig_o = {1'b1, 5'b00000};
            endcase
        end
    end

endmodule
