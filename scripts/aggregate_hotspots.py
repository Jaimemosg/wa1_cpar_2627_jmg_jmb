#!/usr/bin/env python3
"""Aggregate multiple `perf report --stdio` hotspot runs into mean +- std dev.

Reads N per-run hotspot text files produced by:
    perf report --stdio --show-nr-samples --no-children --sort symbol --call-graph none

Computes, per PMU event and per symbol:
  - Mean overhead (%) across the runs where that event was recorded
  - Sample standard deviation (percentage points, N-1 denominator; 0.0 if N <= 1)
  - Mean sample count across those runs
  - Number of runs in which the symbol had >= 1 sample

Symbols absent in a run that recorded the event are counted as 0.0% / 0 samples
for that run so the mean and standard deviation reflect all runs accurately.
"""

import argparse
import math
import re
import sys


EVENT_RE = re.compile(r"^#\s*Samples:\s*\S+\s+of event '([^']+)'")
ROW_RE = re.compile(r"^\s*(\d+(?:\.\d+)?)%\s+([\d,]+)\s+(.+?)\s*$")
IPC_TAIL_RE = re.compile(
    r"\s+(?:-|\d+(?:\.\d+)?)\s+(?:-|\[\d+(?:\.\d+)?%\]|\d+(?:\.\d+)?%)\s*$"
)


def parse_perf_report(path):
    """Parse one perf report --stdio file.

    Returns:
        dict[str, dict[str, tuple[float, int]]]:
            { event_name: { symbol: (overhead_pct, samples) } }
        list[str]:
            Event names in the order they appeared in the file.
    """
    events = {}
    event_order = []
    current_event = None
    has_ipc_columns = False

    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for raw_line in f:
            line = raw_line.rstrip("\r\n")

            if line.startswith("#"):
                m_event = EVENT_RE.match(line)
                if m_event:
                    current_event = m_event.group(1)
                    if current_event not in events:
                        events[current_event] = {}
                        event_order.append(current_event)
                    has_ipc_columns = False
                elif "Overhead" in line and "Symbol" in line:
                    has_ipc_columns = "IPC" in line
                continue

            if not line.strip():
                continue

            m_row = ROW_RE.match(line)
            if not m_row:
                continue

            if current_event is None:
                current_event = "default"
                events[current_event] = {}
                event_order.append(current_event)

            overhead = float(m_row.group(1))
            samples = int(m_row.group(2).replace(",", ""))
            symbol = m_row.group(3)

            if has_ipc_columns:
                symbol = IPC_TAIL_RE.sub("", symbol).rstrip()

            prev_overhead, prev_samples = events[current_event].get(symbol, (0.0, 0))
            events[current_event][symbol] = (
                prev_overhead + overhead,
                prev_samples + samples,
            )

    return events, event_order


def mean_and_stddev(values):
    """Return (mean, sample_stddev) for a non-empty list of floats."""
    n = len(values)
    if n == 0:
        return 0.0, 0.0
    mean = sum(values) / n
    if n == 1:
        return mean, 0.0
    variance = sum((x - mean) ** 2 for x in values) / (n - 1)
    return mean, math.sqrt(variance)


def aggregate_runs(input_paths):
    """Aggregate parsed reports across all input files."""
    all_runs = []
    event_order = []
    seen_events = set()

    for path in input_paths:
        parsed, order = parse_perf_report(path)
        all_runs.append(parsed)
        for ev in order:
            if ev not in seen_events:
                seen_events.add(ev)
                event_order.append(ev)

    total_runs = len(input_paths)
    results = []

    for ev in event_order:
        ev_runs = [run[ev] for run in all_runs if ev in run]
        n_ev_runs = len(ev_runs)
        if n_ev_runs == 0:
            continue

        all_symbols = set()
        total_samples_per_run = []
        for run_map in ev_runs:
            all_symbols.update(run_map.keys())
            total_samples_per_run.append(sum(s for _, s in run_map.values()))

        avg_total_samples, std_total_samples = mean_and_stddev(total_samples_per_run)

        rows = []
        for sym in all_symbols:
            overheads = []
            samples_list = []
            present_count = 0
            for run_map in ev_runs:
                if sym in run_map:
                    ov, smp = run_map[sym]
                    overheads.append(ov)
                    samples_list.append(smp)
                    if smp > 0 or ov > 0.0:
                        present_count += 1
                else:
                    overheads.append(0.0)
                    samples_list.append(0)

            mean_ov, std_ov = mean_and_stddev(overheads)
            mean_smp, _ = mean_and_stddev(samples_list)
            rows.append(
                {
                    "symbol": sym,
                    "mean_overhead": mean_ov,
                    "std_overhead": std_ov,
                    "mean_samples": mean_smp,
                    "present_runs": present_count,
                    "event_runs": n_ev_runs,
                }
            )

        rows.sort(
            key=lambda r: (-r["mean_overhead"], -r["mean_samples"], r["symbol"])
        )
        results.append(
            {
                "event": ev,
                "event_runs": n_ev_runs,
                "total_runs": total_runs,
                "avg_total_samples": avg_total_samples,
                "std_total_samples": std_total_samples,
                "rows": rows,
            }
        )

    return results


