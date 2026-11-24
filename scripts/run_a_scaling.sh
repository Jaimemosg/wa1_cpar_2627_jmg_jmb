#!/bin/bash
#SBATCH -A f202500010hpcvlabuminhoa
#SBATCH -p normal-arm
#SBATCH -t 00:10:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=48
#SBATCH --output=out.o%j
#SBATCH --error=err.e%j

# Version A, OpenMP scalability on one A64FX node (48 cores).
#   Part A: cost vs N on 1 thread         (N = 200 400 800 1600)
#   Part B: speedup vs threads at N=1600  (threads = 2 4 8 12 24 48)
#   Part C: N sweep at 48 threads         (speedup vs N)
# Every run uses the same OpenMP build, so T1 and Tp come from the same code.
#
# Submit from the wa1_jj/ folder:   sbatch scripts/run_a_scaling.sh
# Results: results/md_a_scaling/t<threads>/metric_N<N>.txt

# Load modules INSIDE the ARM node (not on the login node)
ml purge
ml GCC

RESULTS=results/md_a_scaling

run() {   # $1 = particles, $2 = threads
    echo "=== N=$1  threads=$2 ==="
    OMP_NUM_THREADS=$2 make metrics \
        FOLDER_NAME=md_a \
        PARTICLES=$1 \
        REPEATS=5 \
        OPENMP=1 \
        COMPILER="gcc -march=native" \
        RESULTS_FOLDER=$RESULTS/t$2
}

# Part A: N sweep, 1 thread
for N in 200 400 800 1600; do run $N 1; done

# Part B: thread sweep at N=1600 (1 thread already done in Part A)
for T in 2 4 8 12 24 48; do run 1600 $T; done

# Part C: N sweep at 48 threads (N=1600 already done in Part B)
for N in 200 400 800; do run $N 48; done

# Summary: wall time from each perf file (not task-clock, which adds up all threads)
grep "seconds time elapsed" $RESULTS/t*/metric_N*.txt
