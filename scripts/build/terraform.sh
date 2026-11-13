#!/bin/bash
set -euo pipefail
state=${1:?factory, publication, or validation required}
action=${2:?plan, apply, output, or destroy required}
[[ $state =~ ^(factory|publication|validation)$ && $action =~ ^(plan|apply|output|destroy)$ ]] || exit 2
[[ $action != destroy || $state == validation ]] || {
    echo "Automatic destroy is limited to temporary validation resources." >&2; exit 1;
}
: "${TF_BACKEND_ACCOUNT:?}" "${TF_BACKEND_CONTAINER:?}" "${TF_BACKEND_RESOURCE_GROUP:?}"
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
directory="$root/environments/dev/$state"
key=${TF_BACKEND_KEY:-vasp/$state.tfstate}
[[ $key =~ ^[a-zA-Z0-9_./-]+$ && $key != *..* ]] || {
    echo "Backend key must be a safe opaque state path." >&2; exit 2;
}
terraform -chdir="$directory" init -input=false -reconfigure \
    -backend-config="storage_account_name=$TF_BACKEND_ACCOUNT" \
    -backend-config="container_name=$TF_BACKEND_CONTAINER" \
    -backend-config="resource_group_name=$TF_BACKEND_RESOURCE_GROUP" \
    -backend-config="key=$key" -backend-config="use_azuread_auth=true" >&2
shift 2
if [[ $action == output ]]; then
    terraform -chdir="$directory" output -json
else
    if [[ ${TF_APPROVED_APPLY:-0} == 1 && $action != plan ]]; then
        set -- -auto-approve "$@"
    fi
    terraform -chdir="$directory" "$action" -input=false "$@"
fi
