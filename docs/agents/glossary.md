# Glossary — agentic-telemetry-spec

Load-bearing vocabulary for the agentic-telemetry-spec schema suite — one entry per term.
Definitions are extracted from `docs/design-goals.md`, the goal docs
(`docs/01-*.md` … `docs/05-*.md`), and the schema files themselves; see those
sources for full detail. This is a Tier-2 reference — `AGENTS.md` points here.

## Tier 1 / Tier 2 / Tier 3

The specification stratifies the 24 instrumented Claude Code tools by metadata
richness, trading signal quality against token overhead. **Tier 1**
(`AskUserQuestion`, `Task`, `Skill`) carries all five goal fragments — these are
significant decisions with measurable outcomes. **Tier 2** (`Bash`, `Write`,
`Edit`, `SendMessage`, `EnterPlanMode`, `ExitPlanMode`) carries provenance plus
optional `koth` and `decision`, but no `experiment` block. **Tier 3** — 15
high-frequency read/query tools — carries only minimal provenance. Tier is
*computed* by the ingestor from the populated goal blocks, not declared.

## ProvenanceChain / caller_chain

The ordered sequence of caller identities from outermost to immediate, stored in
the `caller_chain` array of the `provenance` fragment. Each element records
`caller_type`, `caller_name`, and an optional `agent_id`. The chain deliberately
omits the *immediate* caller (held separately in `caller_type` / `caller_name`)
to avoid duplication. An empty array marks a top-level call. It must be set at
call time, because the full stack is known only at invocation.

## KoTH (King of the Hill)

An ELO-rating system for Claude Code agents. KoTH tracks win / loss / draw
outcomes from tool invocations, maintains per-domain ratings (editing, planning,
architecture, …), and holds Beta(α, β) priors for Thompson Sampling. A
`source_weights` config scales rating updates by telemetry source — telemetry
1.0×, A/B testing 1.5×, evaluation 2.0×.

## Oracle

A recommendation engine that queries KoTH ELO ratings and Thompson Sampling
parameters to suggest the best agent for a task *before* a tool is invoked. The
Oracle's recommendation and confidence are captured in the `koth` fragment
(`oracle_recommended_agent`, `oracle_recommendation_confidence`) so the actual
selection can later be compared against what was advised.

## ELO

The chess Elo rating formula adapted to agent performance:
`new = old + K · (actual − expected)`, where
`expected = 1 / (1 + 10^((R_b − R_a) / 400))`. Ratings start at 1500 per domain.
The K-factor is weighted by telemetry source. ELO drives the Oracle's initial
candidate shortlist before Thompson Sampling is applied.

## Thompson Sampling (alpha / beta)

A Bayesian bandit algorithm that balances exploration and exploitation. Each
agent holds a Beta(α, β) posterior where α = wins + prior and β = losses + prior
(prior defaults to 1). At query time the Oracle draws one sample per candidate
and picks the highest. Posterior mean = α / (α + β). Agents with few matches
have wide distributions and are occasionally explored; proven agents have narrow
distributions and sample near their true rate.

## outcome_signal

An enum (`win` | `loss` | `draw` | `pending`) in the `koth` fragment recording a
tool call's result, populated by the PostToolUse telemetry hook. `win`: no
error, success true. `loss`: error or failure. `draw`: ambiguous or partial
result. `pending`: deferred, awaiting external validation. For `Bash`, exit 0 =
win; deriving `outcome_signal` for `Write` / `Edit` is an open question — see
`AGENTS.md`.

## decision_id / DecisionContext

A `DecisionContext` is a record of *why* a tool, agent, or skill was selected —
alternatives considered, confidence, intent classification, outcome. Its
`decision_id` (pattern `dec_YYYYMMDD_HHmmss_NNNNNN`) is carried in tool metadata
to bidirectionally join tool calls to the decision that triggered them. It is
set **at call time** by the caller — never post-hoc — to avoid a circular
dependency with `caller_chain` resolution.

## base-metadata allOf composition

`schemas/base/base-metadata.schema.json` is the contract every tool inherits. It
requires `source` + `provenance` and composes the five goal fragments
(`provenance`, `experiment`, `koth`, `decision`, `_compat`) by `$ref` to the
files in `schemas/goals/`. Tool schemas reuse this structure so each goal can
evolve in its own file without a monolithic document.

## _compat / backward compatibility

The `_compat` fragment namespaces migration metadata so the ATS standard can
coexist with legacy metadata shapes indefinitely. It holds `schema_version`
(semver — gates migration logic), `legacy_source` (preserves the original
`AskUserQuestion` `source` string), and `migrated_from` (tool name, old version,
migration date). Schema-version bumps signal additive changes only; breaking
changes require a new major version.

## is_legacy_compat / has_legacy_compat

A boolean distinguishing a genuine pre-ATS caller from an intentionally minimal
Tier 3 implementation. `is_legacy_compat` lives in the `_compat` fragment;
`has_legacy_compat` is its computed mirror on the persisted
`unified-activity-extensions` record. `true` = a legacy caller with unreliable
provenance (excluded from KoTH ELO updates); `false` = a compliant modern caller,
including minimal-by-design Tier 3 calls.

## Reserved / not-yet-specified terms

- **qm_bead_id** — a field in the `docs/design-goals.md` seed schema linking a
  tool call to a Quartermaster / beads work item; absent from the formal
  `provenance` schema. Scope unresolved.
- **tenant_id** — reserved for multi-tenant isolation in the companion database
  schema (`SCHEMA_DATABASE.md`); no first-class JSON Schema support yet.
