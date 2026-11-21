# -----------------------------------------------------------------------------
#  HOW TO READ THIS MAKEFILE (key points)
#
#  1. RULES. The file is a list of rules:
#         target: prerequisites
#         <TAB>command
#         <TAB>command
#     - target        : a name you type, e.g. "make metrics"
#     - prerequisites : targets that run first ("metrics: build" -> build, then metrics)
#     - commands      : ordinary shell commands; each line MUST start with a TAB,
#                       spaces give "missing separator"
#
#  2. TARGET NAMES are free labels chosen by us (build, metrics, hotspots...).
#     Only names starting with a dot are special to make (.PHONY, .DEFAULT_GOAL).
#     .PHONY        : these targets are commands, not files -> always run them
#     .DEFAULT_GOAL : target used when you type just "make" (not used here:
#                     without it, the first target in the file is the default)
#
#  3. VARIABLES.  X = value   defines X;   $(X)   is replaced by its value.
#     "PARTICLES ?= 200" means: 200 unless given on the command line,
#     e.g. "make metrics PARTICLES=800" -> every $(PARTICLES) becomes 800.
#
#  4. COMMENTS start with #. After a variable value, write # with NO space
#     before it, otherwise the spaces become part of the value.
#
#  5. SHELL SYMBOLS inside commands (not make syntax, plain Linux shell):
#     < file      the program reads its input from file (instead of the keyboard)
#     > file      the program's screen output goes to file
#     > /dev/null screen output is thrown away
#     |           sends the output of one command into the next (e.g. | grep)
#     \           at line end: the command continues on the next line
#
#  6. SMALL MAKE DETAILS
#     @command    run the command without printing it first
#     $$          one $ passed to the shell (e.g. $$n = loop variable n)
#     $(MAKE)     calls make again from inside a command (see Example 4)
#
#  7. USEFUL CHECK.  "make -n metrics PARTICLES=200" prints the commands that
#     would run, with all variables replaced, without running anything.

#     Example 1 (a made-up rule, simpler than the ones below):
#         MSG = hello          the variable, defined in the file
#         greet:               the target
#              echo $(MSG)     its command
#
#         make greet  executes:  echo hello
#         - $(MSG) becomes hello because the file says "MSG = hello"

#     Example 2 (made up: the value can come from the command line):
#         NAME ?= world             default value, used if you don't give one
#         greet:
#              echo hello $(NAME)
#
#         make greet                executes:  echo hello world
#         make greet NAME=class     executes:  echo hello class
#         - "?=" means: use world unless you type NAME=... after make
#         - PARTICLES works the same way in this file:
#           "PARTICLES ?= 200", "make build PARTICLES=800"

#     Example 3 (made up: a target that needs another one first):
#         NAME ?= world
#         prepare:
#              echo preparing
#         greet: prepare             greet needs prepare -> prepare runs first
#              echo hello $(NAME)
#
#         make greet  executes:   echo preparing
#                                 echo hello world
#         make prepare executes:  echo preparing          (only that one)
#         - in this file: "metrics: build" -> make metrics compiles first, then measures

#     Example 4 (made up: a loop that calls another target several times):
#         NAME ?= world
#         greet:
#              echo hello $(NAME)
#         greet_all:
#              for n in ana bob; do $(MAKE) greet NAME=$$n; done
#
#         make greet_all  executes:  make greet NAME=ana  ->  echo hello ana
#                                    make greet NAME=bob  ->  echo hello bob
#         - for n in ana bob; do ...; done : shell loop, n takes each value in turn
#         - $(MAKE) : calls make again, here "make greet"
#         - $$n     : $$ passes one $ to the shell, so the shell sees $n (the loop value)
#         - not used in this file; the same idea would run "metrics" for several sizes:
#           "for n in 200 400 800 1600; do $(MAKE) metrics PARTICLES=$$n; done"

#     Example 5 (made up: @ hides the command, shows only its result):
#         greet:
#              echo hello
#         quiet_greet:
#              @echo hello
#
#         make greet        prints:  echo hello      <- the command (shown by make)
#                                    hello           <- its output
#         make quiet_greet  prints:  hello           <- only the output
#         - in this file: "@mkdir -p $(RESULTS_FOLDER)" and "@cat ..." use @ because
#           seeing those commands adds nothing; their result is what matters

