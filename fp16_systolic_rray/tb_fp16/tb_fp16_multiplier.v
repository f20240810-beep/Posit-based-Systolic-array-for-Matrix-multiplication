// Checks fp16_multiplier's exact FP32 product against numpy (computed
// via widening to float32, which is exact for FP16 x FP16 inputs).
`timescale 1ns/1ps

module tb_fp16_multiplier;

    localparam NUM_CASES = 20011;

    reg [63:0] golden [0:NUM_CASES-1]; // {a[15:0], b[15:0], expected[31:0]}

    reg  [15:0] a, b;
    reg  [31:0] expected;
    wire [31:0] fp32_o;

    fp16_multiplier dut (.a(a), .b(b), .fp32_o(fp32_o));

    integer i, errors;

    initial begin
        $readmemh("golden_fp16_mult.hex", golden);
        errors = 0;
        for (i = 0; i < NUM_CASES; i = i + 1) begin
            {a, b, expected} = golden[i];
            #1;
            if (fp32_o !== expected) begin
                errors = errors + 1;
                if (errors <= 20)
                    $display("MISMATCH[%0d]: a=%04x b=%04x got=%08x expected=%08x",
                              i, a, b, fp32_o, expected);
            end
        end
        if (errors == 0)
            $display("PASS: fp16_multiplier matches numpy for all %0d cases.", NUM_CASES);
        else
            $display("FAIL: %0d / %0d mismatches.", errors, NUM_CASES);
        $finish;
    end

endmodule
