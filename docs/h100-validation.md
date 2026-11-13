# H100 validation

## Preconditions and target selection

Select `h100_gpu` in the factory profile set and rebuild a **new** candidate.
Use CUDA target `cc90`, not an A100-only binary. Target sizes:
`Standard_NC40ads_H100_v5` (one GPU) and `Standard_NC80adis_H100_v5` (two GPUs).
Query actual SKU availability/quota in the selected region; A100 quota does
not imply H100 quota. H100 nodearray maximum defaults to zero and must be
explicitly increased through approved integration parameters.

Existing CycleCloud/Slurm must support the SKU's CPU/memory/GRES and first-boot
driver/runtime configuration. No RDMA assumption is made from SKU spelling.

```bash
az vm list-skus --location YOUR_REGION --resource-type virtualMachines \
  --size Standard_NC40ads_H100_v5 --all --output table
export EXPECTED_IMAGE_VERSION_ID='/subscriptions/.../galleries/.../images/.../versions/1.1.0'
export EXPECTED_GPU_COUNT=1
export VASP_VERSION=6.4.3
export VASP_SHARED_PATH=/YOUR_SHARED_POSIX_PATH
export MPI_TCP_ALLOWED_CIDRS='YOUR_COMPUTE_SUBNET_CIDR'
bash scripts/validation/slurm-validate.sh YOUR_H100_PARTITION h100
```

Expected: H100 capability 9.0, compatible driver/CUDA, correct GRES and pinned
image, one-node health and two-node CUDA-buffer TCP communication.
Follow the same registration, physical-vs-visible GPU count, private networking,
scale-up/down and reimage criteria as [A100 validation](a100-validation.md).
Set `VASP_VERSION` to the candidate's declared version. The same per-node image,
all-GPU allocation/GRES, and workflow-version limitations documented in the
A100 guide apply here; manually reviewed evidence is required until corrected.

## Licensed numerical tests

```bash
export VASP_GPU_GENERATION=h100
export VASP_INPUT_DIR=/YOUR_AUTHORIZED_TEST_DIRECTORY
export VASP_OUTPUT_DIR=/YOUR_PRIVATE_RESULTS/h100-single
sbatch --wait -p YOUR_H100_PARTITION --export=ALL examples/slurm/vasp-h100-single-node.sbatch
export VASP_OUTPUT_DIR=/YOUR_PRIVATE_RESULTS/h100-multi
sbatch --wait -p YOUR_H100_PARTITION --export=ALL examples/slurm/vasp-h100-multi-node.sbatch
```

Record reference agreement/tolerances, runtime, counts and exit status privately.
Do not reuse A100 acceptance as H100 certification. If capacity is unavailable,
mark H100 unvalidated and keep its nodearray disabled; do not claim acceptance.

Separate validation Terraform accepts H100 sizes/regions without module changes.
Do not deploy another Slurm controller. Failure/rollback/cleanup follow
[troubleshooting](troubleshooting.md), [rollback](rollback.md), [cleanup](cleanup.md).