def format_report(aggregated, input_paths, particles=None, max_rows=None):
    """Format aggregated hotspot statistics as plain text."""
    total_runs = len(input_paths)
    lines = []

    header = "# Aggregated hotspot self-time report over {} run{}".format(
        total_runs, "" if total_runs == 1 else "s"
    )
    if particles is not None:
        header += " (PARTICLES={})".format(particles)
    lines.append(header)

    if total_runs == 1:
        lines.append("# Source file: {}".format(input_paths[0]))
    elif total_runs > 1:
        lines.append(
            "# Source files: {} .. {}".format(input_paths[0], input_paths[-1])
        )
    lines.append("# Values: Mean overhead (%) +- sample Std Dev (percentage points)")
    lines.append("#")

    if not aggregated:
        lines.append("# No hotspot samples found in the input files.")
        return "\n".join(lines) + "\n"

    for idx, section in enumerate(aggregated):
        if idx > 0:
            lines.append("")
        lines.append(
            "# Event: '{}' (present in {}/{} runs, samples/run: {:.1f} +- {:.1f})".format(
                section["event"],
                section["event_runs"],
                section["total_runs"],
                section["avg_total_samples"],
                section["std_total_samples"],
            )
        )
        lines.append("#")
        lines.append(
            "# {:>8s}  {:>9s}  {:>11s}  {:>6s}  {}".format(
                "Mean %", "Std Dev", "Avg Samples", "Runs", "Symbol"
            )
        )
        lines.append(
            "# {:>8s}  {:>9s}  {:>11s}  {:>6s}  {}".format(
                "........",
                ".........",
                "...........",
                "......",
                "................................",
            )
        )

        rows = section["rows"]
        if max_rows is not None:
            rows = rows[:max_rows]

        for r in rows:
            runs_str = "{}/{}".format(r["present_runs"], r["event_runs"])
            lines.append(
                "  {:7.2f}%  +- {:5.2f}%  {:11.1f}  {:>6s}  {}".format(
                    r["mean_overhead"],
                    r["std_overhead"],
                    r["mean_samples"],
                    runs_str,
                    r["symbol"],
                )
            )

    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(
        description="Aggregate multiple perf report --stdio files into mean +- std dev."
    )
    parser.add_argument(
        "--particles",
        type=int,
        default=None,
        help="Particle count (for report header metadata).",
    )
    parser.add_argument(
        "--repeats",
        type=int,
        default=None,
        help="Number of runs when using --input-prefix.",
    )
    parser.add_argument(
        "--input-prefix",
        default=None,
        help="Prefix for run files (<prefix>1.txt .. <prefix><repeats>.txt).",
    )
    parser.add_argument(
        "--output",
        required=True,
        help="Path to write the aggregated hotspot report.",
    )
    parser.add_argument(
        "--print-top",
        type=int,
        default=0,
        help="If > 0, print the top N hotspot symbols per event to stdout.",
    )
    parser.add_argument(
        "inputs",
        nargs="*",
        help="Explicit list of per-run perf report .txt files.",
    )

    args = parser.parse_args()

    if args.inputs:
        input_paths = list(args.inputs)
    elif args.input_prefix and args.repeats:
        input_paths = [
            "{}{}.txt".format(args.input_prefix, i)
            for i in range(1, args.repeats + 1)
        ]
    else:
        parser.error("Provide either positional input files or --input-prefix with --repeats.")

    aggregated = aggregate_runs(input_paths)
    full_report = format_report(aggregated, input_paths, particles=args.particles)

    with open(args.output, "w", encoding="utf-8") as f:
        f.write(full_report)

    if args.print_top > 0:
        preview = format_report(
            aggregated,
            input_paths,
            particles=args.particles,
            max_rows=args.print_top,
        )
        sys.stdout.write(preview)


if __name__ == "__main__":
    main()
