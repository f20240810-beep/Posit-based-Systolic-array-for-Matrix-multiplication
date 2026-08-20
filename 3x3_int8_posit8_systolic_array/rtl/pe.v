// =============================================================================
// pe.v  -  Processing Element
//
// The systolic array's basic cell. Every cycle it:
//   1. Multiplies its current a_in and b_in (Posit8 bit patterns) using
//      posit8_multiplier - this operates directly on the posit bit
//      patterns, never converting to float/int.
//   2. Adds the exact fixed-point product into its local accumulator
//      (fixed_accumulator) - exact, no rounding.
//   3. Passes a_in through to a_out, and b_in through to b_out, each
//      delayed by one clock - this is what gives the array its
//      "systolic" (skewed, wave-like) data movement: activations flow
//      rightward one column per cycle, weights flow downward one row
//      per cycle.
//
// `result_o` continuously reflects the CURRENT accumulator value,
// converted to Posit8 (the only rounding step, done once here rather
// than after every multiply-add - see fixed_to_posit8.v). The parent
// array/controller samples result_o once the accumulation window for a
// pass has completed (i.e. once the skewed data has fully drained
// through), and asserts `clear` for one cycle before starting a new
// dot-product pass.
// =============================================================================
`timescale 1ns/1ps

module pe #(
    parameter ACC_WIDTH = 48,
    parameter FRAC       = 24
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       clear,     // synchronous: zero the accumulator, start a fresh pass

    input  wire [7:0] a_in,      // activation in, from the left neighbor (or array edge)
    input  wire [7:0] b_in,      // weight in, from the top neighbor (or array edge)

    output wire [7:0] a_out,     // activation out, to the right neighbor (1-cycle delayed)
    output wire [7:0] b_out,     // weight out, to the bottom neighbor (1-cycle delayed)

    output wire [7:0] result_o   // current accumulated dot-product, as Posit8
);

    // ---- Stage 1: Posit multiplier (operates directly on posit bits) ----
    wire signed [ACC_WIDTH-1:0] fixed_prod;
    posit8_multiplier #(.ACC_WIDTH(ACC_WIDTH), .FRAC(FRAC)) u_mult (
        .posit_a (a_in),
        .posit_b (b_in),
        .fixed_o (fixed_prod)
    );

    // ---- Stage 2: exact fixed-point accumulator ----
    wire signed [ACC_WIDTH-1:0] acc_val;
    fixed_accumulator #(.ACC_WIDTH(ACC_WIDTH)) u_acc (
        .clk     (clk),
        .rst_n   (rst_n),
        .clear   (clear),
        .en      (1'b1),          // always accumulate; zero-padded skew inputs make idle cycles a no-op
        .fixed_i (fixed_prod),
        .acc_o   (acc_val)
    );

    // ---- Stage 3: Posit output (rounds exactly once, at readout) ----
    fixed_to_posit8 #(.ACC_WIDTH(ACC_WIDTH), .FRAC(FRAC)) u_f2p (
        .acc_i   (acc_val),
        .posit_o (result_o)
    );

    // ---- Systolic skew registers: pass operands to neighbors, 1 cycle late ----
    reg [7:0] a_out_r, b_out_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_out_r <= 8'b0;
            b_out_r <= 8'b0;
        end else if (clear) begin
            a_out_r <= 8'b0;
            b_out_r <= 8'b0;
        end else begin
            a_out_r <= a_in;
            b_out_r <= b_in;
        end
    end
    assign a_out = a_out_r;
    assign b_out = b_out_r;

endmodule
