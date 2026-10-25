"""Plot the CI capture's frame times and memory into one PNG.

usage: python tool/plot_perf.py OUT_DIR LABEL
reads OUT_DIR/{frames,rss,markers}.csv written by lib/ci/capture_io.dart, writes OUT_DIR/perf_LABEL.png
"""
import csv
import sys

import matplotlib

matplotlib.use('Agg')
import matplotlib.pyplot as plt  # noqa: E402

out, label = sys.argv[1], sys.argv[2]


def read(name):
    with open(f'{out}/{name}.csv', newline='', encoding='utf-8') as f:
        return list(csv.DictReader(f))


frames, rss, markers = read('frames'), read('rss'), read('markers')
ft = [float(r['t_ms']) / 1000 for r in frames]
build = [float(r['build_ms']) for r in frames]
raster = [float(r['raster_ms']) for r in frames]
rt = [float(r['t_ms']) / 1000 for r in rss]
mb = [float(r['rss_mb']) for r in rss]

fig, (a1, a2) = plt.subplots(2, 1, figsize=(12, 7), sharex=True, constrained_layout=True)
a1.plot(ft, raster, lw=0.8, color='#3482ff', label='raster (GPU thread)')
a1.plot(ft, build, lw=0.8, color='#f08c00', label='build (UI thread)')
a1.axhline(1000 / 60, color='#888', ls='--', lw=0.8, label='16.7 ms (60 fps)')
a1.set_ylabel('frame time (ms)')
a1.set_ylim(0, max(40, min(120, max(raster + build + [0]) * 1.1)))
a1.legend(loc='upper right', fontsize=8)
a2.plot(rt, mb, color='#2f9e44')
a2.set_ylabel('process RSS (MB)')
a2.set_xlabel('time (s)')
a2.set_ylim(0, max(mb + [1]) * 1.15)
for m in markers:
    if m['label'].startswith('shot'):
        continue
    x = float(m['t_ms']) / 1000
    for ax in (a1, a2):
        ax.axvline(x, color='#ccc', lw=0.6)
    a2.text(x, a2.get_ylim()[1] * 0.97, m['label'], fontsize=7, rotation=90, va='top', ha='right', color='#666')
n = len(build)
over = sum(1 for b, r in zip(build, raster) if max(b, r) > 1000 / 60)
fig.suptitle(f'mi-glass-flutter-demo on {label}: {n} frames, {over} over 16.7 ms, peak RSS {max(mb + [0]):.0f} MB')
fig.savefig(f'{out}/perf_{label}.png', dpi=110)
print(f'{label}: frames={n} over16ms={over} peakRSS={max(mb + [0]):.0f}MB')
