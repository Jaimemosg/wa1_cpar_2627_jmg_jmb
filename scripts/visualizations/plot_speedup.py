#!/usr/bin/env python3
"""Plot speedup vs threads (linear axes) from the run_a_scaling.sh results.

Reads the wall time ("seconds time elapsed") from
    <results>/t<threads>/metric_N<N>.txt
for every thread count found at the chosen N, computes S = T1 / Tp and
plots it against the ideal S = p.

Usage (from the wa1_jj/ folder):
    python3 scripts/visualizations/plot_speedup.py
    python3 scripts/visualizations/plot_speedup.py --particles 1600 \
        --results results/deucalion/md_a_scaling --output report/images/speedup_N1600.png
"""
import argparse
import re
from pathlib import Path

import matplotlib.pyplot as plt

# perf line:   0.465253 +- 0.000698 seconds time elapsed  ( +-  0.15% )
ELAPSED_RE = re.compile(r"^\s*([\d.]+)\s+\+-\s+([\d.]+)\s+seconds time elapsed", re.M)


def read_times(results, particles):
    """Return {threads: (seconds, spread)} for every t*/metric_N<particles>.txt."""
    times = {}
    for f in results.glob(f"t*/metric_N{particles}.txt"):
        match = ELAPSED_RE.search(f.read_text())
        if match:
            threads = int(f.parent.name[1:])          # "t24" -> 24
            times[threads] = (float(match[1]), float(match[2]))
    return dict(sorted(times.items()))


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--particles", type=int, default=1600)
    parser.add_argument("--results", type=Path, default=Path("results/deucalion/md_a_scaling"))
    parser.add_argument("--output", type=Path, default=None,
                        help="PNG file (default: report/images/speedup_N<particles>.png)")
    args = parser.parse_args()
    output = args.output or Path(f"report/images/speedup_N{args.particles}.png")

    times = read_times(args.results, args.particles)
    if 1 not in times:
        raise SystemExit(f"No 1-thread result for N={args.particles} in {args.results}")

    threads = list(times)
    t1 = times[1][0]
    speedup = [t1 / times[p][0] for p in threads]

    print(f"{'threads':>7} {'seconds':>10} {'speedup':>8} {'efficiency':>10}")
    for p, s in zip(threads, speedup):
        print(f"{p:>7} {times[p][0]:>10.4f} {s:>8.2f} {s / p:>10.0%}")

    max_p = max(threads)
    fig, ax = plt.subplots(figsize=(6, 4.5))
    ax.plot([0, max_p], [0, max_p], "--", color="gray", label="Ideal $S = p$")
    ax.plot(threads, speedup, "o-", color="tab:blue", label="Measured $S = T_1 / T_p$")
    for p, s in zip(threads, speedup):
        if p >= 8:                                    # small p points are too crowded to label
            ax.annotate(f"{s:.1f}", (p, s), textcoords="offset points", xytext=(0, -14),
                        ha="center", fontsize=8)

    ax.set_xlabel("Threads")
    ax.set_ylabel("Speedup")
    ax.set_title(f"Version A speedup, N = {args.particles} (A64FX)")
    ax.set_xticks(threads)
    ax.set_xlim(0, max_p + 2)
    ax.set_ylim(0, max_p + 2)
    ax.grid(alpha=0.3)
    ax.legend()
    fig.tight_layout()

    output.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output, dpi=200)
    print(f"Saved {output}")


if __name__ == "__main__":
    main()
