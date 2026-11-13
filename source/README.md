# Authorized local source

Place an **authorized, clean extracted VASP 6 source tree** in `source/vasp/`.
The required layout is `makefile`, `src/`, and `arch/`. Do not put an archive
at this path. Never download VASP using this project.

Only `src/`, `arch/`, `makefile`, and root `README*` files are accepted.
Remove `testsuite/`, `POTCARS/`, `bin/`, `build/`, calculation inputs/outputs,
license files, and unrelated files before preparation. All symbolic links are
rejected, including internal ones, to avoid extraction and race ambiguity.
Operator makefile templates may be placed in `arch/` and selected by relative
path. No source or template contents are printed by the preparation script.

Obtain an independently reviewed file manifest (JSON mapping relative filenames
to SHA-256 hashes), or an independently approved deterministic archive checksum.
`inventory` creates a candidate manifest for review; it does not authorize it.
Keep that manifest in ignored `private/`, not Git. See
[source staging](../docs/local-source-staging.md).

The entire local input directory is ignored. This README is the only tracked
file under `source/`. Existing files are not moved, extracted, or deleted by
repository setup.
