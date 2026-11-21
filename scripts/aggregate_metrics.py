#!/usr/bin/env python3
"""Collect perf-stat summaries; does not average already averaged reports."""
import argparse
import csv
import re
import sys
from pathlib import Path

NUMBER = r"[0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?"
ELAPSED = re.compile(rf"^\s*({NUMBER})(?:\s*\+-\s*({NUMBER}))?\s+seconds time elapsed", re.M)
FIELDS = ['particles', 'threads', 'runs', 'elapsed_seconds',
          'elapsed_reported_error_seconds', 'speedup', 'parallel_efficiency',
          'seconds_per_particle_squared', 'source']


def collect(results):
    rows = []
    for path in sorted(results.glob('md_a_t*/metric_N*.txt')):
        threads = re.fullmatch(r'md_a_t([1-9][0-9]*)', path.parent.name)
        particles = re.fullmatch(r'metric_N([1-9][0-9]*)\.txt', path.name)
        if not threads or not particles:
            continue
        content = path.read_text()
        elapsed = ELAPSED.search(content)
        if not elapsed or float(elapsed[1]) <= 0:
            raise ValueError(f'{path}: missing or invalid elapsed time; expected dot-decimal perf output')
        runs = re.search(r'\((\d+) runs?\)', content)
        n, t = int(particles[1]), int(threads[1])
        seconds = float(elapsed[1])
        rows.append(dict(particles=n, threads=t, runs=int(runs[1]) if runs else '',
                         elapsed_seconds=seconds,
                         elapsed_reported_error_seconds=float(elapsed[2]) if elapsed[2] else '',
                         seconds_per_particle_squared=seconds / n**2,
                         source=str(path)))
    if not rows:
        raise ValueError(f'No reports found in {results}/md_a_t*/metric_N*.txt')
    baseline = {r['particles']: r['elapsed_seconds'] for r in rows if r['threads'] == 1}
    for row in rows:
        base = baseline.get(row['particles'])
        row['speedup'] = base / row['elapsed_seconds'] if base else ''
        row['parallel_efficiency'] = row['speedup'] / row['threads'] if base else ''
    return sorted(rows, key=lambda r: (r['particles'], r['threads']))


def main():
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--results-dir', type=Path, default=root / 'results')
    parser.add_argument('--output', type=Path, help='CSV destination (default: print CSV to stdout)')
    args = parser.parse_args()
    try:
        rows = collect(args.results_dir)
    except (OSError, ValueError) as error:
        parser.exit(1, f'Error: {error}\n')
    stream = args.output.open('w', newline='') if args.output else sys.stdout
    try:
        writer = csv.DictWriter(stream, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    finally:
        if args.output:
            stream.close()
    print(f'Collected {len(rows)} reports.', file=sys.stderr)


if __name__ == '__main__':
    main()
