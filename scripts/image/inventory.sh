#!/bin/bash
set -euo pipefail
phase=${1:?inventory phase required}
[[ $phase == before || $phase == after ]] || exit 2
install -d -m 755 /opt/vasp-image/manifests
{
    printf 'phase=%s\nutc=%s\n' "$phase" "$(date -u +%FT%TZ)"
    cat /etc/os-release
    uname -r
    dpkg-query -W -f='${Package}\t${Version}\n'
    for binary in nvfortran nvc nvcc mpicc mpirun ompi_info ucx_info h5fc h5pfc; do
        if command -v "$binary" >/dev/null; then
            printf 'discovered_binary=%s\n' "$(command -v "$binary")"
        fi
    done
    for directory in /opt/nvidia /opt/hpcx /opt/microsoft; do
        [[ -d $directory ]] || continue
        find "$directory" -maxdepth 8 \
            \( -name nvfortran -o -name nvcc -o -name hpcx-init.sh -o -name libucp.so \
            -o -name libnccl.so -o -name libhdf5.so -o -name libscalapack.so \) -print
    done
    ldconfig -p | awk '/lib(mpi|ucp|nccl|cudart|fftw|blas|lapack|scalapack|hdf5)/'
} > "/opt/vasp-image/manifests/inventory-$phase.txt"
# Record the platform-image reference actually used on this VM when IMDS exposes it.
curl --fail --silent --show-error --noproxy '*' -H Metadata:true \
    'http://169.254.169.254/metadata/instance/compute/storageProfile/imageReference?api-version=2021-02-01' \
    > "/opt/vasp-image/manifests/base-image-$phase.json"
