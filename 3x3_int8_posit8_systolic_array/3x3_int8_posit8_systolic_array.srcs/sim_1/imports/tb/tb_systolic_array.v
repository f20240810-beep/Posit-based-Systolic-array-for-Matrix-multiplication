// Full 3x3 matrix-multiply testbench: drives the systolic array's edges
// with correctly SKEWED input sequences (row i's activations delayed by
// i cycles, column j's weights delayed by j cycles - the standard
// systolic feeding pattern) and checks every PE's final accumulated
// Posit8 result against a golden reference computed in Python.
`timescale 1ns/1ps

module tb_systolic_array;

    localparam N         = 3;
    localparam ACC_WIDTH = 48;
    localparam FRAC      = 24;
    localparam T_MAX     = 8;
    localparam NUM_CASES = 20;
    localparam CLK_PERIOD = 10;

    reg  [23:0] a_sched [0:NUM_CASES*T_MAX-1];
    reg  [23:0] b_sched [0:NUM_CASES*T_MAX-1];
    reg  [7:0]  expected [0:NUM_CASES*N*N-1];

    reg         clk, rst_n, clear;
    reg  [N*8-1:0] a_edge_flat, b_edge_flat;
    wire [N*N*8-1:0] result_flat;

    systolic_array #(.N(N), .ACC_WIDTH(ACC_WIDTH), .FRAC(FRAC)) dut (
        .clk(clk), .rst_n(rst_n), .clear(clear),
        .a_edge_flat(a_edge_flat), .b_edge_flat(b_edge_flat),
        .result_flat(result_flat)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    integer case_i, t, i, j, errors, base_t, base_r;

    initial begin
        $dumpfile("tb_systolic_array.vcd");
        $dumpvars(0, tb_systolic_array);

        $readmemh("golden_matrix_a.hex", a_sched);
        $readmemh("golden_matrix_b.hex", b_sched);
        $readmemh("golden_matrix_expected.hex", expected);

        clk = 0; rst_n = 0; clear = 0; a_edge_flat = 0; b_edge_flat = 0;
        errors = 0;

        @(negedge clk); rst_n = 1;

        for (case_i = 0; case_i < NUM_CASES; case_i = case_i + 1) begin
            base_t = case_i * T_MAX;

            // Start a fresh pass: clear all PE accumulators
            @(negedge clk); clear = 1; a_edge_flat = 0; b_edge_flat = 0;
            @(negedge clk); clear = 0;

            // Drive the skewed schedule
            for (t = 0; t < T_MAX; t = t + 1) begin
                a_edge_flat = a_sched[base_t + t];
                b_edge_flat = b_sched[base_t + t];
                @(negedge clk);
            end

            // All PEs have now received their full 3-term dot product.
            base_r = case_i * N * N;
            for (i = 0; i < N; i = i + 1) begin
                for (j = 0; j < N; j = j + 1) begin
                    if (result_flat[(i*N+j)*8 +: 8] !== expected[base_r + i*N + j]) begin
                        errors = errors + 1;
                        $display("MISMATCH case=%0d PE(%0d,%0d): got=%02x expected=%02x",
                                  case_i, i, j, result_flat[(i*N+j)*8 +: 8], expected[base_r + i*N + j]);
                    end
                end
            end
        end

        if (errors == 0)
            $display("PASS: systolic_array matches golden matrix multiply for all %0d cases (%0d PE results each).",
                       NUM_CASES, N*N);
        else
            $display("FAIL: %0d mismatches across %0d cases.", errors, NUM_CASES);

        $finish;
    end

endmodule
