# KOTH/Oracle Integration — Closing the Feedback Loop

> **Goal**: Connect tool outcomes to agent ELO ratings and Thompson Sampling recommendations via Oracle.
> **Schema**: `schemas/goals/koth.schema.json`
> **Tier Applicability**: Tier 1 (full koth block), Tier 2 (outcome_signal only)

---

## Overview

The KOTH/Oracle integration closes the agent performance feedback loop:

1. **Oracle consultation**: Before tool invocation, query Oracle for agent recommendations based on historical ELO ratings and Thompson Sampling
2. **Tool invocation**: Execute with Oracle's recommendation context captured in metadata
3. **Outcome extraction**: PostToolUse hook analyzes tool_result to determine win/loss/draw signal
4. **ELO update**: Feed outcome back to `<your-elo-engine>` to update agent ratings and Thompson Sampling parameters
5. **Next iteration**: Improved Oracle recommendations on subsequent calls

This enables agentic learning: agents that consistently succeed rise in the rankings, while underperformers fall. Thompson Sampling balances exploitation (use proven agents) with exploration (test promising but untested agents).

---

## The `koth` Metadata Block

### Schema Fields

```json
{
  "koth": {
    "oracle_consulted": true,
    "oracle_recommended_agent": "morphllm:code-editor",
    "oracle_recommendation_confidence": 0.82,
    "agents_in_options": ["morphllm:code-editor", "general-purpose"],
    "koth_domain": "editing",
    "outcome_signal": "win",
    "question_type": "tooling"
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `oracle_consulted` | boolean | ✅ | Was Oracle queried before this tool call? |
| `oracle_recommended_agent` | string\|null | Conditional | Oracle's top recommendation (required if `oracle_consulted=true`) |
| `oracle_recommendation_confidence` | number\|null | Conditional | Oracle confidence [0.0, 1.0] (required if `oracle_consulted=true`) |
| `agents_in_options` | array\|null | Optional | Agent names in AskUserQuestion options (null for non-agent-selection tools) |
| `koth_domain` | enum\|null | Optional | Domain routing: `architecture`, `planning`, `editing`, `review`, `tooling`, `data`, `security`, `cross_cutting` |
| `outcome_signal` | enum\|null | PostToolUse | `win`, `loss`, `draw`, `pending` (null at call time, set by telemetry hook) |
| `question_type` | enum\|null | Optional | For AskUserQuestion: `architecture`, `approval`, `feature_selection`, `binary_choice`, `priority`, `config`, `workflow`, `tooling`, `naming` |

---

## ELO Signal Extraction Pipeline

### Phase 1: Tool Invocation (PreToolUse)

When a tool is called:

1. **Oracle consultation** (if applicable):
   - Call `oracle_query` with task context, project path, and domain
   - Oracle uses `sample_agent_thompson()` from `<your-elo-engine>` to select from candidates
   - Thompson Sampling draws from each agent's Beta(alpha, beta) distribution
   - Capture `oracle_recommended_agent` and `oracle_recommendation_confidence`

2. **Metadata capture**:
   - Set `oracle_consulted: true` if Oracle was queried
   - For AskUserQuestion with agent options, populate `agents_in_options` array
   - Set `question_type` and `koth_domain` based on intent classification
   - Leave `outcome_signal: null` (populated post-execution)

### Phase 2: Tool Execution

Tool executes. Result can be:
- **Success** (`is_error: false` in tool_result)
- **Failure** (`is_error: true`)
- **Partial success** (UAEF evaluation with assertion pass/fail breakdown → `weighted_success`)

### Phase 3: Outcome Extraction (PostToolUse Hook)

`<your-telemetry-ingestor>` PostToolUse hook:

1. **Read tool_result**:
   - Extract `is_error`, `success` flag (from `toolUseResult.success`), subagent output
   - For Task tool: parse subagent log for errors, test failures, unresolved issues

2. **Determine outcome_signal**:
   - **win**: `is_error=false`, `success=true`, no critical failures in subagent output
   - **loss**: `is_error=true` OR `success=false` OR critical failures detected
   - **draw**: Ambiguous outcome (partial success, mixed signals)
   - **pending**: Deferred outcome awaiting external validation (e.g., UAEF eval suite)

3. **Write outcome to metadata**:
   - Update `koth.outcome_signal` in tool telemetry record
   - Append to `koth-agent-matches.jsonl` (extractor input format)

### Phase 4: ELO Update (<your-elo-engine>)

`extractor.py` reads `koth-agent-matches.jsonl`:

```python
from lib.extractor import ConversationLogParser

