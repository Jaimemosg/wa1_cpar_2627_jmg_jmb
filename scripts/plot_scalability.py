#!/usr/bin/env python3
"""
Parse `perf stat` metric files from `results/` and plot strong scalability
(Speedup vs. # of OpenMP Threads), following 08PC_OptSharedMem.pdf (pp. 7-8).

Expected directory layout:
    results/
    ├── md_baseline/
    │   └── metric_N<PARTICLES>.txt          # Sequential baseline (OPENMP=0)
    ├── md_a/
    │   ├── T1/metric_N<PARTICLES>.txt       # Parallel runs (OPENMP=1)
    │   ├── T2/metric_N<PARTICLES>.txt
    │   └── ...
    └── md_b/
        ├── T1/metric_N<PARTICLES>.txt
        └── ...

Speedup definition (strong scalability):
    S(p) = T_seq / T_par(p)
where T_seq and T_par(p) are the wall-clock `seconds time elapsed` reported by
`perf stat` (not `task-clock`, which sums CPU time across threads).

Example usage:
    python3 scripts/plot_scalability.py --particles 5000
    python3 scripts/plot_scalability.py -N 5000 --versions md_a md_b --output results/speedup_N5000.png
    python3 scripts/plot_scalability.py -N 5000 --no-plot --csv results/speedup_N5000.csv
"""

from __future__ import annotations

import argparse
import csv
import math
import re
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple


# Matches both repeated and single-run `perf stat` wall-clock lines:
#   0.041405894 +- 0.001943348 seconds time elapsed  ( +-  4.69% )
#   0.041405894 seconds time elapsed
ELAPSED_RE = re.compile(
    r"([0-9][0-9,\.]*)\s*(?:\+-\s*([0-9][0-9,\.]*)\s*)?seconds\s+time\s+elapsed"
)
THREAD_DIR_RE = re.compile(r"^[Tt](\d+)$")
METRIC_FILE_RE = re.compile(r"^metric_N(\d+)\.txt$")


def parse_elapsed_seconds(metric_file: Path) -> Tuple[float, float]:
    """Return (mean_seconds, std_seconds) from a `perf stat` metric file."""
    text = metric_file.read_text(encoding="utf-8", errors="replace")
    match = ELAPSED_RE.search(text)
    if not match:
        raise ValueError(f"Could not find 'seconds time elapsed' in {metric_file}")

    mean = float(match.group(1).replace(",", ""))
    std = float(match.group(2).replace(",", "")) if match.group(2) else 0.0
    return mean, std


def detect_particles(baseline_dir: Path) -> int:
    """Auto-detect particle count from `metric_N*.txt` inside the baseline dir."""
    candidates: List[int] = []
    if baseline_dir.is_dir():
        for entry in baseline_dir.iterdir():
            m = METRIC_FILE_RE.match(entry.name)
            if m:
                candidates.append(int(m.group(1)))
    if not candidates:
        raise FileNotFoundError(
            f"No metric_N<PARTICLES>.txt found in {baseline_dir}. "
            "Pass --particles explicitly."
        )
    return max(candidates)


def discover_versions(
    results_dir: Path, baseline_name: str, particles: int
) -> List[str]:
    """Find subdirectories under results_dir that contain T*/metric_N<particles>.txt."""
    versions: List[str] = []
    metric_name = f"metric_N{particles}.txt"
    for entry in sorted(results_dir.iterdir()):
        if not entry.is_dir() or entry.name == baseline_name:
            continue
        has_thread_data = any(
            sub.is_dir()
            and THREAD_DIR_RE.match(sub.name)
            and (sub / metric_name).is_file()
            for sub in entry.iterdir()
        )
        if has_thread_data:
            versions.append(entry.name)
    return versions


def collect_version_data(
    version_dir: Path, particles: int
) -> Dict[int, Tuple[float, float]]:
    """Return {threads: (mean_s, std_s)} for a given parallel version directory."""
    data: Dict[int, Tuple[float, float]] = {}
    metric_name = f"metric_N{particles}.txt"

    if not version_dir.is_dir():
        return data

    for sub in version_dir.iterdir():
        if not sub.is_dir():
            continue
        m = THREAD_DIR_RE.match(sub.name)
        if not m:
            continue
        metric_file = sub / metric_name
        if not metric_file.is_file():
            continue
        threads = int(m.group(1))
        data[threads] = parse_elapsed_seconds(metric_file)

    return dict(sorted(data.items()))


