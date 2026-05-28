# agentic-telemetry-spec: A Composable JSON Schema Suite for Agentic AI Telemetry

## Standardized provenance, A/B experimentation, performance attribution, decision joins, and backward-compatible adoption for multi-agent systems

---

- **Project:** agentic-telemetry-spec contributors
- **Date:** 2026-05-20
- **License:** Apache-2.0
- **Classification:** Technical White Paper

---

## Abstract

Agentic AI systems built on Claude Code and similar primitives lack a shared telemetry vocabulary. In the unmodified baseline, only three of eighteen Claude Code tools carry any structured metadata, and the field present on the most consequential of them — `AskUserQuestion` — is a single opaque `source` string. The remaining tools emit no caller identity, no decision-context join keys, and no agent-attribution signals. As a result, downstream telemetry consumers cannot reproduce a session, attribute an outcome to the agent that produced it, or run controlled experiments across prompt or tool variants.

This paper presents `agentic-telemetry-spec`, an Apache-2.0 JSON Schema suite that defines a unified metadata envelope for every Claude Code primitive. The schema is decomposed into five orthogonal *design goals* — provenance, A/B experimentation, KoTH/Oracle performance attribution, decision-logger joins, and backward compatibility — composed through JSON Schema `$ref` into twenty-four per-tool schemas. A three-tier instrumentation model assigns proportionally more metadata to consequential tools (`AskUserQuestion`, `Task`, `Skill`) while keeping read-heavy primitives (`Read`, `Glob`, `Grep`) cheap. A separate `unified-activity-extensions` schema describes the additive, non-breaking shape exported to JSONL telemetry streams.

The contribution is twofold. First, the schemas establish a vendor-neutral, validator-checkable contract for agentic telemetry that any ingestion pipeline can adopt. Second, the KoTH/Oracle fragment encodes agent performance — ELO ratings, Thompson Sampling Beta parameters, and domain-routed win/loss signals — as a first-class telemetry concern rather than an opaque downstream computation. The suite ships with worked examples for each tier and with explicit integration points for ingestion, decision storage, ELO scoring, and A/B runners.

## Contributions

This work makes the following distinct contributions:

- **A composable, validator-checkable JSON Schema suite** covering twenty-four Claude Code tool primitives, decomposed into five orthogonal design-goal fragments and assembled by `$ref`.
- **A proportional three-tier instrumentation model** that aligns metadata cost with tool consequence, so high-frequency reads stay cheap while high-stakes decisions carry full context.
- **A telemetry-native encoding of agent performance** through the KoTH/Oracle fragment, which exposes ELO ratings, Beta-distributed Thompson Sampling parameters, and outcome signals directly on the tool-call record.
- **A bidirectional decision-join key** linking individual tool calls to `DecisionContext` records, enabling reconstruction of decision lifecycles (pre-decision, post-decision, outcome) from JSONL telemetry.
- **An additive backward-compatibility design** that preserves the legacy `AskUserQuestion` `source` string, isolates ATS metadata behind a single `_compat` block, and reserves the `metadata._dgm` namespace for tools whose `metadata` field is user-controlled.
- **Worked Tier 1, Tier 2, and Tier 3 examples** alongside a unified-activity extension schema that documents how metadata is reshaped into the persisted telemetry record.

---

## 1. Introduction

Production agentic systems make hundreds of tool calls per session: file reads, web fetches, shell invocations, sub-agent spawns, user questions, decision logs. Without structured caller identity on every call, downstream telemetry collapses into an unjoinable stream of action records. Today, in the unmodified Claude Code baseline, the situation is sharper than that: of the eighteen documented tool primitives, only `AskUserQuestion`, `TaskCreate`, and `TaskUpdate` carry any metadata field at all, and only the first of these has a documented shape — a single opaque `source: string` (see `README.md` lines 10-16 and `docs/design-goals.md` lines 11-19).

This deficit blocks four practical capabilities that are routinely expected of mature observability stacks. First, **provenance** — tracing a tool call back through the chain of subagents, skills, and hooks that produced it — is impossible without a caller identity on every record. Second, **A/B experimentation** across prompt templates, option orderings, or selection strategies requires that each call carry an experiment and variant identifier. Third, **agent performance attribution** — the ability to update a per-agent rating based on whether its actions led to a positive outcome — requires both a stable agent identifier and a win/loss signal on the call record. Fourth, **decision reconstruction** — answering "what tool calls informed this decision, and what tool calls executed it?" — requires a bidirectional join between the tool stream and a decision log.

