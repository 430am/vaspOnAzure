#!/bin/bash
set -euo pipefail
umask 077
pipeline=/var/tmp/vasp-image-pipeline
work=/var/tmp/vasp-protected-build
[[ $EUID == 0 ]] || { echo "Image customization requires root." >&2; exit 1; }
[[ ! -e $work ]] || { echo "Protected build directory already exists." >&2; exit 1; }
install -d -m 700 "$work"
cleanup() {
    # Exact, pipeline-owned directories only. Never remove operator input paths.
    rm -rf -- /var/tmp/vasp-protected-build
}
trap cleanup EXIT
cloud-init status --wait
bash "$pipeline/inventory.sh" before
apt-get update -qq
apt-get install -y --no-install-recommends jq curl ca-certificates gnupg python3 \
    build-essential cmake libfftw3-dev libblas-dev liblapack-dev libpmi2-0-dev \
    environment-modules nfs-common rsync pciutils
config=$pipeline/config.json
account=$(jq -r .vasp_source_storage_account_name "$config")
container=$(jq -r .vasp_source_container_name "$config")
blob=$(jq -r .vasp_source_blob_name "$config")
client=$(jq -r .identity_client_id "$config")
checksum=$(jq -r .vasp_source_checksum "$config")
[[ $account =~ ^[a-z0-9]{3,24}$ && $container =~ ^[a-z0-9-]{3,63}$ &&
   $blob =~ ^[a-zA-Z0-9._/-]+$ && $checksum =~ ^[a-f0-9]{64}$ ]] || {
    echo "Invalid source configuration." >&2; exit 1;
}
# Fetch on the build VM over its private endpoint, not through the AIB control plane.
token=$(curl --fail --silent --show-error --noproxy '*' -H Metadata:true \
    "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fstorage.azure.com%2F&client_id=$client" |
    jq -er .access_token)
printf 'header = "Authorization: Bearer %s"\n' "$token" > "$work/curl-auth"
unset token
# Keep authorization out of process arguments, logs, and Terraform state.
curl --fail --silent --show-error --config "$work/curl-auth" \
    -H 'x-ms-version: 2021-12-02' \
    "https://$account.blob.core.windows.net/$container/$blob" -o "$work/source.tar.gz"
rm -- "$work/curl-auth"
python3 "$pipeline/prepare.py" extract --output "$work/source.tar.gz" \
    --expected-checksum "$checksum" --destination "$work/input"
bash "$pipeline/toolchain.sh"
bash "$pipeline/compile.sh"
bash "$pipeline/install-runtime.sh"
bash "$pipeline/inventory.sh" after
cleanup
trap - EXIT
# Remove the source downloader and build configuration before the final scan.
rm -f -- "$pipeline/prepare.py" "$pipeline/config.json"
bash "$pipeline/cleanup.sh"
