# A100 validation acceptance

## Preconditions

Published immutable candidate; reviewed CycleCloud integration; Slurm/GRES
configuration; ANF/shared POSIX access; authorized calculation inputs.
Central US A100 quota is operator-supplied; verify actual capacity/allocations.

| SKU | Physical GPUs | vCPUs |
| --- | ---: | ---: |
| Standard_NC24ads_A100_v4 | 1 | 24 |
| Standard_NC48ads_A100_v4 | 2 | 48 |
| Standard_NC96ads_A100_v4 | 4 | 96 |

Normal submission permissions suffice for jobs; drain/reimage/template changes
need approved administrative access. Do not deploy validation GPUs in PR CI.

## One node, then two nodes

On an approved Slurm-client runner, with a shared POSIX path:

```bash
export EXPECTED_IMAGE_VERSION_ID='/subscriptions/.../galleries/.../images/.../versions/1.0.0'
export EXPECTED_GPU_COUNT=1
export VASP_VERSION=6.4.3
export VASP_SHARED_PATH=/YOUR_SHARED_ANF_PATH
export MPI_TCP_ALLOWED_CIDRS='YOUR_COMPUTE_SUBNET_CIDR'
bash scripts/validation/slurm-validate.sh YOUR_A100_PARTITION a100
```

The script requests a one-node allocation, checks Slurm/node metadata, IMDS
gallery version, GPU generation/count, image/linkage and mount access; submits
a single-node health job and then a two-node GPU-buffer TCP MPI job.
Expected: Slurm registration and allocatable state, correct CPU/memory/GRES,
zero job exits, actual private TCP connections and verified payloads.
For larger SKUs distinguish **physical GPUs** from a task's cgroup visibility;
request all GPUs when proving physical count, and compare node GRES to SKU
metadata. Default production examples deliberately request only one GPU/node.

Set `VASP_VERSION` to the candidate's declared version. The Slurm workflow
currently does not export this value and its jobs default to `6.4.3`; use the
explicit local procedure for other versions pending
[version propagation](backlog.md#b06---select-the-candidate-version-consistently).
The automated validator always requests one GPU, so larger-SKU physical-count
acceptance requires a separately approved all-GPU allocation and GRES evidence.

The expected gallery version is checked only in the initial allocation, not
every node used by later health/MPI jobs. Collect/review each test node's IMDS
version and CycleCloud membership. Printed node/GRES fields and readable/
writable mount checks do not automatically prove all lifecycle criteria.

## Licensed calculations (never CI artifacts)

```bash
export VASP_INPUT_DIR=/YOUR_AUTHORIZED_TEST_DIRECTORY
export VASP_OUTPUT_DIR=/YOUR_PRIVATE_RESULTS/a100-single
sbatch --wait -p YOUR_A100_PARTITION --export=ALL \
  examples/slurm/vasp-a100-single-node.sbatch
export VASP_OUTPUT_DIR=/YOUR_PRIVATE_RESULTS/a100-multi
sbatch --wait -p YOUR_A100_PARTITION --export=ALL \
  examples/slurm/vasp-a100-multi-node.sbatch
sacct -j YOUR_JOB_IDS --format=JobID,State,ExitCode,Elapsed,AllocCPUS,AllocTRES
```

Validate numerical outputs against an authorized reference with documented
tolerances. Exit zero alone is not numerical acceptance. Record runtime,
node/rank/GPU count and status without uploading proprietary input/output.
A tiny smoke test is not a benchmark.

## Cluster lifecycle acceptance

Check CycleCloud UI/API against the intended cluster name and nodearray,
matching the actual VM IDs and pinned image version. Check private forward/
reverse scheduler/peer resolution, scheduler reachability, mount write/read and
UID/GID consistency. After releasing jobs, observe autoscaler idle scale-down.
Perform an approved drain/retire/new-node cycle, confirm a fresh node joins
without manual repair, and repeat the single-node test.

These site-owned lifecycle checks require operator evidence; the script does
not assert them automatically or write a success-shaped promotion receipt.
Record them in the reviewed receipt in [promotion](image-promotion.md).

## Optional standalone GPU deployment

Use the separate validation state only when CycleCloud access is unavailable.
Supply existing RG/subnet, public SSH key, immutable image ID, `enabled=true`,
`vm_size` and `vm_count` in `private/validation.tfvars`:

```bash
bash scripts/build/terraform.sh validation plan -var-file="$PWD/private/validation.tfvars"
# After reviewing the plan and approving temporary GPU deployment:
TF_APPROVED_APPLY=1 bash scripts/build/terraform.sh validation apply -var-file="$PWD/private/validation.tfvars"
bash scripts/build/terraform.sh validation output > generated/validation.json
```

SSH through private routing as `hpcvalidate`; run `image-health.sh runtime` and
`gpu-health.sh a100`. Standalone `mpirun` may be used only for low-level
diagnostics with approved private SSH access and runtime TCP configuration.
Standalone success is **not CycleCloud/Slurm acceptance** and cannot satisfy
their promotion checks.

Failures: preserve only safe metadata, inspect [troubleshooting](troubleshooting.md),
rollback the candidate using [rollback](rollback.md). Cancel named jobs, release
allocations and destroy temporary VMs using [cleanup](cleanup.md).
