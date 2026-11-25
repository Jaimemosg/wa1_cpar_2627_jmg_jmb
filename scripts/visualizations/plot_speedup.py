#!/usr/bin/env python3
"""Plot speedup vs threads (linear axes) from the run_<ver>_scaling.sh results.

Reads the wall time ("seconds time elapsed") from
    <results>/t<threads>/metric_N<N>.txt
for every thread count found at the chosen N, computes S = T1 / Tp and
plots it against the ideal S = p.

Usage (from the project root folder):
    python3 scripts/visualizations/plot_speedup.py
    python3 scripts/visualizations/plot_speedup.py --particles 1600 \
        --results results/deucalion/md_a_scaling --output report/images/speedup_N1600.png
    python3 scripts/visualizations/plot_speedup.py --particles 1600 \
        --results results/deucalion/md_c_scaling --output report/images/speedup_c_N1600.png
"""
import argparse
import re
from pathlib import Path

import matplotlib.pyplot as plt

# perf line:   0.465253 +- 0.000698 seconds time elapsed  ( +-  0.15% )
ELAPSED_RE = re.compile(r"^\s*([\d.]+)\s+\+-\s+([\d.]+)\s+seconds time elapsed", re.M)
VERSION_RE = re.compile(r"md_([a-zA-Z0-9]+)_scaling$")


def infer_version(results: Path):
    """Infer (label, suffix) from a results folder name such as md_c_scaling."""
    match = VERSION_RE.search(results.name)
    if match:
        ver = match.group(1).lower()
        suffix = "" if ver == "a" else f"_{ver}"
        return f"Version {ver.upper()}", suffix
    return results.name, f"_{results.name}"


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
    parser.add_argument("--particles", type=int, nargs="+", default=[1600],
                        help="One or more particle counts N to plot (e.g. --particles 1600 5000)")
    parser.add_argument("--results", type=Path, default=Path("results/deucalion/md_a_scaling"))
    parser.add_argument("--label", type=str, default=None,
                        help="Version label for the plot title (default: inferred from --results)")
    parser.add_argument("--output", type=Path, default=None,
                        help="PNG file (default: report/images/speedup[_<ver>]_N<N>[_N<N>...].png)")
    args = parser.parse_args()
    inferred_label, suffix = infer_version(args.results)
    label = args.label or inferred_label
    ns = args.particles
    n_tag = "_".join(f"N{n}" for n in ns)
    output = args.output or Path(f"report/images/speedup{suffix}_{n_tag}.png")

    series = []
    all_threads = set()
    for n in ns:
        times = read_times(args.results, n)
        if 1 not in times:
            raise SystemExit(f"No 1-thread result for N={n} in {args.results}")
        threads = list(times)
        t1 = times[1][0]
        speedup = [t1 / times[p][0] for p in threads]
        series.append((n, threads, times, speedup))
        all_threads.update(threads)

        print(f"=== {label}, N = {n} ===")
        print(f"{'threads':>7} {'seconds':>10} {'speedup':>8} {'efficiency':>10}")
        for p, s in zip(threads, speedup):
            print(f"{p:>7} {times[p][0]:>10.4f} {s:>8.2f} {s / p:>10.0%}")

    all_threads = sorted(all_threads)
    max_p = max(all_threads)
    colors = ["tab:blue", "tab:orange", "tab:green", "tab:red"]
    markers = ["o-", "s-", "^-", "D-"]

    fig, ax = plt.subplots(figsize=(6, 4.5))
    ax.plot([0, max_p], [0, max_p], "--", color="gray", label="Ideal $S = p$")

    multi = len(series) > 1
    for idx, (n, threads, times, speedup) in enumerate(series):
        color = colors[idx % len(colors)]
        marker = markers[idx % len(markers)]
        curve_label = f"Measured, $N = {n}$" if multi else "Measured $S = T_1 / T_p$"
        ax.plot(threads, speedup, marker, color=color, label=curve_label)

        for p, s in zip(threads, speedup):
            if not multi:
                if p >= 8:                            # small p points are too crowded to label
                    ax.annotate(f"{s:.1f}", (p, s), textcoords="offset points", xytext=(0, -14),
                                ha="center", fontsize=8)
            else:
                if p >= 16:
                    # Place lower curve labels below and higher curve labels above-left
                    if idx == 0:
                        xytext, va = (0, -13), "top"
                    else:
                        xytext = (0, 8) if p == max_p else (-6, 7)
                        va = "bottom"
                    ax.annotate(
                        f"{s:.1f}", (p, s), textcoords="offset points", xytext=xytext,
                        ha="center", va=va, fontsize=8, color=color,
                        bbox=dict(boxstyle="round,pad=0.1", fc="white", ec="none", alpha=0.7),
                    )

    ax.set_xlabel("Threads")
    ax.set_ylabel("Speedup")
    if multi:
        ax.set_title(f"{label} speedup (A64FX)")
    else:
        ax.set_title(f"{label} speedup, N = {ns[0]} (A64FX)")
    ax.set_xticks(all_threads)
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
