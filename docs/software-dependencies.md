# Software dependencies

Install tools on the host that runs each step. Local checks do not need an
Azure login, licensed VASP source, a GPU, or a Slurm cluster.

## Local checks

Use Linux with Bash 4 or newer and the standard GNU utilities (including
Coreutils and Findutils). The [local check runner](../scripts/validation/local-check.sh)
also needs:

| Tool | Requirement |
| --- | --- |
| Git | Repository and ignore-rule checks |
| Python | 3.10 or newer; scripts and tests use the standard library, so no `pip install` is needed |
| Terraform | 1.9 or newer, less than 2.0; init downloads AzureRM and AzAPI as specified by the Terraform roots and lockfiles |
| ShellCheck | 0.10 or newer; required for shell and Slurm job script linting |
| rsync | Required by the local launch-driver tests |

On Ubuntu, install the distribution packages with administrator approval:

```bash
sudo apt-get update
sudo apt-get install bash coreutils findutils git python3 rsync
apt-cache policy shellcheck
```

If Ubuntu offers ShellCheck 0.10 or newer, run `sudo apt-get install shellcheck`.
If it offers an older version or none, install a compatible release using your
organization's approved package source or the upstream release binary for your
architecture. Put it on `PATH`. Install Terraform from HashiCorp's package
repository or an approved HashiCorp release binary. Once the approved apt
repository is configured, the package name is `terraform`.

Verify the tools from the repository root before starting the checks:

```bash
command -v bash git python3 terraform shellcheck rsync
bash --version
python3 --version
terraform version
shellcheck --version
```

If `command -v` omits a tool or a version is outside the supported range, fix
the installation before running `bash scripts/validation/local-check.sh`.
Terraform needs access to its provider registry and download endpoints or an
approved provider mirror; the checks do not initialize an Azure backend.

## Operator workstation

| Task | Additional software |
| --- | --- |
| Prepare the source manifest and archive | Python 3.10+ already listed above |
| Provision, upload, run Image Builder, publish, promote, or clean up | Microsoft Azure CLI (`az`); Terraform for infrastructure and publication, Python for the operation scripts |
| Generate the CycleCloud integration package | Python 3.10+; generation itself does not need the CycleCloud CLI |
| Export, upload, or import CycleCloud configuration | Azure CycleCloud CLI (`cyclecloud`) compatible with the site's CycleCloud 8.x deployment; use the installer supplied by the site |
| Run optional standalone GPU diagnostics | OpenSSH client (`ssh`) and an approved SSH key; `openssh-client` is the Ubuntu package |

Install Azure CLI from your site's software distribution or run
`sudo apt-get install azure-cli` once the approved Microsoft apt repository is
configured. Confirm `az version` works before signing in. Check
`command -v cyclecloud` before the integration step. Azure operations need
approved access to Azure and the relevant private endpoints; the Slurm commands
below can run from a separate approved login host.

## Image Builder and candidate image

Azure VM Image Builder uses the x86-64 Azure Marketplace Ubuntu HPC 22.04 image
(`microsoft-dsvm:ubuntu-hpc:2204:latest`). The base must provide Bash, standard
Linux utilities, `cloud-init`, and `curl` for the initial inventory. The
[customization script](../scripts/image/customize.sh) installs these Ubuntu
packages on the build VM, not the operator workstation:

- Fetch and inspect: `jq`, `curl`, `ca-certificates`, `gnupg`, `python3`, `pciutils`.
- Compile and link: `build-essential`, `cmake`, `libfftw3-dev`, `libblas-dev`,
  `liblapack-dev`, `libpmi2-0-dev`.
- Runtime and mounts: `environment-modules`, `nfs-common`, `rsync`.

The [toolchain script](../scripts/image/toolchain.sh) uses NVIDIA HPC SDK 24.3
by default, with CUDA 12.3, QD, and NVIDIA math libraries. It installs the
selected SDK from NVIDIA's signed apt repository if missing and installation is
enabled. It builds Open MPI 4.1.8 with CUDA and PMI2 support, then builds
ScaLAPACK 2.2.0 against that same MPI. Allow the build VM to reach the approved
Ubuntu and toolchain download endpoints, as well as private source staging.
Use authorized VASP source; see [build profiles](vasp-build-profiles.md) for
the supported templates and optional library compatibility requirements.

## CycleCloud and Slurm validation

| Where | Required software |
| --- | --- |
| CycleCloud server and cluster | Supported CycleCloud 8.x and the site's compatible `cyclecloud-slurm` project/template, Slurm daemons and clients, Munge, and Slurm's `pmi2` plugin. The site supplies GRES, cgroups, accounting, and shared filesystem mounts. |
| Slurm login or submission host | Bash and site-compatible Slurm commands: `sinfo`, `salloc`, `srun`, `sbatch`, `scontrol`, and `sacct` for the tutorial's job accounting. Use the site's client installation, not an arbitrary distro version. |
| Allocated candidate compute nodes | Candidate image with the built VASP profile, environment modules, isolated Open MPI/ScaLAPACK stack, Python, `rsync`, `curl`, and `jq`; Linux utilities including `ip` (`iproute2`), `getent`, and `findmnt` (`util-linux`). The NVIDIA driver must provide `nvidia-smi` and meet the CUDA 12.3 validation baseline of 545.23.08 or newer. The build does not replace the base image's driver. |

Run `srun --version` and `srun --mpi=list` on the submission host. Stop if
`pmi2` is missing, and use the [Slurm launch contract](slurm-integration.md)
to verify the image's MPI client and an actual multi-rank launch. The login
host does not need the candidate image modules or NVIDIA driver.

## CI and optional runner tools

- [Static CI](../.github/workflows/ci.yml) uses an Ubuntu 24.04 GitHub-hosted
  runner and installs Terraform 1.9.8, TFLint 0.55.1, and Trivy 0.76.2 through
  Actions. The runner must also provide the other local-check tools. TFLint
  and Trivy are not required by the local check script.
- Approval-gated self-hosted runners need the tools for their assigned
  workflows: Bash and Git for checkout and shell steps; `az` for Azure/OIDC
  steps; Terraform for infrastructure and publication; Python 3.10+ for source,
  build, promotion, and CycleCloud package generation. The generation workflow
  does not invoke `cyclecloud`. The `licensed-source` runner additionally
  needs approved access to the authorized source; the `slurm-client` runner
  needs the site Slurm client and shared-path access described above.
