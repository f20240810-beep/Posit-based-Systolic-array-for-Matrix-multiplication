# 3x3 Posit(8,0) Systolic Array for Matrix Multiplication

A structural, bottom-up Verilog implementation of a 3x3 systolic array that
performs matrix multiplication entirely in Posit(8,0) arithmetic. Every PE
operates directly on 8-bit Posit bit patterns; conversion to/from plain
integers happens only at the system boundary (encoder in, decoder out).

Target: Xilinx Vivado (behavioral simulation + synthesis). All RTL compiles
cleanly under strict Verilog-2005 (verified with Icarus Verilog `-g2005`),
so no SystemVerilog file-type setting is required in Vivado.

---

## 1. Architecture

```
  int8 matrices A, B
        |
        v
  ================================================================
  |  posit_systolic_top.v                                        |
  |                                                                |
  |   [int8_to_posit8 x 9]   [int8_to_posit8 x 9]                 |
  |         (encode A)            (encode B)                      |
  |              |                    |                           |
  |              v                    v                           |
  |        skew-feed FSM (drives the array's edges in the         |
  |        correct systolic schedule - see Sec. 3)                |
  |              |                    |                           |
  |              v                    v                           |
  |   ==========================================================  |
  |   |  systolic_array.v  (pure Posit8 bit patterns in/out)    |  |
  |   |                                                          | |
  |   |   PE(0,0) -- PE(0,1) -- PE(0,2)                          | |
  |   |     |          |          |                              | |
  |   |   PE(1,0) -- PE(1,1) -- PE(1,2)                          | |
  |   |     |          |          |                              | |
  |   |   PE(2,0) -- PE(2,1) -- PE(2,2)                          | |
  |   |                                                          | |
  |   |   each PE = posit8_multiplier + fixed_accumulator        | |
  |   |             + fixed_to_posit8                            | |
  |   ==========================================================  |
  |              |                                                |
  |              v                                                |
  |        [posit8_to_int8 x 9]  (decode C)                       |
  ================================================================
        |
        v
  int8 matrix C = A x B
```

The array itself (`systolic_array.v`, `pe.v`) never touches an integer or a
float - it only ever sees 8-bit Posit bit patterns. All conversion lives in
`int8_to_posit8.v` / `posit8_to_int8.v`, instantiated only in
`posit_systolic_top.v`, outside the array - exactly matching the requested
architecture.

## 2. Why a wide fixed-point accumulator

Rounding a Posit result after *every* multiply and *every* add would
compound error at each of the 3 accumulation steps per PE. Instead:

- `posit8_multiplier.v` unpacks both Posit8 operands and produces an
  **exact** signed fixed-point product (Q24.24 by default, i.e. a 48-bit
  register with 24 fractional bits) - no rounding, ever, at this stage.
- `fixed_accumulator.v` is a plain exact integer adder/register - it just
  sums these exact fixed-point products cycle by cycle.
- `fixed_to_posit8.v` converts the final accumulated sum back to Posit8
  **once**, at read-out time. This is the *only* place in the entire
  datapath that performs rounding (round-to-nearest-even, saturating at
  +/-maxpos=64, flushing to zero below the representable range).

`posit8_pack.v` is the shared rounding/encoding core used both here and by
`int8_to_posit8.v` - there is exactly one rounding implementation in the
whole design, reused everywhere rounding is needed.

## 3. Systolic feeding schedule

To compute `C[i][j] = sum_k A[i][k]*B[k][j]`, activations for row `i` must
enter the array's left edge starting at cycle `i` (one element per cycle),
and weights for column `j` must enter the top edge starting at cycle `j`.
This way `A[i][k]` and `B[k][j]` always arrive at `PE(i,j)` on the same
cycle (`i+j+k`), for `k = 0,1,2` on three consecutive cycles.
`posit_systolic_top.v`'s FSM generates this schedule automatically from a
plain (non-skewed) input matrix - the caller never has to think about
skewing.

Total latency: `T_MAX = 3*(N-1) + 2` cycles from `start` to `done` (8
cycles for N=3): `clear` (1 cycle) + skewed feed window (7 cycles for
N=3, covering `i+j+k` up to `2+2+2=6` plus 1 margin cycle).

## 4. File listing

### `rtl/` - synthesizable design, bottom-up
| File | Role |
|---|---|
| `posit8_unpack.v` | Leaf: Posit8 bits -> {sign, regime k, 6-bit significand}. Priority-casez regime decoder. |
| `posit8_pack.v` | Leaf: {sign, k, significand} -> Posit8 bits. Round-to-nearest-even, saturating. The **only** rounding logic in the design. |
| `int8_to_posit8.v` | Boundary encoder: signed int8 -> Posit8. |
| `posit8_to_int8.v` | Boundary decoder: Posit8 -> signed int8 (round-half-away-from-zero, saturating). |
| `posit8_multiplier.v` | Posit8 x Posit8 -> exact wide fixed-point product (no rounding). |
| `fixed_accumulator.v` | Exact fixed-point adder/register. |
| `fixed_to_posit8.v` | Wide fixed-point -> Posit8 (normalizes, then calls `posit8_pack`). |
| `pe.v` | Processing Element: multiplier + accumulator + f2p + systolic skew registers. |
| `systolic_array.v` | Parameterized N x N (default 3x3) structural grid of `pe` instances. Pure wiring, no arithmetic. |
| `posit_systolic_top.v` | Full system: encoders + skew-feed FSM + array + decoders. |

