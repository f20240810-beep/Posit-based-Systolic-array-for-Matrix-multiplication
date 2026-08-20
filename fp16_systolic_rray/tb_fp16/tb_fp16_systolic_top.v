// End-to-end FP16 testbench, using the SAME 26 (A,B) matrix pairs as
// tb_posit_systolic_top.v / tb_int8_systolic_top.v for direct
// cross-format comparability.
`timescale 1ns/1ps

module tb_fp16_systolic_top;

    localparam N = 3;
    localparam NUM_CASES = 26;
    localparam CLK_PERIOD = 10;

    reg [7:0] golden_a [0:NUM_CASES*N*N-1];
    reg [7:0] golden_b [0:NUM_CASES*N*N-1];
    reg [7:0] golden_c [0:NUM_CASES*N*N-1];

    reg  clk, rst_n, start;
    reg  signed [N*N*8-1:0] a_matrix_flat_i, b_matrix_flat_i;
    wire done;
    wire signed [N*N*8-1:0] c_matrix_flat_o;

    fp16_systolic_top #(.N(N)) dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .a_matrix_flat_i(a_matrix_flat_i),
        .b_matrix_flat_i(b_matrix_flat_i),
        .done(done),
        .c_matrix_flat_o(c_matrix_flat_o)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    integer case_i, i, j, base, errors;
    reg [7:0] got_byte, exp_byte;

    initial begin
        $readmemh("golden_top_a.hex", golden_a);
        $readmemh("golden_top_b.hex", golden_b);
        $readmemh("golden_fp16_top_c.hex", golden_c);

        clk = 0; rst_n = 0; start = 0;
        a_matrix_flat_i = 0; b_matrix_flat_i = 0;
        errors = 0;

        @(negedge clk); rst_n = 1;
        @(negedge clk);

        for (case_i = 0; case_i < NUM_CASES; case_i = case_i + 1) begin
            base = case_i * N * N;

            for (i = 0; i < N; i = i + 1)
                for (j = 0; j < N; j = j + 1)
                    a_matrix_flat_i[(i*N+j)*8 +: 8] = golden_a[base + i*N + j];
            for (i = 0; i < N; i = i + 1)
                for (j = 0; j < N; j = j + 1)
                    b_matrix_flat_i[(i*N+j)*8 +: 8] = golden_b[base + i*N + j];

            start = 1;
            @(negedge clk);
            start = 0;

            while (done !== 1'b1) @(negedge clk);

            for (i = 0; i < N; i = i + 1) begin
                for (j = 0; j < N; j = j + 1) begin
                    got_byte = c_matrix_flat_o[(i*N+j)*8 +: 8];
                    exp_byte = golden_c[base + i*N + j];
                    if (got_byte !== exp_byte) begin
                        errors = errors + 1;
                        $display("MISMATCH case=%0d C(%0d,%0d): got=%0d expected=%0d",
                                  case_i, i, j, $signed(got_byte), $signed(exp_byte));
                    end
                end
            end

            @(negedge clk);
        end

        if (errors == 0)
            $display("PASS: end-to-end fp16_systolic_top matches golden model for all %0d matrix pairs.", NUM_CASES);
        else
            $display("FAIL: %0d mismatches across %0d cases.", errors, NUM_CASES);

        $finish;
    end

endmodule
