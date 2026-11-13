#!/bin/bash
set -euo pipefail
generation=
if [[ ${1:-} == --generation ]]; then
    generation=${2:?GPU generation required}
    shift 2
fi
[[ -n ${SLURM_JOB_ID:-} ]] || { echo "Task must execute in a Slurm allocation." >&2; exit 1; }
[[ ${OMPI_MCA_pml:-} == ob1 && ${OMPI_MCA_btl:-} == self,smcuda,tcp ]] || {
    echo "Load the verified TCP MPI module." >&2; exit 1;
}
mapfile -t hosts < <(scontrol show hostnames "${SLURM_JOB_NODELIST:?}")
[[ ${#hosts[@]} -gt 0 ]] || { echo "Empty Slurm allocation." >&2; exit 1; }
peer=${VASP_MPI_PEER:-${hosts[0]}}
for host in "${hosts[@]}"; do
    if [[ $host != "$(hostname -s)" && $host != "$(hostname)" ]]; then peer=$host; break; fi
done
peer_ip=$(getent ahostsv4 "$peer" | awk 'NR==1 {print $1}')
[[ -n $peer_ip ]] || { echo "Allocated peer has no forward IPv4 DNS." >&2; exit 1; }
private_ipv4() {
    local ip=$1
    [[ $ip =~ ^10\. || $ip =~ ^192\.168\. || $ip =~ ^172\.(1[6-9]|2[0-9]|3[01])\. ]]
}
private_ipv4 "$peer_ip" || { echo "Allocated peer must resolve to private IPv4." >&2; exit 1; }
reverse_name=$(getent hosts "$peer_ip" | awk 'NR==1 {print $2}')
[[ -n $reverse_name ]] || { echo "Allocated peer has no reverse resolution." >&2; exit 1; }
forward_again=$(getent ahostsv4 "$reverse_name")
[[ $forward_again == *"$peer_ip"* ]] || { echo "Forward/reverse resolution is inconsistent." >&2; exit 1; }
route=$(ip -4 route get "$peer_ip")
interface=${MPI_TCP_INTERFACE:-$(awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' <<< "$route")}
# A route to self uses lo; single-node jobs use the primary default compute route.
if [[ $interface == lo && ${#hosts[@]} == 1 ]]; then
    route=$(ip -4 route get 1.1.1.1)
    interface=$(awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' <<< "$route")
fi
[[ -n $interface && -d /sys/class/net/$interface &&
   ! $interface =~ ^(lo|docker|cni|veth|br-|ib|virbr|tun|tailscale) ]] || {
    echo "No eligible compute Ethernet interface; supply approved MPI_TCP_INTERFACE." >&2; exit 1;
}
local_ip=$(ip -4 -o address show dev "$interface" scope global | awk 'NR==1 {split($4,a,"/"); print a[1]}')
private_ipv4 "$local_ip" || { echo "MPI interface must have a private IPv4 address." >&2; exit 1; }
: "${MPI_TCP_ALLOWED_CIDRS:?Supply the approved compute network CIDRs at job submission or cluster first boot}"
python3 - "$local_ip" "$peer_ip" "$MPI_TCP_ALLOWED_CIDRS" <<'PY'
import ipaddress
import sys
networks = [ipaddress.ip_network(n.strip()) for n in sys.argv[3].split(",")]
if not networks or not all(any(ipaddress.ip_address(a) in n for n in networks) for a in sys.argv[1:3]):
    sys.exit("MPI route/interface is outside the approved compute networks.")
PY
port_min=${MPI_TCP_PORT_MIN:?}
port_count=${MPI_TCP_PORT_COUNT:?}
[[ $port_min =~ ^[0-9]+$ && $port_count =~ ^[0-9]+$ ]] || exit 2
(( port_min >= 1024 && port_count > 0 && port_min + port_count - 1 <= 65535 )) || exit 2
export OMPI_MCA_btl_tcp_if_include="$interface"
export OMPI_MCA_oob_tcp_if_include="$interface"
export OMPI_MCA_btl_tcp_port_min_v4="$port_min"
export OMPI_MCA_btl_tcp_port_range_v4="$port_count"
export OMPI_MCA_pmix=s2
export OMPI_MCA_oob_tcp_dynamic_ipv4_ports="$port_min-$((port_min + port_count - 1))"
export NCCL_SOCKET_IFNAME="=$interface" NCCL_IB_DISABLE=1
if [[ -n $generation ]]; then
    /opt/vasp-image/bin/gpu-health.sh "$generation"
fi
printf 'task=%s host=%s interface=%s address=%s transport=ob1/self,smcuda,tcp cuda_visible=%s\n' \
    "${SLURM_PROCID:-0}" "$(hostname)" "$interface" "$local_ip" "${CUDA_VISIBLE_DEVICES:-unset}"
printf 'cpu_allowed=%s\n' "$(awk '/^Cpus_allowed_list:/ {print $2}' /proc/self/status)"
exec "${@:?Task executable required}"
