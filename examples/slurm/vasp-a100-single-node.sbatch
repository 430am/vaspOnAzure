#!/bin/bash
#SBATCH --job-name=vasp-a100-1
#SBATCH --partition=vasp-a100
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH --time=01:00:00
#SBATCH --signal=B:TERM@60
#SBATCH --output=vasp-%j.log
set -euo pipefail
source /etc/profile.d/modules.sh
module load "vasp/${VASP_VERSION:-6.4.3}-a100"
source /opt/vasp-image/bin/runtime.sh
vasp_run a100
