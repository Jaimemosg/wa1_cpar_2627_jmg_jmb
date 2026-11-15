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
#     make clean                remove binary and generated files
#     Add PARTICLES=<n> to change the number of particles (default 200),
#     e.g. "make metrics PARTICLES=800".
#
#  On the cluster, prefix with srun, e.g.:
#     srun --partition=<arm partition> make hotspots PARTICLES=200
# =============================================================================


# 1. CONFIGURATION & SETTINGS
#    ├── File paths & tools (COMPILER, SOURCE_FILE, INPUT_FILE, PROFILING_BINARY, RESULTS_FOLDER)
#    ├── Compiler & profiling flags (COMPILER_FLAGS)
#    ├── Default parameter (PARTICLES ?= 200)
#    └── Make directive (.PHONY: hotspots build metrics clean)  <-- [No .DEFAULT_GOAL needed]

# 2. MAIN ENTRY POINT: HOTSPOT PROFILING (hotspots: build)  <-- [First target = automatic default for `make`]
#    ├── Step 1: `perf record`   (samples CPU at 10,000 Hz into perf.data)
#    ├── Step 2: `perf report`   (generates self-time hotspot table)
#    └── Step 3: `@grep` preview (prints top hotspot functions to terminal)

# 3. SUPPORTING STEP: COMPILATION (build)
#    └── Compiles MD.cpp with -D NUMBER_OF_PARTICLES and creates results/ folder.

# 4. SECONDARY EXPERIMENT: OVERALL BENCHMARKING (metrics: build)
#    └── Runs `perf stat --repeat 5` to measure baseline time, cycles, and instructions.


# 5. HOUSEKEEPING (clean)
#    └── Removes binary, perf.data, and simulation outputs (keeps results/).




# ==============================================================================
# 1. CONFIGURATION & SETTINGS
# ==============================================================================

# Compiler and file paths
# COMPILER          gcc, the same compiler as the submission Makefile (it compiles .cpp files as C++).
# SOURCE_FILE       Path to the C++ molecular dynamics source code being analyzed.
# INPUT_FILE        Supplied input parameters fed into stdin (title, gas type, temperature, density).
# PROFILING_BINARY  Name of the compiled executable kept separate from the main submission binary.
# RESULTS_FOLDER    Output directory where the perf metrics and hotspot tables are saved.
COMPILER         = gcc
SOURCE_FILE      = ./src/MD.cpp
INPUT_FILE       = ./inputdata.txt
PROFILING_BINARY = md_profiling
RESULTS_FOLDER   = results

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

# Particle count: defaults to 200 for fast initial profiling (assignment part i).
# Override anytime from terminal for full runs: `make hotspots PARTICLES=5000`
PARTICLES ?= 200

# Declare all targets as PHONY (they are action names, not actual files on disk, so Make always runs them).
# Note: .DEFAULT_GOAL is not needed because `hotspots` is placed first in Section 2.
.PHONY: hotspots build metrics clean



# ==============================================================================
# 2. MAIN ENTRY POINT: HOTSPOT PROFILING (Default target when running `make`)
# ==============================================================================
# Identifies which functions consume the most CPU time.
# Prerequisite: `build` runs first so $(PROFILING_BINARY) matches $(PARTICLES).

# Step 1: Record CPU samples into perf.data
# --freq 10000           Samples 10,000 times per second (short form: -F 10000).
# --all-user             Configures all sampled events to measure only user-space code (avoids kernel module permission errors).
# --call-graph fp         Records call chains / stack traces using frame pointers (short form: -g).
# --output perf.data     Saves raw profiling data to perf.data (short form -o perf.data).
# ./$(PROFILING_BINARY)  Runs the compiled binary once with redirected input and discarded stdout.
hotspots: build
	perf record \
		--freq 10000 \
		--all-user \
		--call-graph fp \
		--output perf.data \
		./$(PROFILING_BINARY) \
			< $(INPUT_FILE) \
			> /dev/null

# Step 2: Generate the self-time hotspot table from perf.data
# --input perf.data      Reads the recorded profiling data (short form: -i perf.data).
# --stdio                Outputs plain text instead of an interactive UI so it can be saved to a file.
# --show-nr-samples      Displays the raw sample count column next to percentages (short form: -n).
# --no-children          Measures self-time only (time spent directly inside each function).
# --sort symbol          Groups and sorts rows by function name (short form: -s symbol).
# --call-graph none      Hides call-tree sub-branches to keep a clean, flat ranked list (short form: -g none).
# > <file>               Saves the plain-text report into the results folder.
	perf report \
		--input perf.data \
		--stdio \
		--show-nr-samples \
		--no-children \
		--sort symbol \
		--call-graph none \
		> $(RESULTS_FOLDER)/hotspots_self_N$(PARTICLES).txt

# Step 3: Print a quick summary preview of the top hotspot functions to the terminal
# @                      Hides the command text itself from printing in the terminal.
# --invert-match '^#'    Filters out comment header lines starting with '#' (short form: -v '^#').
# --invert-match '^$$'   Filters out empty lines ('$$' escapes '$' for Make; short form: -v '^$$').
# --lines=6              Prints only the first 6 non-empty lines (short form: -6).
	@grep --invert-match '^#' \
				$(RESULTS_FOLDER)/hotspots_self_N$(PARTICLES).txt \
				| grep --invert-match '^$$' \
				| head --lines=6



# ==============================================================================
# 3. SUPPORTING STEP: COMPILATION (`build`)
# ==============================================================================
# Compiles the profiling executable for $(PARTICLES) particles and prepares the results folder.
#
# $(COMPILER)                          Calls the compiler (gcc).
# $(COMPILER_FLAGS)                    Passes optimization, debug symbol, and warning flags.
# -D NUMBER_OF_PARTICLES=$(PARTICLES)  Defines the compile-time preprocessor macro for particle count.
# $(SOURCE_FILE)                       Input C++ source file (../src/MD.cpp).
# -lm                                  Links the standard math library (`libm`) for functions like sqrt().
# -o $(PROFILING_BINARY)               Sets the output executable name (md_profiling).

build:
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
# Measures total execution time, CPU cycles, and instruction count averaged over 5 runs.
# Prerequisite: `build` runs first so $(PROFILING_BINARY) matches $(PARTICLES).
#
# --repeat 5             Repeats the command 5 times and reports mean +- spread (short form: -r 5).
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
		--repeat 5 \
		--event task-clock,cycles,instructions \
		--output $(RESULTS_FOLDER)/metric_N$(PARTICLES).txt \
		sh -c './$(PROFILING_BINARY) \
				< $(INPUT_FILE) \
				> /dev/null'

	@cat $(RESULTS_FOLDER)/metric_N$(PARTICLES).txt


# ==============================================================================
# 5. HOUSEKEEPING (`clean`)
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
		cp_output.txt \
		cp_average.txt \
		cp_traj.xyz

