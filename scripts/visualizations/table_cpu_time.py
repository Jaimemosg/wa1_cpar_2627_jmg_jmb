#!/usr/bin/env python3
"""Table: does CPU time / threads follow wall time? (run_a_scaling.sh results)

For every thread count at the chosen N, reads from
    <results>/t<threads>/metric_N<N>.txt
the instructions, cycles and wall time, and prints

    threads | instructions | CPI | CPU time | CPU time / threads | wall time

with CPU time = instructions x CPI x seconds/cycle = cycles / f.

Usage (from the wa1_jj/ folder):
    python3 scripts/visualizations/table_cpu_time.py
    python3 scripts/visualizations/table_cpu_time.py --particles 1600 --latex
"""
import argparse
import re
from pathlib import Path

CLOCK_HZ = 2.0e9   # A64FX runs at a fixed 2.0 GHz

# perf lines:  25,314,464,960      cycles  ...
#              22,745,281,788      instructions  ...
#              0.3433 +- 0.0141 seconds time elapsed ...
CYCLES_RE = re.compile(r"^\s*([\d,]+)\s+cycles", re.M)
INSTR_RE = re.compile(r"^\s*([\d,]+)\s+instructions", re.M)
WALL_RE = re.compile(r"^\s*([\d.]+)\s+\+-.*seconds time elapsed", re.M)


def number(match):
    return float(match[1].replace(",", ""))


def read_rows(results, particles):
    """Return [(threads, instructions, cycles, wall)] sorted by threads."""
    rows = []
    for f in results.glob(f"t*/metric_N{particles}.txt"):
        text = f.read_text()
        threads = int(f.parent.name[1:])              # "t24" -> 24
        rows.append((threads, number(INSTR_RE.search(text)),
                      number(CYCLES_RE.search(text)), number(WALL_RE.search(text))))
    return sorted(rows)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--particles", type=int, default=1600)
    parser.add_argument("--results", type=Path, default=Path("results/deucalion/md_a_scaling"))
    parser.add_argument("--latex", action="store_true", help="print a LaTeX tabular instead")
    args = parser.parse_args()

    rows = read_rows(args.results, args.particles)
    if not rows:
        raise SystemExit(f"No results for N={args.particles} in {args.results}")

    header = ["Threads", "Instr. (1e9)", "CPI", "CPU time (s)", "CPU time/threads (s)", "Wall time (s)"]
    table = []
    for p, instr, cycles, wall in rows:
        cpu = instr * (cycles / instr) / CLOCK_HZ     # = instructions x CPI x seconds/cycle
        table.append([f"{p}", f"{instr / 1e9:.2f}", f"{cycles / instr:.2f}",
                      f"{cpu:.2f}", f"{cpu / p:.2f}", f"{wall:.2f}"])

    if args.latex:
        print(r"\begin{tabular}{rrrrrr}")
        print(r"\hline")
        print(" & ".join(header) + r" \\")
        print(r"\hline")
        for row in table:
            print(" & ".join(row) + r" \\")
        print(r"\hline")
        print(r"\end{tabular}")
    else:
        widths = [max(len(h), *(len(r[i]) for r in table)) for i, h in enumerate(header)]
        print("  ".join(h.rjust(w) for h, w in zip(header, widths)))
        for row in table:
            print("  ".join(c.rjust(w) for c, w in zip(row, widths)))


if __name__ == "__main__":
    main()
