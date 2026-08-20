// =============================================================================
// fp16_systolic_top.v
//
// Same external interface, same skew-feed FSM, same T_MAX timing as
// posit_systolic_top.v / int8_systolic_top.v - encoders (int8_to_fp16)
// outside the array, array operates purely on FP16 bit patterns
// (internally accumulating in FP32 - see pe_fp16.v), decoders
// (fp16_to_int8) outside the array.
// =============================================================================
`timescale 1ns/1ps

module fp16_systolic_top #(
    parameter N     = 3,
    parameter T_MAX = 3*(N-1) + 2
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

    wire [15:0] posit_A [0:N-1][0:N-1]; // (kept name "posit_A" for structural
    wire [15:0] posit_B [0:N-1][0:N-1]; //  parallels with posit_systolic_top.v; holds FP16 here)

    genvar gi, gk;
    generate
        for (gi = 0; gi < N; gi = gi + 1) begin : ENC_A_ROW
            for (gk = 0; gk < N; gk = gk + 1) begin : ENC_A_COL
                int8_to_fp16 u_enc_a (
                    .int_i  (a_matrix_reg[(gi*N+gk)*8 +: 8]),
                    .fp16_o (posit_A[gi][gk])
                );
            end
        end
        for (gk = 0; gk < N; gk = gk + 1) begin : ENC_B_ROW
            for (gi = 0; gi < N; gi = gi + 1) begin : ENC_B_COL
                int8_to_fp16 u_enc_b (
                    .int_i  (b_matrix_reg[(gk*N+gi)*8 +: 8]),
                    .fp16_o (posit_B[gk][gi])
                );
            end
        end
    endgenerate

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

    wire [N*16-1:0] a_edge_flat, b_edge_flat;

    generate
        for (gi = 0; gi < N; gi = gi + 1) begin : A_EDGE_MUX
            wire signed [CNT_W:0] k_idx = running ? ($signed({1'b0, t_cnt}) - gi) : -1;
            assign a_edge_flat[gi*16 +: 16] =
                (k_idx >= 0 && k_idx < N) ? posit_A[gi][k_idx[IDX_W-1:0]] : 16'b0;
        end
        for (gi = 0; gi < N; gi = gi + 1) begin : B_EDGE_MUX
            wire signed [CNT_W:0] k_idx = running ? ($signed({1'b0, t_cnt}) - gi) : -1;
            assign b_edge_flat[gi*16 +: 16] =
                (k_idx >= 0 && k_idx < N) ? posit_B[k_idx[IDX_W-1:0]][gi] : 16'b0;
        end
    endgenerate

    wire [N*N*16-1:0] result_flat;

    systolic_array_fp16 #(.N(N)) u_array (
        .clk          (clk),
        .rst_n        (rst_n),
        .clear        (array_clear),
        .a_edge_flat  (a_edge_flat),
        .b_edge_flat  (b_edge_flat),
        .result_flat  (result_flat)
    );

    genvar gr, gc;
    generate
        for (gr = 0; gr < N; gr = gr + 1) begin : DEC_ROW
            for (gc = 0; gc < N; gc = gc + 1) begin : DEC_COL
                fp16_to_int8 u_dec (
                    .fp16_i (result_flat[(gr*N+gc)*16 +: 16]),
                    .int_o  (c_matrix_flat_o[(gr*N+gc)*8 +: 8])
                );
            end
        end
    endgenerate

endmodule
