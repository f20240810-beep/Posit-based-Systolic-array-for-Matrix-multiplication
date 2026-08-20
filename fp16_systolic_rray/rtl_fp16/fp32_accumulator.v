// =============================================================================
// fp32_accumulator.v
//
// Register wrapper around fp32_adder - same clk/rst_n/clear/en
// interface as fixed_accumulator.v (Posit8/INT8's accumulator), so the
// PE-level wiring is identical across all three variants. Unlike
// fixed_accumulator.v, this accumulation is NOT bit-exact across
// multiple adds (each add rounds, per IEEE-754) - a real, reportable
// difference from the Posit8/INT8 designs, where accumulation itself
// never rounds and all error is concentrated at the final read-out
// conversion.
// =============================================================================
`timescale 1ns/1ps

module fp32_accumulator (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        clear,
    input  wire        en,
    input  wire [31:0] fp32_i,
    output reg  [31:0] acc_o
);

    wire [31:0] sum;
    fp32_adder u_add (.a(acc_o), .b(fp32_i), .sum(sum));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            acc_o <= 32'b0;
        else if (clear)
            acc_o <= 32'b0;
        else if (en)
            acc_o <= sum;
    end

endmodule
