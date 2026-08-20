// =============================================================================
// posit_systolic_top.v
//
// Complete system: takes two N x N matrices as plain signed 8-bit
// integers, encodes every element to Posit(8,0) (int8_to_posit8, outside
// the array), automatically generates the correctly-SKEWED feeding
// sequence into the systolic array (so the array itself only ever sees
// pure Posit8 bit patterns and never does any conversion), waits for the
// computation to complete, and decodes every PE's result back to a
// plain signed 8-bit integer (posit8_to_int8, outside the array) for
// the final readable output matrix C = A x B.
//
// Usage:
//   1. Present a_matrix_flat_i / b_matrix_flat_i and pulse `start` for
//      one cycle.
//   2. Wait for `done` to go high (T_MAX = 3*(N-1)+2 cycles later).
//   3. Read c_matrix_flat_o - element (i,j) lives at bits[(i*N+j)*8 +: 8].
//   4. `done` stays high until the next `start`.
//
// Matrix element packing (row-major, matches the systolic_array's
// PE(row,col) result indexing): element (row,col) of a flattened N*N*8
// bus lives at bits[(row*N+col)*8 +: 8].
// =============================================================================
`timescale 1ns/1ps

module posit_systolic_top #(
    parameter N         = 3,
    parameter ACC_WIDTH = 48,
    parameter FRAC       = 24,
    parameter T_MAX      = 3*(N-1) + 2   // feed cycles needed to drain all PEs, plus 1 margin cycle
) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    start,

    input  wire signed [N*N*8-1:0] a_matrix_flat_i,  // A(i,k) at bits[(i*N+k)*8 +: 8]
    input  wire signed [N*N*8-1:0] b_matrix_flat_i,  // B(k,j) at bits[(k*N+j)*8 +: 8]

    output reg                     done,
    output wire signed [N*N*8-1:0] c_matrix_flat_o   // C(i,j) at bits[(i*N+j)*8 +: 8]
);

    localparam IDX_W = (N <= 1) ? 1 : $clog2(N);
    localparam CNT_W = $clog2(T_MAX+1);

    // ---- Latch the input matrices for the whole duration of a pass ----
    reg signed [N*N*8-1:0] a_matrix_reg, b_matrix_reg;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_matrix_reg <= {N*N*8{1'b0}};
            b_matrix_reg <= {N*N*8{1'b0}};
        end else if (start) begin
            a_matrix_reg <= a_matrix_flat_i;
            b_matrix_reg <= b_matrix_flat_i;
        end
    end

    // ---- Encode every matrix element to Posit8 (outside the array) ----
    wire [7:0] posit_A [0:N-1][0:N-1];
    wire [7:0] posit_B [0:N-1][0:N-1];

    genvar gi, gk;
    generate
        for (gi = 0; gi < N; gi = gi + 1) begin : ENC_A_ROW
            for (gk = 0; gk < N; gk = gk + 1) begin : ENC_A_COL
                int8_to_posit8 u_enc_a (
                    .int_i   (a_matrix_reg[(gi*N+gk)*8 +: 8]),
                    .posit_o (posit_A[gi][gk])
                );
            end
        end
        for (gk = 0; gk < N; gk = gk + 1) begin : ENC_B_ROW
            for (gi = 0; gi < N; gi = gi + 1) begin : ENC_B_COL
                int8_to_posit8 u_enc_b (
                    .int_i   (b_matrix_reg[(gk*N+gi)*8 +: 8]),
                    .posit_o (posit_B[gk][gi])
                );
            end
        end
    endgenerate

    // ---- FSM: CLEAR -> RUN (drives the skewed feed) -> DONE ----
    localparam S_IDLE = 2'd0, S_CLEAR = 2'd1, S_RUN = 2'd2, S_DONE = 2'd3;
    reg [1:0]       state;
    reg [CNT_W-1:0] t_cnt;
    reg             array_clear;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            t_cnt       <= {CNT_W{1'b0}};
            done        <= 1'b0;
            array_clear <= 1'b0;
        end else begin
            array_clear <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (start) begin
                        state       <= S_CLEAR;
                        array_clear <= 1'b1;
                        t_cnt       <= {CNT_W{1'b0}};
                        done        <= 1'b0;
                    end
                end
                S_CLEAR: begin
                    state <= S_RUN;
                    t_cnt <= {CNT_W{1'b0}};
                end
                S_RUN: begin
                    if (t_cnt == T_MAX-1) begin
                        state <= S_DONE;
                    end else begin
                        t_cnt <= t_cnt + 1'b1;
                    end
                end
                S_DONE: begin
                    done <= 1'b1;
                    if (start) begin
                        state       <= S_CLEAR;
                        array_clear <= 1'b1;
                        t_cnt       <= {CNT_W{1'b0}};
                        done        <= 1'b0;
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end

    wire running = (state == S_RUN);

    // ---- Per-row / per-column skew multiplexers ----
    // Row i feeds posit_A[i][t_cnt-i] once 0 <= t_cnt-i < N, else zero.
    // Column j feeds posit_B[t_cnt-j][j] once 0 <= t_cnt-j < N, else zero.
    wire [N*8-1:0] a_edge_flat, b_edge_flat;

    generate
        for (gi = 0; gi < N; gi = gi + 1) begin : A_EDGE_MUX
            wire signed [CNT_W:0] k_idx = running ? ($signed({1'b0, t_cnt}) - gi) : -1;
            assign a_edge_flat[gi*8 +: 8] =
                (k_idx >= 0 && k_idx < N) ? posit_A[gi][k_idx[IDX_W-1:0]] : 8'b0;
        end
        for (gi = 0; gi < N; gi = gi + 1) begin : B_EDGE_MUX
            wire signed [CNT_W:0] k_idx = running ? ($signed({1'b0, t_cnt}) - gi) : -1;
            assign b_edge_flat[gi*8 +: 8] =
                (k_idx >= 0 && k_idx < N) ? posit_B[k_idx[IDX_W-1:0]][gi] : 8'b0;
        end
    endgenerate

    // ---- The systolic array itself (pure Posit8 bit patterns in and out) ----
    wire [N*N*8-1:0] result_flat;

    systolic_array #(
        .N         (N),
        .ACC_WIDTH (ACC_WIDTH),
        .FRAC      (FRAC)
    ) u_array (
        .clk          (clk),
        .rst_n        (rst_n),
        .clear        (array_clear),
        .a_edge_flat  (a_edge_flat),
        .b_edge_flat  (b_edge_flat),
        .result_flat  (result_flat)
    );

    // ---- Decode every PE result back to a plain signed integer ----
    genvar gr, gc;
    generate
        for (gr = 0; gr < N; gr = gr + 1) begin : DEC_ROW
            for (gc = 0; gc < N; gc = gc + 1) begin : DEC_COL
                posit8_to_int8 u_dec (
                    .posit_i (result_flat[(gr*N+gc)*8 +: 8]),
                    .int_o   (c_matrix_flat_o[(gr*N+gc)*8 +: 8])
                );
            end
        end
    endgenerate

endmodule
