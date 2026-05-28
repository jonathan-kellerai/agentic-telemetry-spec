# AGENTS.md — agentic-telemetry-spec

This repository is the **agentic-telemetry-spec** JSON Schema suite — a standardized
metadata specification for provenance, A/B testing, KoTH oracle attribution,
decision logging, and backward-compatibility tracking on agentic AI runs built
atop Claude Code primitives.

**Humans read [README.md](README.md). Agents start here.** This file is the
Tier-1 entry point: a table of contents for agent context. It points at deeper
Tier-2 files under `docs/agents/` for agents that need more.

## What this repo IS

- A **JSON Schema specification** (draft 2020-12): 31 schema files defining the
  metadata envelope for 24 Claude Code tool primitives across three richness
  tiers.
- A set of **worked examples** (`examples/`) and **companion design docs**
  (`docs/`).
- Licensed **Apache-2.0** — see `LICENSE` and `NOTICE`.

## What this repo is NOT

- There is **no runtime code** here — no Python, TypeScript, Go, or build system.
- The integration components named in the schemas
  (`<your-telemetry-ingestor>`, `<your-elo-engine>`, `<your-ab-runner>`,
  `<your-decision-store>`) are **caller-owned placeholders**, not shipped
  artifacts. Each consumer wires the schema into its own pipeline.
- The only verification command relevant here is `ajv compile` / `ajv validate`
  (Node `ajv-cli`, opt-in). See `docs/agents/conventions.md`.

## File layout & agent reading order

Read the file that answers your question — do not load the whole tree.

| Question | Read |
|----------|------|
| What is this project, at a glance? | `README.md` (architecture overview) |
| The 5 design goals & their rationale | `docs/design-goals.md` |
| How does goal _N_ work in depth? | `docs/0N-*.md` (`01-provenance` … `05-backward-compat`) |
| What does a term mean? | `docs/agents/glossary.md` |
| The base metadata contract | `schemas/base/base-metadata.schema.json` |
| A goal fragment's fields | `schemas/goals/{provenance,experiment,koth,decision,backward-compat}.schema.json` |
| A specific tool's metadata shape | `schemas/tools/<tool>.schema.json` (24 files) |
| The persisted telemetry record shape | `schemas/telemetry/unified-activity-extensions.schema.json` |
| A worked metadata example per tier | `examples/tier{1,2,3}-*.json` |
| Quick field reference | `SCHEMA_QUICK_REFERENCE.md`, `SCHEMA_DATABASE.md` |

`schemas/` totals 31 files: `base/` (1), `goals/` (5), `telemetry/` (1),
`tools/` (24).

## Conventions agents MUST follow

- **Default branch is `main`.** Never create or use `master`.
- **Conventional Commits.** `<type>(<scope>): <subject>` — subject ≤ 50 chars,
  imperative mood. Types: `feat`, `fix`, `chore`, `docs`, `refactor`. Scope is
  optional but recommended: `schemas`, `docs`, `examples`.
- **Branch naming.** Agent work uses `<agent>/<scope>` — e.g.
  `claude/fix-koth-enum`, `codex/clarify-tier-2-coverage`. Human work uses
  `feat/*`, `fix/*`, `docs/*`, `chore/*`.
- **PRs for publishable files.** Edits to `schemas/**`, `docs/**`,
  `examples/**`, or `README.md` require a pull request. Schema changes must pass
  `ajv compile`; example changes must pass `ajv validate`. Edits to staging
  files (anything matched by `.gitignore`) may be made directly.
- **Never delete a file** without explicit maintainer permission.
- **Semver discipline.** Every schema change updates `CHANGELOG.md` and follows
  semver: removing a required field or changing a field type = **major**; a new
  optional field = **minor**; a doc or example fix = **patch**.
- **Cite precisely.** Internal references use `file:line`; external or academic
  references use a full bibliographic citation.

The full spec, with examples, is in `docs/agents/conventions.md`.

## Open architectural questions

These are unresolved (whitepaper §11, Future Work). Surface them when proposing
architectural amendments — do not silently assume an answer.

1. **Multi-tenant isolation.** A `tenant_id` column is reserved in the companion
   database schema (`SCHEMA_DATABASE.md`) but has no first-class JSON Schema
   support in the metadata envelope.
2. **`outcome_signal` for `Write` / `Edit`.** `Bash` derives win/loss from its
   exit code (0 = win, non-zero = loss). `Write` and `Edit` have no exit code;
   the rule for deciding their `outcome_signal` is unspecified.
3. **`qm_bead_id` scope.** This field appears in the `docs/design-goals.md` seed
   schema but is absent from the formal
   `schemas/goals/provenance.schema.json`. Clarify the intended scope before
   adding it back.

## Tier-2 references

Deeper guidance — load on demand:

- `docs/agents/conventions.md` — Conventional Commits, branch naming, PR style,
  citation format, the `ajv compile` / `ajv validate` workflow.
- `docs/agents/citation.md` — how to cite agentic-telemetry-spec (Apache-2.0
  attribution, BibTeX, `CITATION.cff`).
- `docs/agents/glossary.md` — load-bearing vocabulary (Tier 1/2/3,
  ProvenanceChain, KoTH / Oracle, ELO, Thompson Sampling, `outcome_signal`,
  DecisionContext, `_compat`, and more).
