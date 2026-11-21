# Profiling Guide (`Makefile`)

This project uses a [Makefile](Makefile) to compile and profile different versions of the molecular dynamics (MD) code with `perf`, storing binaries per implementation folder and organizing reports under `results/`.

## Requirements

- `gcc`
- `make`
- `perf` (`linux-tools` / cluster `perf`)
- `python3` (standard library only, used by [scripts/aggregate_hotspots.py](scripts/aggregate_hotspots.py))

## Project Structure

```text
.
├── Makefile
├── inputdata.txt                 # Simulation parameters fed into stdin
├── scripts/
│   └── aggregate_hotspots.py     # Computes mean +- std dev across hotspot runs
├── src/
│   └── <FOLDER_NAME>/
│       ├── MD.cpp (or *.c)       # Source file (first .c or .cpp in the folder)
│       └── md_profiling          # Compiled profiling binary
└── results/
    └── <FOLDER_NAME>/
        ├── hotspots_self_N<P>_run1.txt .. _run<R>.txt
        ├── hotspots_self_N<P>.txt
        ├── metric_N<P>.txt
        ├── cp_average.txt
        ├── cp_output.txt
        └── cp_traj.xyz
```

## Makefile Parameters

All parameters have defaults and can be overridden on the command line as `NAME=value`:

| Parameter | Default | Description |
| :--- | :--- | :--- |
| `FOLDER_NAME` | `md_baseline` | Subfolder inside `src/` containing the `.c` (or `.cpp`) source file. Also selects `results/<FOLDER_NAME>/`. |
| `PARTICLES` | `200` | Number of particles compiled into the binary via `-D NUMBER_OF_PARTICLES=$(PARTICLES)`. |
| `REPEATS` | `5` | Number of repeated runs used to compute mean and standard deviation/spread. |
| `OPENMP` | `0` | Set to `1` to enable OpenMP compilation and linking (`-fopenmp`). |

> **Note:** GNU Make passes custom arguments as `VARIABLE=value` pairs (not `--flags`).

---

## 1. Hotspot Profiling (`make hotspots`)

Identifies which functions take the most self CPU time by sampling with `perf record` and summarizing with `perf report`. `hotspots` is the default target, so `make` and `make hotspots` are equivalent.

### Usage

```bash
# Run with defaults (FOLDER_NAME=md_baseline, PARTICLES=200, REPEATS=5)
make hotspots

# Customize folder, particle count, and repetitions
make hotspots FOLDER_NAME=md_baseline PARTICLES=800 REPEATS=5

# Enable OpenMP (-fopenmp) and optionally set the thread count
make hotspots FOLDER_NAME=md_a OPENMP=1
OMP_NUM_THREADS=4 make hotspots FOLDER_NAME=md_a PARTICLES=800 OPENMP=1
```

### What it does

1. **Builds** the `.c` (or `.cpp`) file inside `src/$(FOLDER_NAME)/` into `src/$(FOLDER_NAME)/md_profiling` with `-O3 -ffast-math -g -fno-omit-frame-pointer` and creates `results/$(FOLDER_NAME)/`.
2. **Records `REPEATS` independent runs** at 10,000 Hz (`--all-user --call-graph fp`), saving each run's flat self-time table to:
   - `results/$(FOLDER_NAME)/hotspots_self_N$(PARTICLES)_run1.txt` ... `_run$(REPEATS).txt`
   *(Any stale `_run*.txt` files for that particle count are cleared before starting.)*
3. **Moves simulation outputs** (`cp_average.txt`, `cp_output.txt`, `cp_traj.xyz`) into `results/$(FOLDER_NAME)/`.
4. **Aggregates all runs** with [scripts/aggregate_hotspots.py](scripts/aggregate_hotspots.py), saving the complete table to `results/$(FOLDER_NAME)/hotspots_self_N$(PARTICLES).txt` and printing the top 6 functions per event to the terminal.

### Reading the aggregated output

```text
#   Mean %    Std Dev  Avg Samples    Runs  Symbol
# ........  .........  ...........  ......  ................................
    57.45%  +-  0.68%        525.6     5/5  [.] Potential()
    41.30%  +-  1.04%        381.2     5/5  [.] computeAccelerations()
```

- **Mean %**: Average self-time overhead across runs where the PMU event was recorded (missing symbols in a run count as `0%`).
- **Std Dev**: Sample standard deviation in percentage points (`0.00%` when `REPEATS=1`).
- **Avg Samples**: Mean number of raw samples recorded in that function per run.
- **Runs**: Number of runs in which the function received at least one sample.
- **Symbol**: Function name (`[.]` = user-space code).

