# Reviewed TODO backlog

This backlog comes from the [full repository review](repository-review.md) of
implementation revision `67bccb3` on 2026-11-13. It is a local work list, not a
set of GitHub issues. Runtime code was not changed in the documentation review.

## Priorities and status

- **P0:** evidence/controls required before production; absence is not proof of
  a code defect.
- **P1:** correctness or operability work needed for reliable release handling.
- **P2:** focused hardening, maintainability, and automation improvements.

All items are open unless marked otherwise. Dependencies below are actual
prerequisites for the stated outcome, not an implied serial implementation order.

| ID | Priority | Type | TODO | Dependencies |
| --- | --- | --- | --- | --- |
| R01 | P0 | Release acceptance | Prove the end-to-end A100 release path on Azure/CycleCloud/Slurm | Trusted environment controls in place; B04/B05/B06 for automated acceptance |
| R02 | P0 | Operator controls | Verify protected environments, runner isolation, OIDC, and private access | None |
| B01 | P1 | Confirmed defect | Normalize runtime input/output paths before changing directory | None |
| B02 | P1 | Operability | Make Terraform confirmation/approved-plan behavior explicit | None |
| B03 | P1 | Lifecycle gap | Align build timeouts and handle caller interruption | None |
| B04 | P1 | Validation gap | Check the expected gallery version on every test node | None |
| B05 | P1 | Validation gap | Allocate/test the selected physical GPU count and assert GRES | None |
| B06 | P1 | Version propagation | Carry the candidate VASP version through workflow validation | None |
| B07 | P1 | Build validation | Load-test every installed profile module | None |
| B08 | P2 | Workflow handoff | Export and validate release-matched pipeline/publication outputs | None |
| T01 | P2 | Test coverage | Add focused offline tests for Azure operation and route/error boundaries | Tests accompany the associated fixes |
| H01 | P2 | Evidence hardening | Strengthen receipt provenance and offline pre-capture scanning | None; integrate with R01 evidence |
| M01 | P2 | Maintenance | Maintain a tested toolchain/base/action/provider compatibility record | None |

R01 can be performed with carefully reviewed manual evidence while automation
fixes are pending. It cannot be claimed complete from static tests alone.

## Release gates

### R01 - Demonstrate workload readiness, not just an image build

**Impact:** no reviewed live build or workload result currently certifies the
repository. A local pass cannot justify promotion.
**Evidence:** [status](../README.md), [A100 acceptance](a100-validation.md),
[H100 acceptance](h100-validation.md), [promotion gate](image-promotion.md).
**Suggested owner:** release operator with Azure, cluster, and workload owners.

**Acceptance criteria**

- [ ] Approved source is privately staged and downloaded with AIB identity;
  the exact archive checksum is verified inside the build.
- [ ] Every selected profile compiles; safe manifests record the resolved base,
  selected stack, linkage, and cleanup results.
- [ ] Candidate replication succeeds, fresh nodes converge/join the intended
  node array, and every test node runs the exact gallery version.
- [ ] Slurm registration, GRES/physical GPUs, CPU/GPU binding, mounts/private DNS,
  single-node and multi-node launch, and private TCP payload evidence pass.
- [ ] Authorized numerical tests meet recorded reference tolerances; protected
  results remain off GitHub artifacts.
- [ ] Scale-down, controlled reimage, termination recovery, rollback canary,
  source deletion/retention, and temporary-resource cleanup are verified.
- [ ] Hardware-specific evidence is reviewed; H100 stays disabled/unvalidated
  unless its independent profile and tests pass.

### R02 - Verify controls that workflow YAML cannot enforce by itself

