# ATS Evolution Telemetry — Database Schema

> **Complete relational database schema for supporting the full suite of ATS metadata across all 18 Claude Code tools, enabling provenance tracing, A/B testing, KOTH/Oracle attribution, decision joins, and agent performance evolution.**

---

## Core Entities

### 1. Sessions

Tracks Claude Code sessions and their telemetry lifecycle.

```sql
CREATE TABLE sessions (
  session_id UUID PRIMARY KEY,
  started_at TIMESTAMP WITH TIME ZONE NOT NULL,
  ended_at TIMESTAMP WITH TIME ZONE,
  project_path_hash VARCHAR(8),  -- SHA256(project_path)[0:8], nullable for hook-level calls
  session_status VARCHAR(32) NOT NULL DEFAULT 'active',  -- active | completed | errored
  total_tool_calls INT DEFAULT 0,
  tier1_calls INT DEFAULT 0,
  tier2_calls INT DEFAULT 0,
  tier3_calls INT DEFAULT 0,
  has_legacy_compat BOOLEAN DEFAULT FALSE,

  CONSTRAINT valid_hash CHECK (project_path_hash IS NULL OR project_path_hash ~ '^[0-9a-f]{8}$')
);

CREATE INDEX idx_sessions_started ON sessions(started_at DESC);
CREATE INDEX idx_sessions_project ON sessions(project_path_hash);
```

### 2. Agents

Registered agents, skills, hooks, and the main orchestrator.

```sql
CREATE TABLE agents (
  agent_id UUID PRIMARY KEY,
  agent_type VARCHAR(32) NOT NULL,  -- skill | agent | hook | main
  fully_qualified_name VARCHAR(255) NOT NULL,  -- e.g., "feature-dev:feature-dev", "code-architect", "UserPromptSubmit"
  plugin_namespace VARCHAR(255),  -- e.g., "feature-dev:feature-dev", NULL for main/hooks
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT valid_agent_type CHECK (agent_type IN ('skill', 'agent', 'hook', 'main')),
  UNIQUE(agent_type, fully_qualified_name)
);

CREATE INDEX idx_agents_type ON agents(agent_type);
CREATE INDEX idx_agents_name ON agents(fully_qualified_name);
```

### 3. Tool Calls (Activity Records)

Core telemetry records — extends unified_activity.jsonl with ATS metadata.

```sql
CREATE TABLE activity_records (
  activity_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES sessions(session_id) ON DELETE CASCADE,
  tool_name VARCHAR(64) NOT NULL,  -- AskUserQuestion, Bash, Edit, Read, etc.
  tool_tier INT NOT NULL,  -- 1 | 2 | 3
  invoked_at TIMESTAMP WITH TIME ZONE NOT NULL,
  completed_at TIMESTAMP WITH TIME ZONE,

  -- Base metadata (all tiers)
  source_caller_type VARCHAR(32) NOT NULL,  -- skill | agent | hook | main
  source_caller_name VARCHAR(255) NOT NULL,  -- Fully-qualified name

  -- Tool input/output (unified_activity base fields)
  tool_input JSONB,
  tool_result JSONB,
  tool_status VARCHAR(32),  -- success | error | timeout

  -- ATS fields (conditional by tier)
  ats_source VARCHAR(255),  -- Format: {caller_type}:{caller_name}
  ats_tier INT NOT NULL,  -- Computed from which goal blocks present
  ats_has_legacy_compat BOOLEAN DEFAULT FALSE,

  CONSTRAINT valid_tier CHECK (tool_tier IN (1, 2, 3)),
  CONSTRAINT valid_ats_tier CHECK (ats_tier IN (1, 2, 3))
);

CREATE INDEX idx_activity_session ON activity_records(session_id);
CREATE INDEX idx_activity_invoked ON activity_records(invoked_at DESC);
CREATE INDEX idx_activity_tool ON activity_records(tool_name);
CREATE INDEX idx_activity_tier ON activity_records(tool_tier);
```

