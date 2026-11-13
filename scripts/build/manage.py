#!/usr/bin/env python3
"""Explicit Azure operations; no source transfer occurs during Terraform plan."""

import argparse
import hashlib
import ipaddress
import json
from pathlib import Path
import re
import socket
import subprocess
import sys
import time


def az(*arguments: str):
    result = subprocess.run(
        ["az", *arguments, "--only-show-errors", "--output", "json"],
        check=True, capture_output=True, text=True
    )
    return json.loads(result.stdout) if result.stdout.strip() else None


def load_pipeline(path: Path) -> dict:
    data = json.loads(path.read_text())
    return data["pipeline"]["value"] if "pipeline" in data else data


def storage_check(config: dict) -> None:
    account = config["vasp_source_storage_account_name"]
    if not re.fullmatch(r"[a-z0-9]{3,24}", account):
        raise ValueError("Storage account name must be lowercase Azure syntax.")
    info = az("storage", "account", "show", "--name", account)
    if (
        info["allowBlobPublicAccess"] is not False
        or info["allowSharedKeyAccess"] is not False
        or info["publicNetworkAccess"] != "Disabled"
        or info["networkRuleSet"]["defaultAction"] != "Deny"
        or info["networkRuleSet"].get("bypass") != "None"
    ):
        raise ValueError("Source account must disable public access/shared keys and deny public networking.")
    addresses = socket.getaddrinfo(f"{account}.blob.core.windows.net", 443)
    approved = [ipaddress.ip_network(n) for n in ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16")]
    if not addresses or not all(any(ipaddress.ip_address(a[4][0]) in n for n in approved) for a in addresses):
        raise ValueError("Storage DNS must resolve exclusively to approved private IPv4 endpoints.")
    if not re.fullmatch(r"[a-z0-9-]{3,63}", config["vasp_source_container_name"]):
        raise ValueError("Invalid source container name.")
    if not re.fullmatch(r"[A-Za-z0-9._/-]+", config["vasp_source_blob_name"]):
        raise ValueError("Blob names cannot contain credentials or query parameters.")
    container = az(
        "storage", "container", "show", "--auth-mode", "login",
        "--account-name", account, "--name", config["vasp_source_container_name"]
    )
    if container["properties"].get("publicAccess") not in (None, "None"):
        raise ValueError("Source container is not private.")


def blob_args(config: dict) -> list[str]:
    return [
        "--auth-mode", "login", "--account-name", config["vasp_source_storage_account_name"],
        "--container-name", config["vasp_source_container_name"],
        "--name", config["vasp_source_blob_name"]
    ]


def upload(pipeline: dict, archive: Path) -> None:
    config = pipeline["source_configuration"]
    storage_check(config)
    checksum = hashlib.sha256()
    with archive.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            checksum.update(chunk)
    actual = checksum.hexdigest()
    if actual != config["vasp_source_checksum"]:
        raise ValueError("Local archive checksum differs from the configured AIB checksum.")
    az("storage", "blob", "upload", *blob_args(config), "--file", str(archive),
       "--overwrite", "false", "--metadata", "sha256=" + actual)
    print("Authorized archive uploaded without anonymous access or SAS.")


def build(pipeline: dict) -> None:
    config = pipeline["source_configuration"]
    storage_check(config)
    blob = az("storage", "blob", "show", *blob_args(config))
    if blob.get("metadata", {}).get("sha256") != config["vasp_source_checksum"]:
        raise ValueError("Staged archive metadata does not match the approved checksum.")
    template = pipeline["template_id"]
    image_id = pipeline["managed_image_id"]
    existing = az("image", "list", "--resource-group", image_id.split("/")[4])
    if any(image["id"].lower() == image_id.lower() for image in existing):
        raise ValueError("An immutable candidate image already exists; use a new pipeline name for another build.")
    az("resource", "invoke-action", "--ids", template, "--action", "Run",
       "--api-version", "2024-02-01", "--no-wait")
    deadline = time.monotonic() + 9 * 3600
    while time.monotonic() < deadline:
        properties = az("resource", "show", "--ids", template, "--api-version", "2024-02-01")["properties"]
        status = properties.get("lastRunStatus", {})
        state = status.get("runState", "")
        if state == "Succeeded":
            image = az("image", "show", "--ids", pipeline["managed_image_id"])
            if image.get("provisioningState") != "Succeeded":
                raise ValueError("AIB reported success but candidate image is not ready.")
            print("Candidate managed image built; publish it in the separate publication state.")
            return
        if state in {"Failed", "Canceled", "PartiallySucceeded"}:
            raise ValueError("AIB failed. Review restricted service logs; do not publish.")
        time.sleep(30)
    raise TimeoutError("AIB timed out; inspect/cancel the running build before retrying.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["upload", "build", "source-cleanup", "promote"])
    parser.add_argument("--pipeline", type=Path, default=Path("generated/pipeline.json"))
    parser.add_argument("--archive", type=Path)
    parser.add_argument("--image-version-id")
    parser.add_argument("--validation-receipt", type=Path)
    parser.add_argument("--approve", action="store_true", required=True)
    args = parser.parse_args()
    if args.command == "promote":
        if args.validation_receipt is None or args.image_version_id is None:
            parser.error("promote requires an immutable --image-version-id and --validation-receipt")
        if not re.fullmatch(
            r"/subscriptions/[a-fA-F0-9-]+/resourceGroups/[\w.-]+/providers/Microsoft\.Compute/"
            r"galleries/[\w.-]+/images/[\w.-]+/versions/\d+\.\d+\.\d+", args.image_version_id
        ):
            raise ValueError("Promotion requires an immutable gallery image version ID without credentials or queries.")
        receipt = json.loads(args.validation_receipt.read_text())
        if (
            receipt.get("image_version_id") != args.image_version_id
            or receipt.get("passed") is not True
            or not all(receipt.get("checks", {}).get(k) is True for k in
                       ("image", "cyclecloud", "slurm", "gpu", "tcp", "vasp"))
            or receipt.get("approved_by_operator") is not True
        ):
            raise ValueError("Promotion requires an operator-reviewed, complete validation receipt for this version.")
        az("resource", "update", "--ids", args.image_version_id, "--api-version", "2023-07-03",
           "--set", "tags.status=promoted", "tags.validation=passed")
        print("Version marked promoted. Production node arrays still require an approved pinned-version update.")
        return
    pipeline = load_pipeline(args.pipeline)
    if args.command == "upload":
        name = pipeline["source_configuration"]["vasp_source_archive_name"]
        if not re.fullmatch(r"[A-Za-z0-9_-][A-Za-z0-9._-]+", name) or ".." in name:
            raise ValueError("Archive name must be a safe filename, not a path.")
        upload(pipeline, args.archive or Path("staging") / name)
    elif args.command == "build":
        build(pipeline)
    else:
        config = pipeline["source_configuration"]
        if config["vasp_source_retention_mode"] not in {"delete", "retain"}:
            raise ValueError("Unsupported source retention mode; cleanup refused.")
        if config["vasp_source_retention_mode"] == "retain":
            print("Explicit retention selected; archive not deleted. Operator owns expiry and access review.")
            return
        storage_check(config)
        az("storage", "blob", "delete", *blob_args(config), "--delete-snapshots", "include")
        if az("storage", "blob", "exists", *blob_args(config))["exists"]:
            raise ValueError("Staged source remains after cleanup.")
        print("Staging blob and visible snapshots deleted; review account retention policies separately.")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError:
        print("Azure operation failed. Check permissions, private connectivity, and restricted Azure logs.", file=sys.stderr)
        sys.exit(1)
    except (OSError, ValueError, KeyError, TimeoutError) as error:
        print(f"Operation failed: {error}", file=sys.stderr)
        sys.exit(1)