**Impact:** approval names and OIDC configuration are not evidence of actual
protected-environment or runner access controls.
**Evidence:** [workflow setup](security.md#workflow-setup),
[approval controls](image-promotion.md#github-approval-controls).
**Suggested owner:** repository/Azure/cluster administrators.

**Acceptance criteria**

- [ ] All six named operational environments have required reviewers and
  trusted-branch restrictions; test that unapproved jobs cannot proceed.
- [ ] OIDC subjects and least-privilege roles are verified for source,
  infrastructure/build/publication, and promotion identities.
- [ ] Source and Slurm runner groups reject unreviewed PR code; licensed inputs,
  approved manifests, and private inputs live outside checkout cleanup.
- [ ] Private source/backend routing, DNS, retention policy, and compute NSG
  scope are verified, with approval records and cleanup owners.
- [ ] Freeze/review inputs between plan and apply, and prevent concurrent
  factory mutation/source cleanup during an active build of the same pipeline.

## Correctness and operability

### B01 - Resolve runtime paths once

**Confirmed:** a relative output directory fails after the driver enters a
different input directory; empty-fixture reproduction returned exit 1 before
the mocked task ran.
**Evidence:** [runtime paths/redirection](../scripts/image/runtime.sh#L59),
[existing runtime tests](../scripts/validation/test_runtime.py).
**Current mitigation:** use absolute input/output/scratch paths.

- [ ] Use normalized paths consistently for launch logs, copy-back, and traps.
- [ ] Add a focused relative-output regression case with a different working
  directory; retain nested-output exclusion, permissions, nonzero exit, and
  TERM behavior.
- [ ] Verify both staged and direct-input execution; update the job guide.

### B02 - Define local Terraform approval and saved-plan behavior

**Confirmed:** `-input=false` prevents interactive confirmation; the approval
flag is required for an unsaved-plan apply/destroy.
**Evidence:** [wrapper](../scripts/build/terraform.sh#L25).
**Current mitigation:** the guides now use command-scoped
`TF_APPROVED_APPLY=1` only after separate plan review/approval.

- [ ] Choose and document an explicit local approval contract: either retain
  the approved noninteractive mode with a clear preflight error, or implement
  a reviewed saved-plan path without silently bypassing authorization.
- [ ] Test unapproved/approved apply and validation destroy offline, including
  backend-key propagation and the factory/publication destroy refusal.
- [ ] Preserve plan-only operation and avoid a globally exported approval flag.

### B03 - Align timeouts and service cleanup

**Confirmed:** workflow 360 minutes < AIB 480 minutes < CLI nine-hour polling;
terminating the caller does not cancel AIB.
**Evidence:** [image workflow](../.github/workflows/image.yml#L21),
[AIB timeout](../modules/image-builder/main.tf#L94),
[polling](../scripts/build/manage.py#L94).
**Current mitigation:** use the local CLI for reviewed longer builds; inspect
and cancel only the exact template run before retry/cleanup.

- [ ] Set coherent supported durations with a margin for service teardown.
- [ ] On timeout/interruption, report the specific run/template and its state;
  define approved cancellation and stopped-service verification.
- [ ] Test success/failure/timeout/interruption with mocked Azure responses;
  never delete staging while AIB remains active.
- [ ] Keep source/private compiler logs out of timeout diagnostics.

### B04 - Validate immutable provenance on every node

**Confirmed:** only the initial allocation checks `EXPECTED_IMAGE_VERSION_ID`.
Later jobs can schedule onto a different or mixed image.
**Evidence:** [validator](../scripts/validation/slurm-validate.sh#L14),
[health job](../examples/slurm/gpu-health-check.sbatch),
[MPI job](../examples/slurm/mpi-tcp-smoke-test.sbatch).
**Current mitigation:** collect and review the expected IMDS version for every
health/MPI/workload node, including fresh canaries.

- [ ] Check the expected immutable gallery version in each validation
  allocation on every allocated node, not just the batch host.
- [ ] Reject mixed-version/missing-IMDS evidence before accepting test results.
- [ ] Add focused mismatch tests; validate a deliberately mixed canary pool
  under an approved live test.

### B05 - Distinguish allocated visibility from physical GPUs

**Confirmed gap:** the validator requests `gpu:1` regardless of
`EXPECTED_GPU_COUNT` and prints rather than fully asserts node GRES.
**Evidence:** [allocation](../scripts/validation/slurm-validate.sh#L14),
[count check](../scripts/validation/gpu-health.sh#L20).
**Current mitigation:** use the one-GPU NC24 A100 target; require manually
reviewed all-GPU allocations and Slurm/SKU evidence for larger machines.

- [ ] Request the approved GPU count consistently for each validation job.
- [ ] Assert selected SKU/physical count, Slurm GRES/allocation, and per-task
  visibility separately; do not interpret a cgroup-visible subset as the SKU.
- [ ] Cover one/two/four-GPU expectations with offline command/allocation
  tests and authorized live target tests, without increasing production
  example rank defaults implicitly.

### B06 - Select the candidate version consistently

**Confirmed gap:** build versions are configurable, but the Slurm workflow
does not export `VASP_VERSION`, and jobs fall back to `6.4.3`.
**Evidence:** [workflow environment](../.github/workflows/slurm-validation.yml#L22),
[module default](../examples/slurm/gpu-health-check.sbatch#L13).
**Current mitigation:** local operators explicitly export the candidate's
version before diagnostics and job submission.

- [ ] Propagate the declared candidate VASP version into workflow diagnostics
  and all validation job exports; verify it against the installed manifests.
- [ ] Add a nondefault-version test that would fail with the current fallback.
- [ ] Document the workflow's required version input/variable and fail clearly
  on missing/mismatched versions instead of selecting a different module.

### B07 - Check all generated VASP modules

**Confirmed gap:** the runtime installer tests only the final loop suffix;
image health does not load each VASP profile module.
**Evidence:** [installer](../scripts/image/install-runtime.sh#L38),
[health loop](../scripts/validation/image-health.sh#L9).

- [ ] Load/unload each selected profile module and verify its binary path,
  profile/version variables, and isolated MPI prefix.
- [ ] Add a multi-profile test in which an earlier module is invalid.
- [ ] Preserve module conflict behavior and verify selected-profile-only builds.

## Focused improvements

### B08 - Make workflow output handoff explicit

**Observed gap:** runner-local output paths are inputs, but factory/publication
workflows do not refresh those files.
**Evidence:** [factory workflow](../.github/workflows/terraform-plan.yml#L38),
[image workflow](../.github/workflows/image.yml#L40).

- [ ] Export safe pipeline/publication output to protected runner storage
  after successful operations; reject stale release identities before use.
- [ ] Coordinate release-specific factory/publication keys and permissions;
  never upload source, private tfvars, or cluster exports as artifacts.
- [ ] Test the handoff and documented manual refresh path without Azure.

### T01 - Test operational failure boundaries

**Observed gap:** existing tests cover packaging, repository structure, and
the mocked job driver, not most Azure operations/node wrappers.
**Evidence:** [preparation tests](../scripts/source/test_prepare.py),
[repository tests](../scripts/validation/repository-check.py),
[runtime tests](../scripts/validation/test_runtime.py).

- [ ] Add only focused cases for changed behavior: storage-policy/checksum
  refusal, immutable-image refusal, terminal build status, incomplete/mismatched
  promotion receipts, and cleanup retain/delete semantics.
- [ ] Mock route/DNS/CIDR and module commands to cover rejected interfaces,
  inconsistent DNS, invalid port intervals, and wrong module/profile.
- [ ] Keep fixtures empty/nonproprietary and tests offline; do not treat mocks
  as proof of real Azure/PMI/GPU interoperability.

### H01 - Improve evidence and image-cleanliness assurance

**Known limitation, not an exhaustive vulnerability finding:** path-based
scans cannot detect arbitrary renamed licensed/secret material; a JSON receipt
does not authenticate the claimed tests.
**Evidence:** [scan scope](security.md#source-and-build-protection),
[receipt trust model](image-promotion.md#preconditions-and-evidence).

- [ ] Define an approved offline pre-capture scanning policy with explicit
  scope/exclusions and failure handling; never send licensed files to third
  parties or inspect active user calculation storage as image residue.
- [ ] Record release/hardware/job/VM IDs, timestamps, numerical tolerances,
  and reviewed safe evidence references with the receipt.
- [ ] Restrict receipt generation/approval and reject stale/incomplete evidence;
  keep proprietary results separate from shareable metadata.

### M01 - Maintain compatibility rather than relying on old pins

**Maintenance work:** the selected NVHPC/CUDA/Open MPI/ScaLAPACK stack and
moving Marketplace `latest` require continuing verification.
**Evidence:** [toolchain](../scripts/image/toolchain.sh),
[profile contract](vasp-build-profiles.md), [CI pins](../.github/workflows/ci.yml),
[factory locks](../environments/dev/factory/.terraform.lock.hcl).

- [ ] Record tested VASP/template, resolved base image, driver, compiler/CUDA,
  MPI/PMIx/PMI2, math-library, Slurm, and CycleCloud versions per hardware target.
- [ ] Review upstream maintenance/security status through the approved process;
  update pins only with checksums, compatibility tests, and new image versions.
- [ ] Verify all supported targets after updates; do not automatically replace
  Microsoft drivers or claim that a smoke test is a benchmark.

## Out of scope

No new CycleCloud cluster/controller, scheduler management Terraform, licensed
inputs, fabricated VASP source, automatic production template update, per-commit
GPU deployment, RDMA claim, or benchmark suite is proposed here.
Do not broaden a backlog fix into those ownership boundaries.
