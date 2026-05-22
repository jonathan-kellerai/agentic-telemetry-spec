# Decision Logger Join

> **Goal**: Correlate tool calls with decision outcomes for agent ELO rating updates
> **Schema**: `schemas/goals/decision.schema.json`
> **Reference Implementation**: `~/.claude/plugins/cache/<your-agent-perf-engine>/tool-performance-analytics/0.1.1/lib/<your-decision-store>`

---

## Problem

Today's telemetry captures **what** tools were called but not **why** they were called or **whether they led to successful outcomes**. The Decision Logger bridges this gap by:

1. Recording the **decision context** when an agent selects a tool/skill/subagent
2. Linking subsequent **tool calls** back to that decision via `decision_id`
3. Tracking **outcomes** (task completion, user feedback, errors) to compute ELO adjustments

Without this join, KOTH can only rate tools in isolation. With it, we can attribute entire decision sequences to agent performance.

---

## DecisionContext Structure

A `DecisionContext` record in `<your-decision-store>.jsonl` captures:

```python
@dataclass
class DecisionContext:
    # Decision identification
    decision_id: str                         # Format: dec_YYYYMMDD_HHmmss_NNNNNN
    timestamp: str                           # ISO8601 UTC timestamp

    # What was decided
    selected_agent: str                      # Agent/skill/tool chosen
    alternatives_considered: list[dict]      # [{agent, confidence}, ...]
    confidence: float                        # 0.0 - 1.0

    # Why it was decided
    intent_classification: str               # exploration | editing | review | planning | autonomous
    context_signals: list[str]               # Keywords that triggered selection
    pattern_ids: list[str]                   # Learned patterns that matched

    # User task context
    user_prompt: str                         # Truncated to 500 chars
    task_domain: str | None                  # frontend | backend | devops | etc.
    project_path: str | None                 # Absolute path (hashed for privacy)

    # Outcome (filled after execution)
    outcome_signal: DecisionSignal | None    # TASK_COMPLETED | TASK_FAILED | USER_REJECTED | etc.
    outcome_details: dict                    # {files_modified, errors, duration_seconds}

    # User feedback (optional)
    user_feedback: str | None                # Explicit feedback text
    feedback_sentiment: float | None         # -1.0 (negative) to 1.0 (positive)
```

Key insight: `decision_id` is set **at call time** by the caller (who knows the active decision context). Tool call metadata carries this ID forward, enabling post-hoc joins.

---

## Schema Field Reference

### `decision_id` (string | null)

**Type**: Pattern-validated string
**Format**: `dec_YYYYMMDD_HHmmss_NNNNNN`
**Join Semantics**: `<your-decision-store>.jsonl[decision_id]` ↔ `unified-activity.jsonl[metadata.decision.decision_id]`
**Null When**: No active decision context (ad-hoc tool calls, hooks)

**Example**:
```json
"decision_id": "dec_20260219_143022_123456"
```

### `intent_classification` (enum | null)

**Type**: Mirrors `DecisionContext.intent_classification`
**Values**: `exploration | editing | review | planning | autonomous`
**Purpose**: Quick filtering without joining to the decisions file
**Null When**: No active decision

Enables queries like "show all editing decisions that failed" without loading full DecisionContext records.

### `entity_id` (string | null)

**Type**: 8-character hex string
**Computation**: First 8 chars of `SHA256(project_path)`
**Purpose**: Privacy-preserving project identification for entity memory joins
**Pattern**: `^[0-9a-f]{8}$`
**Null When**: No project context (system-wide operations)

**Why SHA256?** Matches `EntityMemory.entity_id` hashing in `<your-decision-store>:301-311`. Enables joins to entity preferences without exposing absolute paths in telemetry.

**Example**:
```python
# <your-decision-store>:301
key = f"project:{decision.project_path}"
entity_id = hashlib.sha256(decision.project_path.encode()).hexdigest()[:8]
```

### `signal_type` (enum | null)

**Type**: Position marker in decision lifecycle
**Values**:
- `pre_decision`: Tool calls that **inform** the decision (Read, Grep, WebSearch)
- `post_decision`: Actions **taken after** decision (Write, Edit, Bash, SendMessage)
- `outcome`: Result signals (TaskUpdate status=completed, error events)

**Purpose**: Distinguish exploration from execution from results when reconstructing decision flows.

