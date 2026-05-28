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