### 4. Provenance Chains

Caller identity chains for request traceability.

```sql
CREATE TABLE provenance (
  provenance_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  activity_id UUID NOT NULL REFERENCES activity_records(activity_id) ON DELETE CASCADE,
  session_id UUID NOT NULL REFERENCES sessions(session_id) ON DELETE CASCADE,

  caller_type VARCHAR(32) NOT NULL,  -- skill | agent | hook | main
  caller_name VARCHAR(255) NOT NULL,
  caller_agent_id UUID REFERENCES agents(agent_id) ON DELETE SET NULL,

  project_path_hash VARCHAR(8),  -- First 8 chars of SHA256(project_path)
  timestamp_utc TIMESTAMP WITH TIME ZONE,

  -- Caller chain (parent callers from outermost to immediate)
  caller_chain_depth INT DEFAULT 0,

  CONSTRAINT valid_hash CHECK (project_path_hash IS NULL OR project_path_hash ~ '^[0-9a-f]{8}$'),
  CONSTRAINT valid_type CHECK (caller_type IN ('skill', 'agent', 'hook', 'main'))
);

CREATE INDEX idx_provenance_activity ON provenance(activity_id);
CREATE INDEX idx_provenance_session ON provenance(session_id);
CREATE INDEX idx_provenance_agent ON provenance(caller_agent_id);
```

### 5. Provenance Caller Chain

Parent callers in invocation hierarchy.

```sql
CREATE TABLE provenance_caller_chain (
  chain_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  provenance_id UUID NOT NULL REFERENCES provenance(provenance_id) ON DELETE CASCADE,
  depth INT NOT NULL,  -- 0 = outermost, increments toward immediate

  caller_type VARCHAR(32) NOT NULL,
  caller_name VARCHAR(255) NOT NULL,
  agent_id UUID REFERENCES agents(agent_id) ON DELETE SET NULL,

  CONSTRAINT valid_type CHECK (caller_type IN ('skill', 'agent', 'hook', 'main'))
);

CREATE INDEX idx_chain_provenance ON provenance_caller_chain(provenance_id);
CREATE INDEX idx_chain_depth ON provenance_caller_chain(provenance_id, depth);
```

### 6. Projects / Entities

Privacy-preserving project identification for cross-session entity memory.

```sql
CREATE TABLE entities (
  entity_id VARCHAR(8) PRIMARY KEY,  -- First 8 chars of SHA256(project_path)
  project_path_hash VARCHAR(8) NOT NULL,  -- Same as entity_id, normalized
  first_seen TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_seen TIMESTAMP WITH TIME ZONE,

  total_sessions INT DEFAULT 0,
  total_tool_calls INT DEFAULT 0,
  avg_calls_per_session NUMERIC(8, 2),

  CONSTRAINT valid_hash CHECK (project_path_hash ~ '^[0-9a-f]{8}$')
);

CREATE INDEX idx_entities_first_seen ON entities(first_seen DESC);
```

---

## KOTH/Oracle Integration (Tier 1 & 2)

### 7. KOTH — Agent Performance Ratings

ELO ratings and Thompson Sampling scores for agent selection.

```sql
CREATE TABLE koth_ratings (
  rating_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  agent_id UUID NOT NULL REFERENCES agents(agent_id) ON DELETE CASCADE,

  domain VARCHAR(64),  -- NULL = global, or: architecture | planning | editing | review | tooling | data | security | cross_cutting

  elo_rating NUMERIC(6, 1) NOT NULL DEFAULT 1500,  -- Standard ELO starting point
  wins INT DEFAULT 0,
  losses INT DEFAULT 0,
  draws INT DEFAULT 0,

  -- Thompson Sampling Beta distribution
  alpha INT DEFAULT 1,  -- Beta α (wins + 1)
  beta INT DEFAULT 1,   -- Beta β (losses + 1)

  last_updated TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

  UNIQUE(agent_id, domain)
);

CREATE INDEX idx_koth_agent ON koth_ratings(agent_id);
CREATE INDEX idx_koth_domain ON koth_ratings(domain);
CREATE INDEX idx_koth_elo ON koth_ratings(elo_rating DESC);
```

