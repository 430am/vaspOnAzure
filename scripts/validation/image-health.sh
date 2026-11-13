#!/bin/bash
set -euo pipefail
mode=${1:-runtime}
[[ $mode == build || $mode == runtime || $mode == firstboot ]] || { echo "Use build, runtime or firstboot." >&2; exit 2; }
[[ -d /opt/vasp-image/manifests && -s /opt/vasp-image/manifests/mpi.txt ]] || {
    echo "Safe build manifests are missing." >&2; exit 1;
}
prefix=$(cat /opt/vasp-image/manifests/install-prefix)
source /etc/profile.d/modules.sh
module load mpi/openmpi-tcp
shopt -s nullglob
manifests=(/opt/vasp-image/manifests/cpu_mpi.json /opt/vasp-image/manifests/a100_gpu.json /opt/vasp-image/manifests/h100_gpu.json)
(( ${#manifests[@]} > 0 )) || { echo "No VASP profiles installed." >&2; exit 1; }
for manifest in "${manifests[@]}"; do
    profile=$(jq -er .profile "$manifest")
    version=$(jq -er .vasp_version "$manifest")
    for binary in vasp_std vasp_gam vasp_ncl; do
        path="$prefix/$version/$profile/bin/$binary"
        [[ -x $path ]] || { echo "VASP binary missing." >&2; exit 1; }
        linkage=$(ldd "$path")
        [[ $linkage != *"not found"* && $linkage == *"/opt/vasp-image/toolchain/openmpi/lib/libmpi"* ]] || {
            echo "VASP linkage is unresolved or MPI is inconsistent." >&2; exit 1;
        }
    done
done
# Search installed/local writable trees, excluding approved SDK/compiler source packages.
roots=("$prefix" /opt/vasp-image)
if [[ $mode == build ]]; then
    for directory in /home /root /tmp /var/tmp /mnt; do
        [[ ! -d $directory ]] || roots+=("$directory")
    done
fi
suspects=$(find "${roots[@]}" -xdev \
    \( -type f \( -iname 'POTCAR*' -o -iname '*vasp*.tar*' -o -iname 'vasp*.tgz' \
    -o -iname '*.F' -o -name 'makefile.include' \
    -o -name '*.pem' -o -name '*.pfx' -o -name 'munge.key' \) \
    -o -type f \( -name id_rsa -o -name id_ed25519 -o -name id_ecdsa \) \
    -o -type d \( -name 'vasp.6.*' -o -name '.azure' \) \) -print 2>/dev/null)
[[ -z $suspects ]] || { echo "Prohibited image material detected; publication blocked." >&2; exit 1; }
if [[ $mode == build ]]; then
    [[ ! -f /etc/munge/munge.key && ! -f /etc/slurm/slurm.conf && ! -f /etc/slurm-llnl/slurm.conf ]] || exit 1
    hostkeys=(/etc/ssh/ssh_host_*_key)
    (( ${#hostkeys[@]} == 0 )) || { echo "SSH host keys remain before capture." >&2; exit 1; }
    cluster_configs=$(find /etc /opt -xdev -type f \
        \( -name slurm.conf -o -name munge.key \) -print)
    [[ -z $cluster_configs ]] || { echo "Cluster configuration/keys remain before capture." >&2; exit 1; }
else
    if [[ $mode == runtime ]]; then
        cloud-init status --wait
    fi
    systemctl is-active walinuxagent
    [[ -s /etc/machine-id ]] || { echo "First boot did not regenerate machine identity." >&2; exit 1; }
fi
printf 'Image static/linkage validation passed (%s); runtime cluster identities are allowed only after first boot.\n' "$mode"