#     Example 6 (made up: where a program reads and writes):
#         greet:
#             ./program < input.txt > /dev/null
#
#         - ./program     : the program that runs
#         - < input.txt   : it reads its input from input.txt instead of the keyboard
#         - > /dev/null   : what it prints is thrown away (/dev/null discards everything)
#         - in this file:  ./$(PROFILING_BINARY) < $(INPUT_FILE) > /dev/null
#           = run md_profiling, read ../inputdata.txt, hide its screen output

#     Example 7 (one variable, from the file):
#         in the file :  mkdir -p $(RESULTS_FOLDER)
#         make build  executes:  mkdir -p results
#         - $(RESULTS_FOLDER) becomes results because the file says "RESULTS_FOLDER = results"

#     Example 8 (two variables: one from the file, one from the command line):
#         in the file :  cat $(RESULTS_FOLDER)/metric_N$(PARTICLES).txt
#         make metrics PARTICLES=800  executes:  cat results/metric_N800.txt
#         - $(RESULTS_FOLDER) becomes results  (the file says "RESULTS_FOLDER = results")
#         - $(PARTICLES)      becomes 800      (you typed PARTICLES=800)
# -----------------------------------------------------------------------------
# =============================================================================
#  Question (i): find the hot-spots of the sequential code.
#  Run from this folder (01_hotspots/). Not part of the submission.
#
#     make  (= make hotspots)   which functions take the time         (PL01 Ex.2, PL06)
#     make metrics              time, instructions, cycles -> CPI     (PL00 §3, PL01 Ex.1)
#     make roofline             FLOPs & cache traffic -> Roofline     (A64FX PMU counters)
#     make clean                remove binary and generated files
#     Add FOLDER_NAME=<dir> to select a subfolder under src/ (default md_baseline),
#     PARTICLES=<n> to change the number of particles (default 200),
#     and REPEATS=<r> to change the number of repeated runs (default 5),
#     e.g. "make hotspots FOLDER_NAME=md_baseline PARTICLES=800 REPEATS=5".
#
#  On the cluster, prefix with srun, e.g.:
#     srun --partition=<arm partition> make hotspots FOLDER_NAME=md_baseline PARTICLES=200
# =============================================================================


# 1. CONFIGURATION & SETTINGS
#    ├── Default parameters (FOLDER_NAME ?= md_baseline, PARTICLES ?= 200, REPEATS ?= 5)
#    ├── File paths & tools (COMPILER, SOURCE_DIR, SOURCE_FILE, INPUT_FILE, PROFILING_BINARY, RESULTS_FOLDER, AGGREGATE_SCRIPT)
#    ├── Compiler & profiling flags (COMPILER_FLAGS)
#    └── Make directive (.PHONY: hotspots build metrics roofline clean)  <-- [No .DEFAULT_GOAL needed]

# 2. MAIN ENTRY POINT: HOTSPOT PROFILING (hotspots: build)  <-- [First target = automatic default for `make`]
#    ├── Step 1: Loop 1..REPEATS of `perf record` + `perf report` (saves per-run `_run<i>.txt` files)
#    └── Step 2: `aggregate_hotspots.py` (saves mean +- std dev table & prints top 6 per event)

# 3. SUPPORTING STEP: COMPILATION (build)
#    └── Finds the .c/.cpp source in src/$(FOLDER_NAME), compiles to src/$(FOLDER_NAME)/md_profiling,
#        and creates results/$(FOLDER_NAME)/ folder.

# 4. SECONDARY EXPERIMENT: OVERALL BENCHMARKING (metrics: build)
#    └── Runs `perf stat --repeat $(REPEATS)` to measure baseline time, cycles, and instructions.

# 5. ROOFLINE ANALYSIS: HARDWARE FP & MEMORY COUNTERS (roofline: build)
#    └── Runs `perf stat --repeat $(REPEATS)` on Fujitsu A64FX FP64 & cache-refill counters.

# 6. HOUSEKEEPING (clean)
#    └── Removes binary, perf.data, and simulation outputs (keeps results/).