### 8. KOTH — Tool Call Outcomes

Win/loss signals from individual tool invocations.

```sql
CREATE TABLE koth_outcomes (
  outcome_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  activity_id UUID NOT NULL REFERENCES activity_records(activity_id) ON DELETE CASCADE,

  oracle_consulted BOOLEAN NOT NULL,
  oracle_recommended_agent_name VARCHAR(255),  -- Agent name if Oracle was consulted
  oracle_recommendation_confidence NUMERIC(3, 2),  -- [0.0, 1.0]

  -- Outcome signal
  outcome_signal VARCHAR(32) NOT NULL,  -- win | loss | draw | pending
  outcome_timestamp TIMESTAMP WITH TIME ZONE,

  -- Domain routing
  koth_domain VARCHAR(64),  -- For domain-specific ELO tracking

  -- Question type (for AskUserQuestion)
  question_type VARCHAR(32),  -- architecture | approval | feature_selection | binary_choice | priority | config | workflow | tooling | naming

  CONSTRAINT valid_signal CHECK (outcome_signal IN ('win', 'loss', 'draw', 'pending')),
  CONSTRAINT valid_confidence CHECK (oracle_recommendation_confidence IS NULL OR (oracle_recommendation_confidence >= 0.0 AND oracle_recommendation_confidence <= 1.0))
);

CREATE INDEX idx_outcomes_activity ON koth_outcomes(activity_id);
CREATE INDEX idx_outcomes_signal ON koth_outcomes(outcome_signal);
CREATE INDEX idx_outcomes_timestamp ON koth_outcomes(outcome_timestamp DESC);
```

### 9. KOTH — Agent Options in AskUserQuestion

Training data source: which agents were presented as options and which was selected.

```sql
CREATE TABLE koth_agent_options (
  option_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  outcome_id UUID NOT NULL REFERENCES koth_outcomes(outcome_id) ON DELETE CASCADE,

  agent_name VARCHAR(255) NOT NULL,
  is_selected BOOLEAN NOT NULL DEFAULT FALSE,  -- TRUE for the selected agent
  position INT,  -- Display position in the question

  UNIQUE(outcome_id, agent_name)
);

CREATE INDEX idx_agent_options_outcome ON koth_agent_options(outcome_id);
CREATE INDEX idx_agent_options_selected ON koth_agent_options(is_selected);
```

---

## A/B Testing (Tier 1)

### 10. Experiments

Named A/B test contexts and variant assignments.

```sql
CREATE TABLE experiments (
  experiment_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  experiment_key VARCHAR(255) NOT NULL UNIQUE,  -- e.g., "exp-markdown-preview-2026-02"

  template_id VARCHAR(255),  -- Named question/invocation template (e.g., "arch-decision-v1")
  template_version VARCHAR(16),  -- Semver (e.g., "1.2.0")

  started_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  ended_at TIMESTAMP WITH TIME ZONE,

  status VARCHAR(32) DEFAULT 'active',  -- active | paused | completed | cancelled

  -- Optional metadata
  description TEXT,
  hypothesis TEXT,
  owner VARCHAR(255),  -- Researcher/team name

  CONSTRAINT valid_status CHECK (status IN ('active', 'paused', 'completed', 'cancelled')),
  CONSTRAINT valid_version CHECK (template_version IS NULL OR template_version ~ '^\d+\.\d+\.\d+$')
);

CREATE INDEX idx_experiments_started ON experiments(started_at DESC);
CREATE INDEX idx_experiments_status ON experiments(status);
```

### 11. Experiment Variants

