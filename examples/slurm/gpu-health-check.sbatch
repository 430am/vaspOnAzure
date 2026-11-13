#!/bin/bash
#SBATCH --job-name=gpu-health
#SBATCH --partition=vasp-a100
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --gres=gpu:1
#SBATCH --time=00:10:00
#SBATCH --output=gpu-health-%j.log
set -euo pipefail
generation=${VASP_GPU_GENERATION:-a100}
source /etc/profile.d/modules.sh
module load "vasp/${VASP_VERSION:-6.4.3}-$generation"
source /opt/vasp-image/bin/runtime.sh
vasp_allocation
srun --mpi=none --export=ALL --cpu-bind=cores --gpu-bind=closest \
    /opt/vasp-image/bin/gpu-health.sh "$generation"
srun --mpi=none --export=ALL /opt/vasp-image/bin/image-health.sh runtime
