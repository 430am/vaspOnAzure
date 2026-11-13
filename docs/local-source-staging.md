# Licensed source preparation and private upload

## Preconditions

Authorized VASP 6 source; Python >=3.10; an independently reviewed manifest or
expected deterministic archive checksum. The operator has Blob Data Contributor
on the staging container and management-plane read access to its account.
The runner has routing/private DNS to the Blob private endpoint.
Do not use storage keys, SAS, GitHub-hosted source runners, or source artifacts.

## Exact sequence

1. Extract/obtain the authorized clean tree at `source/vasp/`, using the structure
   in [source README](../source/README.md). Repository code does not extract the
   operator's original archive automatically.
2. Verify ignores without displaying contents:

```bash
git check-ignore source/vasp/src/main.F
git status --short --untracked-files=all
mkdir -p private staging generated
chmod 700 private staging generated
python3 scripts/source/prepare.py inventory \
  --source ./source/vasp --manifest private/candidate-manifest.json --version 6.4.3
```

3. Have an authorized second reviewer compare the candidate file set/checksums
   against the approved source delivery. Record approval outside Git; save the
   approved exact mapping at `private/approved-manifest.json`. An inventory is
   **not** approval and is never automatically promoted to one.
4. Package:

```bash
python3 scripts/source/prepare.py package --source ./source/vasp \
  --manifest private/approved-manifest.json --version 6.4.3 \
  --output staging/vasp-source.tar.gz
```

Alternatively use `--expected-checksum APPROVED_SHA256` instead of `--manifest`.
The archive has sorted entries, zero timestamps/owners, stable modes, and a
zero-timestamp gzip header. Exact bytes are checked against the manifest during
packaging. All links, generated products, potential datasets, license files,
test suites and unapproved root directories are rejected. File contents never
appear in script logs. Archive and manifest output files are mode 0600.

5. Copy the printed SHA-256 into `vasp_source_checksum` in the private factory
   tfvars. It is integrity metadata, not a secret or a credential.
6. Complete [factory apply](image-build.md) and export the pipeline configuration:

```bash
bash scripts/build/terraform.sh factory output > generated/pipeline.json
python3 scripts/build/manage.py upload --pipeline generated/pipeline.json \
  --archive staging/vasp-source.tar.gz --approve
```

The uploader checks public access/shared keys/firewall/private DNS and SHA-256,
then uses `az storage blob upload --auth-mode login --overwrite false`.
It refuses accidental blob replacement. Use a distinct opaque blob name for
each approved source delivery. Keep names free of user/customer/project secrets.

AIB uses its user-assigned identity and a direct in-VM OAuth download.
Actual identity access is proven by that download and the checksum check,
not by the operator's upload success. RBAC propagation can require a retry.
No local path or source bytes are passed through Terraform or `terraform plan`.

## Retention, errors, rollback and cleanup

`vasp_source_retention_mode=delete` is the default and requires the explicit
approved cleanup command in [cleanup](cleanup.md). `retain` is opt-in; document
an expiry/owner externally. Retained staging is never published in the VM image.
BYO soft delete/versioning/backups can retain deleted data; audit those separately.

Manifest or checksum mismatch blocks upload/build. Correct the source delivery
or obtain a new approval; never replace expected checksums merely to make a
failed verification pass. A failed local packaging run may leave a mode-0600
partial archive; delete its exact named path before retrying.
Keep an approved older blob only as long as licensing/policy permits; rollback
of production nodes uses the gallery image, not the source archive.
