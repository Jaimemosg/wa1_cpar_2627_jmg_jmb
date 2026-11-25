#!/bin/bash
#SBATCH -A f202500010hpcvlabuminhoa
#SBATCH -p normal-arm
#SBATCH -t 00:45:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --output=out.o%j
#SBATCH --error=err.e%j

# Sequential baseline (md_baseline) metrics on one A64FX core for plot_scalability.py.
# Collects results/md_baseline/metric_N1600.txt (and metric_N5000.txt by default).
#
# Submit from the project root folder:   sbatch scripts/run_baseline.sh
# Override particle list if needed:      PARTICLES_LIST="1600" sbatch scripts/run_baseline.sh

# Load modules INSIDE the ARM node (not on the login node)
ml purge
ml GCC

FOLDER="md_b"
PARTICLES_LIST=${PARTICLES_LIST:-"1600 5000"}
REPEATS=${REPEATS:-5}
RESULTS_ROOT=${RESULTS_ROOT:-results}
RESULTS=$RESULTS_ROOT/$FOLDER

for N in $PARTICLES_LIST; do
    echo "=== baseline N=$N ==="
    make metrics \
        FOLDER_NAME=$FOLDER \
        PARTICLES=$N \
        REPEATS=$REPEATS \
        OPENMP=0 \
        COMPILER="gcc -march=native" \
        RESULTS_FOLDER=$RESULTS
done

# Summary: wall time from each perf file
grep "seconds time elapsed" $RESULTS/metric_N*.txt
