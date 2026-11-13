"""Focused launch-driver tests using empty input fixtures and mocked Slurm."""

import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]


class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.base = Path(self.temporary.name)
        self.input = self.base / "input"
        self.input.mkdir()
        for name in ("INCAR", "POSCAR", "KPOINTS", "POTCAR"):
            (self.input / name).touch()  # Empty input-presence fixtures, no licensed data.
        self.bin = self.base / "mock/bin"
        self.bin.mkdir(parents=True)
        commands = {
            "mpirun": "#!/bin/bash\necho test-MPI\n",
            "ompi_info": "#!/bin/bash\necho mca:ess:pmi:version:test\necho mca:pmix:s2:version:test\n",
            "scontrol": "#!/bin/bash\necho test-node\n",
            "srun": """#!/usr/bin/python3
import os
from pathlib import Path
import sys
import time
if "--mpi=list" in sys.argv:
    print("pmi2")
elif "--version" in sys.argv:
    print("test-Slurm")
else:
    Path("fixture-result.txt").write_text("diagnostic fixture")
    if os.environ.get("MOCK_SLEEP") == "1":
        time.sleep(30)
    sys.exit(int(os.environ.get("MOCK_EXIT", "0")))
"""
        }
        for name, content in commands.items():
            path = self.bin / name
            path.write_text(content)
            path.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.bin) + ":" + os.environ["PATH"],
                        VASP_MPI_PREFIX=str(self.bin.parent), VASP_MPI_MODE="pmi2",
                        VASP_PROFILE="a100_gpu", VASP_VERSION="6.4.3",
                        SLURM_SUBMIT_DIR=str(self.input), SLURM_JOB_ID="123",
                        SLURM_JOB_NUM_NODES="1", SLURM_NTASKS="1", SLURM_CPUS_PER_TASK="1",
                        SLURM_JOB_NODELIST="test-node")

    def tearDown(self):
        self.temporary.cleanup()

    def launch(self, extra=None):
        return subprocess.run(
            ["bash", "-c", 'source "$1"; vasp_run a100', "bash",
             str(ROOT / "scripts/image/runtime.sh")],
            env=self.env | (extra or {}), capture_output=True, text=True
        )

    def test_nonzero_exit_and_nested_output_copy(self):
        result = self.launch({"MOCK_EXIT": "42"})
        self.assertEqual(result.returncode, 42, result.stderr)
        output = self.input / "results-123"
        self.assertTrue((output / "fixture-result.txt").is_file())
        self.assertFalse((output / "results-123").exists())
        self.assertEqual(output.stat().st_mode & 0o077, 0)

    def test_multi_node_local_scratch_rejected(self):
        result = self.launch({"SLURM_JOB_NUM_NODES": "2", "VASP_STAGE_INPUT": "1"})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("shared POSIX scratch", result.stderr)
        self.assertFalse((self.input / "results-123").exists())

    def test_missing_pmi2_backend_rejected(self):
        (self.bin / "ompi_info").write_text("#!/bin/bash\necho mca:ess:pmi:version:test\n")
        result = self.launch()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("No verified Slurm/Open MPI PMI2 combination", result.stderr)
        self.assertFalse((self.input / "results-123").exists())

    def test_termination_preserves_outputs(self):
        process = subprocess.Popen(
            ["bash", "-c", 'source "$1"; vasp_run a100', "bash",
             str(ROOT / "scripts/image/runtime.sh")],
            env=self.env | {"MOCK_SLEEP": "1"}, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        try:
            deadline = time.monotonic() + 5
            while not (self.input / "fixture-result.txt").exists() and time.monotonic() < deadline:
                time.sleep(0.05)
            self.assertTrue((self.input / "fixture-result.txt").exists())
            process.send_signal(signal.SIGTERM)
            _, errors = process.communicate(timeout=5)
            self.assertEqual(process.returncode, 143, errors)
            self.assertTrue((self.input / "results-123/fixture-result.txt").is_file())
        finally:
            if process.poll() is None:
                process.terminate()
                process.communicate(timeout=5)


if __name__ == "__main__":
    unittest.main()