`agentic-telemetry-spec` addresses these four capabilities, plus a fifth — **backward compatibility** — through a single composable metadata schema. The schema is defined formally in JSON Schema draft 2020-12 (`schemas/base/base-metadata.schema.json` line 2) and partitioned into five orthogonal design-goal fragments, each owning exactly one top-level key in the metadata envelope (`docs/design-goals.md` lines 170-180). The remainder of this paper proceeds as follows. Section 2 describes the repository architecture. Section 3 enumerates the five design goals and their schema fragments. Section 4 motivates the tier system. Section 5 dives into the KoTH/Oracle fragment as the novel algorithmic contribution. Section 6 covers backward compatibility. Section 7 presents concrete use cases. Section 8 is an integration guide. Section 9 surveys related work. Section 10 discusses ecosystem impact, and Section 11 concludes.

---

## 2. Architecture

The `agentic-telemetry-spec` repository is organized around three primary directories — `schemas/`, `docs/`, and `examples/` — plus top-level governance files. The complete on-disk layout is shown below.

```text
agentic-telemetry-spec/
├── schemas/
│   ├── base/
│   │   └── base-metadata.schema.json          # composable root
│   ├── goals/
│   │   ├── provenance.schema.json             # Goal 1
│   │   ├── experiment.schema.json             # Goal 2
│   │   ├── koth.schema.json                   # Goal 3
│   │   ├── decision.schema.json               # Goal 4
│   │   └── backward-compat.schema.json        # Goal 5
│   ├── tools/                                 # 24 per-tool schemas
│   │   ├── ask-user-question.schema.json      # Tier 1
│   │   ├── task.schema.json                   # Tier 1
│   │   ├── skill.schema.json                  # Tier 1
│   │   ├── bash.schema.json                   # Tier 2
│   │   ├── write.schema.json                  # Tier 2
│   │   ├── edit.schema.json                   # Tier 2
│   │   ├── send-message.schema.json           # Tier 2
│   │   ├── enter-plan-mode.schema.json        # Tier 2
│   │   ├── exit-plan-mode.schema.json         # Tier 2
│   │   ├── read.schema.json                   # Tier 3
│   │   ├── glob.schema.json                   # Tier 3
│   │   ├── grep.schema.json                   # Tier 3
│   │   ├── web-search.schema.json             # Tier 3
│   │   ├── web-fetch.schema.json              # Tier 3
│   │   ├── task-create.schema.json            # Tier 3 (metadata._dgm)
│   │   ├── task-update.schema.json            # Tier 3 (metadata._dgm)
│   │   ├── task-list.schema.json              # Tier 3
│   │   ├── task-get.schema.json               # Tier 3
│   │   ├── task-output.schema.json            # Tier 3
│   │   ├── task-stop.schema.json              # Tier 3
│   │   ├── team-create.schema.json            # Tier 3
│   │   ├── team-delete.schema.json            # Tier 3
│   │   ├── tool-search.schema.json            # Tier 3
│   │   └── notebook-edit.schema.json          # Tier 3
│   └── telemetry/
│       └── unified-activity-extensions.schema.json
├── docs/
│   ├── design-goals.md                        # canonical seed spec
│   ├── 01-provenance.md
│   ├── 02-ab-testing.md
│   ├── 03-koth-oracle.md
│   ├── 04-decision-logger.md
│   └── 05-backward-compat.md
├── examples/
│   ├── tier1-ask-user-question.json
│   ├── tier2-bash.json
│   └── tier3-read.json
├── README.md
├── SCHEMA_DATABASE.md
├── SCHEMA_QUICK_REFERENCE.md
├── CHANGELOG.md
├── CONTRIBUTING.md
├── LICENSE
└── NOTICE
```

