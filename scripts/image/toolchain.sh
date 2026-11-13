#!/bin/bash
set -euo pipefail
config=/var/tmp/vasp-image-pipeline/config.json
work=/var/tmp/vasp-protected-build
version=$(jq -r .nvhpc_version "$config")
[[ $version =~ ^[0-9]{2}\.[0-9]{1,2}$ ]] || { echo "Invalid NVHPC version." >&2; exit 1; }
nvroot="/opt/nvidia/hpc_sdk/Linux_x86_64/$version"
if [[ ! -x $nvroot/compilers/bin/nvfortran ]]; then
    [[ $(jq -r .install_missing_nvhpc "$config") == true ]] || {
        echo "Selected NVHPC is missing; installation is disabled." >&2; exit 1;
    }
    curl --fail --silent --show-error https://developer.download.nvidia.com/hpc-sdk/ubuntu/DEB-GPG-KEY-NVIDIA-HPC-SDK \
        -o "$work/nvhpc-key"
    gpg --batch --yes --dearmor -o /usr/share/keyrings/nvidia-hpc-sdk.gpg "$work/nvhpc-key"
    printf '%s\n' 'deb [signed-by=/usr/share/keyrings/nvidia-hpc-sdk.gpg] https://developer.download.nvidia.com/hpc-sdk/ubuntu/amd64 /' \
        > /etc/apt/sources.list.d/nvhpc.list
    apt-get update -qq
    apt-get install -y --no-install-recommends "nvhpc-${version/./-}-cuda-multi"
fi
cuda="$nvroot/cuda/12.3"
[[ -x $cuda/bin/nvcc && -d $cuda/include ]] || {
    echo "Selected SDK must include CUDA 12.3 (A100 sm80 and H100 sm90)." >&2; exit 1;
}
export PATH="$nvroot/compilers/bin:$cuda/bin:/usr/bin:/bin"
export LD_LIBRARY_PATH="$nvroot/compilers/lib"
prefix=/opt/vasp-image/toolchain
install -d -m 755 "$prefix"
mpi_version=4.1.8
mpi_sha=fb41086bbed9300baa2f3d7572491facfe5257412fa524ec5a396aa9101d5c62
curl --fail --silent --show-error \
    "https://download.open-mpi.org/release/open-mpi/v4.1/openmpi-$mpi_version.tar.gz" -o "$work/openmpi.tar.gz"
printf '%s  %s\n' "$mpi_sha" "$work/openmpi.tar.gz" | sha256sum --check --status
tar -xzf "$work/openmpi.tar.gz" -C "$work"
cd "$work/openmpi-$mpi_version"
# One stack for every profile: NVHPC Fortran, CUDA-aware OB1/TCP, and Slurm PMI2.
./configure --prefix="$prefix/openmpi" CC=nvc CXX=nvc++ FC=nvfortran \
    CFLAGS="-O2 -tp px" CXXFLAGS="-O2 -tp px" FCFLAGS="-O2 -tp px" \
    --with-cuda="$cuda" --with-cuda-libdir="$cuda/lib64/stubs" \
    --with-pmi=/usr --with-slurm --with-pmix=internal \
    --without-verbs --without-ucx --without-libfabric --without-psm --without-psm2 \
    --disable-oshmem --disable-mpi-java --disable-ipv6 > "$work/openmpi-configure.log" 2>&1
make -j "$(nproc)" > "$work/openmpi-build.log" 2>&1
make install > "$work/openmpi-install.log" 2>&1
export PATH="$prefix/openmpi/bin:$PATH"
export LD_LIBRARY_PATH="$prefix/openmpi/lib:$LD_LIBRARY_PATH"
ompi_info --parsable --all > "$work/ompi-info"
grep -q 'mpi_built_with_cuda_support:value:true' "$work/ompi-info" || {
    echo "Open MPI CUDA-aware support is missing." >&2; exit 1;
}
grep -q 'mca:ess:pmi:' "$work/ompi-info" || { echo "Open MPI PMI2 component is missing." >&2; exit 1; }
grep -q 'mca:pmix:s2:' "$work/ompi-info" || { echo "Open MPI PMI2 client backend is missing." >&2; exit 1; }
grep -q 'mca:btl:smcuda:' "$work/ompi-info" || { echo "Open MPI smcuda component is missing." >&2; exit 1; }
scalapack_sha=8862fc9673acf5f87a474aaa71cd74ae27e9bbeee475dbd7292cec5b8bcbdcf3
curl --fail --silent --show-error \
    https://github.com/Reference-ScaLAPACK/scalapack/archive/refs/tags/v2.2.0.tar.gz -o "$work/scalapack.tar.gz"
printf '%s  %s\n' "$scalapack_sha" "$work/scalapack.tar.gz" | sha256sum --check --status
tar -xzf "$work/scalapack.tar.gz" -C "$work"
OMPI_ALLOW_RUN_AS_ROOT=1 OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1 \
cmake -S "$work/scalapack-2.2.0" -B "$work/scalapack-build" \
    -DCMAKE_INSTALL_PREFIX="$prefix/math" -DCMAKE_C_COMPILER=mpicc \
    -DCMAKE_Fortran_COMPILER=mpifort -DBUILD_SHARED_LIBS=ON -DBUILD_TESTING=OFF \
    -DCMAKE_C_FLAGS="-O2 -tp px" -DCMAKE_Fortran_FLAGS="-O2 -tp px" \
    -DBLAS_LIBRARIES=/usr/lib/x86_64-linux-gnu/libblas.so \
    -DLAPACK_LIBRARIES=/usr/lib/x86_64-linux-gnu/liblapack.so > "$work/scalapack-configure.log" 2>&1
cmake --build "$work/scalapack-build" -j "$(nproc)" > "$work/scalapack-build.log" 2>&1
cmake --install "$work/scalapack-build" > "$work/scalapack-install.log" 2>&1
printf '%s\n' "$nvroot" > "$prefix/nvroot"
printf '%s\n' "$cuda" > "$prefix/cuda"
nvfortran --version > /opt/vasp-image/manifests/compiler.txt
mpirun --version > /opt/vasp-image/manifests/mpi.txt
nvcc --version > /opt/vasp-image/manifests/cuda.txt
cp "$work/ompi-info" /opt/vasp-image/manifests/ompi-info.txt
