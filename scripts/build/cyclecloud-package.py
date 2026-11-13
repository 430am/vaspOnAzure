#!/usr/bin/env python3
"""Generate a review-only integration package; never contact or mutate CycleCloud."""

import argparse
import json
from pathlib import Path
import re
import shutil
import sys


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pipeline", type=Path, default=Path("generated/pipeline.json"))
    parser.add_argument("--image-version-id", required=True)
    parser.add_argument("--output", type=Path, default=Path("generated/cyclecloud"))
    args = parser.parse_args()
    data = json.loads(args.pipeline.read_text())
    pipeline = data["pipeline"]["value"] if "pipeline" in data else data
    config = pipeline["cyclecloud"]
    if not config["enabled"] or config["update_mode"] != "plan-only":
        raise ValueError("Enable plan-only CycleCloud integration before package generation.")
    version_id = args.image_version_id
    if not re.fullmatch(
        r"/subscriptions/[a-fA-F0-9-]+/resourceGroups/[\w.-]+/providers/Microsoft\.Compute/"
        r"galleries/[\w.-]+/images/[\w.-]+/versions/\d+\.\d+\.\d+", version_id
    ):
        raise ValueError("Supply an immutable Azure Compute Gallery version ID.")
    if not version_id.startswith(pipeline["image_definition_id"] + "/versions/"):
        raise ValueError("Version must belong to the configured image definition.")
    if version_id.rsplit("/", 1)[1] != config["image_version"]:
        raise ValueError("Pinned CycleCloud version does not match the supplied gallery version.")
    for name in ("cluster_name", "project_name", "nodearray_a100", "nodearray_h100",
                 "partition_a100", "partition_h100", "region"):
        if not re.fullmatch(r"[A-Za-z0-9_-]+", config[name]):
            raise ValueError("CycleCloud names must be explicitly supplied safe identifiers.")
    if not config["compute_subnet_id"] or not re.fullmatch(r"/[A-Za-z0-9_./-]+", config["compute_subnet_id"]):
        raise ValueError("Supply an existing compute subnet resource ID.")
    root = Path(__file__).resolve().parents[2]
    args.output.mkdir(parents=True, exist_ok=False)
    shutil.copytree(root / "cyclecloud/projects/vasp-image", args.output / config["project_name"])
    project = args.output / config["project_name"] / "project.ini"
    project.write_text(project.read_text().replace("name = vasp-image", "name = " + config["project_name"]))
    fragment = (root / "cyclecloud/templates/nodearrays.txt").read_text()
    fragment = fragment.replace("cluster-init vasp-image:", f"cluster-init {config['project_name']}:")
    values = {
        "NodeArrayA100": config["nodearray_a100"], "NodeArrayH100": config["nodearray_h100"],
        "SlurmPartitionA100": config["partition_a100"], "SlurmPartitionH100": config["partition_h100"],
        "VaspGalleryImageId": version_id, "VaspRegion": config["region"],
        "VaspComputeSubnetId": config["compute_subnet_id"],
        "A100MachineType": "Standard_NC24ads_A100_v4",
        "H100MachineType": "Standard_NC40ads_H100_v5",
        "VaspA100MaxCount": "2", "VaspH100MaxCount": "0"
    }
    # Resolve immutable identifiers; retain machine/count parameters for site customization.
    for key in ("NodeArrayA100", "NodeArrayH100"):
        fragment = fragment.replace("$" + key, values[key])
    (args.output / "nodearrays.txt").write_text(fragment)
    shutil.copy(root / "cyclecloud/templates/parameters.txt", args.output / "parameters.txt")
    (args.output / "parameters.json").write_text(json.dumps(values, indent=2))
    parts = version_id.split("/")
    (args.output / "image-reference.json").write_text(json.dumps({
        "subscription": parts[2], "resource_group": parts[4], "gallery": parts[8],
        "image_definition": parts[10], "image_version": parts[12],
        "image_version_id": version_id, "region": config["region"],
        "cluster_name": config["cluster_name"], "update_mode": "plan-only"
    }, indent=2))
    print("Integration package generated for review. No existing cluster was modified.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError) as error:
        print(f"Integration generation failed: {error}", file=sys.stderr)
        sys.exit(1)
