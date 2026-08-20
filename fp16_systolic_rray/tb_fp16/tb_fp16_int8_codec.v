// Checks int8_to_fp16 (exhaustive, all 256 integers - must be exact)
// and fp16_to_int8 (exhaustive over all non-inf/nan FP16 patterns).
`timescale 1ns/1ps

module tb_fp16_int8_codec;

    reg [15:0] golden_i2f [0:255];
    reg [23:0] golden_f2i [0:63487]; // {fp16[15:0], expected_int8[7:0]}

    reg  signed [7:0] int_in;
    wire [15:0]        fp16_out;

    reg  [15:0]        fp16_in;
    wire signed [7:0]  int_out;

    integer i, errors_enc, errors_dec;

    int8_to_fp16 u_enc (.int_i(int_in), .fp16_o(fp16_out));
    fp16_to_int8 u_dec (.fp16_i(fp16_in), .int_o(int_out));

    initial begin
        $readmemh("golden_int_to_fp16.hex", golden_i2f);
        $readmemh("golden_fp16_to_int.hex", golden_f2i);

        errors_enc = 0;
        for (i = -128; i < 128; i = i + 1) begin
            int_in = i[7:0];
            #1;
            if (fp16_out !== golden_i2f[i+128]) begin
                errors_enc = errors_enc + 1;
                $display("ENCODE MISMATCH: int=%0d got=%04x expected=%04x", i, fp16_out, golden_i2f[i+128]);
            end
        end

        errors_dec = 0;
        for (i = 0; i < 63488; i = i + 1) begin
            fp16_in = golden_f2i[i][23:8];
            #1;
            if (int_out !== $signed(golden_f2i[i][7:0])) begin
                errors_dec = errors_dec + 1;
                if (errors_dec <= 20)
                    $display("DECODE MISMATCH: fp16=%04x got=%0d expected=%0d",
                              fp16_in, int_out, $signed(golden_f2i[i][7:0]));
            end
        end

        if (errors_enc == 0)
            $display("PASS: int8_to_fp16 exact for all 256 integers.");
        else
            $display("FAIL: int8_to_fp16 had %0d mismatches.", errors_enc);

        if (errors_dec == 0)
            $display("PASS: fp16_to_int8 matches golden model for all 63488 non-inf/nan patterns.");
        else
            $display("FAIL: fp16_to_int8 had %0d / 63488 mismatches.", errors_dec);

        $finish;
    end

endmodule
