#!/bin/bash
#SBATCH -A f202500010hpcvlabuminhoa
#SBATCH -p normal-arm
#SBATCH -t 00:20:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=48
#SBATCH --output=out.o%j
#SBATCH --error=err.e%j

# Load modules INSIDE the ARM node (not on the login node)
ml purge
ml GCC

# Optional parameters (adjust according to the experiment)
FOLDER="__FOLDER__"
PARTICLES=5000
REPEATS=4
OPENMP=1
export OMP_NUM_THREADS=__THREADS__

make metrics  FOLDER_NAME=$FOLDER PARTICLES=$PARTICLES REPEATS=$REPEATS OPENMP=$OPENMP
