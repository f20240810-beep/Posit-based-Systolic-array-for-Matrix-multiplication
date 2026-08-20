// =============================================================================
// fixed_accumulator.v
//
// A plain signed fixed-point accumulator register: on each clock where
// `en` is high, adds `fixed_i` into the running sum. `clear` resets the
// sum to zero (synchronous), used to start a fresh dot-product pass.
// This is an exact integer adder - no rounding happens here; rounding
// only happens once, when the final sum is converted back to Posit8 by
// fixed_to_posit8.v.
// =============================================================================
`timescale 1ns/1ps

module fixed_accumulator #(
    parameter ACC_WIDTH = 48
) (
    input  wire                        clk,
    input  wire                        rst_n,
    input  wire                        clear,
    input  wire                        en,
    input  wire signed [ACC_WIDTH-1:0] fixed_i,
    output reg  signed [ACC_WIDTH-1:0] acc_o
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            acc_o <= {ACC_WIDTH{1'b0}};
        else if (clear)
            acc_o <= {ACC_WIDTH{1'b0}};
        else if (en)
            acc_o <= acc_o + fixed_i;
    end

endmodule
