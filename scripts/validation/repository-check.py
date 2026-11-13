#!/usr/bin/env python3
"""Check references and Git protection without reading proprietary files."""

import json
from pathlib import Path
import re
import subprocess
import sys
import unittest
import importlib.util
import tempfile

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("prepare", ROOT / "scripts/source/prepare.py")
assert spec is not None and spec.loader is not None
prepare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare)


def git(*args: str) -> str:
    return subprocess.run(["git", *args], cwd=ROOT, check=True, capture_output=True, text=True).stdout


def protected(name: str) -> bool:
    path = Path(name)
    return (
        (name.startswith("source/") and name != "source/README.md")
        or name.startswith(("staging/", "private/", "generated/"))
        or prepare.forbidden(Path(path.name))
        or bool(re.search(r"(?i)(^|/)vasp[._-]?\d[^/]*(/|$)", name))
    )


class RepositoryChecks(unittest.TestCase):
    def test_git_ignores_and_history(self):
        for path in ("source/vasp/src/main.F", "source/vasp.tgz", "private/manifest.json",
                     "staging/vasp-source.tar.gz", "elsewhere/POTCAR", "elsewhere/vasp_std"):
            self.assertEqual(subprocess.run(
                ["git", "check-ignore", "-q", path], cwd=ROOT
            ).returncode, 0, path)
        self.assertFalse(protected("source/README.md"))
        self.assertFalse(protected("scripts/build/manage.py"))
        self.assertEqual([n for n in git("ls-files").splitlines() if protected(n)], [])
        if git("rev-list", "--all").strip():
            names = git("log", "--all", "--format=", "--name-only").splitlines()
            self.assertEqual([n for n in names if n and protected(n)], [])

    def test_documentation_links(self):
        for path in [ROOT / "README.md", *sorted((ROOT / "docs").glob("*.md")),
                     ROOT / "source/README.md", ROOT / "examples/slurm/README.md"]:
            self.assertTrue(path.exists(), str(path))
            for target in re.findall(r"\]\(([^)]+)\)", path.read_text()):
                if target.startswith(("https:", "http:", "#")):
                    continue
                self.assertTrue((path.parent / target.split("#")[0]).exists(), f"{path.name}: {target}")

    def test_shell_and_directives(self):
        for pattern in ("scripts/**/*.sh", "cyclecloud/**/*.sh", "examples/slurm/*.sbatch"):
            for path in ROOT.glob(pattern):
                subprocess.run(["bash", "-n", str(path)], check=True)
                if path.suffix == ".sbatch":
                    text = path.read_text()
                    self.assertTrue(text.startswith("#!/bin/bash\n"))
                    self.assertIn("#SBATCH --partition=", text)
                    self.assertIn("#SBATCH --gres=gpu:", text)
                    self.assertNotIn("mpirun ", text)

    def test_cyclecloud_generation_references(self):
        pipeline = {
            "image_definition_id": "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Compute/galleries/g/images/i",
            "cyclecloud": {
                "enabled": True, "update_mode": "plan-only", "cluster_name": "existing",
                "project_name": "vasp-image", "nodearray_a100": "a100", "nodearray_h100": "h100",
                "partition_a100": "a100", "partition_h100": "h100", "region": "centralus",
                "compute_subnet_id": "/subscriptions/test/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/v/subnets/s",
                "image_version": "1.0.0"
            }
        }
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            config = directory / "pipeline.json"
            config.write_text(json.dumps(pipeline))
            subprocess.run([
                sys.executable, str(ROOT / "scripts/build/cyclecloud-package.py"),
                "--pipeline", str(config), "--image-version-id",
                pipeline["image_definition_id"] + "/versions/1.0.0",
                "--output", str(directory / "package")
            ], check=True)
            fragment = (directory / "package/nodearrays.txt").read_text()
            parameters = json.loads((directory / "package/parameters.json").read_text())
            for variable in re.findall(r"\$([A-Za-z0-9_]+)", fragment):
                self.assertIn(variable, parameters)
            self.assertIn("[[nodearray a100]]", fragment)
            self.assertIn("slurm.partition = $SlurmPartitionA100", fragment)
            self.assertTrue((directory / "package/vasp-image/project.ini").exists())


if __name__ == "__main__":
    unittest.main()
