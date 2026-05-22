# A/B Testing Goal — Measuring Tool Invocation Strategy Impact

> **Goal**: Track controlled experiments to measure the impact of different tool invocation strategies, option presentations, and agent selection methods on outcomes.

---

## What A/B Testing Solves

Today, agent/skill selection and tool invocation strategies are difficult to evaluate:

- **Option presentation effects**: Does markdown preview in `AskUserQuestion` improve decision quality?
- **Agent selection methods**: Is Oracle-guided selection better than random assignment?
- **Template stability**: Do revised option framings change user/agent choices?

A/B testing provides controlled comparison by:

1. **Isolating variables** — one change at a time (variant_id)
2. **Controlled assignment** — random, deterministic, or Oracle-guided
3. **Higher signal quality** — 1.5x weight in KOTH ELO calculations vs organic telemetry

---

## The Template System

Named templates enable variant comparison across invocations.

### Template Anatomy

A **template** is a standardized question or tool invocation pattern identified by:

- `template_id` — unique name (e.g., `"arch-decision-v1"`)
- `template_version` — semver (e.g., `"1.2.0"`)

Templates group "same question, different presentation" calls for analysis.

### Example: Architecture Decision Template

```json
{
  "template_id": "arch-decision-v1",
  "template_version": "1.2.0",
  "experiment_id": "exp-markdown-preview-2026-02",
  "variant_id": "markdown-enabled"
}
```

**Variants**:
- `"markdown-enabled"` — shows code preview with syntax highlighting
- `"text-only"` — plain text options only

Both variants ask the *same* question; the A/B test measures whether preview affects choice.

### When to Bump Version

Bump `template_version` when:
- Option framing changes ("Approach A" → "Streaming approach")
- Option ordering changes (randomization vs alphabetical)
- Presentation format changes (list → table)

Unchanged template_version = identical presentation, so outcomes are directly comparable.

---

## Schema Field Reference

All fields are **optional**. The entire `experiment` key is omitted for non-experimental calls.

| Field | Type | Description | Required When Experiment Active |
|-------|------|-------------|--------------------------------|
| `template_id` | `string \| null` | Named template identifier | No (null for ad-hoc) |
| `template_version` | `string \| null` | Semver of template | No (null for ad-hoc) |
| `experiment_id` | `string \| null` | Experiment identifier | **Yes** |
| `variant_id` | `string \| null` | Variant within experiment | **Yes** |
| `assignment_method` | `"random" \| "deterministic" \| "oracle_guided" \| null` | How variant was selected | No |
| `treatment_group` | `"control" \| "treatment" \| null` | Treatment classification | No (variant_id often sufficient) |

### Field Details

#### `template_id` (string | null)

Named question/invocation template (e.g., `"arch-decision-v1"`).

- Null for ad-hoc calls
- Enables grouping "same question, different variants" for analysis
- Should be stable across experiments testing the same decision type

**Examples**: `"arch-decision-v1"`, `"feature-selection-v2"`, `"agent-picker-ui-v3"`

#### `template_version` (string | null)

Semver of the template (e.g., `"1.2.0"`).

- Null for ad-hoc calls
- Bump to test revised option framing or ordering
- Format: `MAJOR.MINOR.PATCH` (must match `^\d+\.\d+\.\d+$`)

**Examples**: `"1.2.0"`, `"2.0.1"`

#### `experiment_id` (string | null)

Active A/B experiment this call participates in.

- Null if not in an experiment
- Maps to `source_weights.ab_testing` in KOTH config (1.5x weight)
- Should be descriptive and time-scoped

**Examples**: `"exp-markdown-preview-2026-02"`, `"exp-oracle-confidence-threshold-q1"`

#### `variant_id` (string | null)

Which variant within the experiment.

- Null if not in an experiment
- Used to partition outcomes by treatment group
- Should be descriptive of the difference being tested

**Examples**: `"markdown-enabled"`, `"text-only"`, `"threshold-0.85"`, `"oracle-guided"`

#### `assignment_method` (enum | null)

How the variant was selected:

- `"random"` — random assignment (ensures no selection bias)
- `"deterministic"` — hash-based assignment (stable across sessions)
- `"oracle_guided"` — Oracle recommendation influenced assignment

Optional; useful for reproducibility analysis.

#### `treatment_group` (enum | null)

Treatment classification:

- `"control"` — baseline/existing behavior
- `"treatment"` — experimental variant

Optional when `variant_id` is descriptive enough (e.g., `"text-only"` is clearly control if `"markdown-enabled"` is the new feature being tested).

---

## ABRunner.py Consumption

The `<your-ab-runner>` module (`~/.claude/plugins/cache/<your-agent-perf-engine>/tool-performance-analytics/0.1.1/lib/<your-ab-runner>`) consumes experiment metadata via two dataclasses:

### ABMatch (Individual Test Case)

