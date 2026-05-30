# conformance/

The OPA/Rego policy that checks a repository's file and directory structure
against the OSS publication standard. It is the machine-checkable half
of this repo — `template/` is the bootstrap half, and both are driven from the
same source of truth, `data.json`.

## Files

- **`data.json`** — the single source of truth. Lists required files,
  directories, `.github/` files, agent docs and scripts; the four artifact
  types and their primary validators; forbidden branches; required `.gitignore`
  patterns; content assertions; and the policy self-integrity digest.
- **`conformance.rego`** — package `conformance.conformance`. Consumes a
  `repo-structure.json` snapshot as `input` and `data.json` as `data`, and emits
  a structured `deny` set.
- **`conformance_test.rego`** — the `opa test` suite.

## Violation shape

Each `deny` entry is `{"rule", "severity", "field", "msg"}`. `severity` is
`error` (blocks CI) or `warning` (reported, non-blocking).

| Surface rule | Meaning |
|--------------|---------|
| `data.conformance.conformance.violations` | every violation |
| `data.conformance.conformance.errors` | error-severity only |
| `data.conformance.conformance.warnings` | warning-severity only |
| `data.conformance.conformance.allow` | `true` when there are zero errors |
| `data.conformance.conformance.summary` | `{allow, total, errors, warnings}` |

## Running it

```bash
# Syntax + type check, and the test suite
opa check conformance/conformance.rego
opa test conformance/

# Evaluate against a repo snapshot (see scripts/scan-repo-structure.sh)
opa eval -d conformance/ -i repo-structure.json \
  'data.conformance.conformance.summary'
```

## Self-integrity

`data.json` carries `policy_integrity.expected_digest` — the SHA-256 of
`conformance.rego`. The `policy_integrity` rule fires if the live policy digest
diverges from the manifest, so the policy cannot be silently weakened without
the digest being refrozen. A second rule (`policy_integrity_manifest`) fires if
the digest field is removed entirely. The digest is `PENDING` until frozen by
the release-hardening step.
