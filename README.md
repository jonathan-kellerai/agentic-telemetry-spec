# Agentic Telemetry Spec — Metadata Schema Specification

> **Formal JSON Schema + companion docs for metadata on all 24 Claude Code primitives.**
> Enables provenance tracing, A/B testing, KOTH/Oracle attribution, decision joins, and backward-compatible migration.

---

## Problem

Today only 3 of 18 Claude Code tools carry metadata, and the unified telemetry hook ignores it entirely:

| Tool | Current State |
|------|--------------|
| `AskUserQuestion` | `{ source: string }` only |
| `TaskCreate` / `TaskUpdate` | Arbitrary object, no schema |
| All 15 other tools | No metadata support |

There is no standard way to trace a tool call to its caller, link it to a decision, or attribute its outcome to an agent's ELO rating.

---

## Solution

A unified metadata schema with 5 design goals, applied at 3 tiers based on tool significance:

### Design Goals

| # | Goal | Key | Description |
|---|------|-----|-------------|
| 1 | Provenance | `provenance` | Trace every call: session → agent → skill/hook → tool |
| 2 | A/B Testing | `experiment` | Named variants + experiment assignment |
| 3 | KOTH/Oracle | `koth` | ELO win/loss signals + Oracle recommendation context |
| 4 | Decision Logger | `decision` | Join key to `DecisionContext` in `<your-decision-store>.jsonl` |
| 5 | Backward Compat | `_compat` | Legacy `source` string remains parseable |

### Tool Tiers

| Tier | Tools | Goals Applied |
|------|-------|--------------|
| **1 — Full** | `AskUserQuestion`, `Task`, `Skill` | All 5 |
| **2 — Partial** | `Bash`, `Write`, `Edit`, `SendMessage`, `EnterPlanMode`, `ExitPlanMode` | Provenance + KOTH + Decision |
| **3 — Minimal** | `Read`, `Glob`, `Grep`, `WebSearch`, `WebFetch`, `TaskCreate`, `TaskUpdate`, `TaskList`, `TaskGet`, `TeamCreate`, `TeamDelete`, `ToolSearch`, `NotebookEdit`, `TaskOutput`, `TaskStop` | Provenance only |

---

## Directory Structure

```text
agentic-telemetry-spec/
├── schemas/
│   ├── base/
│   │   └── base-metadata.schema.json    # Extensible base all tools inherit
│   ├── goals/
│   │   ├── provenance.schema.json       # Goal 1: Caller identity chain
│   │   ├── experiment.schema.json       # Goal 2: A/B test context
│   │   ├── koth.schema.json             # Goal 3: ELO/Oracle signals
│   │   ├── decision.schema.json         # Goal 4: Decision Logger join
│   │   └── backward-compat.schema.json  # Goal 5: Legacy compatibility
│   ├── tools/
│   │   ├── ask-user-question.schema.json
│   │   ├── task.schema.json
│   │   ├── skill.schema.json
│   │   ├── bash.schema.json
│   │   ├── write.schema.json
│   │   ├── edit.schema.json
│   │   └── ...  (24 tool schemas total)
│   └── telemetry/
│       └── unified-activity-extensions.schema.json
├── docs/
│   ├── design-goals.md                  # Seed schema + design rationale
│   ├── 01-provenance.md                 # Goal 1 companion doc
│   ├── 02-ab-testing.md                 # Goal 2 companion doc
│   ├── 03-koth-oracle.md                # Goal 3 companion doc
│   ├── 04-decision-logger.md            # Goal 4 companion doc
│   └── 05-backward-compat.md            # Goal 5 companion doc
└── examples/
    ├── tier1-ask-user-question.json     # Full metadata example
    ├── tier2-bash.json                  # Partial metadata example
    └── tier3-read.json                  # Minimal metadata example
```

---

## Architecture

