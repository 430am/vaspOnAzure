#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$root"
python3 -m unittest discover -s scripts/source -p 'test_*.py'
python3 scripts/validation/repository-check.py
python3 -m unittest discover -s scripts/validation -p 'test_*.py'
terraform fmt -recursive -check
for state in factory publication validation; do
    terraform -chdir="environments/dev/$state" init -backend=false -input=false
    terraform -chdir="environments/dev/$state" validate
done
mapfile -t scripts < <(find scripts examples cyclecloud -type f \( -name '*.sh' -o -name '*.sbatch' \))
shellcheck -x -P SCRIPTDIR "${scripts[@]}"
