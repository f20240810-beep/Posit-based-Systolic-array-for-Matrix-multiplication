// Checks fp32_to_fp16's rounding against numpy's float32->float16 cast,
// excluding true IEEE overflow/underflow inputs where our documented
// saturate/FTZ policy intentionally differs from full IEEE-754.
`timescale 1ns/1ps

module tb_fp32_to_fp16;

    localparam NUM_CASES = 25007;

    reg [47:0] golden [0:NUM_CASES-1]; // {a[31:0], expected[15:0]}

    reg  [31:0] fp32_i;
    reg  [15:0] expected;
    wire [15:0] fp16_o;

    fp32_to_fp16 dut (.fp32_i(fp32_i), .fp16_o(fp16_o));

    integer i, errors;

    initial begin
        $readmemh("golden_fp32_to_fp16.hex", golden);
        errors = 0;
        for (i = 0; i < NUM_CASES; i = i + 1) begin
            {fp32_i, expected} = golden[i];
            #1;
            if (fp16_o !== expected) begin
                errors = errors + 1;
                if (errors <= 20)
                    $display("MISMATCH[%0d]: in=%08x got=%04x expected=%04x",
                              i, fp32_i, fp16_o, expected);
            end
        end
        if (errors == 0)
            $display("PASS: fp32_to_fp16 matches numpy for all %0d cases.", NUM_CASES);
        else
            $display("FAIL: %0d / %0d mismatches.", errors, NUM_CASES);
        $finish;
    end

endmodule
