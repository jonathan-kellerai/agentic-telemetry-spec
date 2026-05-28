# Conventions — agentic-telemetry-spec

Tier-2 detail for `AGENTS.md`.
This is the authoritative source for commit, branch, PR, citation, and validation conventions.
When a convention changes, change it here first.

## Commits — Conventional Commits

Every commit subject follows `<type>(<scope>): <subject>`.

- **`<type>`** — one of: `feat`, `fix`, `docs`, `chore`, `refactor`, `ci`, `revert`, `test`,
  `build`, `perf`. Use `ci` for workflow and `.github/` changes; `docs` for CHANGELOG, README,
  and agent-doc edits.
- **`<scope>`** — optional; names the area touched: `schemas`, `docs`, `examples`, `ci`, `agents`.
  Omit for repo-wide changes.
- **`<subject>`** — imperative mood, ≤ 50 characters, no trailing period.

```text
feat(schemas): add tenant_id to provenance fragment
fix(schemas): correct koth outcome_signal enum values
docs(agents): expand glossary with qm_bead_id term
chore(ci): pin ajv-cli action to commit SHA
docs: update CHANGELOG for v0.1.1
revert(schemas): undo decision fragment restructure
```

Commit body is optional.
When present: explains *why*, separated from subject by one blank line, wrapped at 72 characters.

`commitlint` validates every commit message in CI and in the pre-commit hook.
A non-conforming message fails the build — there is no bypass.

## Branches

The default branch is **`main`**. `master` is forbidden.

| Work type | Pattern | Example |
|-----------|---------|---------|
| Agent work | `<agent>/<scope>` | `claude/fix-koth-enum` |
| Human feature | `feat/<scope>` | `feat/add-tenant-id` |
| Human fix | `fix/<scope>` | `fix/decision-id-pattern` |
| Docs | `docs/<scope>` | `docs/backward-compat` |
| CI / chore | `chore/<scope>` | `chore/pin-actions` |
| Revert | `revert/<scope>` | `revert/outcome-signal-change` |

## Branch and commit edge cases

The cases below are logical but consistently cause agent errors.

- **Never work on `main` or a detached `HEAD`.** Cut a branch before the first commit.
  If you are already on `main`, branch now — before writing anything.
- **Always base off the latest `main`.** Never branch from another in-flight branch.
- **Continuing another agent's branch:** keep the existing `<agent>/<scope>` name.
  Do not rename it to your own agent ID.
- **Multi-scope changes:** prefer one scope per branch and PR. If a change genuinely
  spans scopes, omit `<scope>` from the branch name rather than inventing a compound one.
  Use the same rule in the commit subject.
- **`<scope>` casing:** lowercase, hyphen-separated (`backward-compat`, not `backwardCompat`).
- **Revert branches:** use `revert/<scope>`; commit type is `revert`.
- **Commit type for housekeeping:**
  `CHANGELOG.md` edits = `docs`;
  `.github/` or workflow changes = `ci`;
  `AGENTS.md`, `CLAUDE.md`, `docs/agents/**` = `docs(agents)`.
- **Subjects** are imperative mood with no trailing period; **bodies** wrap at 72 characters.
- **Worktrees** are fine — the branch inside the worktree still follows the same convention.
- **Forks:** external contributors open a PR from a fork branch against this repo's `main`.
  Never from the fork's `main` branch.

## Pull requests

PRs are required for publishable files: `schemas/**`, `docs/**`, `examples/**`, `README.md`,
`AGENTS.md`, `CLAUDE.md`.
Staging files (anything matched by `.gitignore`) may be edited directly.

A PR description states: what changed, why it changed, validation output (`ajv compile` /
`ajv validate` results), and the semver classification (major / minor / patch).

Schema changes that affect the base contract (`schemas/base/`) or a goal fragment
(`schemas/goals/`) carry a higher review bar — see `CODEOWNERS` and `.github/enforcement.md`.

## Citations

- **Internal references** use `file:line` — e.g. `schemas/goals/koth.schema.json:42`.
  Cite the absence of a thing as precisely as its presence: state which file you checked.
- **External or academic references** use a full bibliographic citation: author(s), title,
  venue, year. Never cite from memory — verify the source before writing the citation.

## Validation workflow

```bash
# Compile a single schema (checks JSON Schema draft 2020-12 validity)
ajv compile -s schemas/goals/provenance.schema.json

# Compile all schemas
for schema in schemas/**/*.schema.json; do
  ajv compile -s "$schema" || exit 1
done

# Validate a worked example against its tool schema
ajv validate -s schemas/tools/bash.schema.json -d examples/tier2-bash.json

# Validate all examples
for example in examples/*.json; do
  # Each example filename corresponds to a tool schema; see SCHEMA_QUICK_REFERENCE.md
  ajv validate -s schemas/tools/"$(basename "$example" .json)".schema.json -d "$example"
done
```

Run `ajv compile` before `ajv validate` — a malformed schema produces misleading validation
errors. Fix compile errors first.
`ajv-cli` is opt-in; install via `npm install -g ajv-cli ajv-formats` if not present.