**Example**:
```json
// Read call before decision
{"tool": "Read", "metadata": {"decision": {"signal_type": "pre_decision"}}}

// Write call after decision
{"tool": "Write", "metadata": {"decision": {"signal_type": "post_decision"}}}

// TaskUpdate marking completion
{"tool": "TaskUpdate", "metadata": {"decision": {"signal_type": "outcome"}}}
```

### `parent_decision_id` (string | null)

**Type**: Pattern-validated string (same format as `decision_id`)
**Purpose**: Nested decision tracking for subagent spawns
**Null When**: Top-level decision (no parent)

**Example Hierarchy**:
```
Decision A (parent_decision_id: null)
  → Tool: Task (spawns subagent)
    → Decision B (parent_decision_id: A's decision_id)
      → Tool: Write
      → Tool: Bash
    → Decision B outcome
  → Decision A outcome
```

### `decision_domain` (enum | null)

**Type**: Domain classifier for KOTH subcategory routing
**Values**: `frontend | backend | devops | planning | tooling | data | security | cross_cutting`
**Purpose**: Route decision outcomes to domain-specific ELO buckets
**Null When**: Unclassified or cross-cutting decisions

Enables KOTH to maintain separate ratings like "morphllm:code-editor for backend editing" vs "morphllm:code-editor for frontend editing".

---

## Bidirectional Join Pattern

### Forward Join: Decision → Tool Calls

```sql
-- Get all tool calls triggered by a decision
SELECT * FROM unified_activity
WHERE metadata.decision.decision_id = 'dec_20260219_143022_123456'
ORDER BY timestamp;
```

### Reverse Join: Tool Call → Decision

```sql
-- Get the decision context for a tool call
SELECT d.* FROM koth_decisions d
JOIN unified_activity a ON d.decision_id = a.metadata.decision.decision_id
WHERE a.tool_use_id = 'toolu_abc123';
```

### Outcome Attribution: Decision → Tool Calls → Outcome

```sql
-- Trace decision outcome via tool call results
SELECT
  d.decision_id,
  d.selected_agent,
  d.confidence,
  COUNT(CASE WHEN a.metadata.decision.signal_type = 'outcome' AND a.result.success = true THEN 1 END) as successes,
  COUNT(CASE WHEN a.metadata.decision.signal_type = 'outcome' AND a.result.success = false THEN 1 END) as failures
FROM koth_decisions d
JOIN unified_activity a ON d.decision_id = a.metadata.decision.decision_id
GROUP BY d.decision_id;
```

---

## Circular Dependency Risk

**THE PROBLEM**: `decision_id` must be set **at call time**, but the full `caller_chain` (provenance) is only known **post-hoc** after tool execution completes.

### Unsafe Pattern (DO NOT USE)

```python
# WRONG: Setting decision_id AFTER tool call
tool_result = call_tool("Write", {...})
decision_id = <your-decision-store>.log_decision(...)
# Too late! The tool call metadata already shipped without decision_id
```

### Safe Pattern (USE THIS)

```python
# RIGHT: Log decision BEFORE tool calls
decision_id = <your-decision-store>.log_decision(
    selected_agent="morphllm:code-editor",
    alternatives=[...],
    confidence=0.85,
    intent="editing",
    context_signals=["refactor", "backend"],
    user_prompt=prompt,
)

# Pass decision_id to tool call metadata
call_tool("Write", {
    "file_path": "...",
    "content": "...",
    "metadata": {
        "decision": {"decision_id": decision_id, "signal_type": "post_decision"}
    }
})

# Record outcome AFTER tool execution
<your-decision-store>.record_outcome(decision_id, DecisionSignal.TASK_COMPLETED)
```

**Key Insight**: The caller knows the active decision context at the moment of the tool call. By passing `decision_id` forward as metadata, we avoid the need to backfill it later.

---

## EntityMemory Hashing

### Why SHA256(project_path)?

1. **Privacy**: Telemetry files (unified-activity.jsonl) may be shared across sessions or exported for analysis. Hashing prevents leaking absolute paths like `/Users/alice/secret-client-project`.

2. **Consistency**: `EntityMemory` in `<your-decision-store>:97-125` uses the same hash for project-level preference tracking:
   ```python
   key = f"project:{decision.project_path}"
   entity_id = hashlib.sha256(decision.project_path.encode()).hexdigest()[:8]
   ```

