#!/bin/bash
#SBATCH -A f202500010hpcvlabuminhoa
#SBATCH -p normal-arm
#SBATCH -t 00:45:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=48
#SBATCH --output=out.o%j
#SBATCH --error=err.e%j

# Version C, OpenMP scalability on one A64FX node (48 cores).
#   Part A: cost vs N on 1 thread         (N = 200 400 800 1600)
#   Part B: speedup vs threads at N=1600  (threads = 2 4 8 12 24 48)
#   Part C: N sweep at 48 threads         (speedup vs N)
# Every run uses the same OpenMP build, so T1 and Tp come from the same code.
#
# Submit from the project root folder:   sbatch scripts/run_scaling.sh
# Results: results/md_c_scaling/t<threads>/metric_N<N>.txt

# Load modules INSIDE the ARM node (not on the login node)
ml purge
ml GCC

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <folder>" >&2
    exit 1
fi

FOLDER=$1
REPEATS=${REPEATS:-5}
RESULTS_ROOT=${RESULTS_ROOT:-results}
RESULTS=$RESULTS_ROOT/${FOLDER}_scaling

run() {   # $1 = particles, $2 = threads
    echo "=== N=$1  threads=$2 ==="
    OMP_NUM_THREADS=$2 make metrics \
        FOLDER_NAME=$FOLDER \
        PARTICLES=$1 \
        REPEATS=$REPEATS \
        OPENMP=1 \
        COMPILER="gcc -march=native" \
        RESULTS_FOLDER=$RESULTS/t$2
}

# Part A: N sweep, 1 thread
for N in 200 400 800 1600 3200 5000; do run $N 1; done

# Part B: thread sweep at N=1600 (1 thread already done in Part A)
for T in 2 4 8 12 16 24 32 36 48; do run 1600 $T; done
for T in 2 4 8 12 16 24 32 36 48; do run 5000 $T; done

# Part C: N sweep at 48 threads (N=1600 & 5000 already done in Part B)
for N in 200 400 800 3200; do run $N 48; done

# Summary: wall time from each perf file (not task-clock, which adds up all threads)
grep "seconds time elapsed" $RESULTS/t*/metric_N*.txt