def compute_speedup(
    t_seq: float, std_seq: float, t_par: float, std_par: float
) -> Tuple[float, float]:
    """Compute speedup S = T_seq / T_par and propagated uncertainty."""
    speedup = t_seq / t_par
    rel_seq = (std_seq / t_seq) if t_seq > 0 else 0.0
    rel_par = (std_par / t_par) if t_par > 0 else 0.0
    std_speedup = speedup * math.sqrt(rel_seq**2 + rel_par**2)
    return speedup, std_speedup


def print_summary_table(
    baseline_name: str,
    t_seq: float,
    std_seq: float,
    results: Dict[str, Dict[int, Tuple[float, float]]],
) -> List[Dict[str, object]]:
    """Print a formatted table of times, speedups, and efficiencies; return rows."""
    rows: List[Dict[str, object]] = []

    print(
        f"\nSequential baseline ({baseline_name}): "
        f"{t_seq:.6f} +- {std_seq:.6f} s\n"
    )
    header = (
        f"{'Version':<14} {'Threads':>7} {'Time (s)':>12} "
        f"{'+- Std (s)':>11} {'Speedup':>9} {'+- Std':>8} {'Eff (%)':>9}"
    )
    print(header)
    print("-" * len(header))

    for version, thread_map in results.items():
        for threads, (t_par, std_par) in thread_map.items():
            speedup, std_sp = compute_speedup(t_seq, std_seq, t_par, std_par)
            efficiency = 100.0 * speedup / threads
            print(
                f"{version:<14} {threads:>7d} {t_par:>12.6f} "
                f"{std_par:>11.6f} {speedup:>9.3f} {std_sp:>8.3f} {efficiency:>8.1f}%"
            )
            rows.append(
                {
                    "version": version,
                    "threads": threads,
                    "time_s": t_par,
                    "std_time_s": std_par,
                    "speedup": speedup,
                    "std_speedup": std_sp,
                    "efficiency_pct": efficiency,
                }
            )
    print()
    return rows


def write_csv(csv_path: Path, rows: List[Dict[str, object]]) -> None:
    """Export parsed scalability metrics to CSV."""
    csv_path.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = [
        "version",
        "threads",
        "time_s",
        "std_time_s",
        "speedup",
        "std_speedup",
        "efficiency_pct",
    ]
    with csv_path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)
    print(f"Saved CSV summary to {csv_path}")


def plot_speedup(
    results: Dict[str, Dict[int, Tuple[float, float]]],
    baseline_name: str,
    t_seq: float,
    std_seq: float,
    particles: int,
    max_pus: int,
    output_path: Path,
    show_error_bars: bool,
    show_window: bool,
) -> None:
    """Generate the Speedup vs # of Threads scalability plot."""
    try:
        import matplotlib.pyplot as plt
    except ModuleNotFoundError as exc:
        raise SystemExit(
            "Error: matplotlib is required to generate the plot.\n"
            "Install it with `pip install matplotlib` (or run with --no-plot "
            "to only print the table / export CSV)."
        ) from exc

    all_threads = sorted(
        {t for thread_map in results.values() for t in thread_map.keys()}
    )
    if not all_threads:
        raise SystemExit("No thread measurements found to plot.")

    fig, ax = plt.subplots(figsize=(8.5, 5.5))

    # Ideal speedup line (proportional to PUs, capped at physical PUs as in p.8)
    ideal_x = sorted(set(all_threads + ([max_pus] if max_pus < max(all_threads) else [])))
    ideal_y = [min(t, max_pus) for t in ideal_x]
    ax.plot(
        ideal_x,
        ideal_y,
        linestyle="--",
        color="black",
        linewidth=1.4,
        label=f"Ideal speedup (max {max_pus} PUs)",
        zorder=2,
    )

    markers = ["o", "s", "^", "D", "v", "P", "X"]
    max_speedup = 1.0

    for idx, (version, thread_map) in enumerate(results.items()):
        xs = list(thread_map.keys())
        ys: List[float] = []
        yerrs: List[float] = []
        for t in xs:
            t_par, std_par = thread_map[t]
            sp, std_sp = compute_speedup(t_seq, std_seq, t_par, std_par)
            ys.append(sp)
            yerrs.append(std_sp)
        if ys:
            max_speedup = max(max_speedup, max(ys))

        marker = markers[idx % len(markers)]
        if show_error_bars and any(e > 0 for e in yerrs):
            ax.errorbar(
                xs,
                ys,
                yerr=yerrs,
                marker=marker,
                linestyle="-",
                linewidth=1.8,
                markersize=6,
                capsize=3,
                label=version,
                zorder=3,
            )
        else:
            ax.plot(
                xs,
                ys,
                marker=marker,
                linestyle="-",
                linewidth=1.8,
                markersize=6,
                label=version,
                zorder=3,
            )

    ax.set_title(
        f"Strong Scalability: Speedup vs. OpenMP Threads "
        f"(N={particles}, baseline={baseline_name}: {t_seq:.3f}s)",
        fontsize=11,
        pad=12,
    )
    ax.set_xlabel("# of OpenMP Threads", fontsize=11)
    ax.set_ylabel("Speedup (gain over sequential baseline)", fontsize=11)

    ax.set_xticks(all_threads)
    ax.set_xlim(left=0, right=max(all_threads) * 1.05)
    ax.set_ylim(bottom=0, top=max(max(ideal_y), max_speedup) * 1.08)

    ax.grid(True, linestyle=":", alpha=0.65)
    ax.legend(frameon=True, loc="upper left")

    fig.tight_layout()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output_path, dpi=300)
    print(f"Saved scalability plot to {output_path}")

    if show_window:
        plt.show()


