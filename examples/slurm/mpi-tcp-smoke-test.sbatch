#!/bin/bash
#SBATCH --job-name=mpi-tcp-verify
#SBATCH --partition=vasp-a100
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --gres=gpu:1
#SBATCH --time=00:10:00
#SBATCH --output=mpi-tcp-%j.log
set -euo pipefail
generation=${VASP_GPU_GENERATION:-a100}
[[ $generation == a100 || $generation == h100 ]] || exit 2
source /etc/profile.d/modules.sh
module load "vasp/${VASP_VERSION:-6.4.3}-$generation"
source /opt/vasp-image/bin/runtime.sh
mode=$(vasp_mpi_mode)
vasp_allocation
export MPI_SMOKE_MIN_NODES="${SLURM_JOB_NUM_NODES:?}"
export OMPI_MCA_btl_base_verbose=30
srun --mpi="$mode" --export=ALL --cpu-bind=cores --gpu-bind=closest \
    /opt/vasp-image/bin/mpi-task.sh --generation "$generation" \
    /opt/vasp-image/bin/mpi-smoke --gpu
echo "Verify verbose TCP connection lines use the private addresses reported above; configuration alone is not proof."
