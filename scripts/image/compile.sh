#!/bin/bash
set -euo pipefail
work=/var/tmp/vasp-protected-build
config=/var/tmp/vasp-image-pipeline/config.json
prefix=$(jq -r .vasp_install_prefix "$config")
version=$(jq -r .vasp_version "$config")
[[ $prefix =~ ^/opt/[a-zA-Z0-9_/-]+$ && $prefix != *..* && $version =~ ^6\.[0-9]+\.[0-9]+$ ]] || exit 2
toolchain=/opt/vasp-image/toolchain
nvroot=$(cat "$toolchain/nvroot")
cuda=$(cat "$toolchain/cuda")
export PATH="$toolchain/openmpi/bin:$nvroot/compilers/bin:/usr/bin:/bin"
export LD_LIBRARY_PATH="$toolchain/openmpi/lib:$toolchain/math/lib:$nvroot/compilers/lib:$nvroot/compilers/extras/qd/lib:$cuda/lib64:$nvroot/math_libs/12.3/targets/x86_64-linux/lib"
mapfile -t profiles < <(jq -r '.vasp_build_profiles[]' "$config")
for profile in "${profiles[@]}"; do
    case "$profile" in
        cpu_mpi) target=none; flags=""; default_template=arch/makefile.include.nvhpc ;;
        a100_gpu) target=cc80; flags="-acc -gpu=cc80,cuda12.3"; default_template=arch/makefile.include.nvhpc_acc ;;
        h100_gpu) target=cc90; flags="-acc -gpu=cc90,cuda12.3"; default_template=arch/makefile.include.nvhpc_acc ;;
        *) echo "Unsupported VASP profile." >&2; exit 2 ;;
    esac
    template=$(jq -r --arg profile "$profile" '.vasp_makefile_templates[$profile] // empty' "$config")
    template=${template:-$default_template}
    [[ $template == arch/* && $template != *..* && -f $work/input/vasp/$template ]] || {
        echo "Required operator/bundled makefile template is missing or unsafe." >&2; exit 1;
    }
    tree="$work/$profile"
    cp -a "$work/input/vasp" "$tree"
    cp "$tree/$template" "$tree/makefile.include"
    # Only build configuration is overridden; no licensed source files are patched.
    cat >> "$tree/makefile.include" <<EOF

NVROOT = $nvroot
CC = $toolchain/openmpi/bin/mpicc $flags -tp px
FC = $toolchain/openmpi/bin/mpifort $flags
FCL = $toolchain/openmpi/bin/mpifort $flags -c++libs
CXX_PARS = nvc++ --no_warnings -tp px
VASP_TARGET_CPU = -tp px
FFTW_ROOT = /usr
SCALAPACK = -L$toolchain/math/lib -lscalapack
BLAS = -lblas
LAPACK = -llapack
CPP_OPTIONS := \$(filter-out -DUSENCCL,\$(CPP_OPTIONS))
EOF
    # GNU Make expands these variables after loading the selected template.
    # shellcheck disable=SC2016
    options=$(make -s -C "$tree" -f makefile.include VERSION=std \
        --eval='__vasp_options:;@printf "%s\n" "$(CPP_OPTIONS)"' __vasp_options)
    if [[ $profile != cpu_mpi && $options != *-D_OPENACC* && $options != *-DACC_OFFLOAD* ]]; then
        echo "GPU template must enable the source version's OpenACC backend." >&2; exit 1
    fi
    nccl=false
    hdf5=false
    [[ $options != *-DUSENCCL* ]] || nccl=true
    [[ $options != *-DVASP_HDF5* ]] || hdf5=true
    # Compiler diagnostics can contain licensed lines: keep all output in the protected directory.
    if ! make -C "$tree" DEPS=1 -j "$(nproc)" all > "$work/vasp-$profile.log" 2>&1; then
        echo "VASP $profile compilation failed. Logs are restricted and will be deleted; reproduce only in an approved source environment." >&2
        exit 1
    fi
    install -d -m 755 "$prefix/$version/$profile/bin"
    for binary in vasp_std vasp_gam vasp_ncl; do
        [[ -x $tree/bin/$binary ]] || { echo "Missing requested VASP executable." >&2; exit 1; }
        install -m 755 "$tree/bin/$binary" "$prefix/$version/$profile/bin/$binary"
        linkage=$(ldd "$prefix/$version/$profile/bin/$binary")
        [[ $linkage != *"not found"* ]] || { echo "VASP runtime library is unresolved." >&2; exit 1; }
        [[ $linkage == *"$toolchain/openmpi/lib/libmpi"* ]] || {
            echo "VASP linked against the wrong MPI stack." >&2; exit 1;
        }
        printf '%s\n' "$linkage" > "/opt/vasp-image/manifests/$profile-$binary-linkage.txt"
    done
    jq -n --arg v "$version" --arg p "$profile" --arg target "$target" \
        --arg checksum "$(jq -r .vasp_source_checksum "$config")" \
        --arg nvhpc "$(jq -r .nvhpc_version "$config")" \
        --arg utc "$(date -u +%FT%TZ)" --arg flags "$flags -tp px" \
        --arg pipeline "$(jq -r .pipeline_name "$config")" \
        --argjson nccl "$nccl" --argjson hdf5 "$hdf5" \
        '{vasp_version:$v, profile:$p, gpu_target:$target, source_sha256:$checksum,
          nvhpc:$nvhpc, cuda:"12.3", mpi:"Open MPI 4.1.8", mpi_launch:"PMI2",
          mpi_transport:"OB1 TCP, self, smcuda", scalapack:"2.2.0 (same MPI)",
          math:"Ubuntu BLAS/LAPACK/FFTW; package versions in inventory",
          openacc:($p!="cpu_mpi"), nccl:$nccl, cuda_aware_mpi:true,
          hdf5:$hdf5,
          flags:$flags, cpu_target:"portable px", built_at:$utc, pipeline:$pipeline}' \
        > "/opt/vasp-image/manifests/$profile.json"
done