3. **Join Compatibility**: Tools can join to `koth-entity-memory.json` via `entity_id` without exposing raw paths.

### Example

```python
project_path = "/Users/alice/keller-visual/keller-graph-app"
entity_id = hashlib.sha256(project_path.encode()).hexdigest()[:8]
# entity_id = "a3f9b2c1"
```

Tool call metadata:
```json
{
  "tool": "Write",
  "metadata": {
    "decision": {
      "decision_id": "dec_20260219_143022_123456",
      "entity_id": "a3f9b2c1"
    }
  }
}
```

EntityMemory record:
```json
{
  "project:a3f9b2c1": {
    "entity_type": "project",
    "entity_id": "a3f9b2c1",
    "agent_preferences": {"morphllm:code-editor": 0.82},
    "successful_patterns": ["editing:morphllm:code-editor"]
  }
}
```

---

## Nested Decision Example

### Scenario: Main session spawns a subagent

1. **Main session decides to spawn Explore agent**:
   ```json
   {
     "decision_id": "dec_20260219_143022_123456",
     "selected_agent": "Explore",
     "intent_classification": "exploration",
     "parent_decision_id": null
   }
   ```

2. **Task tool call to spawn Explore**:
   ```json
   {
     "tool": "Task",
     "metadata": {
       "decision": {
         "decision_id": "dec_20260219_143022_123456",
         "signal_type": "post_decision",
         "parent_decision_id": null
       }
     }
   }
   ```

3. **Explore agent makes its own decision** (nested):
   ```json
   {
     "decision_id": "dec_20260219_144530_789012",
     "selected_agent": "morphllm:code-editor",
     "intent_classification": "editing",
     "parent_decision_id": "dec_20260219_143022_123456"
   }
   ```

4. **Explore agent calls morphllm:code-editor**:
   ```json
   {
     "tool": "mcp__archangel__morph_edit_file",
     "metadata": {
       "decision": {
         "decision_id": "dec_20260219_144530_789012",
         "signal_type": "post_decision",
         "parent_decision_id": "dec_20260219_143022_123456"
       }
     }
   }
   ```

**Result**: Full decision tree reconstruction via `parent_decision_id` chain.

---

## Integration with KOTH

### Enriched AgentMatch Export

`<your-decision-store>:425-476` exports decisions as KOTH-compatible `AgentMatch` records with enriched metadata:

```python
{
    "session_id": "dec_20260219_143022_123456",
    "timestamp": "2026-02-19T14:30:22Z",
    "agent": "morphllm:code-editor",
    "success": true,
    "source": "decision_log",

    # Standard KOTH fields
    "tool_use_id": "dec_20260219_143022_123456",
    "description": "editing",
    "prompt": "Refactor auth module...",
    "domain": "backend",
    "project_path": "/abs/path",

    # Enrichment: decision-specific metadata
    "decision_metadata": {
        "confidence": 0.85,
        "alternatives": [{"agent": "Explore", "confidence": 0.6}],
        "context_signals": ["refactor", "backend"],
        "pattern_ids": ["editing:morphllm"],
        "outcome_signal": "task_completed",
        "user_feedback": "Looks good!",
        "feedback_sentiment": 0.9
    }
}
```

### Thompson Sampling Adjustments

`<your-decision-store>:394-423` computes prior adjustments based on entity preferences:

```python
# Entity preference: morphllm:code-editor works well for this project
pref = 0.82  # (0.0 - 1.0)

# Convert to Thompson Sampling prior adjustment
if pref > 0.5:
    alpha_adj = (pref - 0.5) * 5  # +1.6 alpha boost
else:
    beta_adj = (0.5 - pref) * 5   # penalty

# KOTH applies: alpha = base_alpha + alpha_adj, beta = base_beta + beta_adj
```

---

## Summary

The `decision` schema fragment enables:

1. **Bidirectional join**: Tool calls ↔ DecisionContext records
2. **Outcome attribution**: Decision → Tool Calls → Result → ELO update
3. **Nested decisions**: Subagent spawns tracked via `parent_decision_id`
4. **Privacy-preserving joins**: SHA256 hashing for project identification
5. **Lifecycle tracking**: `signal_type` distinguishes pre/post/outcome phases
6. **Domain routing**: `decision_domain` routes outcomes to KOTH subcategories

**Critical Design**: `decision_id` is set **at call time** by the caller to avoid circular dependencies with post-hoc `caller_chain` resolution.
