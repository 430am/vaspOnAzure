# Slurm launch contract

## Preconditions

CycleCloud supplies compatible Slurm daemons/clients, controller discovery,
munge, GRES, cgroups, mounts and autoscaler. This image installs PMI2 client
libraries, not a second Slurm controller. Scheduler plugins are not baked in.
The operator needs ordinary partition submission rights; node inspection/drain
or autoscaler changes need the site's administrative role.

## Verify launch support

```bash
srun --version
srun --mpi=list
sinfo -p YOUR_PARTITION -N -o '%N %T %c %m %G'
scontrol show node YOUR_ALLOCATED_NODE
```

Load `mpi/openmpi-tcp` **on the compute node** before inspecting `ompi_info`.
The runtime selects PMI2 only when both the Slurm `pmi2` plugin and built Open
MPI `ess:pmi` and `pmix:s2` client components exist. A successful multi-rank test is still required
to prove protocol interoperability. Internal Open MPI PMIx is **not** proof
that the site's Slurm PMIx plugin is ABI-compatible.

If PMI2 is unavailable, stop; configure the site's supported plugin or rebuild
an explicitly compatible PMIx/PMI stack through review. Do not force `--mpi=pmix`
or silently fall back to standalone `mpirun`.

```bash
salloc -p YOUR_PARTITION -N 1 -n 2 --gres=gpu:1 --time=00:10:00
source /etc/profile.d/modules.sh
module load mpi/openmpi-tcp
source /opt/vasp-image/bin/runtime.sh
mode=$(vasp_mpi_mode)
export MPI_TCP_ALLOWED_CIDRS='YOUR_COMPUTE_SUBNET_CIDR'
srun --mpi="$mode" --export=ALL /opt/vasp-image/bin/mpi-task.sh \
  /opt/vasp-image/bin/mpi-smoke
exit
```

These module/runtime commands must execute on an allocated compute node if the
login node lacks the image stack. Use `srun --mpi=none --pty bash` to obtain
that shell without launching MPI during setup.
Expected: two verified ranks within one node, correct library stack, nonzero
exit if sums/message payloads fail.

## Production jobs

Use [example jobs](../examples/slurm/README.md): `sbatch` for jobs, `salloc` for
interactive work, `srun` for allocated tasks. Override partition/CPU/task/GPU
directives with submission flags. Scripts display allocation/runtime metadata,
respect Slurm visibility, capture the VASP exit status and copy outputs safely
to a new POSIX directory. Never print or publish licensed input/output.

Repeated health checks should verify mount readiness and correct GRES, not just
`nvidia-smi`. Confirm `scontrol show job JOBID`, cgroup CPU/GPU binding and
allocated task counts. For failures see [troubleshooting](troubleshooting.md).
Cancel only specific job IDs (`scancel JOBID`), release allocations and validate
scale-down. Rollback image versions using [rollback](rollback.md).
