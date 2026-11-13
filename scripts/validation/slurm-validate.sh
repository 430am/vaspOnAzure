#!/bin/bash
set -euo pipefail
partition=${1:?partition required}
generation=${2:?a100 or h100 required}
[[ $partition =~ ^[a-zA-Z0-9_-]+$ && $generation =~ ^(a100|h100)$ ]] || exit 2
: "${EXPECTED_IMAGE_VERSION_ID:?Supply the pinned version resource ID}"
: "${EXPECTED_GPU_COUNT:?Supply the GPU count for the selected SKU}"
: "${MPI_TCP_ALLOWED_CIDRS:?Supply the approved compute subnet CIDRs}"
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
sinfo -p "$partition" -N -o '%N %T %c %m %G'
srun --mpi=list
# An allocation triggers autoscaling; this does not modify the cluster template.
# shellcheck disable=SC2016
salloc --partition="$partition" --nodes=1 --ntasks=1 --cpus-per-task=1 --gres=gpu:1 \
    srun --mpi=none --export=ALL bash -c '
        set -euo pipefail
        scontrol show node "$SLURMD_NODENAME"
        /opt/vasp-image/bin/image-health.sh runtime
        /opt/vasp-image/bin/gpu-health.sh "$1"
        reference=$(curl --fail --silent --show-error --noproxy "*" -H Metadata:true \
          "http://169.254.169.254/metadata/instance/compute/storageProfile/imageReference?api-version=2021-02-01")
        id=$(jq -r ".id // .sharedGalleryImageId // empty" <<< "$reference")
        [[ ${id,,} == ${EXPECTED_IMAGE_VERSION_ID,,} ]] || {
            echo "Node did not boot from the expected gallery version." >&2; exit 1;
        }
        : "${VASP_SHARED_PATH:?Supply required shared POSIX path}"
        test -r "$VASP_SHARED_PATH" && test -w "$VASP_SHARED_PATH"
        findmnt -T "$VASP_SHARED_PATH"
    ' bash "$generation"
sbatch --wait --partition="$partition" --export=ALL,VASP_GPU_GENERATION="$generation" \
    "$root/examples/slurm/gpu-health-check.sbatch"
sbatch --wait --partition="$partition" --export=ALL,VASP_GPU_GENERATION="$generation" \
    "$root/examples/slurm/mpi-tcp-smoke-test.sbatch"
echo "Automated Slurm/image/GPU/MPI checks passed. VASP, cluster identity, scale-down, and reimage evidence are still required for promotion."