The architecture follows a three-layer composition pattern. At the root, `schemas/base/base-metadata.schema.json` declares the metadata envelope with two required keys (`source`, `provenance`) and four optional keys (`experiment`, `koth`, `decision`, `_compat`), each defined by `$ref` to a goal fragment (`base-metadata.schema.json` lines 7-33). The middle layer, `schemas/goals/`, contains the five fragments. The leaf layer, `schemas/tools/`, contains twenty-four tool-specific schemas that consume the base schema and constrain which goal fragments are required for that tool. A separate `schemas/telemetry/unified-activity-extensions.schema.json` describes the shape of the persisted JSONL record — namely, that all ATS fields are nested under a single `dgm` top-level key with a computed `tier` integer (`unified-activity-extensions.schema.json` lines 7-62).

The end-to-end data flow is straightforward:

```text
┌──────────────────────┐    ┌────────────────────────────┐    ┌──────────────────────┐
│  Tool call site      │───▶│  Metadata envelope         │───▶│  Telemetry ingestor  │
│  (skill/agent/hook)  │    │  (per-tool schema)         │    │  _dgm_fields(...)    │
└──────────────────────┘    └────────────────────────────┘    └──────────┬───────────┘
                                                                         │
                            ┌────────────────────────────────────────────┼─────────────────────┐
                            ▼                                            ▼                     ▼
                  ┌──────────────────────┐               ┌──────────────────────┐   ┌────────────────────┐
                  │ unified-activity     │               │ decision store       │   │ ELO / A/B engines  │
                  │ .jsonl (dgm block)   │               │ (decision_id join)   │   │ (outcome signals)  │
                  └──────────────────────┘               └──────────────────────┘   └────────────────────┘
```

---

## 3. The Five Design Goals

The metadata envelope is partitioned into five orthogonal goals. Each owns exactly one top-level key, so a downstream consumer can ignore everything outside its area of concern (`docs/design-goals.md` lines 170-180).

### 3.1 Goal 1 — Provenance

The provenance fragment records the immediate caller of a tool, the surrounding session, the optional spawned-subagent identifier, and the chain of parent callers. Required fields are `session_id`, `caller_type`, and `caller_name` (`schemas/goals/provenance.schema.json` line 82). The `caller_type` is constrained to `skill | agent | hook | main`, mirroring the four execution contexts in Claude Code. The optional `caller_chain` is an ordered array from outermost to immediate, enabling reconstruction of nested invocations such as a skill that spawned a subagent that invoked another skill.

A privacy-preserving `project_path_hash` field stores the first eight hex characters of `SHA256(project_path)` (`schemas/goals/provenance.schema.json` lines 69-74), matching the `EntityMemory.entity_id` hashing pattern. This lets cross-session analytics join records by project without exposing absolute paths.

### 3.2 Goal 2 — A/B Testing (`experiment`)

The experiment fragment carries six optional fields used for controlled experiments: `template_id`, `template_version` (constrained to a semver pattern, `schemas/goals/experiment.schema.json` line 16), `experiment_id`, `variant_id`, `assignment_method` (`random | deterministic | oracle_guided`), and `treatment_group` (`control | treatment`). All fields are optional; the entire `experiment` key is omitted for non-experimental calls (`schemas/goals/experiment.schema.json` line 5). When present, the experiment block is recommended to carry a 1.5x weight in downstream ELO calculations relative to passive telemetry, because the controlled conditions yield higher-signal observations (`schemas/goals/experiment.schema.json` line 21).

### 3.3 Goal 3 — KoTH / Oracle (`koth`)

The KoTH (King-of-the-Hill) fragment links tool calls to per-agent performance state. It carries an `oracle_consulted` boolean (required), the `oracle_recommended_agent` and `oracle_recommendation_confidence` (a `[0.0, 1.0]` Beta-sampled score), the `agents_in_options` array (for `AskUserQuestion` agent-selection questions), the optional `koth_domain`, an `outcome_signal` (`win | loss | draw | pending`), and a `question_type` classifier (`schemas/goals/koth.schema.json` lines 7-44). The `outcome_signal` starts at `pending` at `PreToolUse` and is updated to a terminal value at `PostToolUse`, closing the feedback loop into the ELO engine. Section 5 develops the algorithmic side of this fragment in detail.

### 3.4 Goal 4 — Decision Logger Join (`decision`)

