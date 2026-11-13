# Security and licensing controls

## Trust boundaries and permissions

This repository does not confer a VASP license. Operators must be authorized
to build/use/distribute the private image to its intended users. Source,
potential datasets, proprietary calculations and binaries are never tracked
or uploaded as Actions artifacts. Do not fetch VASP from the internet.

Deterministic archives are **access-controlled**, not application-encrypted:
local mode 0600, private source directory, private endpoint, Storage encryption,
no anonymous/public networking/shared-key access, and container-scoped RBAC.
CMK is optional through `source_key_vault_key_id`; a BYO account owns its CMK/
rotation/Key Vault firewall policy. Key Vault must permit the storage encryption
identity and service's encryption operations. No keys enter Terraform variables.
The CMK input is an ARM resource ID ending `/vaults/VAULT/keys/KEY`, not the
HTTPS key URI returned as `kid`. The created account follows the latest key
version; rotation and Key Vault access are operator-controlled.

AIB identity: source-reader and scoped build/network rights. Operator source
identity: Blob Contributor plus account read for policy verification.
Publication identity: managed-image read and gallery-version write.
CycleCloud identity: gallery read plus its existing compute deployment rights.
Promotion identity: version metadata/tag write, no source access.
Terraform execution: reviewed role-assignment privileges and private state access.
Do not grant general subscription Owner to runtime nodes.

## Source and build protection

Source preparation verifies exact file manifests or approved SHA-256; rejects
links/unexpected file types/generated artifacts and excludes POTCAR/test data.
In-VM extraction verifies approved archive bytes and rejects traversal/links/
duplicates. Source bytes never pass through Terraform `file`, state or content
resources; `file()` only embeds **repository-owned public scripts** in AIB.

In-VM OAuth authorization is held in a mode-0600 curl config, not command-line
arguments. No SAS/storage-key URLs are supported. Source URLs are credential-free
and names must be opaque; SHA-256 values contain no credentials.
Compiler output is restricted because diagnostics may contain licensed source.
All protected build material is removed even on customization failure; inspect
AIB failed disks/staging storage separately because service-side copies/snapshots
can remain after a VM failure. Service logs/artifacts are not exported by CI.

The residual scan is a **targeted filesystem/path check**, not a guarantee of
arbitrary secret detection in every file. Inspect base-image provenance and
site security controls; run approved offline secret/content scanning before
production if your policy requires stronger assurance. Never send licensed
files to a third-party scanning service.
Runtime scans cover image-owned installation trees, not shared user homes or
active calculation scratch. Those legitimately contain externally supplied
licensed input. The wider pre-capture scan runs before cluster mounts/jobs exist.
Trivy rule AZU-0010 is narrowly suppressed on the source account: trusted-service
bypass is deliberately disabled because the in-VM downloader uses a private
endpoint. Enabling that bypass is unnecessary here.

Pre-capture removal includes known munge/Slurm/host-key/account/machine identity.
First boot must regenerate keys and get cluster secrets from CycleCloud.
Do not require runtime munge/slurm.conf to be absent—that would break the cluster.

## Git and CI

```bash
git check-ignore source/vasp/src/main.F
python3 scripts/validation/repository-check.py
git status --short
```

Protection checks inspect tracked/history **paths**, not every historic blob's
contents. Empty Git history at initialization does not certify future commits.
Use approved secret scanning/pre-receive controls as well, and review named files
before commit. Ignore rules are not access controls. Never `git add -f` licensed
input. If content was previously pushed, follow your incident/license response;
adding `.gitignore` does not remove history.

Self-hosted source input must live outside checkout so checkout cleanup cannot
delete it. Use isolated/ephemeral trusted workspaces and approved branch code.
Configure protected environments/reviewers as in [promotion](image-promotion.md).
OIDC avoids long-lived Azure credentials. No normal artifact-upload action exists.
Job inputs/outputs remain on authorized POSIX storage.
Review and pin third-party workflow action updates under your supply-chain policy.

## Network and retention

MPI TCP permits approved private compute peers only; no SSH/MPI public IPs.
Existing NSGs, scheduler ports and DNS policy remain site-owned.
BYO source soft delete/versioning/backups can retain licensed copies after blob
delete; CMK encryption is not a substitute for expiry/RBAC review.

Failures block build/promotion. For key/source exposure revoke access immediately,
retain only approved incident evidence, and use [rollback](rollback.md).
Routine resource/source cleanup is in [cleanup](cleanup.md).

## Workflow setup

Workflows assume trusted, provisioned self-hosted Linux runners with Azure CLI,
Terraform, Python >=3.10, private DNS/routing and appropriate labels:
`azure-hpc`; source workflows additionally `licensed-source`; Slurm workflows
additionally `slurm-client`. Source and Slurm access belong to separate runner
groups and must not be exposed to pull-request code.

Set repository/environment **non-secret** variables:

| Variables | Purpose |
| --- | --- |
| AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID | Factory/build/publication OIDC identity and context |
| AZURE_SOURCE_CLIENT_ID | Source uploader/cleanup identity; container contributor and account read |
| AZURE_PROMOTION_CLIENT_ID | Metadata promotion identity |
| TF_BACKEND_ACCOUNT, TF_BACKEND_CONTAINER, TF_BACKEND_RESOURCE_GROUP | Existing private state backend |
| PUBLICATION_STATE_KEY | Version-specific publication state key; never share an old release's key |
| FACTORY_TFVARS_PATH, PUBLICATION_TFVARS_PATH, VALIDATION_TFVARS_PATH | Absolute paths to approved runner-local input files |
| PIPELINE_JSON_PATH | Absolute path to factory `pipeline` output JSON |
| VASP_SOURCE_DIRECTORY, VASP_APPROVED_MANIFEST_PATH | Authorized source and reviewed manifest outside checkout |
| VASP_VERSION, VASP_SOURCE_ARCHIVE_NAME | Declared source version and safe plain archive filename |
| SLURM_PARTITION_A100, SLURM_PARTITION_H100 | Existing test partitions |
| A100_GPU_COUNT, H100_GPU_COUNT | Expected physical GPU count for the selected test SKU |
| VASP_SHARED_PATH, MPI_TCP_ALLOWED_CIDRS | Existing POSIX mount and approved compute network |
| VALIDATION_RECEIPT_PATH | Absolute path to protected, operator-reviewed receipt |

The build caller needs container Blob Data Reader and account read for its
preflight in addition to infrastructure rights. AIB's own identity has a
separate Blob Reader assignment. Configure these roles explicitly.
OIDC federation subjects must match the named protected environments.
No CycleCloud token/password or private SSH key belongs in these variables.
Slurm-client runners use the site's existing authorized identity/munge setup.
Export existing cluster parameters only to protected runner storage.

Manual apply/destroy workflows use `TF_APPROVED_APPLY=1` only behind required
environment approvals. Review plan dispatch output before approving apply.
Image workflow polling is bounded to six hours; for longer builds use the local
CLI procedure. A timeout does not cancel AIB automatically: inspect/cancel the
specific template run before freeing staging resources or retrying.
Source workflow temporary archives are unique to run ID/attempt and removed on
exit. They are never uploaded as GitHub artifacts.
