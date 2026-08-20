// =============================================================================
// systolic_array_fp16.v
//
// Same structural grid topology as systolic_array.v / systolic_array_int8.v,
// instantiating pe_fp16. Buses are 16 bits wide per element here (vs 8
// for Posit8/INT8) since that's FP16's native width - itself a fair,
// reportable resource-cost difference (wider inter-PE routing) between
// the formats.
// =============================================================================
`timescale 1ns/1ps

module systolic_array_fp16 #(
    parameter N = 3
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  clear,

    input  wire [N*16-1:0]       a_edge_flat,
    input  wire [N*16-1:0]       b_edge_flat,

    output wire [N*N*16-1:0]     result_flat
);

    wire [15:0] a_link [0:N-1][0:N];
    wire [15:0] b_link [0:N][0:N-1];
    wire [15:0] result_grid [0:N-1][0:N-1];

    genvar r, c;

    generate
        for (r = 0; r < N; r = r + 1) begin : GEN_A_EDGE
            assign a_link[r][0] = a_edge_flat[r*16 +: 16];
        end
        for (c = 0; c < N; c = c + 1) begin : GEN_B_EDGE
            assign b_link[0][c] = b_edge_flat[c*16 +: 16];
        end

        for (r = 0; r < N; r = r + 1) begin : GEN_ROW
            for (c = 0; c < N; c = c + 1) begin : GEN_COL
                pe_fp16 u_pe (
                    .clk      (clk),
                    .rst_n    (rst_n),
                    .clear    (clear),
                    .a_in     (a_link[r][c]),
                    .b_in     (b_link[r][c]),
                    .a_out    (a_link[r][c+1]),
                    .b_out    (b_link[r+1][c]),
                    .result_o (result_grid[r][c])
                );
                assign result_flat[(r*N + c)*16 +: 16] = result_grid[r][c];
            end
        end
    endgenerate

endmodule
