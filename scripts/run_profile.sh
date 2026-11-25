#!/bin/bash
#SBATCH -A f202500010hpcvlabuminhoa
#SBATCH -p normal-arm
#SBATCH -t 00:10:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=48
#SBATCH --output=out.o%j
#SBATCH --error=err.e%j

# Load modules INSIDE the ARM node (not on the login node)
ml purge
ml GCC

# Optional parameters (adjust according to the experiment)
FOLDER="md_c"
PARTICLES=200
REPEATS=5
OPENMP=1
# export OMP_NUM_THREADS=4   # Uncomment to set the thread count instead of using all 48

make hotspots FOLDER_NAME=$FOLDER PARTICLES=$PARTICLES REPEATS=$REPEATS OPENMP=$OPENMP
# make metrics  FOLDER_NAME=$FOLDER PARTICLES=$PARTICLES REPEATS=$REPEATS OPENMP=$OPENMP