matches = ConversationLogParser.load_external_matches(
    "~/.claude/telemetry/koth-agent-matches.jsonl",
    source_filter="telemetry"  # vs "evaluation" or "ab_testing"
)

for match in matches:
    if match.outcome_signal == "win":
        # Increment agent's alpha (Thompson Sampling successes)
        # Update Elo rating based on expected vs actual score
    elif match.outcome_signal == "loss":
        # Increment agent's beta (Thompson Sampling failures)
        # Decrement Elo rating
```

`<your-elo-engine>` updates:
- **Elo rating**: Traditional Elo formula with K-factor weighting
- **Thompson Sampling parameters**: Beta(alpha, beta) distribution
  - `alpha` += 1 for wins (successes)
  - `beta` += 1 for losses (failures)
- **Source-specific stats**: Track performance by `source` (telemetry, evaluation, ab_testing)
- **Regression history**: Record confidence deltas for anomaly detection

---

## Oracle Consultation Pattern

### When to Query Oracle

Oracle should be consulted **before** any tool invocation where agent selection is a decision variable:

1. **AskUserQuestion with agent options**: "Which agent should handle this task?"
2. **Task tool invocation**: Selecting `subagent_type` parameter
3. **Skill tool with multiple agent implementations**: Choosing between competing skill variants

Oracle consultation is **optional** for:
- Read-only tools (Read, Grep, Glob, WebSearch)
- Deterministic tools with no agent choice (Write, Edit with fixed strategy)
- Tools where outcome is independent of agent selection

### Oracle API

```python
from lib.oracle import Oracle

oracle = Oracle(<your-elo-engine>=EloRatingEngine(...))

# Query for top recommendation
recommendation = oracle.query(
    candidates=["morphllm:code-editor", "general-purpose", "code-architect"],
    project_path="/Users/name/project",
    task_domain="editing",
    top_n=1
)

# Returns:
{
    "agent": "morphllm:code-editor",
    "confidence": 0.82,
    "elo": 1587.3,
    "win_rate": 0.74,
    "sampled_value": 0.856,  # Thompson Sampling draw
    "all_samples": {
        "morphllm:code-editor": 0.856,
        "general-purpose": 0.723,
        "code-architect": 0.691
    }
}
```

### Thompson Sampling and `oracle_recommendation_confidence`

Thompson Sampling uses **Beta distributions** to model each agent's success probability:

- **Alpha (α)**: Number of successes + prior (default 1.0)
- **Beta (β)**: Number of failures + prior (default 1.0)
- **Confidence**: Posterior mean = α / (α + β)

When Oracle samples:
1. For each candidate agent, draw a random value from Beta(α, β)
2. Select the agent with the highest sampled value
3. Return sampled value as `oracle_recommendation_confidence`

**Key insight**: Confidence balances **exploitation** (high mean) vs **exploration** (high variance). Agents with few matches have wide distributions (high variance) → occasionally sample high values → get tested. Proven agents have narrow distributions (low variance) → consistently sample near their true performance.

Formula for credible interval (95%):
```python
mean = alpha / (alpha + beta)
std = sqrt(alpha * beta / (n^2 * (n + 1)))  # n = alpha + beta
interval = (mean - 1.96*std, mean + 1.96*std)
```

---

## The `agents_in_options` Mechanism

### Training Data Generation

`agents_in_options` is the **primary source** for KOTH training data when using AskUserQuestion:

```json
{
  "tool": "AskUserQuestion",
  "input": {
    "question": "Which agent should refactor this module?",
    "options": ["morphllm:code-editor", "general-purpose"],
    "metadata": {
      "koth": {
        "oracle_consulted": true,
        "oracle_recommended_agent": "morphllm:code-editor",
        "agents_in_options": ["morphllm:code-editor", "general-purpose"]
      }
    }
  }
}

// User selects "morphllm:code-editor"

{
  "tool_result": {
    "selected": "morphllm:code-editor",
    "koth": {
      "outcome_signal": "win"  // morphllm:code-editor gets +1 alpha
    }
  }
}
```

PostToolUse hook extracts:
- **Winner**: Selected agent → `outcome_signal = "win"`, alpha += 1
- **Losers**: Unselected agents in `agents_in_options` → `outcome_signal = "loss"`, beta += 1

This creates **head-to-head match data** for ELO updates without running both agents.

### Source Weighting

`source_weights` in KOTH config (`~/.claude/configs/agent-catalog/leagues/koth-config.yaml`):

```yaml
source_weights:
  telemetry: 1.0        # Implicit outcomes (tool success/failure)
  evaluation: 2.0       # UAEF test suite results (ground truth)
  ab_testing: 1.5       # AskUserQuestion agent selection (user preference)
