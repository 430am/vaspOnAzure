# Rollback to a known validated image

## Preconditions

Approved CycleCloud administrator; previous protected template/parameter export;
previous immutable gallery version retained in its publication state; no running
production jobs on nodes selected for retirement. Do not roll back by editing
the bytes of a gallery version or using floating `latest`.

1. Stop promotion/scale-out changes. Identify affected nodearrays and jobs.
2. Drain **named** affected nodes through site-approved Slurm/CycleCloud
   maintenance procedures:

```bash
scontrol update NodeName=YOUR_AFFECTED_NODE State=DRAIN Reason=image-rollback
squeue -w YOUR_AFFECTED_NODE
```

3. Confirm jobs finished/migrated under site policy. Restore the protected
   previous template/parameters (or change only the reviewed image parameter):

```bash
cyclecloud import_cluster YOUR_CLUSTER -c YOUR_EXISTING_TEMPLATE_TYPE \
  -f private/cluster-before.txt -p private/parameters-before.json --force
```

4. Retire the explicitly identified idle affected VMs using CycleCloud's
   installed-version UI/CLI and autoscaler procedure. Do not terminate the
   scheduler or an entire shared cluster. Template changes alone do not replace
   running VM disks.
5. Trigger a fresh canary allocation:

```bash
salloc -p YOUR_PARTITION -N 1 -n 1 --gres=gpu:1 --time=00:15:00
sinfo -p YOUR_PARTITION -N
```

6. Verify actual IMDS gallery version, first-boot convergence, allocatable state,
   GRES, mounts and the previously accepted health/numerical tests.
7. Release the allocation, verify scale-down and resume production only after
   canary acceptance. Record rollback metadata outside licensed job outputs.

The old image must remain available and accessible to CycleCloud's identity.
Publication `prevent_destroy` protects against accidental deletion. A failed
rollback requires controlled node/identity/DNS diagnosis, not copying munge/
Slurm keys into an image. See [troubleshooting](troubleshooting.md).
Clean the rejected candidate/source/test resources with [cleanup](cleanup.md)
only after confirming no nodes still depend on them.
