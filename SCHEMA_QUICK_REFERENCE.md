# ATS Database Schema — Quick Reference

## Core Tables (10 primary)

| Table | Purpose | Key Fields | Tier |
|-------|---------|-----------|------|
| `sessions` | Track Claude Code session lifecycle | `session_id`, `project_path_hash`, `started_at` | All |
| `agents` | Register skills, agents, hooks, main orchestrator | `agent_id`, `agent_type`, `fully_qualified_name` | All |
| `activity_records` | Primary telemetry records (extends unified-activity.jsonl) | `activity_id`, `session_id`, `tool_name`, `tool_tier`, `invoked_at` | All |
| `provenance` | Caller identity chains for traceability | `provenance_id`, `activity_id`, `caller_type`, `caller_name` | All (Tier 3+) |
| `provenance_caller_chain` | Parent callers in nested invocation hierarchy | `chain_id`, `depth`, `caller_type` | All |
| `entities` | Privacy-preserving project identification | `entity_id` (hash), `first_seen`, `total_sessions` | All |
| `koth_outcomes` | Win/loss signals from individual tool invocations | `outcome_id`, `activity_id`, `outcome_signal`, `outcome_timestamp` | Tier 1–2 |
| `koth_ratings` | ELO ratings + Thompson Sampling for agents | `rating_id`, `agent_id`, `elo_rating`, `alpha`, `beta` | Tier 1–2 |
| `decisions` | Decision context records + decision tree support | `decision_id`, `session_id`, `intent_classification`, `parent_decision_id` | Tier 1–2 |
| `decision_tool_calls` | Links tool calls to decisions | `call_id`, `decision_id`, `activity_id`, `signal_type` | Tier 1–2 |

## A/B Testing Tables (3)

| Table | Purpose | Key Join | Tier |
|-------|---------|----------|------|
| `experiments` | Named A/B test contexts | `experiment_id` | Tier 1 |
| `experiment_variants` | Treatment variants within experiment | `variant_id` | Tier 1 |
| `experiment_assignments` | Individual tool call → variant assignments | `activity_id` ↔ `variant_id` | Tier 1 |

## KOTH/Oracle Support (3 tables)

| Table | Purpose | Key Join | Tier |
|-------|---------|----------|------|
| `koth_ratings` | Agent ELO + Thompson Sampling | `agent_id` → `agents` | Tier 1–2 |
| `koth_outcomes` | Win/loss/draw signals | `activity_id` → `activity_records` | Tier 1–2 |
| `koth_agent_options` | Agent selection training data | `outcome_id` → `koth_outcomes` | Tier 1 |

## Supporting Tables (3)

| Table | Purpose | Key Join | Use Case |
|-------|---------|----------|----------|
| `tier_transitions` | Track adoption from legacy to ATS | `session_id` | Telemetry adoption metrics |
| `legacy_metadata` | Backward compatibility mappings | `activity_id` | Migration support |
| (Materialized Views) | Analytics summaries | Various | Reporting + dashboards |

---

## Critical Joins

### Join 1: Decision Logger (Decision ↔ Activity)

```text
decisions.decision_id ↔ decision_tool_calls.decision_id ↔ decision_tool_calls.activity_id ↔ activity_records.activity_id
```

**Purpose**: Trace which tool calls informed / executed a decision
**Use Case**: Decision tree reconstruction, decision-driven ELO updates

### Join 2: KOTH Ratings (Activity ↔ Agent ↔ Rating)

```text
activity_records.activity_id ↔ koth_outcomes.activity_id ↔ koth_outcomes.outcome_signal
activity_records.source_caller_name ↔ agents.fully_qualified_name ↔ koth_ratings.agent_id
```

**Purpose**: Map tool outcomes to agent ELO changes
**Use Case**: Agent performance evolution, Oracle recommendation calibration

### Join 3: A/B Testing (Activity ↔ Experiment)

