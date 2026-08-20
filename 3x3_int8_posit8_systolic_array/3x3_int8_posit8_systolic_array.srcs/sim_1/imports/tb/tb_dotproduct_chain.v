// Verifies the full "3 multiply-accumulates then round to posit8" chain
// (the exact computation each PE in the array will perform over one
// drain pass) against golden reference vectors covering directed edge
// cases plus randomized int8-sourced and pure-random posit triples.
`timescale 1ns/1ps

module tb_dotproduct_chain;

    localparam ACC_WIDTH = 48;
    localparam FRAC = 24;
    localparam NUM_CASES = 4006;

    reg [55:0] golden [0:NUM_CASES-1]; // {a1,b1,a2,b2,a3,b3,expected} = 7 bytes

    reg [7:0] a1,b1,a2,b2,a3,b3,expected;
    wire signed [ACC_WIDTH-1:0] p1, p2, p3;
    reg  signed [ACC_WIDTH-1:0] sum;
    wire [7:0] posit_result;

    posit8_multiplier #(.ACC_WIDTH(ACC_WIDTH), .FRAC(FRAC)) m1 (.posit_a(a1), .posit_b(b1), .fixed_o(p1));
    posit8_multiplier #(.ACC_WIDTH(ACC_WIDTH), .FRAC(FRAC)) m2 (.posit_a(a2), .posit_b(b2), .fixed_o(p2));
    posit8_multiplier #(.ACC_WIDTH(ACC_WIDTH), .FRAC(FRAC)) m3 (.posit_a(a3), .posit_b(b3), .fixed_o(p3));

    fixed_to_posit8 #(.ACC_WIDTH(ACC_WIDTH), .FRAC(FRAC)) u_f2p (.acc_i(sum), .posit_o(posit_result));

    integer i, errors;

    initial begin
        $readmemh("golden_dotproduct.hex", golden);
        errors = 0;
        for (i = 0; i < NUM_CASES; i = i + 1) begin
            {a1,b1,a2,b2,a3,b3,expected} = golden[i];
            #1;
            sum = p1 + p2 + p3;
            #1;
            if (posit_result !== expected) begin
                errors = errors + 1;
                if (errors <= 20)
                    $display("MISMATCH[%0d]: a1=%02x b1=%02x a2=%02x b2=%02x a3=%02x b3=%02x got=%02x expected=%02x",
                              i, a1,b1,a2,b2,a3,b3, posit_result, expected);
            end
        end
        if (errors == 0)
            $display("PASS: dot-product chain matches golden model for all %0d cases.", NUM_CASES);
        else
            $display("FAIL: %0d / %0d mismatches.", errors, NUM_CASES);
        $finish;
    end

endmodule
