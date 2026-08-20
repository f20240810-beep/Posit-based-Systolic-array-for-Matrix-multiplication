// Exhaustive (256x256) check of posit8_multiplier's exact fixed-point
// output against a golden reference computed in Python.
`timescale 1ns/1ps

module tb_multiplier;

    localparam ACC_WIDTH = 48;
    localparam FRAC = 24;

    reg  [47:0] golden [0:65535]; // index = a*256+b

    reg  [7:0] posit_a, posit_b;
    wire signed [ACC_WIDTH-1:0] fixed_o;

    integer a, b, errors;

    posit8_multiplier #(.ACC_WIDTH(ACC_WIDTH), .FRAC(FRAC)) u_mult (
        .posit_a(posit_a), .posit_b(posit_b), .fixed_o(fixed_o)
    );

    initial begin
        $readmemh("golden_multiplier.hex", golden);
        errors = 0;
        for (a = 0; a < 256; a = a + 1) begin
            for (b = 0; b < 256; b = b + 1) begin
                posit_a = a[7:0];
                posit_b = b[7:0];
                #1;
                if (fixed_o !== golden[a*256+b][ACC_WIDTH-1:0]) begin
                    errors = errors + 1;
                    if (errors <= 20)
                        $display("MISMATCH: a=0x%02x b=0x%02x got=%0d expected=%0d",
                                  a, b, fixed_o, $signed(golden[a*256+b]));
                end
            end
        end
        if (errors == 0)
            $display("PASS: posit8_multiplier matches golden model for all 65536 pairs.");
        else
            $display("FAIL: %0d / 65536 mismatches.", errors);
        $finish;
    end

endmodule