The decision fragment carries a `decision_id` whose format is constrained by the regex `^dec_[0-9]{8}_[0-9]{6}_[0-9]{6}$` (`schemas/goals/decision.schema.json` line 11). This is the bidirectional join key that links a tool call to a `DecisionContext` record in the decision store. Additional fields include `intent_classification` (`exploration | editing | review | planning | autonomous`), the privacy-preserving `entity_id`, a `signal_type` (`pre_decision | post_decision | outcome`) that positions the call in the decision lifecycle, a `parent_decision_id` for nested decisions, and a `decision_domain` for KoTH subcategory routing (`schemas/goals/decision.schema.json` lines 7-38).

The `signal_type` enables a useful temporal reading of a decision: pre-decision tool calls (typically `Read`, `Grep`, `Glob`) inform the decision; post-decision calls (typically `Write`, `Edit`, `Bash`) execute it; outcome calls (`TaskUpdate` with `status=completed`) close it. Reconstructing a decision lifecycle is then a single SQL or JSONL filter.

### 3.5 Goal 5 — Backward Compatibility (`_compat`)

The `_compat` fragment captures migration provenance. It carries a required `schema_version` (semver-constrained, `schemas/goals/backward-compat.schema.json` line 12), an optional `legacy_source` that preserves the original `AskUserQuestion` source string (such as the value `"remember"`, `schemas/goals/backward-compat.schema.json` line 14), a `migrated_from` object recording the source tool name, old schema version, and migration timestamp, and an `is_legacy_compat` boolean that flags records produced by callers that have not yet adopted ATS metadata. Section 6 develops the compatibility design in detail.

---

## 4. The Tier System

The tier system is the proportional-instrumentation principle of `agentic-telemetry-spec`. Not every tool warrants the same metadata footprint. A `Read` call is fired thousands of times in a session; attaching an A/B experiment block to each would inflate telemetry volume without adding signal. An `AskUserQuestion` call, by contrast, is a rare and consequential event: it represents a routed decision, often an agent-selection vote, and its outcome must be attributable.

`agentic-telemetry-spec` therefore defines three tiers (`README.md` lines 38-44):

- **Tier 1 — Full metadata.** All five goal fragments apply. Three tools qualify: `AskUserQuestion`, `Task`, and `Skill`. These represent significant decisions with measurable outcomes — a user vote, a sub-agent spawn, or a named-skill invocation.
- **Tier 2 — Partial metadata.** Provenance is required; KoTH and Decision are optional; Experiment and `_compat` do not apply. Six tools qualify: `Bash`, `Write`, `Edit`, `SendMessage`, `EnterPlanMode`, and `ExitPlanMode`. These execute consequential actions but are not themselves selection events.
- **Tier 3 — Minimal metadata.** Only `source` and the three required `provenance` fields apply. Fifteen tools qualify, primarily high-frequency read/query primitives (`Read`, `Glob`, `Grep`, `WebSearch`, `WebFetch`) and task/team CRUD operations (`TaskCreate`, `TaskUpdate`, `TaskList`, `TaskGet`, `TaskOutput`, `TaskStop`, `TeamCreate`, `TeamDelete`, `ToolSearch`, `NotebookEdit`).

The contrast is concrete. The Tier 3 example for `Read` carries exactly four fields total — one string plus three provenance fields (`examples/tier3-read.json` lines 3-8). The Tier 1 example for `AskUserQuestion` carries the full envelope: `source`, seven provenance fields, six experiment fields, seven KoTH fields, and six decision fields, for a total of twenty-seven populated fields across five blocks (`examples/tier1-ask-user-question.json`). This is roughly a seven-fold metadata expansion for a roughly thousand-fold rarer event — proportional, not flat.

A tier is not declared in the metadata; it is *computed* by the ingestor based on which goal blocks are present, and stored as an integer on the persisted record (`schemas/telemetry/unified-activity-extensions.schema.json` lines 49-53). This means a tool can be promoted from Tier 3 to Tier 2 simply by populating optional fields, without a schema change.

---

## 5. KoTH Oracle: Agent Performance as a First-Class Telemetry Concern

The KoTH/Oracle fragment is the novel algorithmic contribution of `agentic-telemetry-spec`. Most telemetry schemas treat agent performance as a downstream computation: log actions, compute scores later. `agentic-telemetry-spec` inverts that by placing the inputs and outputs of the rating computation directly on the tool-call record.