# ==============================================================================
# 1. CONFIGURATION & SETTINGS
# ==============================================================================

# Default command-line parameters (override with `make <target> FOLDER_NAME=... PARTICLES=... REPEATS=...`)
# FOLDER_NAME       Subfolder inside src/ containing the source file (also used for results/$(FOLDER_NAME)).
# PARTICLES         Particle count compiled into the binary (defaults to 200 for fast initial profiling).
# REPEATS           Number of repeated runs for hotspots, metrics, and roofline (mean +- std dev).
FOLDER_NAME ?= md_baseline
PARTICLES   ?= 200
REPEATS     ?= 5

# Compiler and file paths
# COMPILER          gcc, the same compiler as the submission Makefile (compiles both .c and .cpp files).
# SOURCE_DIR        Subfolder inside src/ for the selected implementation version.
# SOURCE_FILE       First .c (or .cpp) source file found inside $(SOURCE_DIR).
# INPUT_FILE        Supplied input parameters fed into stdin (title, gas type, temperature, density).
# PROFILING_BINARY  Compiled executable stored inside $(SOURCE_DIR).
# RESULTS_FOLDER    Output directory where the perf metrics and hotspot tables are saved for $(FOLDER_NAME).
# AGGREGATE_SCRIPT  Python script that combines per-run hotspot reports into mean +- std dev.
# SIM_OUTPUTS       Simulation output files generated by the executable in the working directory.
COMPILER         = gcc
SOURCE_DIR       = src/$(FOLDER_NAME)
SOURCE_FILE      = $(firstword $(wildcard $(SOURCE_DIR)/*.c $(SOURCE_DIR)/*.cpp))
INPUT_FILE       = ./inputdata.txt
PROFILING_BINARY = ./$(SOURCE_DIR)/md_profiling
RESULTS_FOLDER   = results/$(FOLDER_NAME)
AGGREGATE_SCRIPT = ./scripts/aggregate_hotspots.py
SIM_OUTPUTS      = cp_average.txt cp_output.txt cp_traj.xyz perf.data perf.data.old

# Compiler optimization, profiling, and warning flags
# -O3                       Enables aggressive speed optimizations (loop unrolling, vectorization).
# -ffast-math               Relaxes strict IEEE floating-point rules for faster math calculations.
# -g                        Embeds debug symbols (function names and source line numbers) for perf.
# -fno-omit-frame-pointer   Keeps frame pointers intact so `perf --call-graph fp` can trace call stacks.
# -Wno-unused-result        Silences compiler warnings from unchecked scanf() return values.
COMPILER_FLAGS = \
	-O3 \
	-ffast-math \
	-g \
	-fno-omit-frame-pointer \
	-Wno-unused-result

# Declare all targets as PHONY (they are action names, not actual files on disk, so Make always runs them).
# Note: .DEFAULT_GOAL is not needed because `hotspots` is placed first in Section 2.
.PHONY: hotspots build metrics roofline clean



# ==============================================================================
# 2. MAIN ENTRY POINT: HOTSPOT PROFILING (Default target when running `make`)
# ==============================================================================
# Identifies which functions consume the most CPU time, repeated $(REPEATS) times
# to report mean +- standard deviation (similar to `perf stat --repeat`).
# Prerequisite: `build` runs first so $(PROFILING_BINARY) matches $(PARTICLES).
#
# Step 1: Loop 1..$(REPEATS), recording CPU samples and saving each run's report:
#   - $(RESULTS_FOLDER)/hotspots_self_N$(PARTICLES)_run1.txt .. _run$(REPEATS).txt
#   perf record flags:
#     --freq 10000         Samples 10,000 times per second (short form: -F 10000).
#     --all-user           Measures only user-space code (avoids kernel permission errors).
#     --call-graph fp      Records call chains / stack traces using frame pointers (short form: -g).
#     --output perf.data   Saves raw profiling data to perf.data (short form: -o perf.data).
#   perf report flags:
#     --input perf.data    Reads the recorded profiling data (short form: -i perf.data).
#     --stdio              Outputs plain text instead of an interactive UI.
#     --show-nr-samples    Displays the raw sample count column next to percentages (short form: -n).
#     --no-children        Measures self-time only (time spent directly inside each function).
#     --sort symbol        Groups and sorts rows by function name (short form: -s symbol).
#     --call-graph none    Hides call-tree sub-branches to keep a clean, flat ranked list (short form: -g none).
#
# Step 2: Aggregate the $(REPEATS) per-run reports into mean +- std dev:
#   - Saves the full aggregated table to $(RESULTS_FOLDER)/hotspots_self_N$(PARTICLES).txt
#   - Prints the top 6 hotspot symbols per event to the terminal (--print-top 6).
hotspots: build
	@rm --force $(RESULTS_FOLDER)/hotspots_self_N$(PARTICLES)_run*.txt
	@set -e; \
	for i in $$(seq 1 $(REPEATS)); do \
		echo "=== Hotspots run $$i/$(REPEATS) (FOLDER_NAME=$(FOLDER_NAME), PARTICLES=$(PARTICLES)) ==="; \
		perf record \
			--freq 10000 \
			--all-user \
			--call-graph fp \
			--output perf.data \
			$(PROFILING_BINARY) \
				< $(INPUT_FILE) \
				> /dev/null; \
		perf report \
			--input perf.data \
			--stdio \
			--show-nr-samples \
			--no-children \
			--sort symbol \
			--call-graph none \
			> $(RESULTS_FOLDER)/hotspots_self_N$(PARTICLES)_run$$i.txt; \
	done
	mv --force $(SIM_OUTPUTS) $(RESULTS_FOLDER)/
	python3 $(AGGREGATE_SCRIPT) \
		--particles $(PARTICLES) \
		--repeats $(REPEATS) \
		--input-prefix $(RESULTS_FOLDER)/hotspots_self_N$(PARTICLES)_run \
		--output $(RESULTS_FOLDER)/hotspots_self_N$(PARTICLES).txt \
		--print-top 6



# ==============================================================================
# 3. SUPPORTING STEP: COMPILATION (`build`)
# ==============================================================================
# Compiles the .c/.cpp file inside src/$(FOLDER_NAME) for $(PARTICLES) particles,
# stores the binary inside src/$(FOLDER_NAME), and prepares the results folder.
#
# $(COMPILER)                          Calls the compiler (gcc).
# $(COMPILER_FLAGS)                    Passes optimization, debug symbol, and warning flags.
# -D NUMBER_OF_PARTICLES=$(PARTICLES)  Defines the compile-time preprocessor macro for particle count.
# $(SOURCE_FILE)                       Input .c/.cpp source file inside src/$(FOLDER_NAME).
# -lm                                  Links the standard math library (`libm`) for functions like sqrt().
# -o $(PROFILING_BINARY)               Sets the output executable path (./src/$(FOLDER_NAME)/md_profiling).

build:
	@if [ -z "$(SOURCE_FILE)" ]; then \
		echo "Error: no .c or .cpp source file found in $(SOURCE_DIR)" >&2; \
		exit 1; \
	fi
	$(COMPILER) \
		$(COMPILER_FLAGS) \
		-D NUMBER_OF_PARTICLES=$(PARTICLES) \
		$(SOURCE_FILE) -lm \
		-o $(PROFILING_BINARY)

# Quietly (`@`) creates the output folder without error if it exists (`-p`).
	@mkdir -p $(RESULTS_FOLDER)


# ==============================================================================
# 4. SECONDARY EXPERIMENT: OVERALL BENCHMARKING (`metrics`)
# ==============================================================================
# Measures total execution time, CPU cycles, and instruction count averaged over $(REPEATS) runs.
# Prerequisite: `build` runs first so $(PROFILING_BINARY) matches $(PARTICLES).
#
# --repeat $(REPEATS)    Repeats the command $(REPEATS) times and reports mean +- spread (short form: -r).
# --event ...            Measures specific CPU hardware/software events (short form: -e).
# --output <file>        Saves the perf stat report to a text file (short form: -o).
# sh -c '...'            Runs inside a fresh subshell so $(INPUT_FILE) re-opens from line 1 on each repeat.
# < $(INPUT_FILE)        Feeds the 4 interactive scanf() inputs into stdin:
#                          Line 1: Simulation title / output filename prefix (e.g., argon_run)
#                          Line 2: Noble gas symbol: He, Ne, Ar, Kr, or Xe (e.g., Ar)
#                          Line 3: Initial temperature in Kelvin (e.g., 100.0)
#                          Line 4: Number density in moles/m^3 (e.g., 35000.0)
# > /dev/null            Discards stdout so printing does not slow down the benchmark.
# @cat <file>            Quietly prints (concatenates) the saved report to the terminal.
metrics: build
	perf stat \
		--repeat $(REPEATS) \
		--event task-clock,cycles,instructions \
		--output $(RESULTS_FOLDER)/metric_N$(PARTICLES).txt \
		sh -c '$(PROFILING_BINARY) \
				< $(INPUT_FILE) \
				> /dev/null'
	mv --force $(SIM_OUTPUTS) $(RESULTS_FOLDER)/

	@cat $(RESULTS_FOLDER)/metric_N$(PARTICLES).txt


# ==============================================================================
# 5. ROOFLINE ANALYSIS: HARDWARE FP & MEMORY COUNTERS (`roofline`)
# ==============================================================================
# Measures hardware floating-point operations and cache-line traffic on Deucalion's
# Fujitsu A64FX CPU (where each L1D/L2 cache line refill or writeback is 256 bytes).
# Prerequisite: `build` runs first so $(PROFILING_BINARY) matches $(PARTICLES).
#
# Measured Fujitsu A64FX PMU events:
# - task-clock            CPU time spent executing the program (ms).
# - cycles                Total CPU clock cycles elapsed.
# - instructions          Total retired instructions.
# - fp_dp_fixed_ops_spec  Scalar & fixed-SIMD (NEON) double-precision FP operations.
# - fp_dp_scale_ops_spec  SVE double-precision FP operations (scaled per 128-bit; x4 for 512-bit SVE).
# - l1d_cache_refill      L1D cache line refills from L2 (x 256 Bytes = L1<-L2 traffic).
# - l2d_cache_refill      L2 cache line refills from HBM2 (x 256 Bytes = HBM2 read traffic).
# - l2d_cache_wb          L2 cache line write-backs to HBM2 (x 256 Bytes = HBM2 write traffic).
#
# From the output file ($(RESULTS_FOLDER)/roofline_N$(PARTICLES).txt):
#   Total FLOPs             = fp_dp_fixed_ops_spec + 4 * fp_dp_scale_ops_spec
#   L2 Traffic (Bytes)      = 256 * l1d_cache_refill
#   HBM2 Traffic (Bytes)    = 256 * (l2d_cache_refill + l2d_cache_wb)
#   Operational Intensity   = Total FLOPs / Traffic (Bytes)   [FLOP/Byte]
#   Achieved Performance    = Total FLOPs / Time (seconds)    [GFLOP/s]
roofline: build
	perf stat \
		--repeat $(REPEATS) \
		--event task-clock,cycles,instructions,fp_dp_fixed_ops_spec,fp_dp_scale_ops_spec,l1d_cache_refill,l2d_cache_refill,l2d_cache_wb \
		--output $(RESULTS_FOLDER)/roofline_N$(PARTICLES).txt \
		sh -c '$(PROFILING_BINARY) \
				< $(INPUT_FILE) \
				> /dev/null'
	mv --force $(SIM_OUTPUTS) $(RESULTS_FOLDER)/

	@cat $(RESULTS_FOLDER)/roofline_N$(PARTICLES).txt


# ==============================================================================
# 6. HOUSEKEEPING (`clean`)
# ==============================================================================
# Removes the compiled profiling binary, raw perf recordings, and simulation output files.
# Note: $(RESULTS_FOLDER) is intentionally kept so your saved reports are preserved.
#
# rm                     Standard Unix utility to delete files.
# --force                Deletes files without prompting and ignores missing files (short form: -f).
clean:
	rm \
		--force \
		$(PROFILING_BINARY) \
		perf.data \
		perf.data.old \
		$(SIM_OUTPUTS)

