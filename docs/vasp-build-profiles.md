# Build profiles and toolchain contract

## Supported source and templates

Required authorized layout: `makefile`, `src/`, `arch/`. Default version is 6.4.3.
The pipeline does not change licensed `.F`/`.c` files or invent a source layout.
It copies the operator/bundled makefile to a protected per-profile build tree
and appends **build configuration overrides only**. Source diagnostics are
redirected to restricted temporary logs and deleted, even on failure.

| Profile | Default supplied template | CUDA target | Module |
| --- | --- | --- | --- |
| cpu_mpi | arch/makefile.include.nvhpc | none | vasp/6.4.3-cpu |
| a100_gpu | arch/makefile.include.nvhpc_acc | cc80 / CUDA 12.3 | vasp/6.4.3-a100 |
| h100_gpu | arch/makefile.include.nvhpc_acc | cc90 / CUDA 12.3 | vasp/6.4.3-h100 |

Only explicitly selected `vasp_build_profiles` are built. Each gets
`vasp_std`, `vasp_gam`, `vasp_ncl` under
`/opt/vasp/VERSION/PROFILE/bin`. `vasp_install_prefix` changes the root.
`vasp_makefile_templates` maps a profile to a relative `arch/...` path in the
approved staged source. Different versions/templates require an authorized
build review and fresh numerical validation.

## Internally consistent stack

SDK `nvhpc_version=24.3` supplies NVHPC compilers, QD, CUDA 12.3 and GPU math
libraries. Existing selected SDK installations are reused; missing installation
is controlled by `install_missing_nvhpc`. The NVIDIA signed apt repository
installs the selected release, **not a GPU driver**. The SDK's bundled MPI/
HPC-X is not used.

Open MPI 4.1.8 is built with NVHPC, CUDA-aware OB1/TCP, internal PMIx for internal
services, and Ubuntu's PMI2 client for Slurm direct launch. UCX, verbs and fabric
providers are excluded. ScaLAPACK 2.2.0 is built against **this same MPI**.
Ubuntu FFTW/BLAS/LAPACK use the conventional Fortran math ABI; exact package
versions and link paths are recorded. No MKL/HPC-X/UCX mixture is permitted.

CPU target `-tp px` favors portability across the selected AMD/Intel VM families;
it is not native-CPU optimization. A100 and H100 have independent SASS targets.
The target also applies to C/C++ and the privately built MPI/ScaLAPACK libraries,
so an Intel CPU build VM does not silently specialize those libraries for a
later AMD GPU node.
GPU templates must enable their source release's OpenACC backend. NCCL/HDF5
behavior also depends on the supplied template; check the generated option
summary and actual linkage. This strict TCP build removes `-DUSENCCL` from the
selected makefile configuration: NCCL's separate socket bootstrap can require
ports outside the configured MPI interval. GPU-aware MPI handles communication
instead. The SDK's NCCL library remains available but the VASP feature is off.
Enabling it requires a reviewed build/network change, not just an MPI-port rule.
Default templates leave HDF5 off.
If enabling HDF5, supply a Fortran-compatible library and template, and review
ABI/linkage; installing a random distro Fortran HDF5 module is not sufficient.

## Compatibility and acceptance

The build VM need not have GPUs. It cannot prove runtime driver compatibility.
GPU validation requires the exact generation and a conservative full CUDA 12.3
driver baseline >=545.23.08. An older base driver causes validation failure:
review a supported Marketplace update or a documented compatibility change,
never silently replace the Microsoft driver.

Manifests include selected versions, flags, checksum, timestamps and linkage.
No source/credentials/inputs appear. Inspect through the commands in
[image build](image-build.md). SDK and library pins must be maintained under
the organization's vulnerability/compatibility process; this is not a promise
that historical pins meet every current production security policy.

Failures block build/publication. Reproduce compiler errors only in an approved
local source environment, because build logs may contain licensed code.
Change the template/profile through review and rebuild a new image version.
Rollback/cleanup follow [rollback](rollback.md) and [cleanup](cleanup.md).
