# Existing CycleCloud integration (review-only)

## Preconditions and permissions

Existing supported CycleCloud 8.x and `cyclecloud-slurm` template/project with
`nodearraybase`; private compute subnet; existing controller and shared POSIX
mounts; gallery read/VM deployment rights for CycleCloud's deployment identity.
CLI authentication is interactive or configured by the site's approved secret
store. Terraform never stores CycleCloud passwords/tokens. Verify the exact
CycleCloud/Slurm project version; generated fragments follow the upstream
`nodearraybase`, `slurm.role`, `slurm.hpc`, `slurm.partition` conventions.
The installed version's parser/import is the final schema authority.

Set factory inputs `cyclecloud_integration_enabled=true`, cluster name,
compute subnet ID, project/nodearray/partition names, region and immutable
`cyclecloud_gallery_image_version`. Keep `cyclecloud_update_mode=plan-only`.
Scheduler hostname is optional operational metadata and is not sent to AIB.

## Generate and review

```bash
export IMAGE_VERSION_ID='/subscriptions/.../galleries/.../images/.../versions/1.0.0'
python3 scripts/build/cyclecloud-package.py --pipeline generated/pipeline.json \
  --image-version-id "$IMAGE_VERSION_ID" --output generated/cyclecloud
```

Expected files: nodearrays/parameters fragments, parameter JSON, immutable image
reference, versioned `vasp-image` project with first-boot image health gate.
Names are validated; template placeholders have corresponding parameter values.
H100 `MaxCount=0` prevents unintended scaling until capacity is approved.

The reference records subscription, RG, gallery, definition, version and region.
Both node arrays inherit the **existing** Slurm execute project. No controller,
static node/GRES definitions or keys are created. Site GRES generation must
already be enabled and validated; this project does not overwrite it.

## Secure export and merge

Export to ignored protected storage because existing cluster parameters may
contain secrets:

```bash
umask 077
cyclecloud export_cluster YOUR_CLUSTER > private/cluster-before.txt
cyclecloud export_parameters YOUR_CLUSTER > private/parameters-before.json
```

An authorized reviewer must insert `generated/cyclecloud/nodearrays.txt` into
the exported `[cluster ...]` block **before** its `[parameters ...]` sections,
and append `generated/cyclecloud/parameters.txt`. Save as
`private/cluster-candidate.txt`. Merge `generated/cyclecloud/parameters.json`
into `private/parameters-before.json`, preserving existing values/secrets;
save `private/parameters-candidate.json`.
Review the diff locally, not in GitHub artifacts.

Upload the generated project using an approved CycleCloud CLI account:

```bash
cd generated/cyclecloud/vasp-image
cyclecloud project upload YOUR_LOCKER
cd ../../..
cyclecloud import_cluster YOUR_CLUSTER -c YOUR_EXISTING_TEMPLATE_TYPE \
  -f private/cluster-candidate.txt -p private/parameters-candidate.json --force
```

`YOUR_EXISTING_TEMPLATE_TYPE` is the installed cluster type, commonly `Slurm`.
**Import is an explicit, approved mutation**, not an automated pipeline action.
Perform a parser/import dry run on a nonproduction cluster of the same version
first; CLI versions do not share a universal validate-only flag.
Changing a template does not reimage already running nodes.

## Storage and partitions

Inherited first-boot configuration supplies shared home/input/scratch mounts.
For ANF, configure NFS address/export/mountpoint in the existing mount sections,
not the image. Check NFS version/options, DNS, firewall and UID/GID alignment.
Managed Lustre/BeeGFS need the site's client/init project and supported kernel;
this image does not assume those clients are installed. Blob Storage is staging,
not the default MPI POSIX working filesystem. Do not use BlobFuse for VASP
without an explicit semantics/performance review.

`slurm.partition=$SlurmPartitionA100` and the corresponding H100 field are
partition definitions consumed by CycleCloud's Slurm generator. Do **not**
append hand-written static `NodeName` entries to `slurm.conf`.
See [Slurm integration](slurm-integration.md) for allocation/GRES checks.

## Controlled scale-up, promotion, rollback

Use a temporary allocation in the selected partition to trigger autoscaling:

```bash
salloc -p vasp-a100 -N 1 -n 1 --gres=gpu:1 --time=00:15:00
sinfo -p vasp-a100 -N
scontrol show node
```

Expect an allocatable node, correct GRES and the pinned image ID in IMDS.
Follow [A100 validation](a100-validation.md), then release the allocation with
`exit`; verify idle scale-down. Promote only after scale/reimage/numerical checks.
Rollback restores the exported previous image/parameters with the same explicit
import procedure, drains/retires affected idle nodes, and boots fresh nodes.
See [rollback](rollback.md) and [cleanup](cleanup.md).