def parse_args(argv: Optional[List[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Parse perf stat results and plot Speedup vs. OpenMP threads."
    )
    parser.add_argument(
        "--results-dir",
        type=Path,
        default=Path("results"),
        help="Root results directory (default: results).",
    )
    parser.add_argument(
        "--baseline",
        default="md_baseline",
        help="Subfolder name for sequential baseline (default: md_baseline).",
    )
    parser.add_argument(
        "--versions",
        nargs="+",
        default=None,
        help="Parallel version folders to include (default: auto-discover).",
    )
    parser.add_argument(
        "-N",
        "--particles",
        type=int,
        default=None,
        help="Particle count N in metric_N<N>.txt (default: auto-detect from baseline).",
    )
    parser.add_argument(
        "--max-pus",
        type=int,
        default=48,
        help="Physical PUs for capping ideal speedup (default: 48 for Deucalion A64FX).",
    )
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=None,
        help="Output image path (default: results/scalability_N<N>.png).",
    )
    parser.add_argument(
        "--csv",
        type=Path,
        default=None,
        help="Optional path to export the summary table as CSV.",
    )
    parser.add_argument(
        "--no-error-bars",
        action="store_true",
        help="Disable propagated standard deviation error bars on the plot.",
    )
    parser.add_argument(
        "--no-plot",
        action="store_true",
        help="Print table (and optional CSV) without generating a matplotlib figure.",
    )
    parser.add_argument(
        "--show",
        action="store_true",
        help="Display the plot interactively in a window.",
    )
    return parser.parse_args(argv)


def main(argv: Optional[List[str]] = None) -> int:
    args = parse_args(argv)

    baseline_dir = args.results_dir / args.baseline
    particles = (
        args.particles if args.particles is not None else detect_particles(baseline_dir)
    )
    baseline_file = baseline_dir / f"metric_N{particles}.txt"
    if not baseline_file.is_file():
        print(f"Error: sequential baseline file not found: {baseline_file}", file=sys.stderr)
        return 1

    t_seq, std_seq = parse_elapsed_seconds(baseline_file)

    versions = (
        args.versions
        if args.versions is not None
        else discover_versions(args.results_dir, args.baseline, particles)
    )
    if not versions:
        print(
            f"Error: no parallel version folders with T*/metric_N{particles}.txt "
            f"found under {args.results_dir}.",
            file=sys.stderr,
        )
        return 1

    results: Dict[str, Dict[int, Tuple[float, float]]] = {}
    for version in versions:
        data = collect_version_data(args.results_dir / version, particles)
        if data:
            results[version] = data
        else:
            print(
                f"Warning: no T*/metric_N{particles}.txt files found for '{version}', skipping.",
                file=sys.stderr,
            )

    if not results:
        print("Error: no valid parallel measurements found.", file=sys.stderr)
        return 1

    rows = print_summary_table(args.baseline, t_seq, std_seq, results)

    if args.csv is not None:
        write_csv(args.csv, rows)

    if not args.no_plot:
        output_path = (
            args.output
            if args.output is not None
            else args.results_dir / f"scalability_N{particles}.png"
        )
        plot_speedup(
            results=results,
            baseline_name=args.baseline,
            t_seq=t_seq,
            std_seq=std_seq,
            particles=particles,
            max_pus=args.max_pus,
            output_path=output_path,
            show_error_bars=not args.no_error_bars,
            show_window=args.show,
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
