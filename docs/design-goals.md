# Agentic Telemetry Spec — Design Goals & Seed Schema

> **Source**: Designed in design session `123e4567-e89b-12d3-a456-426614174000`
> **Date**: 2026-02-19
> **Status**: Seed — extended by per-goal researchers in Phase 1

---

## Overview

Today only 3 of 18 Claude Code tools carry metadata:

| Tool | Current Metadata |
|------|-----------------|
| `AskUserQuestion` | `{ source: string }` |
| `TaskCreate` | arbitrary object |
| `TaskUpdate` | arbitrary object |

The unified telemetry hook (`<your-telemetry-ingestor>`) ignores metadata entirely. There is no standard way to:

- Trace a tool call back to its caller
- Link it to a decision in `<your-decision-store>.jsonl`
- Attribute its outcome to an agent's ELO rating
- A/B test different tool invocation strategies

This specification defines a unified metadata schema for every Claude Code primitive.

---

## Design Goals

### 1. Provenance

Trace every tool call to its caller: `session → agent → skill/hook → tool`.

### 2. A/B Testing

Track named template variants and measure option presentation effects across tool invocations.

### 3. KOTH/Oracle Integration

Connect tool outcomes to agent ELO ratings (King-of-the-Hill) and Thompson Sampling updates via Oracle.

### 4. Decision Logger Join

Link tool calls to the `DecisionContext` that triggered them via bidirectional join keys.

### 5. Backward Compatibility

The existing `source: string` field on `AskUserQuestion` remains parseable. All new fields are optional. No breaking changes to tools that already emit metadata.

---

## Seed Schema: AskUserQuestion Metadata

The full metadata object designed as a reference for all 18 tools:

```json
{
  "metadata": {

    // ── Provenance (identity of the caller) ─────────────────────────────────
    "source": "skill:feature-dev:feature-dev",
    // Format: "{caller_type}:{caller_name}"
    // caller_type enum: "skill" | "agent" | "hook" | "main"
    // Examples:
    //   "skill:feature-dev:feature-dev"     (skill name as plugin:skill)
    //   "agent:code-architect"              (subagent by type)
    //   "hook:UserPromptSubmit"             (hook event that fired it)
    //   "main:orchestrator"                 (top-level session)

    "caller_agent_id": "ae02e3e-...",
    // UUID of the agent instance — matches agent_id in SubagentStart/Stop events.
    // Enables exact join across unified-activity records within a session.
    // Null for main orchestrator (not a subagent).

    "caller_skill": "feature-dev:feature-dev",
    // Fully-qualified skill name if a skill is the immediate caller.
    // Null if called from an agent body, hook, or main.

    // ── Template / A/B Testing ──────────────────────────────────────────────
    "template_id": "arch-decision-v1",
    // Named question template. Null for ad-hoc questions.
    // Enables grouping "same question, different variants" for A/B analysis.

    "template_version": "1.2.0",
    // Semver of the template. Bump to test revised option framing or ordering.
    // Null for ad-hoc questions.

    "experiment_id": "exp-markdown-preview-2026-02",
    // Active A/B experiment this call participates in.
    // Null if not part of a controlled experiment.
    // Maps to source_weights.ab_testing in KOTH config.

    "variant_id": "markdown-enabled",
    // Which variant within the experiment.
    // e.g. "markdown-enabled" vs "text-only" for testing preview panel impact.
    // Null if not part of a controlled experiment.

    // ── Question Classification (for KOTH domain routing) ───────────────────
    "question_type": "architecture",
    // Primary type of decision being asked.
    // enum: "architecture" | "approval" | "feature_selection" | "binary_choice"
    //       | "priority" | "config" | "workflow" | "tooling" | "naming"

    "decision_domain": "backend",
    // Domain for KOTH subcategory routing.
    // enum: "frontend" | "backend" | "devops" | "planning" | "tooling"
    //       | "data" | "security" | "cross_cutting"

    // ── Decision Logger Integration ──────────────────────────────────────────
    "decision_id": "dec_20260219_143022_123456",
    // ID of the DecisionContext in <your-decision-store>.jsonl that triggered this call.
    // Enables bidirectional join: Decision → Question → Outcome → ELO update.
    // Null if no active decision context.

    "intent_classification": "planning",
    // Mirrors DecisionContext.intent_classification.
    // enum: "exploration" | "editing" | "review" | "planning" | "autonomous"

    // ── Oracle / KOTH Context ────────────────────────────────────────────────
    "oracle_consulted": true,
    // Was Oracle queried before constructing these options?
    // When true, oracle_recommended_agent and recommendation_confidence are expected.

    "oracle_recommended_agent": "morphllm:code-editor",
    // Oracle's top recommendation at call time (null if oracle_consulted=false).

    "oracle_recommendation_confidence": 0.82,
    // Oracle's confidence score [0,1] (null if oracle_consulted=false).

    "koth_agents_in_options": ["morphllm:code-editor", "general-purpose"],
    // Agent names appearing as options — null if not an agent-selection question.
    // Used post-response to feed win/loss signals back to KOTH ELO ratings.
    // The selected agent gets a "win"; unselected get "losses".
    // Maps to source_weights.ab_testing (1.5x weight, more trusted than telemetry).

    // ── QM / Quartermaster Context ───────────────────────────────────────────
    "qm_bead_id": "keller-graph-app-3f9",
    // Active beads issue this question relates to (null if none).
    // Enables QM outcome tracking: did this question precede task completion?

    "project_path_hash": "a3f9b2c1"
    // First 8 chars of SHA256(project_path) — for entity memory joins without
    // exposing absolute paths in telemetry.
    // Matches EntityMemory.entity_id hashing pattern in <your-decision-store>.
  }
}
```

---

## Tool Tier Classification

### Tier 1 — Full Metadata (All 5 Goals)

Tools that represent significant decisions with measurable outcomes:

- `AskUserQuestion` — user decision with selectable options
- `Task` — spawns a subagent (agent selection = KOTH signal)
- `Skill` — invokes a named skill (skill selection = KOTH signal)

### Tier 2 — Partial Metadata (Provenance + KOTH outcome + Decision join)

Tools that execute consequential actions:

- `Bash`, `Write`, `Edit`, `SendMessage`, `EnterPlanMode`, `ExitPlanMode`

### Tier 3 — Minimal Metadata (Provenance only + `source` string)

High-frequency read/query tools — metadata bloat risk:

- `Read`, `Glob`, `Grep`, `WebSearch`, `WebFetch`
- `TaskCreate`, `TaskUpdate`, `TaskList`, `TaskGet`
- `TeamCreate`, `TeamDelete`, `ToolSearch`
- `NotebookEdit`, `TaskOutput`, `TaskStop`

---

## Key Namespace Boundaries

Each design goal owns one top-level key in the metadata object:

| Goal | Key | Owner Researcher |
|------|-----|-----------------|
| Provenance | `provenance` | provenance-researcher |
| A/B Testing | `experiment` | ab-testing-researcher |
| KOTH/Oracle | `koth` | koth-oracle-researcher |
| Decision Logger | `decision` | decision-logger-researcher |
| Backward Compat | `_compat` | backward-compat-researcher |

The flat `source` string key is shared across all tiers (Tier 3 minimum).
