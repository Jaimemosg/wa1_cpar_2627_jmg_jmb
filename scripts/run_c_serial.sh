#!/bin/bash
#SBATCH -A f202500010hpcvlabuminhoa
#SBATCH -p normal-arm
#SBATCH -t 00:15:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --output=out.o%j
#SBATCH --error=err.e%j

# Version C, serial: vectorized vs non-vectorized. Measures time, cycles, instructions,
# and counts SVE arithmetic instructions in Potential() and computeAccelerations().
# Submit from the project root folder:   sbatch scripts/run_c_serial.sh

# Load modules INSIDE the ARM node (not on the login node)
ml purge
ml GCC

FOLDER="md_c"
PARTICLES=${PARTICLES:-800}
REPEATS=${REPEATS:-5}
RESULTS_ROOT=${RESULTS_ROOT:-results}

VEC_DIR=$RESULTS_ROOT/${FOLDER}_serial_vec
NOVEC_DIR=$RESULTS_ROOT/${FOLDER}_serial_novec

# vec:   -march=native (SVE on A64FX)
rm -f "$VEC_DIR/md_profiling"
make metrics \
    FOLDER_NAME=$FOLDER \
    PARTICLES=$PARTICLES \
    REPEATS=$REPEATS \
    OPENMP=0 \
    COMPILER="gcc -march=native" \
    RESULTS_FOLDER="$VEC_DIR"

if [ ! -f "$VEC_DIR/md_profiling" ] && [ -f "src/$FOLDER/md_profiling" ]; then
    cp "src/$FOLDER/md_profiling" "$VEC_DIR/"
fi

# novec: same, with loop and SLP vectorization disabled
rm -f "$NOVEC_DIR/md_profiling"
make metrics \
    FOLDER_NAME=$FOLDER \
    PARTICLES=$PARTICLES \
    REPEATS=$REPEATS \
    OPENMP=0 \
    COMPILER="gcc -march=native -fno-tree-vectorize -fno-tree-slp-vectorize" \
    RESULTS_FOLDER="$NOVEC_DIR"

if [ ! -f "$NOVEC_DIR/md_profiling" ] && [ -f "src/$FOLDER/md_profiling" ]; then
    cp "src/$FOLDER/md_profiling" "$NOVEC_DIR/"
fi

# Summary table
echo
printf "%-6s %12s %16s %16s\n" build seconds cycles instructions
for TAG in vec novec; do
    M=$RESULTS_ROOT/${FOLDER}_serial_${TAG}/metric_N${PARTICLES}.txt
    printf "%-6s %12s %16s %16s\n" "$TAG" \
        "$(awk '/seconds time elapsed/ {print $1}' "$M")" \
        "$(awk '$2 ~ /^cycles/       {gsub(",","",$1); print $1}' "$M")" \
        "$(awk '$2 ~ /^instructions/ {gsub(",","",$1); print $1}' "$M")"
done

# Count SVE math instructions in both binaries
echo
./scripts/count_sve_math.sh "$VEC_DIR/md_profiling" "$NOVEC_DIR/md_profiling"
