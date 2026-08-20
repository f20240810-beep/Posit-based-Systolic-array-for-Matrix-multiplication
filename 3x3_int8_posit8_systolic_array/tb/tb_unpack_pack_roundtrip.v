// Roundtrip sanity test: posit -> unpack -> pack -> posit must be identity
// for every representable (non-NaR) pattern, since no precision is lost
// going through a 6-bit significand into a 12-bit (zero-padded) slot.
`timescale 1ns/1ps

module tb_unpack_pack_roundtrip;

    reg  [7:0] posit_in;
    wire       sign_w, zero_w, nar_w;
    wire signed [4:0] k_w;
    wire [5:0] sig_w;

    wire [7:0] posit_out;

    integer i, errors;

    posit8_unpack u_unpack (
        .posit_i(posit_in), .sign_o(sign_w), .k_o(k_w),
        .sig_o(sig_w), .zero_o(zero_w), .nar_o(nar_w)
    );

    posit8_pack u_pack (
        .sign_i(sign_w),
        .k_i({{3{k_w[4]}}, k_w}),      // sign-extend 5-bit k to 8-bit
        .sig_i({sig_w, 6'b0}),          // left-justify 6-bit sig into 12-bit slot
        .sticky_i(1'b0),
        .zero_i(zero_w),
        .posit_o(posit_out)
    );

    initial begin
        errors = 0;
        for (i = 0; i < 256; i = i + 1) begin
            if (i == 128) begin
                // NaR pattern - documented as unsupported, skip strict check
                posit_in = i[7:0];
                #1;
            end else begin
                posit_in = i[7:0];
                #1;
                if (posit_out !== posit_in[7:0]) begin
                    errors = errors + 1;
                    $display("MISMATCH: in=0x%02x out=0x%02x  (sign=%b k=%0d sig=%06b zero=%b)",
                              posit_in, posit_out, sign_w, k_w, sig_w, zero_w);
                end
            end
        end
        if (errors == 0)
            $display("PASS: all 255 non-NaR patterns round-tripped exactly.");
        else
            $display("FAIL: %0d mismatches out of 255.", errors);
        $finish;
    end

endmodule
