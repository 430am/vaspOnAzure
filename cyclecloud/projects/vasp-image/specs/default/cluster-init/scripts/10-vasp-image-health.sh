#!/bin/bash
set -euo pipefail
test -x /opt/vasp-image/bin/image-health.sh
# Jetpack/Slurm/munge/mounts are supplied by the inherited CycleCloud project.
# Do not wait for cloud-init from inside its own node initialization.
/opt/vasp-image/bin/image-health.sh firstboot
