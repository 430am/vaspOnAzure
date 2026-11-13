#!/bin/bash
set -euo pipefail
config=/var/tmp/vasp-image-pipeline/config.json
toolchain=/opt/vasp-image/toolchain
nvroot=$(cat "$toolchain/nvroot")
cuda=$(cat "$toolchain/cuda")
prefix=$(jq -r .vasp_install_prefix "$config")
version=$(jq -r .vasp_version "$config")
port_min=$(jq -r .mpi_tcp_port_min "$config")
port_count=$(jq -r .mpi_tcp_port_count "$config")
(( port_min >= 1024 && port_count > 0 && port_min + port_count - 1 <= 65535 )) || {
    echo "Invalid MPI TCP port interval." >&2; exit 1;
}
install -d -m 755 /usr/share/modules/modulefiles/mpi /usr/share/modules/modulefiles/vasp
cat > /usr/share/modules/modulefiles/mpi/openmpi-tcp <<EOF
#%Module1.0
conflict mpi
prepend-path PATH $nvroot/compilers/bin
prepend-path PATH $toolchain/openmpi/bin
prepend-path LD_LIBRARY_PATH $nvroot/compilers/lib
prepend-path LD_LIBRARY_PATH $nvroot/compilers/extras/qd/lib
prepend-path LD_LIBRARY_PATH $toolchain/math/lib
prepend-path LD_LIBRARY_PATH $toolchain/openmpi/lib
prepend-path LD_LIBRARY_PATH $cuda/lib64
prepend-path LD_LIBRARY_PATH $nvroot/math_libs/12.3/targets/x86_64-linux/lib
setenv VASP_MPI_PREFIX $toolchain/openmpi
setenv VASP_MPI_MODE pmi2
setenv MPI_TCP_PORT_MIN $port_min
setenv MPI_TCP_PORT_COUNT $port_count
setenv OMPI_MCA_pml ob1
setenv OMPI_MCA_btl self,smcuda,tcp
setenv OMPI_MCA_coll ^hcoll,ucc
setenv NCCL_IB_DISABLE 1
setenv OMP_NUM_THREADS 1
EOF
mapfile -t profiles < <(jq -r '.vasp_build_profiles[]' "$config")
for profile in "${profiles[@]}"; do
    case "$profile" in
        cpu_mpi) suffix=cpu ;;
        a100_gpu) suffix=a100 ;;
        h100_gpu) suffix=h100 ;;
        *) exit 2 ;;
    esac
    cat > "/usr/share/modules/modulefiles/vasp/$version-$suffix" <<EOF
#%Module1.0
conflict vasp
module load mpi/openmpi-tcp
prepend-path PATH $prefix/$version/$profile/bin
setenv VASP_PROFILE $profile
setenv VASP_VERSION $version
setenv VASP_INSTALL_PREFIX $prefix
EOF
done
export PATH="$toolchain/openmpi/bin:$nvroot/compilers/bin:/usr/bin:/bin"
export LD_LIBRARY_PATH="$toolchain/openmpi/lib:$nvroot/compilers/lib:$cuda/lib64"
mpicc -O2 -tp px -I"$cuda/include" /opt/vasp-image/bin/mpi-smoke.c \
    -L"$cuda/lib64" -lcudart -o /opt/vasp-image/bin/mpi-smoke
rm -- /opt/vasp-image/bin/mpi-smoke.c
cp /var/tmp/vasp-image-pipeline/runtime.sh /opt/vasp-image/bin/runtime.sh
chmod 755 /opt/vasp-image/bin/runtime.sh
source /etc/profile.d/modules.sh
module load "vasp/$version-${suffix}"
[[ $(command -v mpirun) == "$toolchain/openmpi/bin/mpirun" ]] || exit 1
module unload "vasp/$version-${suffix}" mpi/openmpi-tcp
printf '%s\n' "$prefix" > /opt/vasp-image/manifests/install-prefix