```text
Claude Code Tool Call
       │
       ▼
  Tool Metadata
  {
    source: "skill:feature-dev:feature-dev",   ← shared across all tiers
    provenance: { ... },                        ← Tier 3+
    experiment: { ... },                        ← Tier 1 only
    koth: { ... },                              ← Tier 1 + 2
    decision: { ... },                          ← Tier 1 + 2
  }
       │
       ▼
  <your-telemetry-ingestor>                          ← PostToolUse hook
  _base_record() + new _dgm_fields()
       │
       ▼
  unified-activity.jsonl                      ← Telemetry record
  { ...existing_fields, dgm: { ... } }
       │
       ├─► <your-decision-store>.jsonl               ← Decision Logger join
       ├─► <your-elo-engine> (KOTH ratings)       ← Agent ELO updates
       └─► <your-ab-runner> (A/B results)         ← Experiment analytics
```

---

## Integration Points

| System | Integration |
|--------|------------|
| `<your-telemetry-ingestor>` | New `_dgm_fields()` function extracts metadata into telemetry record |
| `unified-activity.schema.json` | Extended by `unified-activity-extensions.schema.json` (non-breaking) |
| `<your-elo-engine>` | Reads `koth.agents_in_options` + response to compute win/loss signals |
| `<your-ab-runner>` | Reads `experiment.experiment_id` + `variant_id` for A/B match extraction |
| `<your-decision-store>` | Reads `decision.decision_id` to link tool calls to `DecisionContext` |

---

## Complete Tool Applicability Matrix

| Tool | Tier | source | provenance | experiment | koth | decision | _compat | Schema File |
|------|------|--------|-----------|-----------|------|----------|---------|-------------|
| `AskUserQuestion` | 1 | ✅ req | ✅ req | ⭕ opt | ✅ req | ✅ req | ⭕ opt | `tools/ask-user-question.schema.json` |
| `Task` | 1 | ✅ req | ✅ req | ⭕ opt | ✅ req | ✅ req | ⭕ opt | `tools/task.schema.json` |
| `Skill` | 1 | ✅ req | ✅ req | ⭕ opt | ✅ req | ✅ req | ⭕ opt | `tools/skill.schema.json` |
| `Bash` | 2 | ✅ req | ✅ req | ❌ n/a | ⭕ opt | ⭕ opt | ❌ n/a | `tools/bash.schema.json` |
| `Write` | 2 | ✅ req | ✅ req | ❌ n/a | ⭕ opt | ⭕ opt | ❌ n/a | `tools/write.schema.json` |
| `Edit` | 2 | ✅ req | ✅ req | ❌ n/a | ⭕ opt | ⭕ opt | ❌ n/a | `tools/edit.schema.json` |
| `SendMessage` | 2 | ✅ req | ✅ req | ❌ n/a | ⭕ opt | ⭕ opt | ❌ n/a | `tools/send-message.schema.json` |
| `EnterPlanMode` | 2 | ✅ req | ✅ req | ❌ n/a | ⭕ opt | ⭕ opt | ❌ n/a | `tools/enter-plan-mode.schema.json` |
| `ExitPlanMode` | 2 | ✅ req | ✅ req | ❌ n/a | ⭕ opt | ⭕ opt | ❌ n/a | `tools/exit-plan-mode.schema.json` |
| `Read` | 3 | ✅ req | ✅ req | ❌ n/a | ❌ n/a | ❌ n/a | ❌ n/a | `tools/read.schema.json` |
| `Glob` | 3 | ✅ req | ✅ req | ❌ n/a | ❌ n/a | ❌ n/a | ❌ n/a | `tools/glob.schema.json` |
| `Grep` | 3 | ✅ req | ✅ req | ❌ n/a | ❌ n/a | ❌ n/a | ❌ n/a | `tools/grep.schema.json` |
| `WebSearch` | 3 | ✅ req | ✅ req | ❌ n/a | ❌ n/a | ❌ n/a | ❌ n/a | `tools/web-search.schema.json` |
| `WebFetch` | 3 | ✅ req | ✅ req | ❌ n/a | ❌ n/a | ❌ n/a | ❌ n/a | `tools/web-fetch.schema.json` |
| `TaskCreate` ⚠️ | 3 | ✅ req | ✅ req | ❌ n/a | ❌ n/a | ❌ n/a | ❌ n/a | `tools/task-create.schema.json` |
| `TaskUpdate` ⚠️ | 3 | ✅ req | ✅ req | ❌ n/a | ❌ n/a | ❌ n/a | ❌ n/a | `tools/task-update.schema.json` |
| `TaskList` | 3 | ✅ req | ✅ req | ❌ n/a | ❌ n/a | ❌ n/a | ❌ n/a | `tools/task-list.schema.json` |
| `TaskGet` | 3 | ✅ req | ✅ req | ❌ n/a | ❌ n/a | ❌ n/a | ❌ n/a | `tools/task-get.schema.json` |
| `TeamCreate` | 3 | ✅ req | ✅ req | ❌ n/a | ❌ n/a | ❌ n/a | ❌ n/a | `tools/team-create.schema.json` |
| `TeamDelete` | 3 | ✅ req | ✅ req | ❌ n/a | ❌ n/a | ❌ n/a | ❌ n/a | `tools/team-delete.schema.json` |
| `ToolSearch` | 3 | ✅ req | ✅ req | ❌ n/a | ❌ n/a | ❌ n/a | ❌ n/a | `tools/tool-search.schema.json` |
| `NotebookEdit` | 3 | ✅ req | ✅ req | ❌ n/a | ❌ n/a | ❌ n/a | ❌ n/a | `tools/notebook-edit.schema.json` |
| `TaskOutput` | 3 | ✅ req | ✅ req | ❌ n/a | ❌ n/a | ❌ n/a | ❌ n/a | `tools/task-output.schema.json` |
| `TaskStop` | 3 | ✅ req | ✅ req | ❌ n/a | ❌ n/a | ❌ n/a | ❌ n/a | `tools/task-stop.schema.json` |