Treatment variants within an experiment.

```sql
CREATE TABLE experiment_variants (
  variant_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  experiment_id UUID NOT NULL REFERENCES experiments(experiment_id) ON DELETE CASCADE,

  variant_key VARCHAR(255) NOT NULL,  -- e.g., "markdown-enabled", "oracle-guided"
  assignment_method VARCHAR(32),  -- random | deterministic | oracle_guided
  treatment_group VARCHAR(32),  -- control | treatment

  total_assignments INT DEFAULT 0,
  successful_outcomes INT DEFAULT 0,

  UNIQUE(experiment_id, variant_key)
);

CREATE INDEX idx_variants_experiment ON experiment_variants(experiment_id);
```

### 12. Experiment Assignments

Individual tool call assignments to experiment variants.

```sql
CREATE TABLE experiment_assignments (
  assignment_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  activity_id UUID NOT NULL REFERENCES activity_records(activity_id) ON DELETE CASCADE,
  variant_id UUID NOT NULL REFERENCES experiment_variants(variant_id) ON DELETE CASCADE,

  assigned_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  outcome VARCHAR(32),  -- win | loss | draw | pending

  UNIQUE(activity_id, variant_id)
);

CREATE INDEX idx_assignments_activity ON experiment_assignments(activity_id);
CREATE INDEX idx_assignments_variant ON experiment_assignments(variant_id);
CREATE INDEX idx_assignments_outcome ON experiment_assignments(outcome);
```

---

## Decision Logger (Tier 1 & 2)

### 13. Decisions

Decision context records that trigger or are informed by tool calls.

```sql
CREATE TABLE decisions (
  decision_id VARCHAR(32) PRIMARY KEY,  -- Format: dec_YYYYMMDD_HHmmss_NNNNNN

  session_id UUID NOT NULL REFERENCES sessions(session_id) ON DELETE CASCADE,
  entity_id VARCHAR(8) REFERENCES entities(entity_id) ON DELETE SET NULL,

  intent_classification VARCHAR(32),  -- exploration | editing | review | planning | autonomous
  decision_domain VARCHAR(32),  -- frontend | backend | devops | planning | tooling | data | security | cross_cutting

  created_at TIMESTAMP WITH TIME ZONE NOT NULL,
  resolved_at TIMESTAMP WITH TIME ZONE,

  -- Decision tree support
  parent_decision_id VARCHAR(32) REFERENCES decisions(decision_id) ON DELETE SET NULL,
  decision_depth INT DEFAULT 0,  -- 0 = top-level, increments for nested decisions

  CONSTRAINT valid_intent CHECK (intent_classification IS NULL OR intent_classification IN ('exploration', 'editing', 'review', 'planning', 'autonomous')),
  CONSTRAINT valid_domain CHECK (decision_domain IS NULL OR decision_domain IN ('frontend', 'backend', 'devops', 'planning', 'tooling', 'data', 'security', 'cross_cutting')),
  CONSTRAINT valid_id_format CHECK (decision_id ~ '^dec_[0-9]{8}_[0-9]{6}_[0-9]{6}$')
);

CREATE INDEX idx_decisions_session ON decisions(session_id);
CREATE INDEX idx_decisions_entity ON decisions(entity_id);
CREATE INDEX idx_decisions_parent ON decisions(parent_decision_id);
CREATE INDEX idx_decisions_created ON decisions(created_at DESC);
```

### 14. Decision Tool Calls

Links tool calls to the decisions they inform or execute.

