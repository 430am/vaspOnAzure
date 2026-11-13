# Repository review

## Scope and conclusion

Reviewed on 2026-11-13 against implementation revision `67bccb3`: all 74 tracked
files, including Terraform roots/modules/locks, eight workflows, build/runtime
scripts, tests, CycleCloud fragments/project, Slurm examples, protection/lint
configuration, contributor instructions, and existing documentation.
This change adds documentation only; findings below are not runtime fixes.

**Conclusion:** the repository provides a coherent image-factory implementation
with strong ownership boundaries and safe local checks. It is not demonstrated
to be Azure/GPU/workload ready. Local passes must not be used as production
certification. Prioritized work and completion criteria are in the
[backlog](backlog.md).

Licensed source, private inputs/results, ignored operator files, credentials,
remote Azure/GitHub configuration, and live clusters were not inspected.
No Azure authentication, deployment, build, source upload, cluster mutation,
GPU allocation, or numerical calculation was performed. This is a code and
operability review, not an exhaustive vulnerability audit.

## Architecture and ownership

- **Factory state:** private source storage/network, gallery definition,
  managed identity/RBAC, and AIB template. Terraform embeds repository-owned
  scripts, not licensed source.
- **Build result:** AIB's intermediate managed image is an external artifact;
  creating the template does not execute the build.
- **Publication state:** produces a numeric gallery version, excludes it from
  `latest`, and prevents accidental destruction.
- **Validation state:** optional one/two private GPU VMs; disabled by default.
  It does not deploy a scheduler or certify CycleCloud convergence.
- **CycleCloud:** remains existing infrastructure. The generator prepares
  fragments/project content; an approved operator imports them.
- **Slurm:** owns allocation and launch. Production examples use `srun` through
  the isolated Open MPI stack; no baked hostfiles or automatic `mpirun` fallback.

See [architecture](architecture.md) and the
[beginner tutorial](tutorial.md) for the workflow and approval boundaries.

## Coverage inventory

| Reviewed area | Implementation and assessment |
| --- | --- |
| Entry point and 14 existing guides | [README](../README.md), [docs](./), [source contract](../source/README.md): ownership, licensing, operations, rollback, and uncertified status already documented; beginner narrative and consolidated backlog were missing |
| Contributor/protection/lint configuration | [instructions](../.github/copilot-instructions.md), [ignore rules](../.gitignore), [ShellCheck config](../.shellcheckrc), [TFLint config](../.tflint.hcl), [Actionlint config](../.github/actionlint.yaml): appropriate source exclusions; ignore/path checks are not content scanning |
| Factory root | [main](../environments/dev/factory/main.tf), [variables](../environments/dev/factory/variables.tf), [versions](../environments/dev/factory/versions.tf), [example inputs](../environments/dev/factory/terraform.tfvars.example), [lock](../environments/dev/factory/.terraform.lock.hcl): source configuration and review-only cluster outputs; placeholders require operator replacement |
| Publication root | [configuration](../environments/dev/publication/main.tf), [lock](../environments/dev/publication/.terraform.lock.hcl): independent state, numeric versions, protected lifecycle, operational tags ignored by Terraform |
| Validation root | [configuration](../environments/dev/validation/main.tf), [lock](../environments/dev/validation/.terraform.lock.hcl): existing RG/subnet and public SSH key, opt-in private VMs |
| Infrastructure modules | [network](../modules/network/main.tf), [source staging](../modules/source-staging/main.tf), [gallery](../modules/compute-gallery/main.tf), [AIB](../modules/image-builder/main.tf), [validation](../modules/validation/main.tf): clear responsibilities; real provider/network/RBAC behavior still needs Azure acceptance |
| Source preparation | [prepare](../scripts/source/prepare.py), [tests](../scripts/source/test_prepare.py): deterministic packaging, exact manifest/checksum validation, regular-file-only extraction, layout and traversal checks |
| Build operations | [Azure operations](../scripts/build/manage.py), [Terraform wrapper](../scripts/build/terraform.sh), [integration generator](../scripts/build/cyclecloud-package.py): explicit approval markers and separate generation; Azure operations lack focused mocked tests |
| Image customization | [customize](../scripts/image/customize.sh), [inventory](../scripts/image/inventory.sh), [toolchain](../scripts/image/toolchain.sh), [compile](../scripts/image/compile.sh), [runtime installer](../scripts/image/install-runtime.sh), [cleanup](../scripts/image/cleanup.sh): checksum-protected download, isolated builds, protected diagnostics and pre-capture cleanup; only last VASP module is load-tested |
| Runtime and node checks | [job driver](../scripts/image/runtime.sh), [image health](../scripts/validation/image-health.sh), [GPU health](../scripts/validation/gpu-health.sh), [task wrapper](../scripts/validation/mpi-task.sh), [MPI payload](../scripts/validation/mpi-smoke.c), [Slurm validator](../scripts/validation/slurm-validate.sh): allocation-aware private TCP and CUDA-buffer checks, but incomplete per-node release/GRES assertions |
| Local validation | [runner](../scripts/validation/local-check.sh), [repository checks](../scripts/validation/repository-check.py), [runtime tests](../scripts/validation/test_runtime.py): 12 tests, shell syntax/directives, links, ignored/history paths, generation consistency, output/termination behavior |
| CycleCloud project/templates | [project](../cyclecloud/projects/vasp-image/project.ini), [first-boot gate](../cyclecloud/projects/vasp-image/specs/default/cluster-init/scripts/10-vasp-image-health.sh), [node arrays](../cyclecloud/templates/nodearrays.txt), [parameters](../cyclecloud/templates/parameters.txt): existing Slurm inheritance, no controller/secrets, H100 maximum zero; installed parser/convergence remains unverified |
| All six Slurm jobs | [health](../examples/slurm/gpu-health-check.sbatch), [TCP MPI](../examples/slurm/mpi-tcp-smoke-test.sbatch), [A100 single](../examples/slurm/vasp-a100-single-node.sbatch), [A100 multi](../examples/slurm/vasp-a100-multi-node.sbatch), [H100 single](../examples/slurm/vasp-h100-single-node.sbatch), [H100 multi](../examples/slurm/vasp-h100-multi-node.sbatch), [input/placement guide](../examples/slurm/README.md): conservative one GPU/rank per node, configurable partitions, private calculation outputs |
| All eight workflows | [CI](../.github/workflows/ci.yml), [source](../.github/workflows/source.yml), [factory](../.github/workflows/terraform-plan.yml), [image](../.github/workflows/image.yml), [integration](../.github/workflows/cyclecloud.yml), [standalone resources](../.github/workflows/validation-resources.yml), [Slurm](../.github/workflows/slurm-validation.yml), [promotion](../.github/workflows/promotion.yml): pinned actions, manual operational dispatches, OIDC, source isolation; external protection settings and timeout/output coordination remain operator responsibilities |

