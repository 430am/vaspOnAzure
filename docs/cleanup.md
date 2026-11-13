# Controlled cleanup

## Preconditions and scope

Authorized operator, stopped builds/jobs, reviewed exact resource IDs and state
scope. Never delete the existing CycleCloud scheduler/installation/network.
Never recursively remove source/workspace/home directories. Retain rollback
gallery versions and their states until release policy permits retirement.

## Protected staging

```bash
python3 scripts/build/manage.py source-cleanup --pipeline generated/pipeline.json --approve
rm -f -- staging/vasp-source.tar.gz staging/vasp-source.tar.gz.json
```

`delete` removes the named blob/visible snapshots and checks nonexistence;
`retain` explicitly leaves it and prints that decision. BYO soft-delete/version/
backup copies require separate policy-aware purge/expiry review. Do not remove
the authorized local source tree automatically.

The Actions source job removes only its exact local archive/receipt on exit.
Do not put licensed input within the Actions checkout cleanup boundary.

## Standalone validation resources

```bash
bash scripts/build/terraform.sh validation plan -destroy -var-file="$PWD/private/validation.tfvars"
bash scripts/build/terraform.sh validation destroy -var-file="$PWD/private/validation.tfvars"
```

Expected: only validation-state VM/NIC resources deleted; existing RG/subnet
remain. Verify `terraform.sh validation output` reports empty arrays.
Remember disks and quota may remain after interrupted operations; inspect
the exact resource IDs before any manual removal.

## Slurm/CycleCloud tests

Cancel named test jobs with `scancel JOBID` or exit the allocation. Verify jobs
finished and the site's idle timeout removes/deallocates test nodes. Follow the
site's nodearray reset procedure without deleting the scheduler or cluster.
Remove scratch only after checking final outputs and resolving its **exact**
job-specific path. Licensed outputs are retained/deleted under data policy.

## AIB staging and intermediate images

After a failed/canceled build, inspect AIB's last-run/staging RG metadata and
delete only explicitly identified abandoned disks/VMs/storage after the service
has stopped. Those assets may contain licensed source even if customization's
EXIT trap normally cleans up.

The intermediate managed image can be deleted after gallery replication,
validation and rollback retention review:

```bash
az image delete --ids YOUR_EXACT_INTERMEDIATE_MANAGED_IMAGE_ID
```

Factory Terraform does not own this external build artifact. Keep published
version states: they reference the input ID as provenance.
Gallery versions have `prevent_destroy`; retirement requires a reviewed
lifecycle/state policy change in that **release's publication state**, not
`terraform state rm` as an unreviewed shortcut.

Automatic factory/gallery destruction is intentionally absent. Manually review
ownership/dependencies and a Terraform destroy plan if dismantling a dedicated
factory; BYO resources must never be swept into cleanup. See
[rollback](rollback.md) before removing any production-consumed version.
