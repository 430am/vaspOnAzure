# Tutorial: from a local checkout to a validated A100 candidate

This lesson is for readers new to Azure, Slurm, and this VASP image factory.
You will follow one candidate through preparation, compilation, publication,
cluster integration, validation, and a promotion decision.

**This is an operator-assisted workflow, not a production certification.**
The repository passes local static checks; an Azure build and workload
acceptance have not been demonstrated by this review. Read the
[repository review](repository-review.md) and [backlog](backlog.md) first.
Do not continue past a failed check.

## 1. Understand what you are building

| Term | Meaning in this lesson |
| --- | --- |
| Azure subscription | The administrative and billing boundary for resources |
| Resource group | A collection of Azure resources with a shared lifecycle |
| Terraform | Describes resources and records their identities in a state file |
| Private endpoint | A private network address used to reach an Azure service |
| Managed identity | An Azure identity for a service, without a stored password |
| Azure VM Image Builder (AIB) | Creates a temporary VM, compiles software, and captures an image |
| Azure Compute Gallery | Stores versioned VM images, such as `1.0.0` |
| CycleCloud | Provisions compute nodes and converges the existing cluster configuration |
| Node array | A CycleCloud group of nodes sharing a machine type and configuration |
| Slurm partition | A scheduler group to which users submit jobs |
| Slurm allocation | The nodes, CPUs, and GPUs granted to a job |
| MPI rank | One cooperating process in a parallel calculation |
| GRES | Slurm's generic-resource model, used here to allocate GPUs |
| Environment module | Selects a consistent VASP/compiler/MPI runtime environment |

The flow is:

```text
approved source -> private staging -> AIB -> managed image
    -> immutable gallery candidate -> existing CycleCloud/Slurm
    -> GPU/TCP/numerical evidence -> operator-approved promotion
```

The image contains reusable software, not scheduler configuration or cluster
credentials. Terraform has separate factory, publication, and optional
validation states. CycleCloud integration is generated for review; importing
it is a separate administrative action. See [architecture](architecture.md).

## 2. Prepare your workspace without touching licensed source

**Preconditions:** a checkout of this repository on Linux; Git, Python >=3.10,
Terraform >=1.9 and <2.0, ShellCheck >=0.10, and `rsync`. Provider registry
access is required for Terraform initialization.
**Permissions:** ordinary local filesystem access; no Azure login is needed.
Run from the repository root:

```bash
git status --short
bash scripts/validation/local-check.sh
umask 077
mkdir -p private staging generated
chmod 700 private staging generated
```

**Expected result:** three groups of four tests report `OK`, Terraform format
checking succeeds, all three Terraform roots validate, and ShellCheck exits
zero. A missing executable is a failed check, not a pass.

**Security and validation:** these checks use empty fixtures and do not read
licensed source or create Azure resources. Ignored directories are not access
controls; keep the checkout and private files accessible only to authorized
users. Never stage those directories in Git.

**Failure, rollback, cleanup:** install missing tools using your approved local
tooling policy and rerun. No cloud rollback is needed. Do not remove pre-existing
files or the repository when cleaning a workspace.

## 3. Collect approvals and site inputs

**Preconditions:** an authorized VASP delivery and an existing CycleCloud/Slurm
cluster. A beginner should work with the cluster and Azure administrators.
**Permissions:** have the administrators confirm the following roles; do not
request general subscription Owner for compute nodes.

| Operation | Required access |
| --- | --- |
| Source inventory/package | License authorization and local source read access |
| Factory provisioning | Resource deployment, identity assignment, RBAC management, private backend access |
| Source upload/delete | Container Blob Data Contributor and storage-account management read |
| Build preflight | Container Blob Data Reader and storage-account management read |
| AIB VM download | The template's user-assigned identity, with container Blob Data Reader |
| Publication | Intermediate image read and gallery image-version write |
| Integration | Approved CycleCloud project upload/import; deployment identity can read the gallery |
| Slurm tests | Submission rights in an approved GPU partition |
| Promotion | Image-version tag write and release approval |