```sql
CREATE TABLE decision_tool_calls (
  call_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  decision_id VARCHAR(32) NOT NULL REFERENCES decisions(decision_id) ON DELETE CASCADE,
  activity_id UUID NOT NULL REFERENCES activity_records(activity_id) ON DELETE CASCADE,

  signal_type VARCHAR(32) NOT NULL,  -- pre_decision | post_decision | outcome
  sequence_order INT,  -- Order within the decision lifecycle

  CONSTRAINT valid_signal CHECK (signal_type IN ('pre_decision', 'post_decision', 'outcome')),
  UNIQUE(decision_id, activity_id, signal_type)
);

CREATE INDEX idx_decision_calls_decision ON decision_tool_calls(decision_id);
CREATE INDEX idx_decision_calls_activity ON decision_tool_calls(activity_id);
CREATE INDEX idx_decision_calls_signal ON decision_tool_calls(signal_type);
```

---

## Cross-Tier Telemetry Views

### 15. Tier Transition Metrics

Tracking adoption progress from pre-ATS to full Tier 1 coverage.

```sql
CREATE TABLE tier_transitions (
  transition_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES sessions(session_id) ON DELETE CASCADE,

  from_tier INT,
  to_tier INT,
  transition_timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

  transition_reason VARCHAR(255),  -- e.g., "legacy_caller_upgraded"

  CONSTRAINT valid_tiers CHECK (from_tier IS NULL OR from_tier IN (1, 2, 3)),
  CONSTRAINT valid_to_tier CHECK (to_tier IN (1, 2, 3))
);

CREATE INDEX idx_transitions_session ON tier_transitions(session_id);
```

---

## Backward Compatibility

### 16. Legacy Metadata Mappings

For callers migrating from pre-ATS metadata format.

```sql
CREATE TABLE legacy_metadata (
  legacy_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  activity_id UUID NOT NULL REFERENCES activity_records(activity_id) ON DELETE CASCADE,

  -- Legacy source field (original format before ATS)
  legacy_source_string VARCHAR(255),

  -- Whether this record came from pre-ATS caller
  is_legacy_compat BOOLEAN DEFAULT FALSE,

  -- Mapping to ATS fields
  migrated_to_tier INT,
  migration_timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_legacy_activity ON legacy_metadata(activity_id);
CREATE INDEX idx_legacy_compat ON legacy_metadata(is_legacy_compat);
```

---

## Materialized Views for Analytics

### 17. Agent Performance Summary

```sql
CREATE MATERIALIZED VIEW agent_performance_summary AS
SELECT
  a.agent_id,
  a.fully_qualified_name,
  a.agent_type,
  COUNT(DISTINCT ar.activity_id) as total_invocations,
  SUM(CASE WHEN ko.outcome_signal = 'win' THEN 1 ELSE 0 END) as wins,
  SUM(CASE WHEN ko.outcome_signal = 'loss' THEN 1 ELSE 0 END) as losses,
  ROUND(100.0 * SUM(CASE WHEN ko.outcome_signal = 'win' THEN 1 ELSE 0 END) / NULLIF(COUNT(DISTINCT ar.activity_id), 0), 2) as win_rate,
  kr.elo_rating,
  kr.domain,
  MAX(ar.invoked_at) as last_invoked
FROM agents a
LEFT JOIN activity_records ar ON ar.source_caller_name = a.fully_qualified_name
LEFT JOIN koth_outcomes ko ON ko.activity_id = ar.activity_id
LEFT JOIN koth_ratings kr ON kr.agent_id = a.agent_id
GROUP BY a.agent_id, a.fully_qualified_name, a.agent_type, kr.elo_rating, kr.domain;

CREATE INDEX idx_agent_perf_agent ON agent_performance_summary(agent_id);
```

### 18. Session Activity Summary