**Legend**: ✅ req = required, ⭕ opt = optional, ❌ n/a = not applicable (omit)

⚠️ **TaskCreate / TaskUpdate collision**: These tools use `metadata` as a user-data field. ATS metadata nests at `metadata._dgm` — not at the top level of the metadata object. See `docs/05-backward-compat.md`.

---

## Validation

```bash
# Validate all schemas against JSON Schema draft 2020-12
ajv validate --spec=draft2020 --strict=false -s schemas/base/base-metadata.schema.json -d examples/tier1-ask-user-question.json

# Validate telemetry extension compatibility
ajv validate --spec=draft2020 --strict=false -s schemas/telemetry/unified-activity-extensions.schema.json

# Run all validations
for schema in schemas/**/*.schema.json; do ajv compile --spec=draft2020 --strict=false -s "$schema"; done
```

---

## Status

| Phase | Status | Description |
|-------|--------|-------------|
| 0 | Complete | Repo init, base schema, seed docs |
| 1 | Complete | 5 goal schemas + companion docs |
| 2 | Complete | Per-tool schema composition (24 tool schemas) |
| 3 | Complete | Telemetry extension, examples, v0.1.0 public release |

---

## Contributing

Each design goal has a dedicated researcher. Schema fragments live in `schemas/goals/`.
Base schema at `schemas/base/base-metadata.schema.json` defines namespace boundaries.
See `docs/design-goals.md` for the complete seed schema and rationale.

---

### For agents

Agents reading this repo should start at [AGENTS.md](AGENTS.md), not this README.
Claude Code users: see [CLAUDE.md](CLAUDE.md), which imports `AGENTS.md`. The
agent files document the conventions, vocabulary, and contribution discipline
agents are expected to follow.