Agree on the subscription, resource group, backend, build/endpoint/compute
subnets, private DNS, shared POSIX filesystem, and test partition.
Reserve quota and a budget for one CPU build VM and up to two A100 test nodes.
This lesson uses `centralus`, `Standard_NC24ads_A100_v4` (one GPU),
VASP `6.4.3`, and gallery version `1.0.0`; change them only through review.

```bash
export VASP_VERSION=6.4.3
export PIPELINE_NAME=vasp-dev-001
export IMAGE_VERSION=1.0.0
export FACTORY_STATE_KEY="vasp/factory/$PIPELINE_NAME.tfstate"
export PUBLICATION_STATE_KEY="vasp/publication/$IMAGE_VERSION.tfstate"
```

**Approval gates:** separately authorize source reads, packaging/upload,
factory apply, AIB start, publication, cluster import, GPU allocation, and
promotion. CLI `--approve` and `TF_APPROVED_APPLY=1` express a decision; they
do not obtain approval or validate a license.

**Security, failure, rollback, cleanup:** do not run deployment steps without
private routing and DNS. A NAT gateway does not connect your workstation to a
private endpoint. If inputs or permissions are incomplete, stop here; nothing
needs to be rolled back. For Actions, configure actual required reviewers,
trusted branches, OIDC subjects, and runner groups using
[workflow setup](security.md#workflow-setup); environment names alone do not
protect a workflow.

## 4. Inventory and package approved source

**Preconditions:** explicit approval to read the authorized clean tree at
`source/vasp/`; its required structure is described in the
[source README](../source/README.md).
**Permissions:** license-authorized local read access and an independent reviewer.
The following commands must be run by that authorized operator, not by ordinary
CI:

```bash
git check-ignore source/vasp/src/main.F
python3 scripts/source/prepare.py inventory --source ./source/vasp \
  --manifest private/candidate-manifest.json --version "$VASP_VERSION"
```

**Expected result:** Git reports the ignored path and the script reports a
candidate manifest. This contains filenames/checksums, not source text.

Stop for independent review against the authorized delivery. The reviewer must
provide the approved exact mapping at `private/approved-manifest.json`; merely
renaming the candidate is not approval. After packaging approval:

```bash
python3 scripts/source/prepare.py package --source ./source/vasp \
  --manifest private/approved-manifest.json --version "$VASP_VERSION" \
  --output staging/vasp-source.tar.gz
```

**Expected result:** a private archive and JSON receipt with `sha256`,
`vasp_version`, `detected_version`, and `file_count`. Copy the approved
archive SHA-256 into the factory inputs in the next step.

**Security and validation:** no POTCAR, calculation data, binaries, links, or
generated build trees belong in this archive. Do not display source or upload
the manifest/archive as GitHub artifacts.

**Failure, rollback, cleanup:** mismatch or unexpected layout means stop and
review the delivery, not change the checksum to silence the error. Commands
refuse existing output files. After review, remove only a known partial archive
before retrying. Source preparation changes no cluster or cloud resource.
See [source staging](local-source-staging.md) for the checksum alternative and
retention policy.

## 5. Provision the factory, then upload

**Preconditions:** approved source checksum; registered Azure providers and
supported AIB region; an existing private Terraform backend separate from
licensed-source storage. Confirm private endpoint routing/DNS and package
repository egress with the Azure administrator.
**Permissions:** factory deployment/RBAC and backend access; source upload
requires the separate roles in step 3.

Replace all `YOUR_*` values before running:

```bash
export TF_BACKEND_ACCOUNT=YOUR_BACKEND_ACCOUNT
export TF_BACKEND_CONTAINER=YOUR_STATE_CONTAINER
export TF_BACKEND_RESOURCE_GROUP=YOUR_BACKEND_RG
az login
az account set --subscription YOUR_SUBSCRIPTION_ID
cp environments/dev/factory/terraform.tfvars.example private/factory.tfvars
```

Edit the private copy: use the real subscription/resource group, a globally
unique lowercase storage-account name, the checksum, matching `name` and VASP
version, and `vasp_build_profiles = ["a100_gpu"]`. The example placeholders
are deliberately invalid.

For this lesson also set `cyclecloud_integration_enabled = true`, the existing
cluster name and compute subnet, the real A100 partition name, and
`cyclecloud_gallery_image_version = "1.0.0"`. Keep update mode `plan-only`.
This permits later package generation; it does not modify the cluster.
Review BYO network/storage/gallery/identity choices using
[factory inputs](../environments/dev/factory/variables.tf).

```bash
TF_BACKEND_KEY="$FACTORY_STATE_KEY" bash scripts/build/terraform.sh factory plan \
  -var-file="$PWD/private/factory.tfvars"
```

Review the plan and obtain apply approval. Freeze the inputs and reviewed
checkout between plan and apply; this sequence recomputes the plan rather than
applying a saved plan. Replan after any change.

```bash
TF_BACKEND_KEY="$FACTORY_STATE_KEY" TF_APPROVED_APPLY=1 \
  bash scripts/build/terraform.sh factory apply -var-file="$PWD/private/factory.tfvars"
TF_BACKEND_KEY="$FACTORY_STATE_KEY" bash scripts/build/terraform.sh factory output \
  > generated/pipeline.json
```

**Expected result:** the factory resources and template exist, and the output
contains a `pipeline.value` object. Apply creates the template, not a VASP build.
Without the approval flag, the wrapper's `-input=false` prevents confirmation.
Do not export that flag globally.

After separate upload approval:

```bash
python3 scripts/build/manage.py upload --pipeline generated/pipeline.json \
  --archive staging/vasp-source.tar.gz --approve
```

**Expected result:** `Authorized archive uploaded without anonymous access or SAS.`
The uploader checks private access, DNS, and checksum and refuses replacement.

**Security and validation:** plans contain repository scripts/configuration,
not licensed source. Protect state and private inputs. BYO resources are not
automatically repaired. Refresh the pipeline output after approved factory
changes; workflows do not export it for you.

**Failure, rollback, cleanup:** for storage 403 or public DNS, fix approved
RBAC/connectivity instead of enabling keys/public access. Review partial applies
in the same factory state. Do not destroy shared infrastructure or overwrite a
staged blob. Keep a unique pipeline/blob identity for subsequent builds; use
[cleanup](cleanup.md) for source and abandoned build resources.

## 6. Compile a candidate image

**Preconditions:** uploaded approved archive and matching template/output.
**Permissions:** build preflight access and authorized AIB Run action; AIB's VM
uses its own managed identity for source read and distribution.
After explicit build approval:

```bash
python3 scripts/build/manage.py build --pipeline generated/pipeline.json --approve
```

**Expected result:** `Candidate managed image built; publish it in the separate publication state.`
AIB verifies the archive, builds the selected profiles, installs modules,
records inventories, removes protected source/build material, and performs
pre-capture checks. The CPU build VM does not prove GPU execution.

**Security and validation:** compiler logs can contain licensed lines and are
restricted/deleted. Review failures only in an authorized environment. The
base is `microsoft-dsvm:ubuntu-hpc:2204:latest`, resolved at build time, not a
guaranteed fixed set of driver/library versions.

**Failure, rollback, cleanup:** the CLI polls for up to nine hours; AIB allows
eight hours, while the image workflow stops after six. A caller timeout does
not cancel the service. Use the exact template's status/Cancel procedure in
[troubleshooting](troubleshooting.md) before cleanup or retry. Never rerun over
a published managed-image name; use a new pipeline and factory state.

## 7. Publish an immutable gallery candidate

**Preconditions:** successful managed image and reviewed publication inputs.
**Permissions:** intermediate image read and gallery-version write.
Read the two IDs from the exported pipeline:

```bash
python3 - <<'PY'
import json
from pathlib import Path
pipeline = json.loads(Path("generated/pipeline.json").read_text())["pipeline"]["value"]
print("managed_image_id =", pipeline["managed_image_id"])
print("image_definition_id =", pipeline["image_definition_id"])
PY
```

Create `private/publication.tfvars` with the exact IDs:

```hcl
subscription_id     = "YOUR_SUBSCRIPTION_ID"
managed_image_id    = "YOUR_EXACT_MANAGED_IMAGE_RESOURCE_ID"
image_definition_id = "YOUR_EXACT_GALLERY_IMAGE_DEFINITION_RESOURCE_ID"
image_version       = "1.0.0"
location            = "centralus"
replication_regions = ["centralus"]
```

```bash
TF_BACKEND_KEY="$PUBLICATION_STATE_KEY" bash scripts/build/terraform.sh publication plan \
  -var-file="$PWD/private/publication.tfvars"
```

After reviewing the plan and approving publication:

```bash
TF_BACKEND_KEY="$PUBLICATION_STATE_KEY" TF_APPROVED_APPLY=1 \
  bash scripts/build/terraform.sh publication apply -var-file="$PWD/private/publication.tfvars"
TF_BACKEND_KEY="$PUBLICATION_STATE_KEY" bash scripts/build/terraform.sh publication output \
  > generated/publication.json
IMAGE_VERSION_ID=$(python3 -c 'import json; print(json.load(open("generated/publication.json"))["image_version_id"]["value"])')
export IMAGE_VERSION_ID
az resource show --ids "$IMAGE_VERSION_ID" --api-version 2023-07-03 \
  --query properties --output json
```

**Expected result:** version `1.0.0`, candidate tags, `excludeFromLatest=true`,
successful provisioning and replication to every requested region.
Review replication status; if not exposed by this response, obtain the detailed
status through the Azure administrator before proceeding.

**Security and validation:** this publishes licensed binaries privately, not
source. Confirm licensing and gallery RBAC. Keep each publication state's key
for its release; never reuse it to replace a version.

**Failure, rollback, cleanup:** do not consume incomplete replicas. Gallery
`prevent_destroy` is intentional. Preserve the prior validated version and
state. Intermediate image retirement is a separate approved action after
validation/retention review, not a routine factory destroy.

## 8. Generate and approve CycleCloud integration

**Preconditions:** replicated candidate; matching factory CycleCloud settings;
an existing compatible cluster/project and shared POSIX mounts.
**Permissions:** generation needs local output access only; export/upload/import
needs the authorized CycleCloud administrator.

```bash
python3 scripts/build/cyclecloud-package.py --pipeline generated/pipeline.json \
  --image-version-id "$IMAGE_VERSION_ID" --output generated/cyclecloud
cyclecloud export_cluster YOUR_CLUSTER > private/cluster-before.txt
cyclecloud export_parameters YOUR_CLUSTER > private/parameters-before.json
```

**Expected result:** a review-only project, node-array/parameter fragments,
parameter JSON, and immutable image reference. A100 allows up to two nodes;
H100 is disabled with maximum zero. No cluster has changed yet.

Have the administrator merge the fragments and parameters into the protected
exports as described in [CycleCloud integration](cyclecloud-integration.md).
Preserve existing configuration/secrets. Save
`private/cluster-candidate.txt` and `private/parameters-candidate.json`.
Test parser/import behavior on a nonproduction cluster of the same version.
The next commands mutate the cluster and require separate approval:

```bash
cd generated/cyclecloud/vasp-image
cyclecloud project upload YOUR_LOCKER
cd ../../..
cyclecloud import_cluster YOUR_CLUSTER -c YOUR_EXISTING_TEMPLATE_TYPE \
  -f private/cluster-candidate.txt -p private/parameters-candidate.json --force
```

If you configured a nondefault project name, use its generated directory.

**Security and validation:** exports can contain secrets; keep them out of Git
and artifacts. Confirm the inherited Slurm/GRES/mount configuration, correct
private subnet, numeric image reference, approved node maxima, and rollback
export before import. Import does not reimage existing nodes.

**Failure, rollback, cleanup:** an existing generation directory is refused;
use a fresh named output for a new package rather than deleting review evidence.
For import/convergence failure, stop scale-out and restore the prior exports
using [rollback](rollback.md). Do not copy scheduler/Munge configuration into
the image.

## 9. Validate Slurm, GPUs, and private TCP

**Preconditions:** approved integration and GPU spend; a Slurm client connected
to the existing cluster; private DNS, approved compute-network TCP rules, and
a shared POSIX path. No licensed calculation input is needed for diagnostics.
**Permissions:** GPU partition submission rights; network-rule changes, if
needed, require the existing network owner's separate approval.

On the approved Slurm client:

```bash
export EXPECTED_IMAGE_VERSION_ID="$IMAGE_VERSION_ID"
export EXPECTED_GPU_COUNT=1
export VASP_VERSION=6.4.3
export VASP_SHARED_PATH=/YOUR_SHARED_POSIX_PATH
export MPI_TCP_ALLOWED_CIDRS='YOUR_COMPUTE_SUBNET_CIDR'
srun --version
srun --mpi=list
bash scripts/validation/slurm-validate.sh YOUR_A100_PARTITION a100
```

**Expected result:** a one-node allocation passes image/version/GPU/mount
checks, followed by health and two-node MPI jobs. MPI rank output includes
`nodes=2`, `cuda_buffers=1`, and `verified=1`. Review actual TCP connection
lines for the approved private addresses; setting MCA options is not proof.
The default TCP interval is 20000-21023, not the scheduler's own ports.

**Security and validation:** PMI2 support must be present in Slurm and the
isolated Open MPI stack. Stop if it is unavailable; never guess a PMIx mode or
launch outside the allocation. Obtain the compute-node MPI/PMIx component
inventory using [Slurm integration](slurm-integration.md).
The transport is private Ethernet TCP, not RDMA or GPUDirect RDMA.

**Current automation limits:** the validator checks the gallery version in its
first allocation, not on every later test node, and prints rather than asserts
all Slurm/GRES fields. An administrator must confirm the pinned image, physical
GPU count, GRES, shared-mount behavior, and CycleCloud membership for every test
node. This lesson deliberately uses the one-GPU SKU; larger SKUs need an
approved all-GPU allocation and separate physical-count evidence.
Collect scale-up/down and fresh-node/reimage evidence using
[A100 validation](a100-validation.md).

**Failure, rollback, cleanup:** inspect safe job metadata and private logs using
[troubleshooting](troubleshooting.md). Cancel only named jobs with
`scancel YOUR_JOB_ID`. Verify that no test allocation remains and idle nodes
scale down. If the candidate is rejected, use the previous pinned version.

## 10. Submit authorized VASP calculations

**Preconditions:** passing diagnostics plus an authorized input directory and
numerical reference/tolerances chosen by the workload owner.
**Permissions:** licensed-input access and normal Slurm submission rights.
Keep the input/output directories on approved private POSIX storage.

Use absolute paths and a new output directory for each job:

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

**Expected result:** jobs exit zero, private outputs are retained, and numerical
results agree with the approved reference within the recorded tolerances.
The examples request one rank and one GPU per node; that is not a tuning
recommendation. A small smoke test is not a performance benchmark.

**Security and validation:** never display/upload calculation contents. Job
stdout/stderr may contain proprietary results. Use a dedicated input directory:
copy-back preserves its files. Relative output paths currently fail when the
driver changes directory; absolute paths avoid that known issue.

**Failure, rollback, cleanup:** nonzero exits block acceptance. TERM/INT recovery
retains outputs; scratch is not automatically removed. Confirm recovery on the
actual cluster, not just in mocks. Cancel only named jobs, retain outputs under
the licensed-data policy, and clean only resolved job-specific scratch paths
after review. See [job inputs and placement](../examples/slurm/README.md).

## 11. Make the promotion decision

**Preconditions:** reviewed evidence for this exact immutable version: image
cleanliness/linkage, every test node's image, CycleCloud convergence/lifecycle,
Slurm/GRES, GPU generation/count, private TCP payloads, and numerical VASP
agreement. H100 needs a separately built `h100_gpu` profile and its own
[validation](h100-validation.md); A100 evidence does not certify it.
**Permissions:** release approval and image-version metadata/tag write.

The authorized reviewer creates `private/validation-receipt.json` using the
shape in [promotion](image-promotion.md). Do not copy success flags as a
substitute for evidence. After explicit promotion approval:

```bash
python3 scripts/build/manage.py promote --approve \
  --image-version-id "$IMAGE_VERSION_ID" \
  --validation-receipt private/validation-receipt.json
az resource show --ids "$IMAGE_VERSION_ID" --query tags --output json
```

**Expected result:** tags `status=promoted` and `validation=passed`.
Promotion changes tags only; it neither updates CycleCloud nor enables floating
gallery `latest`. Roll out the pinned version through another approved
integration/canary/reimage decision, preserving the previous reference.

**Security and validation:** the receipt is an operator assertion, not
authenticated test provenance. Restrict receipt writes and retain evidence
IDs, timestamps, hardware targets, and tolerances privately.

**Failure, rollback, cleanup:** incomplete evidence means keep the candidate
unpromoted. Do not weaken the gate. Use [rollback](rollback.md) if production
canaries fail; retire rejected candidates only through release policy.

## 12. Roll back and clean up deliberately

**Preconditions:** stopped builds/test jobs, reviewed exact resources, retained
previous version/exports, and checked output retention.
**Permissions:** cluster administration for rollback, source-delete rights for
staging, and deployment rights for optional validation resources.

For a rejected rollout, drain only the affected named nodes and verify jobs
have finished before restoring the protected template:

```bash
scontrol update NodeName=YOUR_AFFECTED_NODE State=DRAIN Reason=image-rollback
squeue -w YOUR_AFFECTED_NODE
cyclecloud import_cluster YOUR_CLUSTER -c YOUR_EXISTING_TEMPLATE_TYPE \
  -f private/cluster-before.txt -p private/parameters-before.json --force
```

Have the administrator retire only the affected idle compute VMs, boot a fresh
canary, and repeat the prior version's accepted tests. Do not terminate the
existing controller or shared cluster. See [rollback](rollback.md).

After source cleanup approval:

```bash
python3 scripts/build/manage.py source-cleanup --pipeline generated/pipeline.json --approve
rm -f -- staging/vasp-source.tar.gz staging/vasp-source.tar.gz.json
```

**Expected result:** the named staging blob is deleted and nonexistence checked
in default `delete` mode. Explicit `retain` mode leaves it; review expiry and
BYO soft-delete/version/backup policies separately. Local source is not removed.

This lesson does not create standalone validation VMs. If you separately used
the optional validation state, review its own destroy plan before approving:

```bash
bash scripts/build/terraform.sh validation plan -destroy \
  -var-file="$PWD/private/validation.tfvars"
TF_APPROVED_APPLY=1 bash scripts/build/terraform.sh validation destroy \
  -var-file="$PWD/private/validation.tfvars"
bash scripts/build/terraform.sh validation output
```

Use the same validation backend key used during deployment, not a factory or
publication key. Expect empty VM/IP arrays after successful destruction.

**Security, validation, and failures:** canceled/failed AIB runs can leave
licensed material on service-owned disks even when the script cleanup succeeds.
Check restricted staging resources after the service stops. Verify Slurm jobs
finish and idle nodes scale down; review retained images, NAT gateways, disks,
and source copies for continuing cost/access. Do not destroy factory/gallery
resources as a shortcut. Follow [cleanup](cleanup.md) for explicit ownership
and release-retirement rules.

You have finished when either the exact candidate has complete reviewed
acceptance and a controlled rollout, or it remains explicitly unvalidated with
tests/resources stopped and production still on a known-good image.
