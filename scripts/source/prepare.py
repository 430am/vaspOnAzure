#!/usr/bin/env python3
"""Validate and deterministically package authorized local input; never log contents."""

import argparse
import gzip
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import sys
import tarfile


def digest(path: Path) -> str:
    checksum = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            checksum.update(chunk)
    return checksum.hexdigest()


def forbidden(path: PurePosixPath) -> bool:
    return any(
        re.match(r"(?i)^(potcar|license|licence|munge\.key|vasp_(std|gam|ncl))", part)
        or part.lower() in {"bin", "build", "testsuite", ".git"}
        or part.lower() in {"incar", "poscar", "outcar", "wavecar", "chgcar", "vasprun.xml"}
        for part in path.parts
    ) or path.suffix.lower() in {".o", ".mod", ".tgz", ".gz", ".zip", ".key", ".pem", ".lic"}


def inspect(root: Path) -> dict[str, str]:
    if root.is_symlink() or not root.is_dir():
        raise ValueError("Source must be a real readable directory.")
    for name in ("makefile", "src", "arch"):
        path = root / name
        if not path.exists() or path.is_symlink():
            raise ValueError("Expected source structure: makefile, src/, arch/.")
    if not (root / "makefile").is_file() or not all((root / p).is_dir() for p in ("src", "arch")):
        raise ValueError("Source structure has incorrect file types.")
    files: dict[str, str] = {}
    for path in sorted(root.rglob("*")):
        relative = PurePosixPath(path.relative_to(root).as_posix())
        if path.is_symlink():
            raise ValueError("Symbolic links are not accepted.")
        if forbidden(relative):
            raise ValueError("Input contains prohibited or generated material; sanitize it first.")
        if relative.parts[0] not in {"src", "arch", "makefile"} and not (
            len(relative.parts) == 1 and relative.name.startswith("README")
        ):
            raise ValueError("Input includes files outside the approved source layout.")
        if path.is_dir():
            continue
        if not path.is_file() or not os.access(path, os.R_OK):
            raise ValueError("Source includes unreadable or non-regular files.")
        files[str(relative)] = digest(path)
    if not any(n.startswith("src/") for n in files) or not any(n.startswith("arch/") for n in files):
        raise ValueError("Source and architecture directories cannot be empty.")
    return files


def identify_version(root: Path) -> str | None:
    versions: set[str] = set()
    for name in ("README.md", "README", "src/version.F", "src/main.F"):
        path = root / name
        if path.is_file():
            # Only the version is returned. No source text is printed or persisted.
            text = path.read_text(errors="replace")
            versions.update(re.findall(r"(?i)vasp[. _-]+(6\.\d+\.\d+)", text))
    if len(versions) > 1:
        raise ValueError("Ambiguous source version; operator review is required.")
    return next(iter(versions), None)


def package(root: Path, output: Path, files: dict[str, str]) -> str:
    output = output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    if output.is_relative_to(root.resolve()):
        raise ValueError("Archive must be outside the source tree.")
    with output.open("xb") as raw:
        os.chmod(output, 0o600)
        with gzip.GzipFile(fileobj=raw, mode="wb", filename="", mtime=0) as zipped:
            with tarfile.open(fileobj=zipped, mode="w", format=tarfile.PAX_FORMAT) as archive:
                for name, expected in files.items():
                    path = root / name
                    with path.open("rb") as stream:
                        before = os.fstat(stream.fileno())
                        if not stat.S_ISREG(before.st_mode) or path.is_symlink():
                            raise ValueError("Source changed while packaging.")
                        info = tarfile.TarInfo("vasp/" + name)
                        info.size = before.st_size
                        info.mode = 0o755 if before.st_mode & 0o111 else 0o644
                        info.mtime = 0
                        data = stream.read()
                        if len(data) != info.size or hashlib.sha256(data).hexdigest() != expected:
                            raise ValueError("Source changed while packaging.")
                        archive.addfile(info, io.BytesIO(data))
    return digest(output)


def extract(archive: Path, destination: Path, expected: str) -> None:
    if not re.fullmatch(r"[a-f0-9]{64}", expected) or digest(archive) != expected:
        raise ValueError("Archive SHA-256 does not match.")
    if destination.exists():
        raise ValueError("Extraction destination must not already exist.")
    destination.mkdir(mode=0o700, parents=False)
    with tarfile.open(archive, "r:gz") as source:
        members = source.getmembers()
        names: set[str] = set()
        for member in members:
            relative = PurePosixPath(member.name)
            if (
                relative.is_absolute() or ".." in relative.parts or "\\" in member.name
                or not relative.parts or relative.parts[0] != "vasp"
                or not member.isfile() or forbidden(relative)
                or member.name in names
                or member.name != relative.as_posix()
            ):
                raise ValueError("Unsafe or unexpected archive member.")
            names.add(member.name)
        # Regular-file-only extraction also works on Ubuntu 22.04's Python 3.10.
        for member in members:
            path = destination / member.name
            path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            content = source.extractfile(member)
            if content is None:
                raise ValueError("Archive member has no readable file data.")
            with content, path.open("xb") as output:
                shutil.copyfileobj(content, output)
            path.chmod(member.mode & 0o777)
    inspect(destination / "vasp")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["inventory", "package", "extract"])
    parser.add_argument("--source", type=Path, default=Path("./source/vasp"))
    parser.add_argument("--output", type=Path, default=Path("staging/vasp-source.tar.gz"))
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--expected-checksum")
    parser.add_argument("--version", default="6.4.3")
    parser.add_argument("--destination", type=Path)
    args = parser.parse_args()
    if args.command == "extract":
        if args.destination is None or args.expected_checksum is None:
            parser.error("extract requires --destination and --expected-checksum")
        extract(args.output, args.destination, args.expected_checksum)
        return
    root = args.source.absolute()
    files = inspect(root)
    detected = identify_version(root)
    if detected is not None and detected != args.version:
        raise ValueError("Detected VASP version differs from the declared version.")
    if args.command == "inventory":
        if args.manifest is None:
            parser.error("inventory requires --manifest for subsequent independent review")
        args.manifest.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        with args.manifest.open("x") as stream:
            os.chmod(args.manifest, 0o600)
            json.dump(files, stream, sort_keys=True, indent=2)
        print("Candidate manifest created. Review independently before authorizing packaging.")
        return
    if args.manifest is None and args.expected_checksum is None:
        parser.error("package requires an approved --manifest or --expected-checksum")
    if args.manifest is not None:
        approved = json.loads(args.manifest.read_text())
        if approved != files:
            raise ValueError("Approved source manifest does not match the exact source file set.")
    checksum = package(root, args.output.absolute(), files)
    if args.expected_checksum is not None and checksum != args.expected_checksum:
        args.output.unlink()
        raise ValueError("Approved archive checksum does not match; archive removed.")
    receipt = {
        "sha256": checksum, "vasp_version": args.version,
        "detected_version": detected, "file_count": len(files)
    }
    receipt_path = args.output.with_suffix(args.output.suffix + ".json")
    with receipt_path.open("x") as stream:
        os.chmod(receipt_path, 0o600)
        json.dump(receipt, stream, sort_keys=True, indent=2)
    print(json.dumps(receipt))


if __name__ == "__main__":
    try:
        main()
    except ValueError as error:
        print(f"Preparation failed: {error}", file=sys.stderr)
        sys.exit(1)
    except (OSError, tarfile.TarError) as error:
        print(f"Preparation failed ({type(error).__name__}); inspect readability, archive structure, and output permissions.", file=sys.stderr)
        sys.exit(1)
