# Enforcement — agentic-telemetry-spec

Tier-2 detail for `AGENTS.md`.
How the conventions are enforced — what is automated, what is gated by review, and what is
self-protecting.

## Automated gates

| Gate | Where it runs | What it checks |
|------|--------------|----------------|
| `ajv compile` | CI and pre-commit hook | Every schema in `schemas/**/*.schema.json` is valid JSON Schema draft 2020-12. |
| `ajv validate` | CI and pre-commit hook | Every example in `examples/*.json` validates against its tool schema. |
| `scripts/check-sanitization.sh` | CI and pre-commit hook | No internal term from the denylist appears in the publishable tree. The denylist is base64-encoded inside the script so the script does not itself republish those terms. |
| Markdown lint | CI | `markdownlint-cli2` over every Markdown file. |
| Link check | CI | `lychee` resolves every link. |
| `commitlint` | CI, on every pull request | Every commit message is a valid Conventional Commit (`commitlint.config.js`). |
| Conformance policy | CI | The reusable `kellerai-oss-template` workflow evaluates the repository structure. agentic-telemetry-spec calls it via `uses:` pinned to a commit SHA — a policy upgrade only takes effect when the SHA is explicitly bumped. |

The pre-commit hook is managed by `lefthook`.
Install once with `lefthook install`; it then runs schema compilation and the sanitization gate
before every commit.
CI runs the same gates, so the hook is a convenience — not the sole line of defence.

## Reviewed, not automated

- **`CODEOWNERS`** (`.github/CODEOWNERS`) routes pull-request review for sensitive paths to
  `@jonathan-kellerai`. Locked paths: `.github/`, `LICENSE`, `NOTICE`, `AGENTS.md`, `CLAUDE.md`,
  `schemas/base/`, `schemas/goals/`. Leaf tool schemas (`schemas/tools/**`) stay open.
- The **PR template** (`.github/PULL_REQUEST_TEMPLATE.md`) requires: summary, artifacts touched,
  validation output (`ajv compile` result), semver classification, and a contributor checkbox.
  Reviewers confirm the validation output and semver claim are consistent.
- An **IP-leak audit** — a qualitative pass beyond the sanitization regex — is run before any
  machine-generated artifact is added to the publishable tree. The regex gate is necessary but not
  sufficient. Precedent: `docs/codebase-atlas.html` passed regex checks but embedded private git
  history and was excluded from publication (`OSS-PUBLICATION-STANDARD.md §15`).

## Semver discipline for schema changes

Every schema change must update `CHANGELOG.md` and carry a semver classification:

| Change | Classification |
|--------|---------------|
| Remove a required field; change a field type; restructure breaking consumers | **major** |
| Add a new optional field; add a new schema file; extend an existing enum | **minor** |
| Correct a description; fix a typo; update an example; improve docs | **patch** |

State the classification in the commit subject and the PR body.
The classification is checked by a reviewer — it is not automated.

## Where a convention lives

`AGENTS.md` and the files under `docs/agents/` are canonical.
When a convention changes:

1. Change it in `docs/agents/conventions.md` (or the relevant Tier-2 file) first.
2. Update the `AGENTS.md` summary if the Tier-1 overview is now stale.
3. Propagate to `CONTRIBUTING.md` and `README.md` if either restates it.

`README.md` and `CONTRIBUTING.md` are downstream of `docs/agents/`.
A reviewer who sees a convention in `README.md` that is absent from `docs/agents/` should treat
`docs/agents/` as authoritative and flag the discrepancy.

## Glossary review cadence

Every change that introduces new load-bearing vocabulary must, in the same pull request, add or
update the relevant term in `docs/agents/glossary.md`.
A reviewer who sees new vocabulary with no glossary entry should block the PR.

## Conformance policy — deny families and policy integrity

The `kellerai-oss-template` conformance workflow validates this repository's structure on every
push and pull request. The policy source is `conformance/conformance.rego` in the template repo;
`agentic-telemetry-spec` calls it via a pinned `uses:` SHA. The deny families are:

