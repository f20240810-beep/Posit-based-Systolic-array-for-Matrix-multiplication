// =============================================================================
// pe_int8.v  -  INT8 fixed-point Processing Element
//
// Structurally identical to pe.v (Posit8's PE): multiply, accumulate
// exactly, convert once at readout, pass operands to neighbors with a
// 1-cycle skew delay. Only the multiplier and the final conversion
// differ from the Posit8 PE - the accumulator and skew registers are
// bit-for-bit the same microarchitecture. This is intentional: it
// isolates the numeric format as the only variable between the two
// designs for benchmarking purposes.
// =============================================================================
`timescale 1ns/1ps

module pe_int8 #(
    parameter ACC_WIDTH = 32
) (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              clear,

    input  wire signed [7:0] a_in,
    input  wire signed [7:0] b_in,

    output wire signed [7:0] a_out,
    output wire signed [7:0] b_out,

    output wire signed [7:0] result_o
);

    wire signed [ACC_WIDTH-1:0] fixed_prod;
    int8_multiplier #(.ACC_WIDTH(ACC_WIDTH)) u_mult (
        .a(a_in), .b(b_in), .fixed_o(fixed_prod)
    );

    wire signed [ACC_WIDTH-1:0] acc_val;
    fixed_accumulator #(.ACC_WIDTH(ACC_WIDTH)) u_acc (
        .clk(clk), .rst_n(rst_n), .clear(clear),
        .en(1'b1), .fixed_i(fixed_prod), .acc_o(acc_val)
    );

    fixed_to_int8 #(.ACC_WIDTH(ACC_WIDTH)) u_f2i (
        .acc_i(acc_val), .int8_o(result_o)
    );

    reg signed [7:0] a_out_r, b_out_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_out_r <= 8'sd0;
            b_out_r <= 8'sd0;
        end else if (clear) begin
            a_out_r <= 8'sd0;
            b_out_r <= 8'sd0;
        end else begin
            a_out_r <= a_in;
            b_out_r <= b_in;
        end
    end
    assign a_out = a_out_r;
    assign b_out = b_out_r;

endmodule
