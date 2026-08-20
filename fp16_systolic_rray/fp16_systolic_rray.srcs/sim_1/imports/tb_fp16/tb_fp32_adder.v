// Checks fp32_adder against numpy's float32 addition (IEEE-754
// round-to-nearest-even reference), covering directed edge cases,
// general random values, near-cancellation pairs, and realistic
// FP16-product-plus-accumulator pairs.
`timescale 1ns/1ps

module tb_fp32_adder;

    localparam NUM_CASES = 8015;

    reg [95:0] golden [0:NUM_CASES-1]; // {a[31:0], b[31:0], expected[31:0]}

    reg  [31:0] a, b, expected;
    wire [31:0] sum;

    fp32_adder dut (.a(a), .b(b), .sum(sum));

    integer i, errors;

    initial begin
        $readmemh("golden_fp32_adder.hex", golden);
        errors = 0;
        for (i = 0; i < NUM_CASES; i = i + 1) begin
            {a, b, expected} = golden[i];
            #1;
            if (sum !== expected) begin
                errors = errors + 1;
                if (errors <= 20)
                    $display("MISMATCH[%0d]: a=%08x b=%08x got=%08x expected=%08x",
                              i, a, b, sum, expected);
            end
        end
        if (errors == 0)
            $display("PASS: fp32_adder matches numpy for all %0d cases.", NUM_CASES);
        else
            $display("FAIL: %0d / %0d mismatches.", errors, NUM_CASES);
        $finish;
    end

endmodule