```

`agents_in_options` outcomes are tagged `source="ab_testing"` → 1.5x weight in ELO calculations.

---

## `outcome_signal` Lifecycle

### Timeline

| Stage | `outcome_signal` Value | Set By |
|-------|----------------------|--------|
| PreToolUse | `null` | Tool caller |
| Tool execution | `null` | — |
| PostToolUse hook | `"win"`, `"loss"`, `"draw"`, or `"pending"` | `<your-telemetry-ingestor>` |
| Extractor reads telemetry | Used for ELO update | `extractor.py` |

### Signal Determination Logic

```python
def determine_outcome_signal(tool_result, tool_name):
    is_error = tool_result.get("is_error", False)
    success = tool_result.get("toolUseResult", {}).get("success", True)

    if tool_name == "Task":
        # Parse subagent output
        output = tool_result.get("content", "")
        if "test failed" in output.lower() or "error:" in output.lower():
            return "loss"
        if success and not is_error:
            return "win"
        return "draw"

    elif tool_name == "Skill":
        # Skills report success explicitly
        if success and not is_error:
            return "win"
        elif is_error or not success:
            return "loss"
        return "draw"

    elif tool_name == "AskUserQuestion":
        # If agents_in_options present, extract selection
        selected = tool_result.get("selected")
        if selected:
            return "win"  # For selected agent
        return "draw"

    # Default fallback
    if is_error:
        return "loss"
    elif success:
        return "win"
    return "draw"
```

### Pending Outcomes

`"pending"` is used when outcome requires deferred validation:

1. **UAEF evaluation suites**: Tool call triggers test execution, results written to `eval-results.jsonl` asynchronously
2. **Long-running tasks**: Subagent spawned for multi-step operation, final success unknown at PostToolUse time
3. **User validation required**: Tool call requests user review before marking success/failure

Pending signals are resolved by:
- **UAEF hook**: Reads eval results, updates `outcome_signal` in telemetry
- **SessionEnd hook**: Final reconciliation of deferred outcomes

---

## Per-Tool Applicability

### Tier 1: Full `koth` Block

**Tools**: AskUserQuestion, Task, Skill

**Fields populated**:
- All 7 koth fields (oracle_consulted, oracle_recommended_agent, oracle_recommendation_confidence, agents_in_options, koth_domain, outcome_signal, question_type)

**Use case**: These tools represent **agent selection decisions** with measurable outcomes. Full KOTH context enables:
- Oracle consultation before invocation
- Training data generation via `agents_in_options`
- ELO updates based on tool execution success

### Tier 2: Partial `koth` Block (outcome_signal only)

**Tools**: Bash, Write, Edit, SendMessage, EnterPlanMode, ExitPlanMode

**Fields populated**:
- `oracle_consulted: false` (Oracle not queried)
- `oracle_recommended_agent: null`
- `oracle_recommendation_confidence: null`
- `agents_in_options: null`
- `koth_domain: null`
- `outcome_signal: "win"|"loss"|"draw"` (set by PostToolUse)
- `question_type: null`

**Use case**: These tools execute **consequential actions** but don't involve agent selection. Outcome signals feed into:
- Project-level success metrics (beads issue closure correlation)
- Agent performance attribution (if executed within a Task/Skill context)
- Decision Logger outcome tracking

### Tier 3: No `koth` Block

**Tools**: Read, Glob, Grep, WebSearch, WebFetch, TaskCreate, TaskUpdate, TaskList, TaskGet, TeamCreate, TeamDelete, ToolSearch, NotebookEdit, TaskOutput, TaskStop

**Rationale**: High-frequency read/query tools with minimal outcome signal. Adding koth metadata creates:
- Context bloat (thousands of Read calls per session)
- Noisy training data (read failures rarely actionable)
- Marginal value (outcomes don't drive agent selection)

**Exception**: If a Tier 3 tool is executed **within a Task/Skill context**, its outcome contributes to the parent tool's `outcome_signal` (indirect attribution).

---

## Integration with DecisionLogger

The `koth` block links to DecisionLogger via the `decision` metadata block:

```json
{
  "metadata": {
    "decision": {
      "decision_id": "dec_20260219_143022_123456",
      "intent_classification": "planning"
    },
    "koth": {
      "oracle_consulted": true,
      "oracle_recommended_agent": "code-architect",
      "outcome_signal": "win",
      "koth_domain": "planning"
    }
  }
}
```

**Bidirectional join**:
- DecisionContext → tool call (via `decision_id`)
- Tool call → ELO update (via `koth.outcome_signal`)
- ELO update → Thompson Sampling priors (via DecisionLogger entity memory)

**Agno-style preference learning**:
`<your-elo-engine>` calls `<your-decision-store>.get_thompson_sampling_weights()` to apply preference-based adjustments:
```python
alpha_adj, beta_adj = <your-decision-store>.get_thompson_sampling_weights(
    agent="morphllm:code-editor",
    project_path="/Users/name/project",
    task_domain="editing"
)

