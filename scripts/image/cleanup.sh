#!/bin/bash
set -euo pipefail
# These are mutable cluster/machine identities, not reusable image assets.
rm -f -- /etc/munge/munge.key /etc/slurm/slurm.conf /etc/slurm-llnl/slurm.conf
find /etc/ssh -maxdepth 1 -type f -name 'ssh_host_*' -delete
rm -f -- /root/.ssh/authorized_keys /root/.bash_history
apt-get clean
bash /opt/vasp-image/bin/image-health.sh build
cloud-init clean --logs --seed
waagent -deprovision+user -force
# Empty machine ID is regenerated at boot. Do not disable cloud-init or the Azure agent.
truncate -s 0 /etc/machine-id
if [[ -f /var/lib/dbus/machine-id && ! -L /var/lib/dbus/machine-id ]]; then
    truncate -s 0 /var/lib/dbus/machine-id
fi
# AIB owns its staging directory and the final capture/deprovision lifecycle.
rm -rf -- /var/tmp/vasp-image-pipeline
