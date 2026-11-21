#!/bin/sh
set -eu

# Keep perf reports compatible with the aggregation script.
export LC_ALL=C
cd "$(dirname "$0")"
export OMP_DYNAMIC=FALSE

# Override these lists through environment variables for smaller/custom runs.
PARTICLE_COUNTS=${PARTICLE_COUNTS:-"200 400 800 1600"}
THREAD_COUNTS=${THREAD_COUNTS:-"1 2 4"}
REPEATS=${REPEATS:-5}

for threads in $THREAD_COUNTS; do
    export OMP_NUM_THREADS="$threads"
    for n in $PARTICLE_COUNTS; do
        printf '\nBenchmarking %s particles with %s threads\n' "$n" "$threads"
        make metrics FOLDER_NAME=md_a OPENMP=1 \
            PARTICLES="$n" REPEATS="$REPEATS" \
            RESULTS_FOLDER="results/md_a_t${threads}"
    done
done
