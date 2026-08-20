// =============================================================================
// systolic_array.v
//
// Structural N x N grid of PEs (N=3 by default, per the 3x3 requirement -
// widen by overriding the N parameter if a bigger array is ever needed).
// This module contains NO arithmetic of its own - it is pure wiring: it
// instantiates PE cells in a grid and connects each one's a_out/b_out to
// its right/bottom neighbor's a_in/b_in, giving the classic systolic
// "diagonal wave" dataflow:
//
//        b_edge[0]   b_edge[1]   b_edge[2]
//            |           |           |
//   a_edge[0]-- PE(0,0) -- PE(0,1) -- PE(0,2)
//            |           |           |
//   a_edge[1]-- PE(1,0) -- PE(1,1) -- PE(1,2)
//            |           |           |
//   a_edge[2]-- PE(2,0) -- PE(2,1) -- PE(2,2)
//
// Row r's activations enter from the left edge; column c's weights enter
// from the top edge. To multiply two 3x3 matrices A (rows) and B
// (columns) correctly, the TOP-LEVEL controller must feed each edge in
// SKEWED order (row r's data delayed by r cycles, column c's data
// delayed by c cycles) - that skewing is done outside this module (see
// posit_systolic_top.v / its testbench), keeping this module a pure,
// reusable structural grid.
//
// Ports are flattened (std_logic_vector style) for maximum portability
// into Vivado structural/behavioral flows: row/column r's or c's 8-bit
// slice of a flattened bus lives at bits [r*8 +: 8].
// =============================================================================
`timescale 1ns/1ps

module systolic_array #(
    parameter N         = 3,
    parameter ACC_WIDTH = 48,
    parameter FRAC       = 24
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  clear,

    input  wire [N*8-1:0]        a_edge_flat,   // per-row left-edge inputs
    input  wire [N*8-1:0]        b_edge_flat,   // per-column top-edge inputs

    output wire [N*N*8-1:0]      result_flat    // per-PE results, index r*N+c
);

    // Internal grid wiring (unpacked arrays of 8-bit posit buses).
    // a_link[row][col]: col=0..N-1 feed PE inputs, col=N is the rightmost
    // PE's output edge (unused outside the array).
    wire [7:0] a_link [0:N-1][0:N];
    // b_link[row][col]: row=0..N-1 feed PE inputs, row=N is the bottom
    // PE's output edge (unused outside the array).
    wire [7:0] b_link [0:N][0:N-1];

    wire [7:0] result_grid [0:N-1][0:N-1];

    genvar r, c;

    generate
        // Tie the array's edges to the flattened edge input buses.
        for (r = 0; r < N; r = r + 1) begin : GEN_A_EDGE
            assign a_link[r][0] = a_edge_flat[r*8 +: 8];
        end
        for (c = 0; c < N; c = c + 1) begin : GEN_B_EDGE
            assign b_link[0][c] = b_edge_flat[c*8 +: 8];
        end

        // Instantiate the PE grid, bottom-up structural style: each PE's
        // a_out/b_out feeds directly into the next PE's a_in/b_in.
        for (r = 0; r < N; r = r + 1) begin : GEN_ROW
            for (c = 0; c < N; c = c + 1) begin : GEN_COL
                pe #(
                    .ACC_WIDTH (ACC_WIDTH),
                    .FRAC      (FRAC)
                ) u_pe (
                    .clk       (clk),
                    .rst_n     (rst_n),
                    .clear     (clear),
                    .a_in      (a_link[r][c]),
                    .b_in      (b_link[r][c]),
                    .a_out     (a_link[r][c+1]),
                    .b_out     (b_link[r+1][c]),
                    .result_o  (result_grid[r][c])
                );

                assign result_flat[(r*N + c)*8 +: 8] = result_grid[r][c];
            end
        end
    endgenerate

endmodule