```sql
CREATE MATERIALIZED VIEW session_activity_summary AS
SELECT
  s.session_id,
  s.project_path_hash,
  s.started_at,
  s.ended_at,
  COUNT(DISTINCT ar.activity_id) as tool_invocations,
  COUNT(DISTINCT CASE WHEN ar.tool_tier = 1 THEN ar.activity_id END) as tier1_calls,
  COUNT(DISTINCT CASE WHEN ar.tool_tier = 2 THEN ar.activity_id END) as tier2_calls,
  COUNT(DISTINCT CASE WHEN ar.tool_tier = 3 THEN ar.activity_id END) as tier3_calls,
  COUNT(DISTINCT d.decision_id) as decisions_made,
  COUNT(DISTINCT ea.variant_id) as experiment_variants_tested
FROM sessions s
LEFT JOIN activity_records ar ON ar.session_id = s.session_id
LEFT JOIN decisions d ON d.session_id = s.session_id
LEFT JOIN experiment_assignments ea ON ea.activity_id = ar.activity_id
GROUP BY s.session_id, s.project_path_hash, s.started_at, s.ended_at;

CREATE INDEX idx_session_summary_session ON session_activity_summary(session_id);
```

---

## Indexing Strategy

### Query Patterns

1. **Recent activity**: `activity_records(invoked_at DESC)` + `sessions(started_at DESC)`
2. **Agent performance**: `koth_outcomes(activity_id)` + `koth_ratings(agent_id)`
3. **Decision tracing**: `decisions(decision_id)` + `decision_tool_calls(decision_id)`
4. **Experiment results**: `experiment_assignments(variant_id)` + `experiments(experiment_id)`
5. **Project entity**: `sessions(project_path_hash)` + `entities(entity_id)`

### High-Cardinality Columns

- `activity_id`: UUID, expected 10M+ records/year → hash index
- `session_id`: UUID, expected 10k-100k sessions/year → standard index
- `agent_id`: UUID, expected 100-1000 agents → small, standard index
- `invoked_at`: Timestamp, range queries frequent → DESC index
- `project_path_hash`: 8-char string, frequent filters → standard index

---

## Schema Evolution / Versioning

### Current Version: 1.0.0

**Date**: 2026-03-09

**Supported ATS Goals**:

- Provenance (Goal 1) ✅
- A/B Testing (Goal 2) ✅
- KOTH/Oracle (Goal 3) ✅
- Decision Logger (Goal 4) ✅
- Backward Compatibility (Goal 5) ✅

**Future Extensions** (reserved columns, migration notes):

- `L7_semantic`: Semantic clustering data (reserved in activity_records)
- `L8_data_leakage`: Data leakage signals (reserved in activity_records)
- Multi-tenant isolation: `tenant_id` (reserved in all core tables)
- Real-time streaming: `_kafka_partition` metadata (reserved)

---

## Deployment Notes

### Required Extensions

```sql
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
```

### Partitioning Strategy (for large-scale deployment)

```sql
-- Partition activity_records by time (monthly)
CREATE TABLE activity_records_2026_01 PARTITION OF activity_records
  FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');

-- Partition decisions by depth (for tree traversal optimization)
-- Partition experiment_assignments by variant_id (for analytics)
```

### Replication Considerations

- Primary replica: All tables with eager synchronous commit
- Read replicas: Materialized views refreshed every 5 minutes
- Sharding: Optional — by `project_path_hash` for multi-tenant deployment

---

## Validation Constraints

All constraints listed above enforce:

1. Data integrity (NOT NULL, UNIQUE, FOREIGN KEY)
2. Domain validity (CHECK constraints on enums)
3. Format compliance (PATTERN constraints for UUIDs, semver, decision IDs)
4. Range safety (numeric bounds for ELO ratings, Thompson Sampling parameters)
5. Referential integrity (CASCADE DELETE on logical containers)

---

## Integration with ATS Metadata Extraction

The database is designed to be populated by:

1. **`your-telemetry-ingestor`** → `_dgm_fields()` extracts metadata
2. **`your-decision-store`** → Inserts `decisions` and joins to `activity_records`
3. **`your-elo-engine`** → Updates `koth_ratings` based on outcome signals
4. **`your-ab-runner`** → Records `experiment_assignments` and variant metrics

All extraction functions should use **parameterized queries** to prevent injection and ensure data consistency.
