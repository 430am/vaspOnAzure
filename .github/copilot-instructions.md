# GitHub Copilot instructions: Azure CycleCloud Slurm VASP image

## Project purpose

This repository builds an Azure Compute Gallery image for licensed VASP workloads running through Slurm in an existing Azure CycleCloud environment.

The implementation uses:

- Terraform.
- Azure VM Image Builder.
- microsoft\-dsvm:ubuntu\-hpc:2204:latest.
- Locally supplied, licensed VASP source.
- Azure NC\-series A100 and H100 compute nodes.
- Slurm\-managed execution.
- MPI over Azure Ethernet and TCP.

The initial build and validation region is centralus. The default GPU validation target is Standard\_NC24ads\_A100\_v4.

## Ownership boundaries

The image pipeline owns:

- VASP compilation.
- VASP runtime binaries.
- Environment modules.
- Compatible compiler and runtime libraries.
- MPI\-over\-TCP runtime profiles.
- GPU and MPI health checks.
- Safe build manifests.
- Azure Compute Gallery image publication.

Azure CycleCloud owns:

- Compute\-node provisioning.
- Node\-array configuration.
- Scheduler discovery.
- Slurm configuration.
- Munge configuration.
- Node identity.
- Partition membership.
- Autoscaling.
- Cluster\-specific mounts.
- Cluster\-specific networking settings.
- First\-boot convergence.

Slurm owns:

- Resource allocation.
- Task placement.
- CPU allocation.
- GPU allocation.
- Process launch.
- Job accounting.
- Job termination.
- Production VASP execution.

Do not place CycleCloud\- or Slurm\-owned mutable configuration into the image.

## VASP source rules

Authorized VASP source is supplied locally under:

source/vasp/

unless the operator explicitly selects another path.

Never:

- Commit VASP source or binaries.
- Commit POTCAR data.
- Commit proprietary VASP inputs or outputs.
- Display source contents in logs.
- Download VASP from an external source.
- Create substitute or fabricated VASP source.
- Upload VASP source as an ordinary GitHub Actions artifact.
- Pass source content through Terraform variables or state.

Always:

- Validate the source directory.
- Generate a checksum.
- Stage it through protected Azure Storage.
- Use managed identity for Azure Image Builder access.
- Verify the checksum inside the build.
- Remove source archives, extracted source, and object files before publication.
- Scan for accidentally retained source material.
- Record only safe build metadata.

The repository must include strong .gitignore rules and a tracked source/README.md.

## Image\-source rules

Use:

- Publisher: microsoft\-dsvm
- Offer: ubuntu\-hpc
- SKU: 2204
- Version: latest

Capture the resolved source and installed\-component versions in a safe image manifest.

Do not assume installed CUDA, NVIDIA driver, MPI, HPC\-X, UCX, NCCL, compiler, or math\-library versions. Detect them.

Do not replace Microsoft\-provided GPU drivers unless a documented compatibility requirement makes replacement necessary.

## VASP build profiles

Keep independent build profiles for:

- CPU MPI.
- NVIDIA A100.
- NVIDIA H100.

Do not assume one GPU binary is optimal for both A100 and H100.

Install profiles into versioned directories under /opt/vasp/.

Expose profiles with environment modules.

The selected VASP compilation toolchain and runtime MPI stack must be compatible. Never compile against one MPI implementation and unintentionally launch through another.

Do not invent VASP makefile variables or source paths. Inspect the operator\-supplied source structure and use an explicitly supplied makefile template when required.

## CycleCloud rules

Treat the CycleCloud environment as existing infrastructure.

Do not create or modify a CycleCloud cluster unless the operator explicitly enables that action.

Generate:

- CycleCloud project content.
- Cluster\-template fragments.
- Image references.
- Node\-array examples.
- Rollback instructions.

Do not embed:

- CycleCloud credentials.
- Scheduler credentials.
- Cluster secrets.
- Scheduler hostnames.
- Static node names.
- Munge keys.
- Cluster\-specific slurm.conf.

Use an immutable Azure Compute Gallery image version in production CycleCloud node arrays.

Do not use a floating gallery latest reference for production nodes.

## Slurm rules

Production jobs must run through Slurm.

Prefer:

- sbatch for batch jobs.
- salloc for interactive allocations.
- srun for task launch.

Use standalone mpirun only for isolated image diagnostics or when the installed Slurm/MPI integration explicitly requires MPI\-managed launch inside an existing allocation.