# Adjust priors based on historical user preferences
alpha = base_alpha + wins + alpha_adj
beta = base_beta + losses + beta_adj
```

This enables **contextual bandit learning**: agents that performed well on similar projects/domains get boosted priors.

---

## Example: Full Workflow

### 1. Oracle Consultation (PreToolUse)

User prompt: "Refactor the authentication module to use dependency injection"

```python
# Agent orchestrator consults Oracle
oracle_result = oracle.query(
    candidates=["morphllm:code-editor", "general-purpose", "code-architect"],
    project_path="/Users/name/backend",
    task_domain="editing"
)

# Oracle returns: {"agent": "morphllm:code-editor", "confidence": 0.82}
```

### 2. Tool Invocation

```json
{
  "tool": "Task",
  "input": {
    "subagent_type": "morphllm:code-editor",
    "prompt": "Refactor auth module for DI",
    "metadata": {
      "koth": {
        "oracle_consulted": true,
        "oracle_recommended_agent": "morphllm:code-editor",
        "oracle_recommendation_confidence": 0.82,
        "agents_in_options": null,
        "koth_domain": "editing",
        "outcome_signal": null,
        "question_type": null
      }
    }
  }
}
```

### 3. Tool Execution

MorphLLM code-editor subagent executes. Subagent log shows:
```
✓ Refactored AuthService to use constructor injection
✓ Updated tests to pass DI container
✓ All 47 tests passing
```

### 4. Outcome Extraction (PostToolUse)

```python
# <your-telemetry-ingestor>
tool_result = {...}
subagent_output = extract_subagent_output(tool_result)

if "tests passing" in subagent_output and not tool_result.get("is_error"):
    outcome = "win"
else:
    outcome = "loss"

# Update metadata
metadata["koth"]["outcome_signal"] = outcome
```

### 5. Telemetry Write

```jsonl
{"session_id": "abc123", "tool": "Task", "agent": "morphllm:code-editor", "success": true, "koth": {"outcome_signal": "win", ...}}
```

### 6. ELO Update (Next Run)

```python
# extractor.py
matches = load_external_matches("koth-agent-matches.jsonl")

for match in matches:
    if match.agent == "morphllm:code-editor" and match.outcome_signal == "win":
        rating = ratings["morphllm:code-editor"]
        rating.alpha += 1  # Thompson Sampling success
        rating.elo += k_factor * (1.0 - expected_score)  # Elo update
```

### 7. Next Oracle Query

Next time user asks for code editing:
```python
oracle.query(candidates=[...])
# morphllm:code-editor now has higher alpha → higher sampled values → more likely to be recommended
```

---

## References

- **KOTH Rating Engine**: `~/.claude/plugins/cache/<your-agent-perf-engine>/tool-performance-analytics/0.1.1/lib/<your-elo-engine>`
- **Signal Extractor**: `~/.claude/plugins/cache/<your-agent-perf-engine>/tool-performance-analytics/0.1.1/lib/extractor.py`
- **Initial Seeding**: `~/.claude/configs/agent-catalog/leagues/initial-seeding.yaml`
- **KOTH Config**: `~/.claude/configs/agent-catalog/leagues/koth-config.yaml`
- **Telemetry Hook**: `~/.claude/plugins/cache/<your-hooks-plugin>/unified-telemetry/1.0.0/hooks/<your-telemetry-ingestor>`
- **Thompson Sampling**: [Wikipedia: Thompson Sampling](https://en.wikipedia.org/wiki/Thompson_sampling)
- **Beta Distribution**: [Wikipedia: Beta Distribution](https://en.wikipedia.org/wiki/Beta_distribution)
