"""
Accuracy benchmark: Posit8 vs INT8 vs FP16 systolic-array matrix
multiplication, each simulated to match its RTL implementation
bit-for-bit, compared against a float64 reference.

Two DELIBERATELY SEPARATE experiments (conflating these is a common
mistake in less careful format comparisons):

  EXPERIMENT A - "Native arithmetic precision": inputs are quantized to
  int8 (all 3 accelerators take int8 input, so this step is identical
  and fair across formats), but the comparison uses each format's
  NATIVE, unclamped internal result (Posit8's decoded real value,
  INT8's full un-saturated int32 accumulator, FP16's decoded real
  value) against the exact int8 dot product. This isolates each
  format's intrinsic accumulation/rounding behavior with no shared
  output-width bottleneck - this is what a numeric-format comparison
  in the literature (e.g. Gustafson, "Deep Positron") actually
  measures.

  EXPERIMENT B - "System-level, as-deployed": the FULL RTL pipeline
  including the final round-down to an 8-bit int8 OUTPUT (since that
  is genuinely this project's chosen system boundary format). At large
  input magnitudes this experiment is dominated by output SATURATION
  rather than arithmetic precision - itself a real, worth-reporting
  finding (see the "why do INT8 and FP16 look identical at large
  magnitude" note in the generated report) - so it's run at magnitudes
  representative of realistic use (small-integer weight/activation-like
  data) where the output format doesn't saturate on nearly every
  sample.

Metrics: MAE, RMSE, Max Absolute Error, and SQNR (Signal-to-Quantization-
Noise Ratio, dB) - the standard metric in the posit/quantization
literature.
"""
import numpy as np
import math
import json
import sys
sys.path.insert(0, '.')
from golden_posit8 import decode as p8_decode, encode as p8_encode

N = 3  # matches the 3x3 systolic array's accumulation depth

# ---------------------------------------------------------------------------
# Per-format simulated pipelines - each matches its RTL bit-for-bit.
# Each returns (native_value, int8_output_value).
# ---------------------------------------------------------------------------

def quantize_int8(x):
    r = math.floor(abs(x) + 0.5) * (1 if x >= 0 else -1)
    return max(-128, min(127, int(r)))

def dot_posit8(a_int8, b_int8):
    s = 0.0
    for a, b in zip(a_int8, b_int8):
        pa = p8_encode(float(a)); pb = p8_encode(float(b))
        s += p8_decode(pa) * p8_decode(pb)
    p_sum = p8_encode(s)
    native = p8_decode(p_sum)
    native = 0.0 if native != native else native
    return native, quantize_int8(native)

def dot_int8(a_int8, b_int8):
    s = sum(int(a) * int(b) for a, b in zip(a_int8, b_int8))  # exact int32, unclamped
    native = float(s)
    return native, max(-128, min(127, s))

def dot_fp16(a_int8, b_int8):
    acc = np.float32(0.0)
    for a, b in zip(a_int8, b_int8):
        a16 = np.float16(float(a)); b16 = np.float16(float(b))
        prod32 = np.float32(a16) * np.float32(b16)
        acc = np.float32(acc) + np.float32(prod32)
    result16 = np.float16(acc)
    native = float(result16)
    return native, quantize_int8(native)

def dot_exact(a_vals, b_vals):
    return float(sum(float(a) * float(b) for a, b in zip(a_vals, b_vals)))

FORMATS = {'Posit8': dot_posit8, 'INT8': dot_int8, 'FP16': dot_fp16}

# ---------------------------------------------------------------------------
# Metrics
# ---------------------------------------------------------------------------

def compute_metrics(errors, signal_vals):
    errors = np.array(errors, dtype=np.float64)
    signal_vals = np.array(signal_vals, dtype=np.float64)
    mae = float(np.mean(np.abs(errors)))
    rmse = float(np.sqrt(np.mean(errors**2)))
    max_err = float(np.max(np.abs(errors)))
    signal_power = float(np.mean(signal_vals**2))
    noise_power = float(np.mean(errors**2))
    sqnr_db = float('inf') if noise_power == 0 or signal_power == 0 \
              else 10 * math.log10(signal_power / noise_power)
    return dict(mae=mae, rmse=rmse, max_err=max_err, sqnr_db=sqnr_db)