### 5.1 ELO Ratings

Each agent carries a per-domain ELO rating. The companion database schema starts ratings at 1500 and updates them in response to win/loss signals (`SCHEMA_DATABASE.md` line 176). The standard ELO update rule applies:

$$R_a' = R_a + K \cdot (S_a - E_a), \quad E_a = \frac{1}{1 + 10^{(R_b - R_a)/400}}$$

where $R_a, R_b$ are the agents' pre-match ratings, $S_a \in \{1, 0.5, 0\}$ encodes the match result, $E_a$ is the expected score, and $K$ is the update step. In `agentic-telemetry-spec`, an `AskUserQuestion` with `agents_in_options = [a, b, c]` and a user selection of $a$ produces one win for $a$ and one loss each for $b$ and $c$ — the question itself is the "match." The `outcome_signal` field on the KoTH fragment carries the result; the `agents_in_options` field carries the participants.

### 5.2 Thompson Sampling with Beta Distributions

Beyond ELO, `agentic-telemetry-spec` exposes Thompson Sampling state. Each agent (optionally per domain) carries Beta-distribution shape parameters $\alpha$ and $\beta$, initialized to $1$ (`SCHEMA_DATABASE.md` lines 181-184). After $w$ wins and $\ell$ losses, the posterior is:

$$\theta_i \sim \text{Beta}(\alpha_i + w_i, \beta_i + \ell_i)$$

with expected value:

$$E[\theta_i] = \frac{\alpha_i + w_i}{\alpha_i + \beta_i + w_i + \ell_i}$$

For agent selection, the Oracle draws one sample $\hat{\theta}_i$ per candidate from each agent's posterior, recommends $\arg\max_i \hat{\theta}_i$, and records the sampled value as `oracle_recommendation_confidence`. The Beta posterior naturally encodes both the central tendency (win rate) and the uncertainty (sample size): an agent with $10$ wins and $0$ losses has a posterior centered near $1.0$ but with a wide tail, whereas an agent with $1000$ wins and $0$ losses is tightly concentrated. Thompson Sampling exploits this exploration/exploitation trade-off without manual tuning.

### 5.3 Domain-Specific ELO Routing

`agentic-telemetry-spec` partitions ratings by domain. The KoTH fragment carries a `koth_domain` constrained to `architecture | planning | editing | review | tooling | data | security | cross_cutting | null` (`schemas/goals/koth.schema.json` line 31). An agent excellent at editing may be mediocre at architecture; routing outcomes to per-domain Beta posteriors prevents averaging across these regimes. A `null` value falls through to the global rating pool.

### 5.4 The Oracle as Recommendation Interface

The Oracle is the read interface to the agent-rating state. When invoked, it samples the relevant per-domain Beta posteriors, identifies the highest sample, and returns `(oracle_recommended_agent, oracle_recommendation_confidence)`. These are recorded on the KoTH fragment at call time (`schemas/goals/koth.schema.json` lines 12-21). The `oracle_consulted` boolean is the gating flag: it is the only required field on the KoTH block (`schemas/goals/koth.schema.json` line 45), reflecting the fact that some Tier 1 and Tier 2 calls bypass the Oracle entirely.

### 5.5 Closing the Feedback Loop via `outcome_signal`

The `outcome_signal` field is the write interface. At `PreToolUse`, the ingestor sets it to `pending`. At `PostToolUse`, the ingestor updates it to `win`, `loss`, or `draw` based on the tool result (`schemas/telemetry/unified-activity-extensions.schema.json` line 67). This update is what drives the ELO and Beta posterior updates. The full lifecycle of a single `AskUserQuestion` agent-selection call is therefore:

1. Oracle samples Beta posteriors, returns recommendation.
2. `agentic-telemetry-spec` envelope is constructed with `oracle_consulted=true`, `oracle_recommended_agent`, `oracle_recommendation_confidence`, `agents_in_options`, and `outcome_signal=pending`.
3. User selects an agent.
4. `PostToolUse` updates `outcome_signal` to `win` for the selected agent (and `loss` records are derivable for the others from `agents_in_options`).
5. ELO and Beta posteriors update accordingly.