---

## 2. Overall Benchmarking (`make metrics`)

Measures wall-clock time, `task-clock`, CPU `cycles`, and retired `instructions` averaged over `REPEATS` runs using `perf stat --repeat`.

### Usage

```bash
# Run with defaults (FOLDER_NAME=md_baseline, PARTICLES=200, REPEATS=5)
make metrics

# Customize folder, particle count, and repetitions
make metrics FOLDER_NAME=md_baseline PARTICLES=800 REPEATS=10

# Enable OpenMP (-fopenmp) with a specific thread count
OMP_NUM_THREADS=4 make metrics FOLDER_NAME=md_a PARTICLES=800 OPENMP=1
```

### What it does

1. **Builds** `src/$(FOLDER_NAME)/md_profiling` for `$(PARTICLES)` particles.
2. **Runs `perf stat --repeat $(REPEATS)`** on `task-clock,cycles,instructions`, saving the report to `results/$(FOLDER_NAME)/metric_N$(PARTICLES).txt`.
3. **Moves simulation outputs** (`cp_average.txt`, `cp_output.txt`, `cp_traj.xyz`) into `results/$(FOLDER_NAME)/`.
4. **Prints** the saved report to the terminal.

---

## Other Useful Commands

### Compile only

```bash
make build FOLDER_NAME=md_baseline PARTICLES=800
```

### Clean temporary files

Removes `src/$(FOLDER_NAME)/md_profiling`, `perf.data` / `perf.data.old` (both in the root directory and in `results/$(FOLDER_NAME)/`), and any root-level simulation outputs while preserving saved reports in `results/`:

```bash
make clean FOLDER_NAME=md_baseline
```

### Preview commands without executing (dry run)

```bash
make -n hotspots FOLDER_NAME=md_baseline PARTICLES=800 REPEATS=5
make -n metrics  FOLDER_NAME=md_baseline PARTICLES=800 REPEATS=5
```

### Running on a SLURM cluster

Prefix any `make` command with `srun`:

```bash
srun --partition=<partition> make hotspots FOLDER_NAME=md_baseline PARTICLES=200 REPEATS=5
srun --partition=<partition> make metrics  FOLDER_NAME=md_baseline PARTICLES=200 REPEATS=5
```

---

## Profiling a New Implementation Version

1. Create a new subfolder under `src/` with your `.c` (or `.cpp`) file, e.g. `src/md_v1/MD.c`.
2. Run `hotspots` and `metrics` pointing `FOLDER_NAME` to it:

```bash
make hotspots FOLDER_NAME=md_v1 PARTICLES=200 REPEATS=5
make metrics  FOLDER_NAME=md_v1 PARTICLES=200 REPEATS=5

# For OpenMP versions, add OPENMP=1 (and optionally OMP_NUM_THREADS)
OMP_NUM_THREADS=4 make hotspots FOLDER_NAME=md_a PARTICLES=800 OPENMP=1
OMP_NUM_THREADS=4 make metrics  FOLDER_NAME=md_a PARTICLES=800 OPENMP=1
```

The binary will be compiled to `src/md_v1/md_profiling` and all reports and simulation outputs will be saved under `results/md_v1/`.


## Algorithm A: particle and thread-count experiment

From the project folder, run the benchmark and then collect the results:

```bash
sh benchmark_particles.sh
python3 scripts/aggregate_metrics.py --output results/metrics_summary.csv
```

The benchmark tests **200, 400, 800, 1600, and 3200 particles** with
**1, 2, and 4 threads**, repeating each combination **5 times**.
It uses `inputdata.txt`. Timing includes simulation output but excludes compilation.

- Individual reports: `results/md_a_t<threads>/metric_N<particles>.txt`
- Combined results: `results/metrics_summary.csv`

The CSV includes runtime, reported uncertainty, speedup relative to one thread,
and parallel efficiency. Speedup compares the same particle count;
efficiency is speedup divided by threads (1.0 = 100%).

For a smaller test:

```bash
PARTICLE_COUNTS="200 400" THREAD_COUNTS="1 2" REPEATS=2 sh benchmark_particles.sh
```

Rerunning replaces matching reports. Simulation files retain only the final run
for each thread count. Generated reports and the summary CSV are ignored by Git.