# ---------------------------------------------------------------------------
# EXPERIMENT A: native-precision magnitude sweep
# ---------------------------------------------------------------------------

def run_native_sweep(magnitudes, trials_per_magnitude=500, seed=0):
    rng = np.random.default_rng(seed)
    results = {fmt: {'sqnr': [], 'mae': []} for fmt in FORMATS}

    for M in magnitudes:
        errs = {fmt: [] for fmt in FORMATS}
        sig = []
        for _ in range(trials_per_magnitude):
            a_real = rng.uniform(-M, M, size=N)
            b_real = rng.uniform(-M, M, size=N)
            a_i8 = [quantize_int8(x) for x in a_real]
            b_i8 = [quantize_int8(x) for x in b_real]
            ref = dot_exact(a_i8, b_i8)  # exact int8 dot product - the reference for "arithmetic accuracy"
            sig.append(ref)
            for fmt, fn in FORMATS.items():
                native, _ = fn(a_i8, b_i8)
                errs[fmt].append(native - ref)
        for fmt in FORMATS:
            m = compute_metrics(errs[fmt], sig)
            results[fmt]['sqnr'].append(m['sqnr_db'])
            results[fmt]['mae'].append(m['mae'])
    return results

# ---------------------------------------------------------------------------
# EXPERIMENT B: system-level (int8 output), realistic magnitude
# ---------------------------------------------------------------------------

def run_system_level(sigma, num_trials=5000, seed=1):
    rng = np.random.default_rng(seed)
    errs = {fmt: [] for fmt in FORMATS}
    sig = []
    for _ in range(num_trials):
        a_real = rng.normal(0, sigma, size=N)
        b_real = rng.normal(0, sigma, size=N)
        a_i8 = [quantize_int8(x) for x in a_real]
        b_i8 = [quantize_int8(x) for x in b_real]
        ref = dot_exact(a_real, b_real)  # true real-valued reference (end-to-end)
        sig.append(ref)
        for fmt, fn in FORMATS.items():
            _, out8 = fn(a_i8, b_i8)
            errs[fmt].append(out8 - ref)
    return {fmt: compute_metrics(errs[fmt], sig) for fmt in FORMATS}

if __name__ == "__main__":
    print("=== Experiment A: native arithmetic precision, magnitude sweep ===")
    magnitudes = [1, 2, 4, 8, 16, 32, 64, 100, 127]
    sweep = run_native_sweep(magnitudes)
    for fmt in FORMATS:
        print(f"  {fmt}:")
        for M, sq in zip(magnitudes, sweep[fmt]['sqnr']):
            print(f"    |value|<={M:4d}: SQNR={sq:7.2f} dB")

    print("\n=== Experiment B: system-level, realistic small-magnitude data (sigma=5) ===")
    sysA = run_system_level(sigma=5.0)
    for fmt in FORMATS:
        m = sysA[fmt]
        print(f"  {fmt:8s}: SQNR={m['sqnr_db']:7.2f} dB   MAE={m['mae']:.4f}   RMSE={m['rmse']:.4f}   MaxErr={m['max_err']:.1f}")

    print("\n=== Experiment B: system-level, large-magnitude data (sigma=40, demonstrates output saturation dominance) ===")
    sysB = run_system_level(sigma=40.0)
    for fmt in FORMATS:
        m = sysB[fmt]
        print(f"  {fmt:8s}: SQNR={m['sqnr_db']:7.2f} dB   MAE={m['mae']:.4f}   RMSE={m['rmse']:.4f}   MaxErr={m['max_err']:.1f}")

    with open('sweep_results.json', 'w') as f:
        json.dump({'magnitudes': magnitudes, 'results': sweep}, f, indent=2)
    with open('system_level_results.json', 'w') as f:
        json.dump({'sigma5': sysA, 'sigma40': sysB}, f, indent=2)

    print("\nSaved sweep_results.json / system_level_results.json")
