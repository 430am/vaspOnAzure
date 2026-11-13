# Private Ethernet TCP MPI

## Preconditions and network scope

Treat NC A100/H100 as Ethernet targets unless Azure SKU metadata and configured
interfaces prove otherwise. No RDMA/GPUDirect RDMA is claimed.
The compute subnet NSG/site firewall must permit the configured TCP interval
**only between approved compute peers** and permit existing Slurm/DNS/storage
traffic. This repository does not overwrite the existing subnet NSG.

Defaults: `mpi_tcp_port_min=20000`, `mpi_tcp_port_count=1024` -> 20000–21023.
Port count must support concurrent ranks/jobs; assess conflicts and increase
through reviewed factory inputs. Open MPI BTL and diagnostic OOB ports use this
interval. Slurm controller/PMI traffic retains its site-owned ports.

With explicit approval from the owner of the existing compute NSG, an example
scoped rule is:

```bash
az network nsg rule create --resource-group YOUR_NETWORK_RG --nsg-name YOUR_COMPUTE_NSG \
  --name vasp-mpi-tcp --priority 410 --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes YOUR_COMPUTE_SUBNET_CIDR --source-port-ranges '*' \
  --destination-address-prefixes YOUR_COMPUTE_SUBNET_CIDR --destination-port-ranges 20000-21023
```

Review priority/conflicts and the configured interval first. This is a manual
site-network change, not an automatic Terraform cluster modification. Do not
substitute Internet or `*` as the source network.

The `mpi/openmpi-tcp` module selects OB1 and `self,smcuda,tcp`; UCX/openib are
not used. NCCL IB is disabled; NCCL sockets use the selected interface.
VASP's NCCL feature is disabled in this strict-port build. Merely setting
`NCCL_SOCKET_IFNAME` does not confine NCCL's separate bootstrap ports; a future
NCCL-enabled build needs its own reviewed network policy.
Shared memory/CUDA IPC remain eligible within one VM; TCP stages CUDA buffers
through host memory across VMs. No cross-node GPU-direct claim is made.

## Interface selection and DNS

`mpi-task.sh` executes independently on each allocated node. It resolves a peer
from `SLURM_JOB_NODELIST`, checks private forward/reverse IPv4 consistency, and
uses the route to that peer to discover the compute interface. Single-node
loopback routes use the primary default route. Loopback, IB, Docker, CNI, veth,
bridge/tunnel interfaces are excluded. No interface name is baked in.

Multi-homed sites must supply approved `MPI_TCP_INTERFACE` if routing alone
would select a management interface. It must have a private IPv4 address.
Site firewall rules and subnet routing—not an interface label alone—prove
that MPI stays in the approved compute network.
Set `MPI_TCP_ALLOWED_CIDRS` (comma-separated IPv4 CIDRs) through site first-boot
environment configuration or job submission. Both local interface and peer
addresses must be within this approved scope. This rejects a management-only
route even when it has a private IP. Cluster-specific CIDRs are not baked in.

## Validate actual communication

```bash
export MPI_TCP_ALLOWED_CIDRS='YOUR_COMPUTE_SUBNET_CIDR'
sbatch --wait --partition=YOUR_A100_PARTITION examples/slurm/mpi-tcp-smoke-test.sbatch
```

For H100 export `VASP_GPU_GENERATION=h100` and override the partition.
The test requires two nodes, checks processor-name diversity, host-buffer
collectives, GPU-buffer neighbor transfers, checksums and CUDA runtime/driver
compatibility. Verbose Open MPI logs show actual TCP connection establishment.
Review source/destination private IPs and selected interfaces, not just MCA
settings. Capture additional `ss -tnp`/network traces on allocated peers when
site policy permits, storing only non-sensitive transport evidence.

All environment is exported through `srun --export=ALL`. No hostfiles are baked
in and no `mpirun` escapes a Slurm allocation.

Success criteria: every rank verifies payloads; ranks span at least two nodes;
actual connection logs match private interface addresses; no openib/UCX/verbs
selection; Slurm exit status zero. A transport-setting printout alone is not
accepted as TCP proof in a promotion receipt.

Failure: inspect DNS, allowed port interval, Slurm PMI2, module/MPI prefix and
CUDA visibility. Do not disable firewall protections as a workaround.
Rollback the module/image through [rollback](rollback.md); release test jobs
and inspect scale-down using [cleanup](cleanup.md).
