# Private VASP image factory for Azure CycleCloud

Terraform + Azure VM Image Builder create a reusable compute image from
`microsoft-dsvm:ubuntu-hpc:2204:latest`. A separate publication state publishes
an immutable private Azure Compute Gallery version. Existing CycleCloud/Slurm
provides node identity, configuration, authentication, mounts, and autoscaling.

**Status:** implemented for local static validation; not Azure/GPU certified.
An actual build, existing-cluster convergence, PMI2 interoperability, and licensed
numerical tests are mandatory before production promotion. No Azure resources
are created by repository setup or CI pull-request checks.

## Layout

| Path | Responsibility |
| --- | --- |
| [modules/](modules/) | Network, staging, gallery, AIB, optional private GPU VMs |
| [environments/dev/](environments/dev/) | Independent factory/publication/validation states |
| [scripts/source/](scripts/source/) | Reviewed manifest and deterministic archive |
| [scripts/image/](scripts/image/) | Inventory, isolated toolchain, selected builds, cleanup |
| [scripts/build/](scripts/build/) | Explicit operations and integration generation |
| [scripts/validation/](scripts/validation/) | Static, linkage, GPU, Slurm and MPI diagnostics |
| [cyclecloud/](cyclecloud/) | Review-only project/template integration |
| [examples/slurm/](examples/slurm/) | A100/H100 production launch examples |
| [source/README.md](source/README.md) | Authorized local source requirements |
| [.github/workflows/](.github/workflows/) | Static CI and approval-gated operations |

## Defaults

Region `centralus`; CPU build VM `Standard_D32as_v5`; runtime validation
`Standard_NC24ads_A100_v4`; only `a100_gpu` built. Additional choices are
`cpu_mpi`, `h100_gpu`, NC48/NC96 A100, NC40/NC80 H100. Regions, VM size and
replication regions are inputs, not changes to module code.

The selected stack is NVHPC 24.3 + CUDA 12.3 + isolated CUDA-aware Open MPI
4.1.8 + same-MPI ScaLAPACK 2.2.0. Existing Microsoft drivers are not replaced.
The conservative GPU runtime check requires driver >=545.23.08.
Review the maintenance/security suitability of these compatibility pins for
your VASP release. See [build profiles](docs/vasp-build-profiles.md).

## Start here

1. Review [architecture](docs/architecture.md) and [security](docs/security.md).
2. Prepare licensed source using [local staging](docs/local-source-staging.md).
3. Provision and build using [image build](docs/image-build.md).
4. Review manifests and publish a candidate; it is excluded from gallery `latest`.
5. Generate/apply reviewed [CycleCloud integration](docs/cyclecloud-integration.md).
6. Validate [A100](docs/a100-validation.md), [TCP MPI](docs/mpi-over-tcp.md),
   and licensed VASP calculations through Slurm.
7. [Promote](docs/image-promotion.md) only after complete reviewed evidence.
8. Keep [rollback](docs/rollback.md) and [cleanup](docs/cleanup.md) procedures.

## Local checks

Requires Git, Terraform >=1.9, Python >=3.10, ShellCheck >=0.10 and outbound
access to provider registries. CI additionally runs TFLint and Trivy.
Local launch-driver tests also require `rsync`; the image installs it.

```bash
bash scripts/validation/local-check.sh
```

No source is read by these checks. The packaging tests use empty structural
fixtures, not VASP code. No commits or GitHub remote are created automatically.
Before the first commit, review `git status --short`, run the protection checks,
and stage specific repository files, never licensed input.
