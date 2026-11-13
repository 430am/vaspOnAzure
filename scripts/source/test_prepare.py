import gzip
import importlib.util
import io
from pathlib import Path
import tarfile
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location("prepare", Path(__file__).with_name("prepare.py"))
assert SPEC is not None and SPEC.loader is not None
prepare = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(prepare)


class PreparationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.base = Path(self.temp.name)
        self.root = self.base / "input"
        (self.root / "src").mkdir(parents=True)
        (self.root / "arch").mkdir()
        # Empty packaging fixtures, not substitute VASP source.
        for name in ("makefile", "src/empty.F", "arch/empty"):
            (self.root / name).touch()

    def tearDown(self):
        self.temp.cleanup()

    def test_deterministic_roundtrip(self):
        files = prepare.inspect(self.root)
        first = prepare.package(self.root, self.base / "a.tar.gz", files)
        (self.root / "src/empty.F").touch()
        second = prepare.package(self.root, self.base / "b.tar.gz", files)
        self.assertEqual(first, second)
        prepare.extract(self.base / "a.tar.gz", self.base / "extracted", first)
        self.assertEqual(files, prepare.inspect(self.base / "extracted/vasp"))

    def test_symlinks_and_proprietary_inputs_rejected(self):
        link = self.root / "src/link"
        link.symlink_to("/etc/passwd")
        with self.assertRaises(ValueError):
            prepare.inspect(self.root)
        link.unlink()
        (self.root / "src/POTCAR").touch()
        with self.assertRaises(ValueError):
            prepare.inspect(self.root)

    def test_checksum_and_traversal_rejected(self):
        archive = self.base / "bad.tar.gz"
        with tarfile.open(archive, "w:gz") as stream:
            info = tarfile.TarInfo("vasp/../../escape")
            info.size = 1
            stream.addfile(info, io.BytesIO(b"x"))
        with self.assertRaises(ValueError):
            prepare.extract(archive, self.base / "bad", "0" * 64)
        with self.assertRaises(ValueError):
            prepare.extract(archive, self.base / "bad", prepare.digest(archive))

    def test_changed_source_not_authorized(self):
        files = prepare.inspect(self.root)
        (self.root / "src/empty.F").write_bytes(b"changed packaging fixture")
        with self.assertRaises(ValueError):
            prepare.package(self.root, self.base / "changed.tar.gz", files)


if __name__ == "__main__":
    unittest.main()
