#!/bin/bash
# Sourced by job drivers; per-task TCP setup executes on the allocated node.
set -euo pipefail
umask 077

vasp_copy_outputs() {
    local relative
    local filters=(--exclude=stdout.log --exclude=stderr.log)
    relative=$(realpath --relative-to="$VASP_JOB_WORK" "$VASP_JOB_OUTPUT")
    if [[ $relative != .. && $relative != ../* ]]; then
        filters+=("--exclude=/$relative/***")
    fi
    rsync -a --chmod=D700,F600 "${filters[@]}" -- "$VASP_JOB_WORK/" "$VASP_JOB_OUTPUT/"
}

vasp_terminate() {
    local status=${1:?}
    if kill -0 "$VASP_STEP_PID" 2>/dev/null; then
        kill -TERM "$VASP_STEP_PID"
    fi
    wait "$VASP_STEP_PID" || printf 'Slurm step terminated; saving recoverable outputs.\n' >&2
    vasp_copy_outputs
    exit "$status"
}

vasp_mpi_mode() {
    [[ -n ${SLURM_JOB_ID:-} ]] || { echo "A Slurm allocation is required." >&2; return 1; }
    [[ $(command -v mpirun) == "${VASP_MPI_PREFIX:?Load mpi/openmpi-tcp}/bin/mpirun" ]] || {
        echo "MPI module and executable do not agree." >&2; return 1;
    }
    local modes info
    modes=$(srun --mpi=list 2>&1)
    info=$(ompi_info --parsable --all)
    if [[ $modes == *pmi2* && $info == *mca:ess:pmi:* && $info == *mca:pmix:s2:* && ${VASP_MPI_MODE:-} == pmi2 ]]; then
        printf '%s\n' pmi2
    else
        echo "No verified Slurm/Open MPI PMI2 combination. Review Slurm plugins; PMIx is not assumed compatible." >&2
        return 1
    fi
}

vasp_allocation() {
    printf 'job=%s nodes=%s tasks=%s cpus_per_task=%s\n' "${SLURM_JOB_ID:?}" \
        "${SLURM_JOB_NUM_NODES:?}" "${SLURM_NTASKS:?}" "${SLURM_CPUS_PER_TASK:-1}"
    scontrol show hostnames "${SLURM_JOB_NODELIST:?}"
    srun --version
    mpirun --version
}

vasp_run() {
    local generation=${1:?a100 or h100 required} mode rc=0
    [[ $generation == a100 || $generation == h100 ]] || return 2
    [[ ${VASP_PROFILE:-} == "${generation}_gpu" ]] || {
        echo "Loaded VASP profile does not match the requested GPU generation." >&2; return 1;
    }
    : "${SLURM_SUBMIT_DIR:?}" "${SLURM_NTASKS:?}" "${VASP_VERSION:?Load VASP module}"
    mode=$(vasp_mpi_mode)
    vasp_allocation
    local input=${VASP_INPUT_DIR:-$SLURM_SUBMIT_DIR}
    local output=${VASP_OUTPUT_DIR:-$SLURM_SUBMIT_DIR/results-$SLURM_JOB_ID}
    local scratch=${VASP_SCRATCH_DIR:-}
    local work=$input
    # Multi-node working directories must be on shared POSIX storage.
    if [[ ${VASP_STAGE_INPUT:-0} == 1 ]]; then
        if (( SLURM_JOB_NUM_NODES > 1 )) && [[ ${VASP_SCRATCH_SHARED:-0} != 1 ]]; then
            echo "Multi-node staging requires explicitly shared POSIX scratch." >&2; return 1
        fi
        scratch=${scratch:-${SLURM_TMPDIR:-}}
        [[ -n $scratch && -d $scratch ]] || { echo "Supply an existing scratch directory." >&2; return 1; }
        work=$(mktemp -d "$scratch/vasp-$SLURM_JOB_ID.XXXXXX")
        rsync -a --chmod=D700,F600 -- "$input/" "$work/"
    fi
    for required in INCAR POSCAR KPOINTS POTCAR; do
        [[ -r $work/$required ]] || { echo "Required authorized calculation input is missing." >&2; return 1; }
    done
    [[ ! -e $output ]] || { echo "Output destination must not already exist." >&2; return 1; }
    mkdir -p -- "$output"
    # Persist termination outputs too; never remove scratch automatically.
    VASP_JOB_WORK=$(realpath "$work") VASP_JOB_OUTPUT=$(realpath "$output")
    cd "$work"
    local binary=${VASP_BINARY:-vasp_std}
    [[ $binary == vasp_std || $binary == vasp_gam || $binary == vasp_ncl ]] || return 2
    srun --export=ALL --mpi="$mode" --cpu-bind=cores --gpu-bind=closest \
        /opt/vasp-image/bin/mpi-task.sh --generation "$generation" \
        "$binary" > "$output/stdout.log" 2> "$output/stderr.log" &
    VASP_STEP_PID=$!
    trap 'vasp_terminate 143' TERM
    trap 'vasp_terminate 130' INT
    wait "$VASP_STEP_PID" || rc=$?
    vasp_copy_outputs
    trap - TERM INT
    printf 'VASP job exit=%s; outputs retained in the configured POSIX destination.\n' "$rc"
    return "$rc"
}
