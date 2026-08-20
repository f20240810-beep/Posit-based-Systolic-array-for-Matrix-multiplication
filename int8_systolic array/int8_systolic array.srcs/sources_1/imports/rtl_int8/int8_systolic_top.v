// =============================================================================
// int8_systolic_top.v
//
// Same interface, same skew-feed FSM, same T_MAX timing as
// posit_systolic_top.v - the only structural difference is that INT8
// is already the array's native compute format, so there is no
// encoder/decoder bank (int8_to_posit8 / posit8_to_int8's role is
// simply "not needed" here - matrices are latched and fed directly).
// This keeps the comparison fair: identical control/timing
// microarchitecture, differing only in whether a format-conversion
// step is needed at all - itself a meaningful, reportable difference
// between fixed-point and alternative-format accelerators.
// =============================================================================
`timescale 1ns/1ps

module int8_systolic_top #(
    parameter N         = 3,
    parameter ACC_WIDTH = 32,
    parameter T_MAX      = 3*(N-1) + 2
) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    start,

    input  wire signed [N*N*8-1:0] a_matrix_flat_i,
    input  wire signed [N*N*8-1:0] b_matrix_flat_i,

    output reg                     done,
    output wire signed [N*N*8-1:0] c_matrix_flat_o
);

    localparam IDX_W = (N <= 1) ? 1 : $clog2(N);
    localparam CNT_W = $clog2(T_MAX+1);

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

    wire signed [N*8-1:0] a_edge_flat, b_edge_flat;

    genvar gi;
    generate
        for (gi = 0; gi < N; gi = gi + 1) begin : A_EDGE_MUX
            wire signed [CNT_W:0] k_idx = running ? ($signed({1'b0, t_cnt}) - gi) : -1;
            assign a_edge_flat[gi*8 +: 8] =
                (k_idx >= 0 && k_idx < N) ? a_matrix_reg[(gi*N + k_idx[IDX_W-1:0])*8 +: 8] : 8'sd0;
        end
        for (gi = 0; gi < N; gi = gi + 1) begin : B_EDGE_MUX
            wire signed [CNT_W:0] k_idx = running ? ($signed({1'b0, t_cnt}) - gi) : -1;
            assign b_edge_flat[gi*8 +: 8] =
                (k_idx >= 0 && k_idx < N) ? b_matrix_reg[(k_idx[IDX_W-1:0]*N + gi)*8 +: 8] : 8'sd0;
        end
    endgenerate

    systolic_array_int8 #(
        .N         (N),
        .ACC_WIDTH (ACC_WIDTH)
    ) u_array (
        .clk          (clk),
        .rst_n        (rst_n),
        .clear        (array_clear),
        .a_edge_flat  (a_edge_flat),
        .b_edge_flat  (b_edge_flat),
        .result_flat  (c_matrix_flat_o)
    );

endmodule
