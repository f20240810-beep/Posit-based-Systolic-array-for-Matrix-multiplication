// =============================================================================
// fp32_to_fp16.v
//
// Rounds the FP32 accumulator's final value down to FP16 at read-out -
// analogous to fixed_to_posit8.v / fixed_to_int8.v's role for the
// other two variants. Round-to-nearest-even on the dropped 13
// mantissa bits, saturates to FP16's max finite value (65504) on
// overflow (rather than emitting infinity - documented simplification,
// consistent with the rest of the project), flushes to zero on
// underflow below FP16's normal range (consistent FTZ policy).
// =============================================================================
`timescale 1ns/1ps

module fp32_to_fp16 (
    input  wire [31:0] fp32_i,
    output reg  [15:0] fp16_o
);

    wire        sign    = fp32_i[31];
    wire [7:0]  exp_f   = fp32_i[30:23];
    wire [22:0] frac23  = fp32_i[22:0];
    wire        zero_in = (exp_f == 8'd0);
    wire signed [9:0] exp_unbiased = {2'b0, exp_f} - 10'sd127;

    // Round the 23-bit fraction down to 10 bits, round-to-nearest-even.
    wire [9:0] kept10    = frac23[22:13];
    wire       round_bit = frac23[12];
    wire       sticky    = |frac23[11:0];
    wire       round_up  = round_bit & (sticky | kept10[0]);

    wire [10:0] rounded11 = {1'b0, kept10} + round_up;
    wire        mant_carry = rounded11[10];
    wire signed [9:0] exp_after_round = mant_carry ? (exp_unbiased + 10'sd1) : exp_unbiased;
    wire [9:0]        mant_final_pre  = mant_carry ? 10'b0 : rounded11[9:0];

    // FP16 finite normal range: unbiased exponent -14..15.
    wire overflow  = (exp_after_round > 10'sd15);
    wire underflow = (exp_after_round < -10'sd14);

    wire [4:0] exp16_biased = exp_after_round[4:0] + 5'd15;

    always @* begin
        if (zero_in)
            fp16_o = 16'b0;
        else if (overflow)
            fp16_o = {sign, 5'b11110, 10'b1111111111}; // +-65504 (max finite), no infinity output
        else if (underflow)
            fp16_o = 16'b0; // flush to zero (documented FTZ simplification)
        else
            fp16_o = {sign, exp16_biased, mant_final_pre};
    end

endmodule