```text
activity_records.activity_id ↔ experiment_assignments.activity_id ↔ experiment_variants.variant_id ↔ experiments.experiment_id
```

**Purpose**: Segment outcomes by experiment variant
**Use Case**: A/B result analysis, template iteration

### Join 4: Provenance Chain (Activity → Session → Entity)

```text
activity_records.activity_id ↔ provenance.activity_id → provenance.session_id → sessions.session_id
sessions.project_path_hash ↔ entities.entity_id
```

**Purpose**: Full request traceability from activity → session → project
**Use Case**: Per-project metrics, entity memory joins

---

## Tier Distribution

### Tier 1 (Full) — 3 Tools

All 5 goals: Provenance + Experiment + KOTH + Decision + Compat

- **Tools**: AskUserQuestion, Task, Skill
- **Tables**: activity_records + provenance + experiment_assignments + koth_outcomes + legacy_metadata

### Tier 2 (Partial) — 6 Tools

Provenance + KOTH + Decision (no A/B testing)

- **Tools**: Bash, Write, Edit, SendMessage, EnterPlanMode, ExitPlanMode
- **Tables**: activity_records + provenance + koth_outcomes + decision_tool_calls

### Tier 3 (Minimal) — 9 Tools

Provenance only

- **Tools**: Read, Glob, Grep, WebSearch, WebFetch, TaskCreate, TaskUpdate, TaskList, TaskGet, TeamCreate, TeamDelete, ToolSearch, NotebookEdit, TaskOutput, TaskStop
- **Tables**: activity_records + provenance

---

## Query Patterns & Recommended Indexes

### Pattern 1: Recent Activity by Agent

```sql
SELECT * FROM activity_records
  JOIN provenance USING (activity_id)
WHERE source_caller_name = 'morphllm:code-editor'
  AND invoked_at > NOW() - INTERVAL '1 day'
ORDER BY invoked_at DESC
LIMIT 100;
```

**Indexes**: `activity_records(invoked_at DESC)`, `provenance(activity_id)`

### Pattern 2: Agent ELO Evolution

```sql
SELECT
  kr.agent_id, kr.domain, kr.elo_rating,
  kr.wins, kr.losses, kr.alpha, kr.beta,
  ko.outcome_timestamp
FROM koth_ratings kr
  LEFT JOIN koth_outcomes ko ON ...
WHERE kr.agent_id = $1
  AND kr.domain = 'editing'
ORDER BY ko.outcome_timestamp DESC;
```

**Indexes**: `koth_ratings(agent_id, domain)`, `koth_outcomes(activity_id)`

### Pattern 3: Decision Tree Reconstruction

```sql
WITH RECURSIVE decision_tree AS (
  SELECT * FROM decisions WHERE decision_id = $1
  UNION ALL
  SELECT d.* FROM decisions d
    JOIN decision_tree dt ON d.parent_decision_id = dt.decision_id
)
SELECT * FROM decision_tree
  LEFT JOIN decision_tool_calls USING (decision_id)
  LEFT JOIN activity_records USING (activity_id)
ORDER BY decision_depth, signal_type;
```

**Indexes**: `decisions(decision_id, parent_decision_id)`, `decision_tool_calls(decision_id)`

### Pattern 4: Experiment Results by Variant

```sql
SELECT
  ev.variant_key,
  COUNT(DISTINCT ea.activity_id) as assignments,
  SUM(CASE WHEN ko.outcome_signal = 'win' THEN 1 ELSE 0 END) as wins,
  SUM(CASE WHEN ko.outcome_signal = 'loss' THEN 1 ELSE 0 END) as losses,
  ROUND(100.0 * SUM(CASE WHEN ko.outcome_signal = 'win' THEN 1 ELSE 0 END) / COUNT(DISTINCT ea.activity_id), 2) as win_rate
FROM experiment_variants ev
  LEFT JOIN experiment_assignments ea USING (variant_id)
  LEFT JOIN koth_outcomes ko USING (activity_id)
WHERE ev.experiment_id = $1
GROUP BY ev.variant_id, ev.variant_key;
```

