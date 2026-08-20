# Methodology: Posit8 vs INT8 vs FP16 Systolic Array Comparison

## 1. Goal and independent variable

Compare three 8-bit-input numeric formats (Posit(8,0), INT8 fixed-point,
FP16) for 3×3 systolic-array matrix multiplication, isolating **numeric
format** as the sole independent variable. Everything else that could
confound the comparison is held fixed across all three implementations.

## 2. Architectural parity (what's held constant)

| | Posit8 | INT8 | FP16 |
|---|---|---|---|
| Array topology | 3×3 systolic grid | identical | identical |
| Control FSM | identical `IDLE→CLEAR→RUN→DONE` | identical | identical |
| Skew-feed schedule / `T_MAX` | 8 cycles | 8 cycles | 8 cycles |
| System boundary format | int8 in/out | int8 in/out (native) | int8 in/out |
| Accumulation policy | exact, wide, rounds once at output | exact (INT32), saturates once at output | rounds every accumulate step (real FP32 add), rounds once more at output |

The accumulation *policy* differs deliberately per format - each was
chosen to match how that format is actually built in real hardware
(see each `rtl_*/` README-style header comments), not arbitrarily:
Posit8 and INT8 can both accumulate exactly in a wide register with no
per-step rounding; FP16 cannot (its accumulator, FP32, has a bounded
significand, so summing values of different magnitude genuinely
requires rounding at each step) - matching why real mixed-precision
hardware (e.g. Tensor Cores) works this way. This is documented
explicitly so a reader can judge whether it's a fair comparison point
rather than an unstated design choice.

## 3. Accuracy methodology

See `benchmark/ACCURACY_REPORT.md` for full detail. Summary:
float64 reference, SQNR (dB) as the primary metric (standard in the
posit/quantization literature), two separate experiments to avoid
conflating "arithmetic precision" with "output-width saturation":
(A) native/unclamped precision vs. magnitude sweep, (B) full
system-level pipeline (int8 output) at realistic vs. large magnitude.

## 4. Hardware benchmarking methodology

- **Utilization**: post-*implementation* (placed), not post-synthesis.
- **Fmax**: binary-search clock-period sweep (`vivado_scripts/fmax_binary_search.tcl`),
  not a single guessed period - converges to within 0.1 ns.
- **Power**: SAIF-based (real switching activity from simulating the
  same representative test set used for functional verification),
  reported alongside a vectorless baseline for comparison
  (`vivado_scripts/power_saif_flow.tcl`).
- **Target part**: identical across all three variants (fill in once
  chosen - Zynq-7020 is a reasonable default given the FPGA-AI
  research context this project sits in).
- **Latency/throughput**: derived analytically (`T_MAX` cycles ×
  measured period), not simulated separately, since it follows
  directly from Fmax once measured.

## 5. Verification status

All RTL is verified bit-for-bit against Python/NumPy golden models
before any hardware benchmarking - see each variant's testbenches
(`tb/`, `tb_int8/`, `tb_fp16/`) for exact coverage (ranges from
exhaustive 65536-case sweeps for the multipliers to thousands of
randomized + directed cases for full end-to-end matrix multiplies).
This matters for the benchmark's validity: hardware numbers from a
functionally-incorrect design would be meaningless.

## 6. Known scope limitations (stated explicitly, not hidden)

- No NaR/Inf/NaN propagation (Posit8 NaR, FP16 Inf/NaN both treated as
  zero) and no subnormal support (FTZ) - consistent simplification
  across formats, documented in each module's header.
- INT8's output is plain int8 (no per-tensor quantization scale/
  zero-point) - a full quantized-NN INT8 pipeline is a natural
  extension, out of scope here for consistency with the other two
  variants' plain-integer boundary.
- Accuracy benchmark uses synthetic (uniform sweep) and Gaussian
  (realistic-proxy) data, not weights extracted from an actual trained
  model - noted as a natural next step if this becomes a larger project.