## Implemented strengths

1. Source preparation and upload are separate from Terraform; upload uses Entra
   login, while AIB downloads through its managed identity and verifies SHA-256.
2. Created staging disables public networking, shared keys, anonymous access,
   and trusted-service bypass. BYO storage is checked rather than silently changed.
3. CPU/A100/H100 builds are independent, versioned, and use one isolated MPI/
   ScaLAPACK stack. Microsoft GPU drivers are not automatically replaced.
4. The TCP wrapper discovers a route/interface on each allocated node, checks
   private forward/reverse resolution and approved CIDRs, and excludes unsuitable
   interfaces. The diagnostic verifies payloads, not just printed settings.
5. Source/build trees and known machine/cluster identities are removed before
   capture. Runtime checks correctly allow identities created at first boot.
6. Promotion requires a complete reviewed receipt for an exact version and
   only sets tags; production remains pinned to an explicitly imported version.

## Confirmed defects and operational gaps

| ID | Finding and impact | Evidence |
| --- | --- | --- |
| B01 | Relative `VASP_OUTPUT_DIR` is resolved for copy-back but the original relative string is used for redirection after `cd`. With a different input directory, the step fails before VASP runs. Empty-fixture reproduction exited 1 with `relative-output/stdout.log: No such file or directory`. Use absolute paths pending a fix. | [driver path setup/redirection](../scripts/image/runtime.sh#L59) |
| B02 | The wrapper passes `-input=false` for apply/destroy and only adds `-auto-approve` with `TF_APPROVED_APPLY=1`. Previous local examples omitted it, so ordinary unsaved-plan applies cannot ask for confirmation. Guides now document the explicit, command-scoped approval flag; wrapper behavior remains unchanged. | [wrapper](../scripts/build/terraform.sh#L25) |
| B03 | Image workflow timeout is 360 minutes, AIB timeout is 480 minutes, and CLI polling is nine hours. A valid long build can outlive the workflow; there is no automatic service cancellation. | [workflow](../.github/workflows/image.yml#L21), [AIB](../modules/image-builder/main.tf#L94), [polling](../scripts/build/manage.py#L94) |
| B04 | Expected gallery version is checked only in the initial one-node allocation. Later health/MPI jobs can use other nodes without checking that version, allowing mixed-image evidence. | [validator](../scripts/validation/slurm-validate.sh#L14), [health job](../examples/slurm/gpu-health-check.sbatch), [MPI job](../examples/slurm/mpi-tcp-smoke-test.sbatch) |
| B05 | Validation always requests one GPU but compares visibility to a supplied physical GPU count. Larger SKUs/cgroup isolation need all-GPU allocations and separate GRES assertions. Node/GRES output is printed, not fully validated automatically. | [allocation/count](../scripts/validation/slurm-validate.sh#L14), [GPU count](../scripts/validation/gpu-health.sh#L20) |
| B06 | Terraform allows other VASP 6 versions, but the Slurm workflow does not export `VASP_VERSION`; example jobs default to `6.4.3`. Nondefault releases require explicit local exports and are not correctly selected by that workflow's declared environment. | [version input](../environments/dev/factory/variables.tf#L141), [workflow environment](../.github/workflows/slurm-validation.yml#L22), [module selection](../examples/slurm/gpu-health-check.sbatch#L13) |
| B07 | Runtime installation creates every selected VASP module but load-tests only the last loop suffix. Image health checks binaries using the MPI module, not each VASP module. A broken earlier profile module can escape build checks. | [module installation/load check](../scripts/image/install-runtime.sh#L38), [image health](../scripts/validation/image-health.sh#L9) |
| B08 | Factory/image workflows consume runner-local paths but do not export/refresh the pipeline JSON after factory apply or the publication result after publication. Operators must explicitly hand off matching outputs. | [factory workflow](../.github/workflows/terraform-plan.yml#L38), [image workflow](../.github/workflows/image.yml#L40) |

These findings are classified and expanded in [backlog](backlog.md).
Documentation mitigations do not resolve the code defects.

## Unverified assumptions and improvement areas

- Marketplace image availability, current driver compatibility, package/SDK
  repository availability, template support, and every requested profile build.
- Real AIB private-network proxy behavior, RBAC propagation, CMK/BYO policies,
  gallery replication, and image deprovisioning/first boot.
- Installed CycleCloud parser/import schema, project inheritance, GRES/cgroups,
  scheduler discovery, shared filesystem semantics, scale-down, and reimage.
- Real Slurm PMI2/Open MPI interoperability, every allocated node's image, CPU/
  GPU placement, cross-node TCP connection evidence, and licensed numerics.
- GitHub environments, OIDC federation, runner-group restrictions, and approved
  plan/apply coordination. YAML alone cannot establish these controls.
- Targeted residual/path scans are not comprehensive content/secret scans.
  Promotion receipt flags are assertions, not authenticated test provenance.
- Toolchain pins and action/provider locks need a maintained compatibility and
  supply-chain review; no current vulnerability suitability claim is made here.

## Validation evidence

Executed the existing
[local-check runner](../scripts/validation/local-check.sh):

```bash
bash scripts/validation/local-check.sh
```

| Check | Result |
| --- | --- |
| Source preparation tests | 4/4 passed with empty structural fixtures |
| Repository tests | 4/4 passed: ignored/history paths, documentation links, shell syntax/directives, CycleCloud generation references |
| Mocked runtime tests | 4/4 passed: exit propagation/output copy, shared-scratch guard, missing PMI2 rejection, TERM recovery |
| Terraform format | Passed |
| Factory/publication/validation `init -backend=false` and `validate` | All passed; no live backend or resources used |
| ShellCheck | Passed for all repository shell/job scripts |
| Relative output regression probe | Reproduced B01 using existing mock setup and empty inputs; absolute-path baseline tests passed |
| TFLint, Trivy, Actionlint | Not run in this review; CI configures TFLint and Trivy, not Actionlint |
| Azure, GPUs, live Slurm, licensed VASP | Not run |

The first local-check attempt stopped because ShellCheck was missing. A
session-local ShellCheck 0.11.0 was obtained and the complete runner then passed;
no system-wide dependency was installed. Terraform was 1.17.1.
After documentation edits, the existing repository checks were rerun.
Local link/heading/line anchors were checked across all 20 documentation files,
and all 53 Bash example blocks passed syntax checks without execution.

## Documentation changes from this review

- Added the [tutorial](tutorial.md), this review, and the [backlog](backlog.md).
- Linked learning, operational, reference, and explanation material from the
  [README](../README.md).
- Corrected local approval commands and timeout descriptions; documented
  absolute-path requirements, validation limits, and compute-shell setup.

Operational guides remain the task-specific authority. The tutorial supplies
learning context without replacing site approval, production readiness tests,
or the existing rollback/cleanup procedures.