### `tb/` - testbenches (self-checking, compare against a Python golden model)
| File | Checks | Coverage |
|---|---|---|
| `tb_unpack_pack_roundtrip.v` | unpack -> pack round-trips to the same bits | all 255 non-NaR patterns |
| `tb_int_posit_codec.v` | `int8_to_posit8` / `posit8_to_int8` | all 256 integers, all 256 patterns |
| `tb_multiplier.v` | `posit8_multiplier`'s exact fixed-point product | all 256x256 = 65536 operand pairs |
| `tb_dotproduct_chain.v` | multiplier -> accumulate -> `fixed_to_posit8`, incl. saturation/tie edge cases | 4006 directed + randomized cases |
| `tb_pe.v` | clocked PE (skew registers + accumulator + rounding) | same 4006 cases, fully clocked, VCD dump |
| `tb_systolic_array.v` | full 3x3 array with correctly skewed feeding | 20 full matrix-multiply cases, VCD dump |
| `tb_posit_systolic_top.v` | end-to-end: plain int matrices in -> plain int matrix out | 26 cases incl. saturation/identity/zero, VCD dump |

Each `tb_*.v` is paired with `golden_*.hex` file(s) it reads via
`$readmemh` - keep these alongside the testbenches (add them as
simulation-only data files in Vivado, not as HDL sources).

### `python_reference_model/golden.py`
The Python model used to derive the Posit(8,0) bit-field tables and
generate every `golden_*.hex` vector file. Not required for
synthesis/simulation - included for reference/extension (e.g. if you want
to regenerate vectors for a wider test sweep).

## 5. Running in Vivado

1. Create a new RTL project, add every file in `rtl/` as a design source.
2. Add every file in `tb/*.v` as **simulation** sources, and every
   `tb/golden_*.hex` as a simulation data file (Add Sources -> Add or
   Create Simulation Sources; make sure the `.hex` files end up in the
   simulation working directory - or edit the `$readmemh(...)` paths to
   an absolute path if Vivado's working directory differs).
3. Set the desired `tb_*.v` as the simulation top (e.g.
   `tb_posit_systolic_top` for the full end-to-end run).
4. Run Behavioral Simulation. Each testbench prints a single `PASS:` /
   `FAIL:` line to the Tcl console. `tb_pe`, `tb_systolic_array`, and
   `tb_posit_systolic_top` also call `$dumpvars`, and Vivado's own
   waveform viewer will show every signal in the DUT hierarchy
   (activations/weights skewing across the array, each PE's accumulator
   converging, `done` pulsing) - just add the signals of interest from
   the Scope pane.
5. For synthesis, `posit_systolic_top` is the top-level module. Default
   parameters give a 3x3 array; override `N` (and `T_MAX`, which is
   derived from `N` automatically) to resize.

## 6. Verified precision behavior (examples)

- `1 x 1 + 1 x 1 + 1 x 1 = 3` exactly.
- Products/sums that exceed Posit(8,0)'s range (+/-64) saturate to
  +/-maxpos rather than wrapping.
- Exact ties (e.g. a dot product landing exactly halfway between two
  representable Posit8 values) round to the nearer *even* bit pattern,
  verified down to the regime boundary edge cases (e.g. exactly between
  minPos and 2*minPos).

## 7. Known, documented simplifications

- **NaR (Not-a-Real)** is not propagated through the datapath - any NaR
  input to the multiplier or decoder is treated as zero. Full NaR
  semantics (infinity-like propagation) were considered out of scope for
  this systolic-array demo; flag this explicitly if your project needs
  it.
- **Deep underflow flush-to-zero**: `posit8_pack.v` flushes to exact zero
  for any value whose true regime would need `k < -6` (i.e. magnitudes
  far below minPos, specifically below half of minPos where 0 truly is
  the nearest representable value in most cases, and even closer values
  in the rare remaining cases) - this only matters for the fixed-point
  accumulator path (`fixed_to_posit8.v`), since Posit8's own regime range
  is naturally +-6, so this path is already the correct nearest-value
  behavior in the region it's ever actually exercised. Documented here
  for completeness in case `ACC_WIDTH`/`FRAC` are changed.
- `int8_to_posit8` / `posit8_to_int8` were chosen (per project scope) as
  the boundary format instead of IEEE-754 float, to keep the testbenches
  simple; swapping in a float32<->Posit8 converter would only require
  replacing these two boundary modules - the array and PE are unaffected
  either way.

## 8. Parameters

| Parameter | Default | Meaning |
|---|---|---|
| `N` | 3 | Array dimension (N x N). |
| `ACC_WIDTH` | 48 | Accumulator width in bits. |
| `FRAC` | 24 | Accumulator fractional bits. Chosen so the multiplier's shift-into-accumulator is always a left shift (always exact) across Posit(8,0)'s full regime range. |
| `T_MAX` | `3*(N-1)+2` | Cycles from `start` to `done` (derived automatically from `N`). |
