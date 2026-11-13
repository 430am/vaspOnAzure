# Architecture and state boundaries

## Preconditions and ownership

Existing CycleCloud, scheduler, compute networking, private DNS and storage are
operator-owned. Terraform requires resource deployment and RBAC role-assignment
permissions in the factory scopes. It never imports an existing cluster.

```text
approved local source -> private Blob endpoint <- AIB VM managed identity
                                                 |
Ubuntu HPC latest -> CPU build VM -> clean generalized managed image
                                                 |
publication state -> immutable private gallery version (candidate)
                                                 |
review-only package -> existing CycleCloud -> Slurm GPU nodes
                                                 |
GPU + TCP + licensed tests -> reviewed receipt -> promotion tags
```

States use distinct backend keys: `vasp/factory.tfstate`,
`vasp/publication.tfstate`, `vasp/validation.tfstate`. Use a separate backend
container/account for each if policy requires stronger separation. AIB's
intermediate managed image is an explicit external build result, not a
Terraform-owned resource. Terraform owns its template, not repeated run state.
Gallery publication uses that result in its own state. Never run a second AIB
build over the same published candidate: use a new factory `name` and state key
or a separate environment for each build pipeline.

CycleCloud integration is **generation only**: no fourth mutable cluster state
is needed. If later authorized to manage cluster APIs, implement a separate
state and explicit ownership contract; this repository refuses automatic apply.
No secondary controller or CycleCloud installation exists.
`TF_BACKEND_KEY` provides an explicit per-command override for release/environment
state separation. Keep publication keys version-specific and preserve old states.

## Network

BYO build subnet must be in the AIB region, have private-link-service network
policies disabled, permit AzureLoadBalancer TCP 60001 to AIB's proxy, and allow
the proxy to SSH to its build VM. Build VM egress needs Ubuntu/NVIDIA package
repositories, public open-source release archives, and Azure service endpoints.
The source archive uses private Blob DNS and managed-identity RBAC.

If no subnet is supplied, the network module creates an isolated VNet with
separate build/endpoint subnets and a NAT gateway. Its public IP is **outbound
only**, not attached to build/validation VMs. A trusted runner still needs
peering/VPN and the private DNS link/forwarding. Review non-overlapping prefixes
before apply. Existing subnet/NSG/DNS settings are not modified automatically.

The account denies public networking, anonymous blobs and shared-key access.
Terraform uses storage management resources without carrying source content.
For BYO storage, security policy is checked by the explicit uploader; existing
retention/soft-delete/CMK policy remains the operator's responsibility.

## Build and first boot

Inventory is captured before and after customization. Only missing OS packages
and the selected missing SDK are installed. The isolated MPI and ScaLAPACK are
built deliberately even if incompatible base equivalents exist. Driver changes,
UCX tuning, Slurm installation, and cluster secrets are omitted.

Pre-capture scans reject licensed input/build remnants and machine secrets.
Cloud-init and waagent deprovisioning preserve first-boot convergence.
Runtime validation must allow the keys/configuration legitimately supplied at
first boot; absence checks for cluster identities apply **before capture**.

## Failure and rollback

Unsuccessful customization must not publish. AIB service logs and partial disks
are restricted because failures can retain licensed material. Inspect the
service-owned staging resource group and remove only explicitly identified
resources after canceling the build. Restore the previous pinned gallery version
as described in [rollback](rollback.md). See [cleanup](cleanup.md).
