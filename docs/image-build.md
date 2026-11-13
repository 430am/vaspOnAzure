# Factory provisioning, build and publication

## Preconditions and permissions

Terraform >=1.9, Azure CLI, approved source checksum; registered
`Microsoft.VirtualMachineImages`, `Microsoft.Compute`, `Microsoft.Storage`,
`Microsoft.Network`, `Microsoft.ManagedIdentity` providers; supported AIB region.
Operator/OIDC principal needs factory resource deployment, role definitions/
assignments, identity assignment and network access. Publication principal needs
gallery image-version write and intermediate image read. AIB identity receives
container Blob Data Reader, scoped image publication permissions and VNet
Network Contributor. Review these scopes before apply.

Supply an existing **private Terraform backend**, distinct from licensed-source
storage. Use Entra authentication, private access, encryption, restricted RBAC
and independent state keys. Do not place secrets in tfvars.

```bash
export TF_BACKEND_ACCOUNT=YOUR_BACKEND_ACCOUNT
export TF_BACKEND_CONTAINER=YOUR_STATE_CONTAINER
export TF_BACKEND_RESOURCE_GROUP=YOUR_BACKEND_RG
az login
az account set --subscription YOUR_SUBSCRIPTION_ID
mkdir -p private generated
chmod 700 private generated
cp environments/dev/factory/terraform.tfvars.example private/factory.tfvars
```

Edit private inputs: subscription/RG, unique storage account, approved SHA-256,
profile selection, BYO network/gallery/identity/storage where required.
`source/README.md` explains the clean source layout. No resource action runs
during preparation or Terraform plan.

## Provision and upload

```bash
bash scripts/build/terraform.sh factory plan -var-file="$PWD/private/factory.tfvars"
bash scripts/build/terraform.sh factory apply -var-file="$PWD/private/factory.tfvars"
bash scripts/build/terraform.sh factory output > generated/pipeline.json
python3 scripts/build/manage.py upload --pipeline generated/pipeline.json --approve
```

Expected: private storage/container/endpoint, generalized Gen2 gallery definition,
identity/RBAC and AIB template. Plan contains script code and non-secret build
configuration, **never licensed source**. BYO resource security is not silently
changed; the staging uploader rejects insecure storage. BYO gallery definitions
must be Linux, generalized and Gen2; BYO gallery RBAC must remain private.

## Explicit build

```bash
python3 scripts/build/manage.py build --pipeline generated/pipeline.json --approve
```

The command verifies staged metadata, starts AIB, polls bounded status and checks
the intermediate image. AIB performs: OAuth fetch/checksum; safe extraction;
base inventory; dependency/toolchain setup; requested compilation; linkage/
module checks; runtime installation; protected-directory removal; residual scan;
cloud-init/waagent deprovisioning; managed image distribution.

The source Marketplace `latest` is resolved **at AIB run time**. The IMDS
image reference and package inventories are saved under `/opt/vasp-image/manifests`.
Resolved version availability is an Azure-side check, not inferred locally.

## Publish a candidate (separate state)

Each release needs its own publication backend key. The commands below use the
default first-release state. For another version, prefix **each publication
command only** with `TF_BACKEND_KEY=vasp/publication/1.1.0.tfstate`.
Do not point factory operations at a publication state. The wrapper reconfigures
the backend without migrating old release state. In Actions set the non-secret
`PUBLICATION_STATE_KEY` variable for the intended release.

Create `private/publication.tfvars` with these non-secret values, using factory
outputs for the IDs:

```hcl
subscription_id     = "YOUR_SUBSCRIPTION_ID"
managed_image_id    = "/subscriptions/.../providers/Microsoft.Compute/images/vasp-dev-001"
image_definition_id = "/subscriptions/.../galleries/vasp_private/images/vasp-ubuntu-hpc-2204"
image_version       = "1.0.0"
location            = "centralus"
replication_regions = ["centralus"]
```

```bash
bash scripts/build/terraform.sh publication plan -var-file="$PWD/private/publication.tfvars"
bash scripts/build/terraform.sh publication apply -var-file="$PWD/private/publication.tfvars"
bash scripts/build/terraform.sh publication output > generated/publication.json
```

Expected: immutable version `1.0.0`, `exclude_from_latest=true`, candidate tags.
`prevent_destroy` prevents accidental version deletion. AIB does not publish
directly into the production gallery. Repeated builds need distinct managed
image names; retain publication state per release using distinct backend keys/
environment copies. Do not replace a published version's bytes.

## Review on a validation node

After [CycleCloud integration](cyclecloud-integration.md), within an allocation:

```bash
srun --mpi=none bash -c 'ls /opt/vasp-image/manifests; cat /opt/vasp-image/manifests/a100_gpu.json'
srun --mpi=none /opt/vasp-image/bin/image-health.sh runtime
```

These manifests contain safe metadata only. Do not retrieve protected compilation
logs or source. Runtime health success proves static/linkage/boot checks, not
numerical VASP correctness. Validate GPU/TCP and licensed calculations before
[promotion](image-promotion.md). Failed builds require restricted AIB staging
inspection/cancellation; see [troubleshooting](troubleshooting.md).
Rollback and remove source using [rollback](rollback.md) and [cleanup](cleanup.md).
