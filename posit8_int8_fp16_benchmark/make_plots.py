import json
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

with open('sweep_results.json') as f:
    sweep = json.load(f)
with open('system_level_results.json') as f:
    syslevel = json.load(f)

magnitudes = sweep['magnitudes']
results = sweep['results']

# Plot 1: SQNR vs magnitude (the headline plot)
fig, ax = plt.subplots(figsize=(8, 5.5))
colors = {'Posit8': '#2E86AB', 'INT8': '#A23B72', 'FP16': '#F18F01'}
markers = {'Posit8': 'o', 'INT8': 's', 'FP16': '^'}

for fmt in ['Posit8', 'INT8', 'FP16']:
    sqnr = results[fmt]['sqnr']
    # cap 'inf' for plotting purposes at 100 dB with a visual marker
    plot_vals = [min(v, 100) if v != float('inf') else 100 for v in sqnr]
    ax.plot(magnitudes, plot_vals, marker=markers[fmt], color=colors[fmt],
            label=fmt, linewidth=2, markersize=7)

ax.set_xscale('log')
ax.set_xlabel('Input value magnitude bound (|a|,|b| <= M)', fontsize=11)
ax.set_ylabel('SQNR (dB), capped at 100 for display', fontsize=11)
ax.set_title('Native arithmetic precision vs. value magnitude\n(3-term dot product, int8 inputs, no output-format bottleneck)', fontsize=11)
ax.legend(fontsize=11)
ax.grid(True, alpha=0.3)
ax.axhline(100, color='gray', linestyle=':', linewidth=0.8, alpha=0.5)
ax.text(1.2, 101, 'exact (SQNR = inf)', fontsize=8, color='gray')
plt.tight_layout()
plt.savefig('plot_sqnr_vs_magnitude.png', dpi=150)
plt.close()

# Plot 2: system-level bar chart
fig, ax = plt.subplots(figsize=(7, 5))
formats = ['Posit8', 'INT8', 'FP16']
x = np.arange(len(formats))
width = 0.35

sqnr_small = [syslevel['sigma5'][f]['sqnr_db'] for f in formats]
sqnr_large = [syslevel['sigma40'][f]['sqnr_db'] for f in formats]

ax.bar(x - width/2, sqnr_small, width, label='Realistic magnitude (sigma=5)', color='#2E86AB')
ax.bar(x + width/2, sqnr_large, width, label='Large magnitude (sigma=40)', color='#A23B72')
ax.set_xticks(x)
ax.set_xticklabels(formats, fontsize=11)
ax.set_ylabel('SQNR (dB)', fontsize=11)
ax.set_title('System-level accuracy (full pipeline, int8 output)\nOutput saturation dominates at large magnitude for all formats', fontsize=10)
ax.legend(fontsize=9)
ax.grid(True, alpha=0.3, axis='y')
plt.tight_layout()
plt.savefig('plot_system_level.png', dpi=150)
plt.close()

print("Plots saved.")
