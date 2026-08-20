// Checks int8_to_posit8 and posit8_to_int8 against golden reference vectors
// (generated in Python from a brute-force nearest-value Posit(8,0) model).
`timescale 1ns/1ps

module tb_int_posit_codec;

    reg  [7:0] golden_i2p [0:255]; // index = int+128
    reg  [7:0] golden_p2i [0:255]; // index = posit pattern

    reg  signed [7:0] int_in;
    wire [7:0]        posit_out;

    reg  [7:0]        posit_in;
    wire signed [7:0] int_out;

    integer i, errors_enc, errors_dec;

    int8_to_posit8 u_enc (.int_i(int_in), .posit_o(posit_out));
    posit8_to_int8 u_dec (.posit_i(posit_in), .int_o(int_out));

    initial begin
        $readmemh("golden_int_to_posit.hex", golden_i2p);
        $readmemh("golden_posit_to_int.hex", golden_p2i);

        errors_enc = 0;
        for (i = -128; i < 128; i = i + 1) begin
            int_in = i[7:0];
            #1;
            if (posit_out !== golden_i2p[i+128]) begin
                errors_enc = errors_enc + 1;
                $display("ENCODE MISMATCH: int=%0d got=0x%02x expected=0x%02x",
                          i, posit_out, golden_i2p[i+128]);
            end
        end

        errors_dec = 0;
        for (i = 0; i < 256; i = i + 1) begin
            posit_in = i[7:0];
            #1;
            if (int_out !== $signed(golden_p2i[i])) begin
                errors_dec = errors_dec + 1;
                $display("DECODE MISMATCH: posit=0x%02x got=%0d expected=%0d",
                          i, int_out, $signed(golden_p2i[i]));
            end
        end

        if (errors_enc == 0)
            $display("PASS: int8_to_posit8 matches golden model for all 256 integers.");
        else
            $display("FAIL: int8_to_posit8 had %0d mismatches.", errors_enc);

        if (errors_dec == 0)
            $display("PASS: posit8_to_int8 matches golden model for all 256 patterns.");
        else
            $display("FAIL: posit8_to_int8 had %0d mismatches.", errors_dec);

        $finish;
    end

endmodule