**Indexes**: `experiment_assignments(variant_id)`, `koth_outcomes(activity_id)`

---

## Data Volume Estimates (Annual, 1000 concurrent sessions)

| Table | Rows/Year | Growth | Notes |
| ----- | --------- | ------ | ----- |
| `sessions` | ~100K | ~1.1 sessions/min avg | 10–100K concurrent |
| `activity_records` | ~10M | ~1150 calls/min avg | 18 tools × ~60 calls/session |
| `provenance` | ~10M | Parallel to activity_records | One per activity |
| `provenance_caller_chain` | ~5M | ~0.5 per activity avg | Average 2–3 levels |
| `agents` | ~500 | Slow growth | New skills/agents added gradually |
| `koth_outcomes` | ~5M | ~50% of all activities | Tier 1–2 tools only |
| `koth_ratings` | ~5K | Slow growth | per (agent, domain) pair |
| `decisions` | ~1M | ~10% of activity_records | 1 decision per ~10 activities |
| `decision_tool_calls` | ~3M | ~3 tool calls per decision avg | Pre + post + outcome |
| `experiment_assignments` | ~500K | ~5% of Tier 1 calls | A/B testing subset |
| `experiments` | ~100 | Slow growth | New tests per quarter |

**Disk Usage**: ~150–200 GB (indexes + data + replication) for annual historical data

---

## Schema Maintenance

### Monitoring Queries

1. **Check data freshness**:

   ```sql
   SELECT MAX(invoked_at) as latest_activity, NOW() - MAX(invoked_at) as lag
   FROM activity_records;
   ```

2. **Monitor table sizes**:

   ```sql
   SELECT schemaname, tablename, pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename))
   FROM pg_tables
   WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
   ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
   ```

3. **Check index efficiency**:

   ```sql
   SELECT schemaname, tablename, indexname, idx_scan, idx_tup_read, idx_tup_fetch
   FROM pg_stat_user_indexes
   ORDER BY idx_scan DESC;
   ```

### Maintenance Tasks

- **Vacuum**: Weekly on active tables (activity_records, koth_outcomes, decisions)
- **Reindex**: Monthly on high-cardinality columns
- **Partition**: Monthly rotation for time-series tables
- **Refresh materialized views**: Every 5–10 minutes (automated)

---

## Security & Privacy

### Sensitive Data Handling

- **Passwords, API keys**: Never stored in activity_records.tool_input/tool_result (filter upstream)
- **Project paths**: Hashed to 8-char SHA256 in `project_path_hash` + `entities.entity_id`
- **Session IDs**: UUIDs only, no correlation to user identity
- **Agent names**: Fully qualified but non-identifying (e.g., "morphllm:code-editor")

### Access Control

- Activity records: Read by analytics team, write by `your-telemetry-ingestor` only
- Decisions: Read by `your-decision-store`, write by `your-decision-store`
- KOTH ratings: Read by Oracle + agents, write by `your-elo-engine` only
- Experiments: Read by `your-ab-runner`, write by `your-ab-runner`
- Legacy metadata: Read-only archive, no updates

---

## Backward Compatibility

### Legacy Caller Handling

Pre-ATS callers with only `source` string field:

1. Detected by `legacy_metadata.is_legacy_compat = TRUE`
2. Source string parsed into `provenance` fields
3. Tier computed as 3 (minimal provenance)
4. Tracked in `tier_transitions` for adoption metrics

### Migration Path

```text
Legacy source string
  ↓ (parse by <your-telemetry-ingestor>)
  ↓
ATS provenance block
  ↓ (extract by _dgm_fields())
  ↓
activity_records.dgm.provenance
  ↓ (backfill if needed)
  ↓
provenance table
```
