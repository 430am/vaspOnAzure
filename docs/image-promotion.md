# Controlled image promotion

## Preconditions and evidence

An immutable candidate with successful replication; full validation through
the intended existing cluster; licensed numerical reference agreement; explicit
operator approval. Promotion identity needs tag-write access to the version.
It does not need source container access or CycleCloud credentials.

Save an **operator-reviewed** receipt in ignored `private/validation-receipt.json`:

```json
{
  "image_version_id": "/subscriptions/.../galleries/.../images/.../versions/1.0.0",
  "passed": true,
  "approved_by_operator": true,
  "checks": {
    "image": true,
    "cyclecloud": true,
    "slurm": true,
    "gpu": true,
    "tcp": true,
    "vasp": true
  }
}
```

This is the required data shape, **not supplied proof**. Set each flag only after
reviewing associated safe logs/job IDs/VM IDs, numerical comparison and lifecycle
evidence. Keep evidence IDs/timestamps/tolerances in the private review record.
The gate validates fields and exact version; it cannot authenticate a fabricated
receipt. Protected-environment approval and controlled receipt storage are part
of the trust model. Require fresh reviewed receipts for each release/hardware
target and restrict writes to release approvers.

## Promote and consume

```bash
python3 scripts/build/manage.py promote --approve \
  --image-version-id "$IMAGE_VERSION_ID" \
  --validation-receipt private/validation-receipt.json
az resource show --ids "$IMAGE_VERSION_ID" --query tags --output json
```

Expected tags: `status=promoted`, `validation=passed`. The version remains
excluded from floating `latest`. Publication state ignores these operational
tags; its image bytes/version remain immutable.

Promotion does **not** mutate a CycleCloud cluster. Set
`cyclecloud_gallery_image_version` to the approved numeric version, generate
and review a new [integration package](cyclecloud-integration.md), import the
reviewed template/parameters explicitly, and retire/recreate idle canary nodes
before broader rollout. Keep the previous pinned reference.

## GitHub approval controls

Enable required reviewers and trusted-branch restrictions for environments
`licensed-source`, `image-infrastructure`, `image-publication`,
`cyclecloud-integration`, `gpu-validation`, `image-promotion`.
Workflow YAML naming an environment alone does **not** enable approvals.
Configure OIDC federated subjects per environment, least-privilege Azure roles
and a separate source principal. Protect workflow modifications and do not allow
unreviewed PR code on licensed-source or Slurm-client runners.

Failure: refuse promotion, correct evidence/validation, not the gate.
Rollback promoted usage through [rollback](rollback.md); remove obsolete
candidate/source/temporary resources using [cleanup](cleanup.md).
