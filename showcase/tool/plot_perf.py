"""Curves and tables from the perf mode's CSV (lib/ci/shots.dart).

usage: python tool/plot_perf.py IN_DIR OUT_DIR [BASE_URL]
reads IN_DIR/perf_<label>.csv, one per platform (lines may carry a log prefix before "PERF,"),
writes OUT_DIR/curve_<label>.png, OUT_DIR/compare.png and OUT_DIR/README.md
"""
import glob
import os
import sys

import matplotlib

matplotlib.use('Agg')
import matplotlib.pyplot as plt  # noqa: E402

src, out = sys.argv[1], sys.argv[2]
base = sys.argv[3] if len(sys.argv) > 3 else ''
os.makedirs(out, exist_ok=True)
FIELDS = ['frames', 'fps', 'b50', 'b95', 'r50', 'r95', 'rmax', 'g50', 'g95', 'gmax', 'over', 'rss']


def load(path):
    run = {'meta': None, 'scenes': {}, 'frames': [], 'done': False}
    with open(path, encoding='utf-8', errors='replace') as f:
        for line in f:
            i = line.find('PERF,')
            if i < 0:
                continue
            p = line[i:].strip().split(',')
            if p[1] == 'M' and len(p) >= 8:
                run['meta'] = p[2:8]
            elif p[1] == 'S' and len(p) >= 15:
                run['scenes'][p[2]] = dict(zip(FIELDS, map(float, p[3:15])))
            elif p[1] == 'F' and len(p) >= 7:
                run['frames'].append((p[2], float(p[3]) / 1000, float(p[4]), float(p[5]), float(p[6])))
            elif p[1] == 'E':
                run['done'] = True
    return run


runs = {}
for path in sorted(glob.glob(os.path.join(src, '**', 'perf_*.csv'), recursive=True)):
    label = os.path.basename(path)[5:-4]
    run = load(path)
    if run['frames']:
        runs[label] = run

for label, run in runs.items():
    frames = run['frames']
    t = [f[1] for f in frames]
    fig, (a1, a2, a3) = plt.subplots(3, 1, figsize=(13, 8), sharex=True, constrained_layout=True, height_ratios=[3, 2, 1])
    a1.plot(t, [min(f[4], 120) for f in frames], lw=0.6, color='#3482ff', label='gap between frames')
    a1.axhline(1000 / 60, color='#888', ls='--', lw=0.7, label='16.7 ms')
    a1.axhline(33.4, color='#e8590c', ls='--', lw=0.7, label='33.4 ms')
    a1.set_ylabel('frame gap (ms, cut at 120)')
    a1.legend(loc='upper right', fontsize=8)
    a2.plot(t, [f[3] for f in frames], lw=0.6, color='#7048e8', label='raster')
    a2.plot(t, [f[2] for f in frames], lw=0.6, color='#f08c00', label='build')
    a2.set_ylabel('thread time (ms)')
    a2.legend(loc='upper right', fontsize=8)
    ends, rss = [], []
    start = {}
    for f in frames:
        start.setdefault(f[0], f[1])
    for name, s in start.items():
        a1.axvline(s, color='#ddd', lw=0.6)
        a2.axvline(s, color='#ddd', lw=0.6)
        a1.text(s, a1.get_ylim()[1] * 0.98, name, fontsize=7, rotation=90, va='top', color='#666')
        last = max(f[1] for f in frames if f[0] == name)
        ends.append(last)
        rss.append(run['scenes'].get(name, {}).get('rss', 0))
    a3.step(ends, rss, where='post', color='#2f9e44')
    a3.set_ylabel('RSS (MB)')
    a3.set_xlabel('time (s)')
    a3.set_ylim(0, max(rss + [1]) * 1.15)
    m = run['meta'] or ['?'] * 6
    fig.suptitle(f'{label}: {m[5]}, {m[1]} Hz, {m[2]}x{m[3]} @{m[4]}' + ('' if run['done'] else ' (run did not finish)'))
    fig.savefig(os.path.join(out, f'curve_{label}.png'), dpi=110)
    plt.close(fig)

scenes = []
for run in runs.values():
    scenes += [s for s in run['scenes'] if s not in scenes]
if runs:
    fig, axes = plt.subplots(2, 1, figsize=(13, 7), constrained_layout=True)
    width = 0.8 / len(runs)
    for i, (label, run) in enumerate(runs.items()):
        xs = [k + i * width for k in range(len(scenes))]
        axes[0].bar(xs, [run['scenes'].get(s, {}).get('g95', 0) for s in scenes], width, label=label)
        axes[1].bar(xs, [run['scenes'].get(s, {}).get('rss', 0) for s in scenes], width, label=label)
    for ax, title in zip(axes, ['frame gap p95 (ms), lower is better', 'RSS at the end of each scene (MB)']):
        ax.set_xticks([k + 0.4 - width / 2 for k in range(len(scenes))], scenes, rotation=20, ha='right', fontsize=8)
        ax.set_title(title, fontsize=10)
        ax.legend(fontsize=8)
    axes[0].axhline(1000 / 60, color='#888', ls='--', lw=0.7)
    fig.savefig(os.path.join(out, 'compare.png'), dpi=110)
    plt.close(fig)

md = ['# hyper_showcase performance', '']
md.append('CI runners have no real GPU unless noted: Windows and Linux render in software, the Android emulator uses '
          'SwiftShader and the iOS simulator runs a debug build. Read these for regressions, crashes and the relative '
          'weight of scenes, not as what a phone would do.')
md += ['', f'![compare]({base}compare.png)', '']
missing = [lb for lb, r in runs.items() if not r['done']]
if missing:
    md += [f'Did not finish: {", ".join(missing)}', '']
for label, run in runs.items():
    m = run['meta'] or ['?'] * 6
    md += [f'## {label}', '', f'{m[0]}, {m[5]}, {m[1]} Hz, {m[2]}x{m[3]} @{m[4]}', '']
    md += [f'![{label}]({base}curve_{label}.png)', '']
    md += ['| scene | frames | fps | gap p50 | gap p95 | gap max | >33 ms | raster p95 | RSS MB |', '|---|---|---|---|---|---|---|---|---|']
    for name, s in run['scenes'].items():
        md.append(f"| {name} | {s['frames']:.0f} | {s['fps']:.0f} | {s['g50']:.1f} | {s['g95']:.1f} | {s['gmax']:.1f} | "
                  f"{s['over']:.0f} | {s['r95']:.1f} | {s['rss']:.0f} |")
    md.append('')
if not runs:
    md.append('No platform produced data.')
with open(os.path.join(out, 'README.md'), 'w', encoding='utf-8') as f:
    f.write('\n'.join(md) + '\n')
print(', '.join(f"{k}: {len(v['frames'])} frames" for k, v in runs.items()) or 'no data')