Before choosing the launch mode, inspect:

- srun \-\-mpi=list
- Slurm version.
- Open MPI version.
- PMIx version.
- PMI2 availability.
- Installed Slurm MPI plugins.

Do not hard\-code a PMIx mode without confirming compatibility.

Never launch tasks outside the Slurm allocation.

Get node count, task count, CPUs, GPUs, and hostnames from Slurm rather than hard\-coded hostfiles.

## MPI\-over\-TCP rules

The default path for the target NC A100 and H100 node arrays is MPI over private Azure Ethernet and TCP unless the selected SKU and environment explicitly expose and configure RDMA.

- Detect the compute Ethernet interface.
- Do not hard\-code eth0.
- Exclude loopback, Docker, CNI, and InfiniBand interfaces from the default TCP profile.
- Do not claim RDMA or GPUDirect RDMA over Ethernet.
- Restrict the MPI TCP port range to the CycleCloud compute network.
- Use private DNS and private IP addresses.
- Verify the transport used during validation.
- Propagate required MPI environment variables through srun.
- Do not bake hostfiles into the image.

MPI examples must operate on nodes granted by the Slurm allocation.

## Slurm job\-script rules

Example jobs belong under examples/slurm/.

Every job must:

- Use valid \#SBATCH directives.
- Load the correct VASP and MPI modules.
- Request GPUs through the existing cluster's GRES model.
- Use srun as the default task launcher.
- Avoid CPU and GPU oversubscription.
- Print safe runtime metadata.
- Use allocation\-derived host information.
- Use configurable scratch and output paths.
- Capture and return the VASP exit code.
- Handle termination signals.
- Avoid printing proprietary input content.
- Avoid distributing POTCAR or other licensed input data.

Partition names must be configurable or clearly marked for substitution.

Do not assume the same ranks\-per\-GPU setting is optimal for every VASP calculation.

## Terraform rules

Terraform owns the image factory and optional validation infrastructure.

Do not put the contents of VASP source files into Terraform configuration, variables, resources, outputs, plans, or state.

Keep separate state boundaries for:

- Image\-factory infrastructure.
- Gallery image publication.
- Temporary validation resources.
- Optional CycleCloud integration.

Avoid importing the existing CycleCloud environment into Terraform unless explicitly requested.

Default CycleCloud integration to generation or plan\-only mode.

Never output:

- Secrets.
- SAS tokens.
- Storage keys.
- Private keys.
- CycleCloud passwords.
- Licensed\-source paths containing credentials.

## GitHub Actions rules

Use GitHub OIDC for Azure authentication.

The workflow that accesses local VASP source should run only on a controlled self\-hosted runner or another explicitly approved trusted execution environment.

Do not send the source to a normal GitHub\-hosted runner unless the operator has approved that architecture and licensing permits it.

Require manual approval before:

- Reading the VASP source directory.
- Uploading the source archive.
- Starting the image build.
- Publishing an image.
- Updating a CycleCloud template.
- Deploying GPU nodes.
- Promoting an image version.

Do not deploy A100 or H100 nodes on each commit.

Add concurrency controls and timeouts for image builds and GPU validation.

Upload only non\-sensitive logs and manifests.

## Validation rules

Image build completion does not prove workload readiness.

Validation must prove:

- The node boots.
- CycleCloud configuration converges.
- The node joins the cluster.
- Slurm registers the node.
- Slurm detects GPUs and GRES correctly.
- The expected gallery image version is running.
- The selected environment modules load.
- The VASP binary resolves its MPI and GPU libraries.
- Single\-node srun works.
- Multi\-node srun works.
- MPI traffic uses private Ethernet and TCP.
- No licensed source remains in the image.
- No credentials or cluster\-specific secrets remain in the image.
- A controlled VASP smoke test succeeds when authorized input is available.

Do not describe a smoke test as a performance benchmark.

## Documentation rules

Every operational procedure must include:

- Preconditions.
- Required permissions.
- Exact commands.
- Expected output.
- Security implications.
- Validation criteria.
- Failure modes.
- Rollback steps.
- Cleanup steps.

Document separately:

- Source staging.
- Image compilation.
- Image publication.
- CycleCloud template integration.
- Slurm job submission.
- TCP MPI validation.
- Image promotion.
- Rollback.
- Source and validation\-resource cleanup.

When code and documentation differ, update both in the same change.

