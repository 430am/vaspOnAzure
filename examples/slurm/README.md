# Job inputs and placement

No calculation inputs are shipped. Supply authorized `INCAR`, `POSCAR`,
`KPOINTS`, and `POTCAR` in an existing POSIX directory. Do not commit them.

Override partition names with `sbatch --partition=YOUR_PARTITION`. Defaults request
one GPU and one MPI rank **per node**, deliberately using only one GPU on larger
SKUs. This is a conservative example, not a performance recommendation.
To use more GPUs, override **both** `--gres=gpu:N` and `--ntasks-per-node=N`.
Multiple ranks per GPU require explicit allocation/binding review; the wrapper
does not assign or override `CUDA_VISIBLE_DEVICES`. Slurm `--gpu-bind=closest`
and `--cpu-bind=cores` use available topology. Review `scontrol show job`,
`nvidia-smi topo -m`, and the site's cgroup/GRES configuration.

Set `VASP_INPUT_DIR`, `VASP_OUTPUT_DIR`, `VASP_BINARY` (std/gam/ncl executable
name), and `VASP_VERSION` through `--export=ALL` or your login environment.
Outputs default to a new `results-JOBID` directory. Existing output destinations
are rejected. Inputs are never printed. Calculation stdout/stderr are private
job outputs and **must not be CI artifacts**.
Also supply `MPI_TCP_ALLOWED_CIDRS` for the approved compute network(s).
Use a dedicated calculation input directory rather than a general home/project
directory: staging/copy-back preserves that directory's files.

Optional staging: `VASP_STAGE_INPUT=1`, `VASP_SCRATCH_DIR=/existing/path`.
For a single node, an existing `SLURM_TMPDIR` may be used. Multiple nodes require
`VASP_SCRATCH_SHARED=1` and shared POSIX scratch; per-node local scratch is not
a shared VASP working directory. Scratch is retained on failure/termination for
operator recovery. Use explicit named-path cleanup after checking final outputs.

`OMP_NUM_THREADS=1` is the non-OpenMP template default. CPUs per rank can be
reduced if unnecessary. One-rank smoke tests do not establish MPI correctness;
use the two-node diagnostic. `NCORE`/`KPAR` and numerical convergence remain
calculation-specific and are not changed by job scripts.