| Rule name | Severity | Trigger condition |
|-----------|----------|-------------------|
| `data_sentinel` | error | `data.schema` absent — conformance manifest not loaded |
| `required_file` | error | A path listed in `data.json:schema.required_files` is missing from the repo |
| `required_dir` | error | A path listed in `data.json:schema.required_dirs` is missing |
| `required_github_file` | error | A path in `data.json:schema.required_github_files` is missing |
| `required_agent_doc` | error | A Tier-2 agent doc in `data.json:schema.required_agent_docs` is missing |
| `required_script` | error | A script listed in `data.json:schema.required_scripts` is missing |
| `artifact_type_known` | error | `input.artifact_type` is not in `data.json:schema.artifact_types` |
| `artifact_dir` | error | The artifact type's default directory is absent |
| `agents_md_length` | warning | `AGENTS.md` exceeds `data.json:content_assertions.agents_md_max_lines` (currently 150) |
| `claude_md_length` | warning | `CLAUDE.md` exceeds `data.json:content_assertions.claude_md_max_lines` (currently 80) |
| `claude_md_import` | error | `CLAUDE.md` first content line is not `@AGENTS.md` |
| `readme_agent_footer` | warning | `README.md` is missing the `For agents` footer marker |
| `gitignore_coverage` | error | `.gitignore` does not cover a pattern from `data.json:schema.gitignore_required_patterns` |
| `forbidden_branch` | error | A branch name listed in `data.json:schema.forbidden_branches` (`master`) is present |
| `primary_validator_wired` | warning | No CI workflow references the artifact type's primary validator |
| `trust_dial_wired` | error | The trust-dial gate workflow is present but no CI step evaluates `data.conformance.trust_dial` |
| `policy_integrity` | error | The live SHA-256 digest of `conformance/conformance.rego` does not match `data.json:policy_integrity.expected_digest` |
| `policy_integrity_manifest` | error | `data.json:policy_integrity.expected_digest` is absent |
| `affects_manifest_complete` | error | A file in the blast-radius pulse scope (`conformance/`, `template/`, `scripts/`, `docs/agents/`) is not reachable from any entry in `conformance/affects.json` |

### Policy self-integrity mechanism

`data.json:policy_integrity.expected_digest` pins the SHA-256 of `conformance/conformance.rego`.
The `policy_integrity` deny rule fires whenever the live digest captured by
`scripts/scan-repo-structure.sh` differs from the pinned value — detecting silent tampering.

After any edit to `conformance/conformance.rego`, refreeze the digest before committing:

```bash
shasum -a 256 conformance/conformance.rego   # macOS
sha256sum conformance/conformance.rego        # Linux
```

Update `conformance/data.json:policy_integrity.expected_digest` with the output hex string.
Omit the filename — only the 64-character hex digest is stored.
The digest and the doc update must land in the same commit (see `BR-001-conformance-rego` in
`conformance/affects.json`).

## Blast-radius pulse — affects manifest (BR-011)

`conformance/affects.json` is the blast-radius pulse manifest. It declares cross-file
relationships: when a file matching `when_changed` appears in a git diff, the pulse engine fires
the entry, computes which `affects` globs are missing from the diff, and reports `required_actions`
as owed.

`BR-011-affects-manifest` (`conformance/affects.json:178-194`) is the self-referential entry that
covers changes to the manifest itself. It has `severity: "error"` and `verifiable: true`, so any
edit to `conformance/affects.json` with owed actions is a hard CI block.

### Required actions when editing `conformance/affects.json`

1. **BR-011-affects-manifest-1** — For each new or renamed entry, add a positive test case
   (verifies the entry fires) and a cleared test case (verifies all actions DONE yields
   `verdict == "clear"`) in `conformance/blast_radius_test.rego`. Match the style of existing
   test blocks (see the `test_br011_fires_on_affects_manifest_edit` /
   `test_br011_clears_when_actions_done` pair added in this rollout).

2. **BR-011-affects-manifest-2** — Document the new or changed entry in this file
   (`docs/agents/enforcement.md`) — rule name, severity, `verifiable` flag, trigger condition,
   and the required-action IDs.

Both actions must be declared in the commit message footer as `Pulse-Action: BR-011-affects-manifest-1 DONE`
and `Pulse-Action: BR-011-affects-manifest-2 DONE`, or the pre-commit hook rejects the commit.
