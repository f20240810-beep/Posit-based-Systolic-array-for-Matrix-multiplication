// =============================================================================
// pe_fp16.v  -  FP16 Processing Element
//
// Same PE shape as pe.v (Posit8) and pe_int8.v (INT8): multiply,
// accumulate, convert-once-at-readout, 1-cycle skew registers. Here
// "accumulate" is a real FP32 add (rounds every step, per IEEE-754 -
// see fp32_accumulator.v's header for why this is a genuine,
// reportable difference from the other two variants) rather than an
// exact integer add.
// =============================================================================
`timescale 1ns/1ps

module pe_fp16 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        clear,

    input  wire [15:0] a_in,
    input  wire [15:0] b_in,

    output wire [15:0] a_out,
    output wire [15:0] b_out,

    output wire [15:0] result_o
);

    wire [31:0] fp32_prod;
    fp16_multiplier u_mult (.a(a_in), .b(b_in), .fp32_o(fp32_prod));

    wire [31:0] acc_val;
    fp32_accumulator u_acc (
        .clk(clk), .rst_n(rst_n), .clear(clear),
        .en(1'b1), .fp32_i(fp32_prod), .acc_o(acc_val)
    );

    fp32_to_fp16 u_f2f (.fp32_i(acc_val), .fp16_o(result_o));

    reg [15:0] a_out_r, b_out_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_out_r <= 16'b0;
            b_out_r <= 16'b0;
        end else if (clear) begin
            a_out_r <= 16'b0;
            b_out_r <= 16'b0;
        end else begin
            a_out_r <= a_in;
            b_out_r <= b_in;
        end
    end
    assign a_out = a_out_r;
    assign b_out = b_out_r;

endmodule