```python
@dataclass
class ABMatch:
    test_id: str
    agent_a: str
    agent_b: str
    winner: Literal["agent_a", "agent_b", "draw"]
    agent_a_score: float = 0.0
    agent_b_score: float = 0.0
    timestamp: str = field(default_factory=lambda: datetime.now(UTC).isoformat())
    metadata: dict[str, Any] = field(default_factory=dict)  # ← experiment fields go here
    source: str = "ab_testing"
```

The `metadata` dict should contain the `experiment` object from tool telemetry:

```python
{
    "template_id": "arch-decision-v1",
    "template_version": "1.2.0",
    "experiment_id": "exp-markdown-preview-2026-02",
    "variant_id": "markdown-enabled"
}
```

### ABResults (Aggregate Analysis)

```python
@dataclass
class ABResults:
    agent_a: str
    agent_b: str
    description: str
    total_matches: int
    agent_a_wins: int
    agent_b_wins: int
    draws: int
    agent_a_win_rate: float
    agent_b_win_rate: float
    # Bayesian statistics
    agent_a_confidence: float  # Posterior mean
    agent_b_confidence: float
    agent_a_credible_interval: tuple[float, float]  # 95% CI
    agent_b_credible_interval: tuple[float, float]
    agent_a_alpha: float  # Thompson Sampling Beta distribution params
    agent_a_beta: float
    agent_b_alpha: float
    agent_b_beta: float
    # Statistical significance
    probability_a_better: float  # P(agent_a > agent_b)
    is_significant: bool  # True if P > 0.95
    effect_size: float  # Difference in posterior means
    matches: list[ABMatch] = field(default_factory=list)
    timestamp: str = field(default_factory=lambda: datetime.now(UTC).isoformat())
```

`ABRunner.run_comparison()` aggregates matches and calculates:

1. **Win rates** — raw frequencies
2. **Bayesian confidence** — Beta distribution posterior means
3. **Thompson Sampling** — Monte Carlo simulation (10k samples by default) to calculate `P(agent_a > agent_b)`
4. **Statistical significance** — `is_significant = True` if `probability_a_better >= 0.95`

### Integration Pattern

```python
from <your-ab-runner> import ABRunner, ABMatch

# Extract experiment metadata from telemetry
matches = []
for event in telemetry_events:
    if event.get("experiment", {}).get("experiment_id") == "exp-markdown-preview-2026-02":
        match = ABMatch(
            test_id=event["provenance"]["session_id"],
            agent_a="text-only",
            agent_b="markdown-enabled",
            winner=determine_winner(event),  # custom logic
            metadata=event["experiment"]
        )
        matches.append(match)

# Run comparison
runner = ABRunner(significance_threshold=0.95)
results = runner.run_comparison(
    agent_a="text-only",
    agent_b="markdown-enabled",
    test_cases=[asdict(m) for m in matches],
    description="Markdown preview impact on architecture decisions"
)

print(runner.generate_report(results))
```

---

## KOTH Integration: 1.5x Weight Rationale

A/B testing signals receive **1.5x weight** in KOTH ELO calculations compared to organic telemetry.

### Why Higher Weight?

**Controlled conditions** reduce noise:

1. **Identical question** — templates ensure same decision type
2. **Isolated variable** — only presentation/method changes
3. **Explicit assignment** — no selection bias (random/deterministic)
4. **Clear outcome** — winner determined by objective criteria

**Organic telemetry** has higher variance:

- Ad-hoc questions (no template)
- User context varies (time of day, prior decisions)
- Selection bias (users pick agents they already trust)

### KOTH Config

```yaml
source_weights:
  ab_testing: 1.5  # ← Experiment signals
  direct_feedback: 1.2
  unified_telemetry: 1.0  # ← Organic signals
  performance_test: 0.8
```

When a tool outcome is recorded with `experiment.experiment_id != null`, KOTH applies 1.5x weight to the ELO update.

---

## A/B Test Lifecycle

### 1. Design Phase

Define the hypothesis and variants:

```json
{
  "experiment_id": "exp-oracle-confidence-threshold-q1",
  "hypothesis": "Higher Oracle confidence threshold (0.85 vs 0.70) reduces bad recommendations",
  "control_variant": {
    "variant_id": "threshold-0.70",
    "treatment_group": "control"
  },
  "treatment_variant": {
    "variant_id": "threshold-0.85",
    "treatment_group": "treatment"
  },
  "template_id": "agent-selector-v2",
  "template_version": "2.1.0"
}
```

### 2. Assign Variant

During tool invocation, assign a variant:

```python
import random

def assign_variant(experiment_id: str, session_id: str) -> dict:
    """Assign variant for A/B test."""
    # Deterministic: hash session_id for stable assignment
    variant_id = "threshold-0.85" if hash(session_id) % 2 == 0 else "threshold-0.70"

    return {
        "template_id": "agent-selector-v2",
        "template_version": "2.1.0",
        "experiment_id": experiment_id,
        "variant_id": variant_id,
        "assignment_method": "deterministic",
        "treatment_group": "treatment" if variant_id == "threshold-0.85" else "control"
    }
```

