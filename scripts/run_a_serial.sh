#!/bin/bash
#SBATCH -A f202500010hpcvlabuminhoa
#SBATCH -p normal-arm
#SBATCH -t 00:15:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --output=out.o%j
#SBATCH --error=err.e%j

# Version A, serial: vectorized vs non-vectorized. Measures time, cycles, instructions.
# Submit from the wa1_jj/ folder:   sbatch scripts/run_a_serial.sh

# Load modules INSIDE the ARM node (not on the login node)
ml purge
ml GCC

FOLDER="md_a"
PARTICLES=${PARTICLES:-800}
REPEATS=${REPEATS:-5}
RESULTS_ROOT=${RESULTS_ROOT:-results}

# vec:   -march=native (SVE on A64FX)
make metrics \
 FOLDER_NAME=$FOLDER \
 PARTICLES=$PARTICLES \
 REPEATS=$REPEATS \
 OPENMP=0 \
 COMPILER="gcc -march=native" \
 RESULTS_FOLDER=$RESULTS_ROOT/${FOLDER}_serial_vec

cp src/$FOLDER/md_profiling $RESULTS_ROOT/${FOLDER}_serial_vec/

# novec: same, with loop and SLP vectorization disabled
make metrics \
 FOLDER_NAME=$FOLDER \
 PARTICLES=$PARTICLES \
 REPEATS=$REPEATS \
 OPENMP=0 \
 COMPILER="gcc -march=native -fno-tree-vectorize -fno-tree-slp-vectorize" \
 RESULTS_FOLDER=$RESULTS_ROOT/${FOLDER}_serial_novec
cp src/$FOLDER/md_profiling $RESULTS_ROOT/${FOLDER}_serial_novec/

# Summary table
echo
printf "%-6s %12s %16s %16s\n" build seconds cycles instructions
for TAG in vec novec; do
    M=$RESULTS_ROOT/${FOLDER}_serial_${TAG}/metric_N${PARTICLES}.txt
    printf "%-6s %12s %16s %16s\n" $TAG \
        "$(awk '/seconds time elapsed/ {print $1}' $M)" \
        "$(awk '$2 ~ /^cycles/       {gsub(",","",$1); print $1}' $M)" \
        "$(awk '$2 ~ /^instructions/ {gsub(",","",$1); print $1}' $M)"
done
