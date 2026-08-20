// =============================================================================
// systolic_array_int8.v
//
// Identical structural wiring to systolic_array.v (Posit8's array) -
// same grid topology, same skew-register dataflow - instantiating
// pe_int8 instead of pe. See systolic_array.v for the full dataflow
// diagram and explanation; not repeated here to avoid drift between
// copies of the same comment.
// =============================================================================
`timescale 1ns/1ps

module systolic_array_int8 #(
    parameter N         = 3,
    parameter ACC_WIDTH = 32
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  clear,

    input  wire [N*8-1:0]        a_edge_flat,
    input  wire [N*8-1:0]        b_edge_flat,

    output wire [N*N*8-1:0]      result_flat
);

    wire signed [7:0] a_link [0:N-1][0:N];
    wire signed [7:0] b_link [0:N][0:N-1];
    wire signed [7:0] result_grid [0:N-1][0:N-1];

    genvar r, c;

    generate
        for (r = 0; r < N; r = r + 1) begin : GEN_A_EDGE
            assign a_link[r][0] = a_edge_flat[r*8 +: 8];
        end
        for (c = 0; c < N; c = c + 1) begin : GEN_B_EDGE
            assign b_link[0][c] = b_edge_flat[c*8 +: 8];
        end

        for (r = 0; r < N; r = r + 1) begin : GEN_ROW
            for (c = 0; c < N; c = c + 1) begin : GEN_COL
                pe_int8 #(.ACC_WIDTH(ACC_WIDTH)) u_pe (
                    .clk      (clk),
                    .rst_n    (rst_n),
                    .clear    (clear),
                    .a_in     (a_link[r][c]),
                    .b_in     (b_link[r][c]),
                    .a_out    (a_link[r][c+1]),
                    .b_out    (b_link[r+1][c]),
                    .result_o (result_grid[r][c])
                );
                assign result_flat[(r*N + c)*8 +: 8] = result_grid[r][c];
            end
        end
    endgenerate

endmodule