### 3. Record Invocation

Attach experiment metadata to tool call:

```python
metadata = {
    "source": "skill:agent-selector:agent-selector",
    "provenance": {...},
    "experiment": assign_variant("exp-oracle-confidence-threshold-q1", session_id),
    "koth": {...},
    "decision": {...}
}

# Pass to AskUserQuestion, Skill, Task, etc.
```

### 4. Capture Outcome

Tool result determines winner:

- `AskUserQuestion` → selected option
- `Skill` → success/failure (exit code, exception)
- `Task` → task completion (TaskUpdate status=completed)

Store outcome in telemetry with experiment metadata preserved.

### 5. Analyze Results

Use `ABRunner` to aggregate and calculate significance:

```python
runner = ABRunner()
results = runner.run_comparison(
    agent_a="threshold-0.70",
    agent_b="threshold-0.85",
    test_cases=load_test_cases("exp-oracle-confidence-threshold-q1"),
    description="Oracle confidence threshold impact"
)

if results.is_significant:
    print(f"✅ Significant: {results.agent_a} vs {results.agent_b}")
    print(f"   P(A > B) = {results.probability_a_better:.3f}")
    print(f"   Effect size = {results.effect_size:+.3f}")
else:
    print(f"⚠️  Not significant (need {results.total_matches} more samples)")
```

### 6. Promote Winner

If treatment wins with statistical significance:

1. Update default config to use treatment variant
2. Bump `template_version` (e.g., `2.1.0` → `2.2.0`)
3. Archive experiment results
4. Monitor for regression

---

## Example Experiment Configurations

### Experiment 1: Markdown Preview Impact

**Hypothesis**: Markdown code preview in `AskUserQuestion` improves architecture decision quality.

```json
{
  "experiment_id": "exp-markdown-preview-2026-02",
  "template_id": "arch-decision-v1",
  "template_version": "1.2.0",
  "control_variant": {
    "variant_id": "text-only",
    "treatment_group": "control"
  },
  "treatment_variant": {
    "variant_id": "markdown-enabled",
    "treatment_group": "treatment"
  },
  "assignment_method": "random",
  "success_metric": "user_selected_option_matches_oracle_recommendation",
  "target_sample_size": 100
}
```

### Experiment 2: Oracle Confidence Threshold

**Hypothesis**: Higher Oracle confidence threshold (0.85) reduces low-quality recommendations.

```json
{
  "experiment_id": "exp-oracle-confidence-threshold-q1",
  "template_id": "agent-selector-v2",
  "template_version": "2.1.0",
  "control_variant": {
    "variant_id": "threshold-0.70",
    "treatment_group": "control"
  },
  "treatment_variant": {
    "variant_id": "threshold-0.85",
    "treatment_group": "treatment"
  },
  "assignment_method": "deterministic",
  "success_metric": "selected_agent_task_completion_rate",
  "target_sample_size": 200
}
```

### Experiment 3: Agent Selection Method

**Hypothesis**: Oracle-guided agent selection outperforms random selection for code review tasks.

```json
{
  "experiment_id": "exp-agent-selection-method-code-review",
  "template_id": "task-spawn-v1",
  "template_version": "3.0.0",
  "control_variant": {
    "variant_id": "random-selection",
    "treatment_group": "control",
    "assignment_method": "random"
  },
  "treatment_variant": {
    "variant_id": "oracle-guided-selection",
    "treatment_group": "treatment",
    "assignment_method": "oracle_guided"
  },
  "success_metric": "code_review_quality_score",
  "target_sample_size": 150
}
```

---

## Best Practices

### Do

- ✅ Use `template_id` + `template_version` to group identical questions
- ✅ Isolate one variable per experiment (variant_id)
- ✅ Collect 100+ samples before analyzing significance
- ✅ Archive experiment results after promotion/rejection
- ✅ Use deterministic assignment for session-stable experiences
- ✅ Set `experiment_id = null` for ad-hoc/non-experimental calls

### Don't

- ❌ Change template presentation mid-experiment (invalidates comparison)
- ❌ Manually cherry-pick "good" outcomes (biases results)
- ❌ Compare across different `template_version` values
- ❌ Stop early when P(A > B) < 0.95 (needs more samples)
- ❌ Run multiple experiments on the same template simultaneously

---

## Related Goals

- **Provenance** — tracks caller chain (session → agent → skill)
- **KOTH/Oracle** — consumes A/B outcomes for ELO updates
- **Decision Logger** — joins experiment to DecisionContext via `decision_id`

All four goals work together to close the feedback loop: experiment → outcome → ELO update → Oracle recommendation improvement.