This loop is closed entirely within the schema-defined fields. No out-of-band signaling is required.

---

## 6. Backward Compatibility as a Schema Concern

Backward compatibility in `agentic-telemetry-spec` is not an implementation detail; it is its own design goal, with its own schema fragment, its own top-level key, and its own semver-gated migration provenance.

The pre-ATS baseline has three quirks the schema must accommodate. First, `AskUserQuestion` already carries a flat `source: string` field. Existing callers emit values like `"remember"`. Second, `TaskCreate` and `TaskUpdate` already have a `metadata` field, but it is user-data: arbitrary content owned by the calling code. Third, the remaining fifteen tools have no metadata at all.

`agentic-telemetry-spec` addresses each. The `source` string is preserved verbatim — the new `source` field at the root of the envelope uses the same key name and a backward-compatible string shape (`schemas/base/base-metadata.schema.json` lines 8-12). When a legacy caller is migrated, the original value is copied into `_compat.legacy_source` (`schemas/goals/backward-compat.schema.json` line 14), so no information is lost.

For `TaskCreate` and `TaskUpdate`, where `metadata` is a user-data field, ATS metadata is nested at `metadata._dgm` rather than at the top of `metadata` (`README.md` line 159). The telemetry ingestor must check both locations (`schemas/telemetry/unified-activity-extensions.schema.json` line 66). The `_dgm` prefix is a reserved namespace, signaling to downstream consumers and to users of the `metadata` field that this subtree is owned by the telemetry layer.

Migrated records carry an explicit migration record under `_compat.migrated_from`, including the source tool name, the old schema version (semver-constrained), and an ISO 8601 migration timestamp (`schemas/goals/backward-compat.schema.json` lines 17-37). The `is_legacy_compat` boolean lets telemetry filters distinguish "no metadata because old caller" from "intentionally minimal because Tier 3," which is essential for measuring adoption progress.

Finally, the `_compat.schema_version` field (`schemas/goals/backward-compat.schema.json` line 9) gates the entire envelope under semver. Future breaking changes to any goal fragment require a major-version bump, and the ingestor can route records through different parsing paths based on the version string.

---

## 7. Use Cases

### 7.1 Cross-Session Agent Comparability

A team running multiple Claude Code sessions across different developers wants to know which agent type produces the most accepted edits. Today, without standardized telemetry, this requires log-spelunking. With `agentic-telemetry-spec`, the team filters `unified-activity.jsonl` for records where `dgm.source` starts with `agent:`, joins to KoTH outcome records, and computes acceptance rates per `caller_name`. The `project_path_hash` provides anonymized project grouping. No agent-side instrumentation is needed beyond the metadata envelope.

### 7.2 Auditing Tool Invocations for Security Review

A security reviewer needs to know which actor — a user, a skill, a subagent, or a hook — initiated each `Bash` invocation in a session. Because `Bash` is a Tier 2 tool, every call carries a full `provenance` block including `caller_type`, `caller_name`, and a `caller_chain` from the outermost invocation inward (`schemas/goals/provenance.schema.json` lines 36-67). The reviewer can reconstruct the chain of trust for any individual command.

### 7.3 A/B Testing Prompt Template Variants

A prompt engineer wants to test whether adding Oracle-guided agent options to `AskUserQuestion` improves user satisfaction. They define an experiment `exp-oracle-guidance-2026-02` with two variants, `oracle-guided` and `random`. Each `AskUserQuestion` call carries the experiment fragment with `assignment_method` recording which variant was applied. The Tier 1 example in the repository demonstrates exactly this pattern (`examples/tier1-ask-user-question.json` lines 13-20). Downstream analytics partition outcomes by `variant_id` and apply standard A/B significance tests.

### 7.4 Reproducing a Session from Telemetry

An incident responder needs to reproduce a session that produced an unexpected result. The `provenance.session_id` field appears on every tool call, allowing the full sequence to be reconstructed in temporal order via `provenance.timestamp_utc`. Decision boundaries are recoverable from `decision.decision_id` and `decision.signal_type`. The chain of subagent spawns is recoverable from `provenance.agent_id` and `provenance.caller_chain`. The session is replayable from the telemetry stream alone.

---

## 8. Integration Guide

### 8.1 Minimum (Tier 3) Adoption

