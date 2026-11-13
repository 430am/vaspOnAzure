# Troubleshooting

Use safe metadata and approved private logs. Never print VASP source/POTCAR or
upload build/calculation logs to GitHub artifacts.

| Failure | Check and correction |
| --- | --- |
| Source manifest mismatch | Review exact approved delivery; remove unapproved roots/tests/binaries/links. Do not blindly regenerate approval. |
| Storage 403/DNS public | Entra identity, container RBAC propagation, private endpoint routing/DNS. Public access/keys are intentionally disabled. |
| Terraform backend failure | Existing private state account, Blob RBAC, login/OIDC, endpoint DNS. Backend is not source staging. |
| AIB template/build network | Provider registration, region, subnet private-link policy, NSG proxy 60001, egress, identity network rights. |
| SDK/template missing | Selected NVHPC release/CUDA path, installation policy, authorized `arch/...` template. No silent source patch. |
| Compiler failure | Reproduce in an approved source environment; image diagnostics are protected and deleted. Update a reviewed template, not source in CI. |
| Linkage wrong MPI | Load isolated module; examine safe ldd manifests; exclude HPC-X/MKL/vendor-MPI contamination. |
| GPU compatibility | Exact SKU/capability, base driver >=545.23.08, CUDA runtime; never overwrite driver automatically. |
| Slurm cannot launch PMI2 | `srun --mpi=list`, built `ess:pmi` support, site's Slurm plugin availability. PMIx version equivalence is not assumed. |
| Multi-node hangs | Private forward/reverse DNS, actual route/interface, approved TCP interval, rank placement and scheduler PMI traffic. |
| Node does not join | Jetpack/slurm project version, scheduler discovery/munge first boot, image ID, DNS/mount/GRES convergence. Do not bake cluster fixes into the image. |
| VASP failure | Private input completeness, supported calculation options, numerical reference, GPU visibility; inspect outputs on approved filesystem. |
| Gallery replication | Target-region availability, publication permissions, managed-image provenance; never promote incomplete replicas. |

## Safe status commands

```bash
az resource show --ids YOUR_AIB_TEMPLATE_ID --api-version 2024-02-01 \
  --query properties.lastRunStatus --output json
az resource show --ids YOUR_IMAGE_VERSION_ID --query properties.provisioningState
sinfo -p YOUR_PARTITION -N
scontrol show job YOUR_JOB_ID
sacct -j YOUR_JOB_ID --format=JobID,State,ExitCode,Elapsed
```

AIB can retain failed-build material in its service-owned staging RG. View that
scope only with authorized access. Never distribute full customization logs.

Stop runaway jobs/builds by **specific IDs**:

```bash
scancel YOUR_JOB_ID
az resource invoke-action --ids YOUR_AIB_TEMPLATE_ID --action Cancel \
  --api-version 2024-02-01
```

After cancellation verify AIB is no longer running before attempting cleanup.
Do not retry onto an existing published managed-image name. Allocate a new
pipeline name/version and follow [image build](image-build.md).

Rollback production to the previous pinned version using [rollback](rollback.md).
Clean only identified test resources/source artifacts using [cleanup](cleanup.md).
