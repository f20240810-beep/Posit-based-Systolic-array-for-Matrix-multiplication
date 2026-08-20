// Clocked testbench for a single PE. Drives 3 (a,b) pairs per pass
// (clear, then 3 MAC cycles) and checks the accumulated Posit8 result
// against the same golden dot-product vectors used for the combinational
// chain test - this time exercising the real clocked accumulator and
// skew registers, not just the combinational math.
`timescale 1ns/1ps

module tb_pe;

    localparam ACC_WIDTH = 48;
    localparam FRAC = 24;
    localparam NUM_CASES = 4006;
    localparam CLK_PERIOD = 10;

    reg [55:0] golden [0:NUM_CASES-1];

    reg        clk, rst_n, clear;
    reg  [7:0] a_in, b_in;
    wire [7:0] a_out, b_out, result_o;

    pe #(.ACC_WIDTH(ACC_WIDTH), .FRAC(FRAC)) dut (
        .clk(clk), .rst_n(rst_n), .clear(clear),
        .a_in(a_in), .b_in(b_in),
        .a_out(a_out), .b_out(b_out),
        .result_o(result_o)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    reg [7:0] a1,b1,a2,b2,a3,b3,expected;
    integer i, errors;

    initial begin
        $dumpfile("tb_pe.vcd");
        $dumpvars(0, tb_pe);

        $readmemh("golden_dotproduct.hex", golden);
        clk = 0; rst_n = 0; clear = 0; a_in = 0; b_in = 0;
        errors = 0;

        @(negedge clk); rst_n = 1;

        for (i = 0; i < NUM_CASES; i = i + 1) begin
            {a1,b1,a2,b2,a3,b3,expected} = golden[i];

            // Start a fresh pass
            @(negedge clk); clear = 1; a_in = 8'b0; b_in = 8'b0;
            @(negedge clk); clear = 0;

            // Three multiply-accumulate cycles
            a_in = a1; b_in = b1; @(negedge clk);
            a_in = a2; b_in = b2; @(negedge clk);
            a_in = a3; b_in = b3; @(negedge clk);

            // result_o now reflects the accumulated sum
            if (result_o !== expected) begin
                errors = errors + 1;
                if (errors <= 20)
                    $display("MISMATCH[%0d]: a1=%02x b1=%02x a2=%02x b2=%02x a3=%02x b3=%02x got=%02x expected=%02x",
                              i, a1,b1,a2,b2,a3,b3, result_o, expected);
            end
        end

        if (errors == 0)
            $display("PASS: clocked PE matches golden model for all %0d cases.", NUM_CASES);
        else
            $display("FAIL: %0d / %0d mismatches.", errors, NUM_CASES);

        $finish;
    end

endmodule