A caller adopting Tier 3 only needs four fields:

```json
{
  "source": "agent:code-explorer",
  "provenance": {
    "session_id": "123e4567-e89b-12d3-a456-426614174000",
    "caller_type": "agent",
    "caller_name": "code-explorer"
  }
}
```

This is the verbatim shape of `examples/tier3-read.json`. Any tool can adopt Tier 3 immediately by attaching this envelope to its `metadata` parameter.

### 8.2 Full (Tier 1) Adoption

A Tier 1 caller (`AskUserQuestion`, `Task`, `Skill`) populates all five blocks. The complete shape is shown in `examples/tier1-ask-user-question.json`. The minimum required additions over Tier 3 are the `koth` block (with `oracle_consulted` as the only required field, `schemas/goals/koth.schema.json` line 45) and the `decision` block (all fields optional, `schemas/goals/decision.schema.json`).

### 8.3 Validation with ajv

Every schema in the suite is JSON Schema draft 2020-12. Validation uses any compliant validator; `ajv` is the reference choice (`README.md` lines 167-174):

```bash
ajv validate \
  -s schemas/base/base-metadata.schema.json \
  -d examples/tier1-ask-user-question.json

ajv validate \
  -s schemas/telemetry/unified-activity-extensions.schema.json

for schema in schemas/**/*.schema.json; do
  ajv compile -s "$schema"
done
```

### 8.4 Integration Points

The schema suite is designed to plug into four downstream systems, named in the documentation with generic placeholders (`README.md` lines 117-124, `schemas/telemetry/unified-activity-extensions.schema.json` lines 10, 37, 65):

- `<your-telemetry-ingestor>` — a `PostToolUse` hook that extracts metadata into the persisted JSONL record via a `_dgm_fields()` function.
- `<your-decision-store>` — a JSONL store where each line is a `DecisionContext`. Joined to telemetry by `decision.decision_id`.
- `<your-elo-engine>` — a service that consumes `koth.outcome_signal` and `koth.agents_in_options` to update per-agent ELO and Beta posteriors.
- `<your-ab-runner>` — an analytics service that reads `experiment.experiment_id` and `variant_id` to compute variant-level outcome statistics.

`agentic-telemetry-spec` makes no assumptions about the implementation of these components. The schemas are the contract.

---

## 9. Related Work

**OpenTelemetry GenAI semantic conventions** define attributes for LLM spans — model name, token counts, latency, and recently a small set of tool-call attributes. They focus on the *LLM call* as the unit of observation. `agentic-telemetry-spec` operates one level up: the *tool call*, with caller chains, decision joins, and agent-selection signals that OTel GenAI does not model. The two are complementary, not overlapping.

**LangSmith** provides end-to-end tracing for LangChain applications and rich UI for trace inspection. Its data model is vendor-specific and emphasizes chain visualization. `agentic-telemetry-spec` is a vendor-neutral schema that any tracing tool — LangSmith included — could consume or emit. It does not provide a UI; it provides a contract.

**Weights & Biases Weave** focuses on logging LLM calls and evaluations into a managed backend. Like LangSmith, it is a product rather than an open schema. `agentic-telemetry-spec`'s composable goal fragments — particularly the KoTH fragment exposing Beta-distributed Thompson Sampling state — are not part of the Weave data model.

**Langfuse** is open-source and ships a documented data model for traces, observations, and scores. The closest overlap is around scoring, where Langfuse exposes a flexible numeric/categorical score per trace. `agentic-telemetry-spec`'s differentiation is the explicit treatment of agent performance through the `koth` fragment, the bidirectional decision-join key with positional `signal_type`, the proportional tier system, and the formally-versioned `_compat` block for backward-compatible adoption.

In short, the existing ecosystem covers *traces of LLM calls* well and *agent performance attribution* less well. `agentic-telemetry-spec` contributes a schema-first treatment of the latter, with explicit interoperability hooks for the former.

---

## 10. Contribution to the Open-Source AI Community

Standardized telemetry schemas matter for the open-source AI ecosystem for four reasons.

First, **reproducibility**. A session that emits only opaque action logs cannot be replayed. A session whose every tool call carries `session_id`, `caller_chain`, and timestamps can be reconstructed end-to-end from a flat JSONL stream. Reproducibility is the foundation for debugging, regression testing, and incident response.

