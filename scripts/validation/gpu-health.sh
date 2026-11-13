#!/bin/bash
set -euo pipefail
generation=${1:?a100 or h100 required}
case "$generation" in
    a100) expected=8.0 ;;
    h100) expected=9.0 ;;
    *) echo "Unknown GPU validation generation." >&2; exit 2 ;;
esac
query=$(nvidia-smi --query-gpu=name,driver_version,compute_cap --format=csv,noheader)
printf '%s\n' "$query"
while IFS=, read -r _name driver capability; do
    capability=${capability// /}
    [[ $capability == "$expected" ]] || { echo "GPU compute capability differs from requested build profile." >&2; exit 1; }
    minimum=$(printf '%s\n' 545.23.08 "${driver// /}" | sort -V | head -n 1)
    [[ $minimum == 545.23.08 ]] || {
        echo "CUDA 12.3 full compatibility requires driver >=545.23.08. Do not replace the base driver automatically." >&2; exit 1;
    }
done <<< "$query"
[[ -n $query ]] || { echo "No GPU detected." >&2; exit 1; }
if [[ -n ${EXPECTED_GPU_COUNT:-} ]]; then
    count=$(nvidia-smi --query-gpu=uuid --format=csv,noheader | wc -l)
    (( count == EXPECTED_GPU_COUNT )) || { echo "GPU count differs from selected VM SKU." >&2; exit 1; }
fi