Second, **interoperability**. As long as telemetry shapes are vendor-specific, every tool — every dashboard, every analytics pipeline, every evaluation harness — must be rewritten per provider. A shared JSON Schema contract decouples emitters from consumers. `agentic-telemetry-spec` is licensed Apache-2.0, the goal fragments are independently consumable, and the suite imposes no runtime dependency on the calling system.

Third, **auditability**. Provenance chains, decision joins, and backward-compatibility migration records collectively answer the question "what happened, who caused it, and why?" These are not optional concerns for systems deployed in regulated environments.

Fourth, **agent performance comparability**. As open-source agent catalogs grow, comparing agents across implementations requires a shared performance vocabulary. `agentic-telemetry-spec`'s KoTH fragment — ELO ratings, Beta-distributed posteriors, domain-routed outcomes — is a candidate shared vocabulary that can be adopted by any agent runtime.

---

## 11. Conclusion

`agentic-telemetry-spec` defines a unified JSON Schema suite for agentic AI telemetry, partitioned into five orthogonal design goals and composed into twenty-four per-tool schemas through a three-tier instrumentation model. The novel contribution is the schema-native treatment of agent performance through the KoTH/Oracle fragment, which places ELO ratings, Thompson Sampling Beta parameters, and outcome signals directly on the tool-call record rather than treating them as opaque downstream concerns. The backward-compatibility design — a dedicated `_compat` fragment, preservation of legacy source strings, reservation of the `metadata._dgm` namespace, and semver gating — addresses adoption in a way that established telemetry schemas typically do not.

Future work falls in three directions. **Multi-tenant isolation** is reserved as `tenant_id` columns in the companion database schema (`SCHEMA_DATABASE.md` line 526) and warrants first-class schema-level support. **Quartermaster (QM) integration** — linking tool calls to externally tracked work items via fields such as `qm_bead_id` (`docs/design-goals.md` lines 133-134) — would close the loop between telemetry and project management. **Additional language SDKs** beyond reference Python tooling — particularly TypeScript and Go bindings generated from the JSON Schemas — would broaden adoption.

The schemas are the contract. The implementation is open.

---

## References

All references are file paths within the `agentic-telemetry-spec` repository at version 1.0.0.

1. `README.md` — Repository overview, problem statement, applicability matrix.
2. `SCHEMA_DATABASE.md` — Relational database schema for telemetry persistence.
3. `SCHEMA_QUICK_REFERENCE.md` — One-page quick-reference for all five fragments.
4. `docs/design-goals.md` — Canonical seed schema and design rationale.
5. `docs/01-provenance.md` — Provenance companion document.
6. `docs/02-ab-testing.md` — A/B testing companion document.
7. `docs/03-koth-oracle.md` — KoTH/Oracle companion document.
8. `docs/04-decision-logger.md` — Decision Logger companion document.
9. `docs/05-backward-compat.md` — Backward compatibility companion document.
10. `schemas/base/base-metadata.schema.json` — Composable root schema.
11. `schemas/goals/provenance.schema.json` — Goal 1 fragment.
12. `schemas/goals/experiment.schema.json` — Goal 2 fragment.
13. `schemas/goals/koth.schema.json` — Goal 3 fragment.
14. `schemas/goals/decision.schema.json` — Goal 4 fragment.
15. `schemas/goals/backward-compat.schema.json` — Goal 5 fragment.
16. `schemas/telemetry/unified-activity-extensions.schema.json` — Persisted-record extension schema.
17. `schemas/tools/ask-user-question.schema.json` — Tier 1 reference tool schema.
18. `schemas/tools/bash.schema.json` — Tier 2 reference tool schema.
19. `schemas/tools/read.schema.json` — Tier 3 reference tool schema.
20. `examples/tier1-ask-user-question.json` — Tier 1 worked example.
21. `examples/tier2-bash.json` — Tier 2 worked example.
22. `examples/tier3-read.json` — Tier 3 worked example.
23. `LICENSE`, `NOTICE` — Apache-2.0 license and attribution.
24. `CHANGELOG.md` — Version history.
25. `CONTRIBUTING.md` — Contribution guidelines.
