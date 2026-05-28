# Provenance — Caller Identity Chain

**Goal**: Trace every tool call to its caller (`session → agent → skill/hook → tool`)

**Schema**: `../schemas/goals/provenance.schema.json`

---

## What Provenance Solves

Today, `<your-telemetry-ingestor>` has no way to answer:

- Which skill invoked this `AskUserQuestion`?
- Which subagent called `Bash`?
- What's the full call chain from user prompt to tool execution?

The `provenance` object provides a complete identity chain for every tool call, enabling:

- **Traceability**: Link tool calls back to skills, agents, hooks, or main orchestrator
- **Agent accountability**: Join tool outcomes to agent instance UUIDs for ELO attribution
- **Cross-session memory**: Join by `project_path_hash` without exposing absolute paths
- **Debugging**: Reconstruct full call stacks for failed tools

---

## Schema Field Reference

### `session_id` (string, required)

UUID of the Claude Code session. Matches `session_id` in `<your-telemetry-ingestor>` `_base_record()`.

**Format**: UUID
**Example**: `"123e4567-e89b-12d3-a456-426614174000"`

### `agent_id` (string | null, optional)

UUID of the spawned subagent instance. Null for main orchestrator. Matches `agent_id` in `SubagentStart`/`SubagentStop` events.

**Format**: UUID
**Example**: `"ae02e3e1-4f7b-4d9c-8cc8-1a2b3c4d5e6f"` (subagent), `null` (main)

### `caller_type` (string, required)

Type of the immediate caller.

**Enum**: `"skill"` | `"agent"` | `"hook"` | `"main"`
**Example**: `"skill"`

### `caller_name` (string, required)

Fully-qualified name of the immediate caller.

**Format varies by `caller_type`**:

- **skill**: `"plugin:skill"` (e.g., `"feature-dev:feature-dev"`)
- **agent**: agent type name (e.g., `"code-architect"`)
- **hook**: hook event name (e.g., `"UserPromptSubmit"`)
- **main**: `"orchestrator"`

**Example**: `"feature-dev:feature-dev"`

### `caller_chain` (array of objects, optional)

Parent callers from outermost to immediate. Each item has `caller_type`, `caller_name`, and optional `agent_id`. Empty array for top-level calls.

**Default**: `[]`
**Example**:

```json
[
  {
    "caller_type": "main",
    "caller_name": "orchestrator",
    "agent_id": null
  },
  {
    "caller_type": "agent",
    "caller_name": "code-architect",
    "agent_id": "ae02e3e1-4f7b-4d9c-8cc8-1a2b3c4d5e6f"
  }
]
```

### `project_path_hash` (string | null, optional)

First 8 characters of `SHA256(project_path)`. Enables entity memory joins without exposing absolute paths in telemetry.

**Format**: `^[0-9a-f]{8}$`
**Example**: `"a3f9b2c1"`

Matches `EntityMemory.entity_id` hashing pattern in `<your-decision-store>`.

### `timestamp_utc` (string | null, optional)

ISO 8601 datetime when the tool was called (UTC timezone).

**Format**: ISO 8601 date-time
**Example**: `"2026-02-19T14:30:22.123456Z"`

---

## Extracting Provenance in `<your-telemetry-ingestor>`

Update `_base_record()` to extract provenance from the metadata object:

```python
def _base_record(hook_input: dict[str, Any]) -> dict[str, Any]:
    """Create base record with common fields."""
    session_id = hook_input.get("session_id", "")

    # Extract provenance from metadata if present
    tool_input = hook_input.get("tool_input", {})
    metadata = tool_input.get("metadata", {})
    provenance = metadata.get("provenance", {})

    record = {
        "ts": datetime.now(tz=timezone.utc).isoformat(),
        "session": session_id[:8] if session_id else "",
        "event": hook_input.get("hook_event_name", "unknown"),
        "tool": hook_input.get("tool_name", ""),
    }

    # Add provenance fields if present
    if provenance:
        record["caller_type"] = provenance.get("caller_type")
        record["caller_name"] = provenance.get("caller_name")
        record["agent_id"] = provenance.get("agent_id")
        if provenance.get("caller_chain"):
            record["caller_chain_depth"] = len(provenance["caller_chain"])
        if provenance.get("project_path_hash"):
            record["project_hash"] = provenance["project_path_hash"]

    return record
```

---

## Caller Chain Population Pattern

**CRITICAL**: `caller_chain` must be set at **call time**, not post-hoc.

### Top-level tool call (from main orchestrator)

```json
{
  "session_id": "123e4567-e89b-12d3-a456-426614174000",
  "agent_id": null,
  "caller_type": "main",
  "caller_name": "orchestrator",
  "caller_chain": []
}
```

### Skill calling a tool

```json
{
  "session_id": "123e4567-e89b-12d3-a456-426614174000",
  "agent_id": null,
  "caller_type": "skill",
  "caller_name": "feature-dev:feature-dev",
  "caller_chain": []
}
```

### Subagent calling a tool

```json
{
  "session_id": "123e4567-e89b-12d3-a456-426614174000",
  "agent_id": "ae02e3e1-4f7b-4d9c-8cc8-1a2b3c4d5e6f",
  "caller_type": "agent",
  "caller_name": "code-architect",
  "caller_chain": [
    {
      "caller_type": "main",
      "caller_name": "orchestrator",
      "agent_id": null
    }
  ]
}
```

### Nested: main → agent → skill → tool

```json
{
  "session_id": "123e4567-e89b-12d3-a456-426614174000",
  "agent_id": "ae02e3e1-4f7b-4d9c-8cc8-1a2b3c4d5e6f",
  "caller_type": "skill",
  "caller_name": "feature-dev:feature-dev",
  "caller_chain": [
    {
      "caller_type": "main",
      "caller_name": "orchestrator",
      "agent_id": null
    },
    {
      "caller_type": "agent",
      "caller_name": "code-architect",
      "agent_id": "ae02e3e1-4f7b-4d9c-8cc8-1a2b3c4d5e6f"
    }
  ]
}
```

---

## Per-Tier Applicability

| Tier | Tools | Provenance Fields |
|------|-------|------------------|
| **Tier 1** | `AskUserQuestion`, `Task`, `Skill` | All 7 fields (full provenance) |
| **Tier 2** | `Bash`, `Write`, `Edit`, `SendMessage`, `EnterPlanMode`, `ExitPlanMode` | All 7 fields (full provenance) |
| **Tier 3** | `Read`, `Glob`, `Grep`, `WebSearch`, `WebFetch`, `TaskCreate`, `TaskUpdate`, `TaskList`, `TaskGet`, `TeamCreate`, `TeamDelete`, `ToolSearch`, `NotebookEdit`, `TaskOutput`, `TaskStop` | Minimal: `session_id`, `caller_type`, `caller_name` (no `agent_id`, `caller_chain`, `project_path_hash`, `timestamp_utc`) |

**Rationale**: Tier 3 tools are high-frequency reads. Full provenance would bloat telemetry without proportional value.

---

## Example Provenance Objects by Tier

### Tier 1 Example (AskUserQuestion from skill)

```json
{
  "session_id": "123e4567-e89b-12d3-a456-426614174000",
  "agent_id": null,
  "caller_type": "skill",
  "caller_name": "feature-dev:feature-dev",
  "caller_chain": [],
  "project_path_hash": "a3f9b2c1",
  "timestamp_utc": "2026-02-19T14:30:22.123456Z"
}
```

### Tier 2 Example (Bash from subagent)

```json
{
  "session_id": "123e4567-e89b-12d3-a456-426614174000",
  "agent_id": "ae02e3e1-4f7b-4d9c-8cc8-1a2b3c4d5e6f",
  "caller_type": "agent",
  "caller_name": "code-architect",
  "caller_chain": [
    {
      "caller_type": "main",
      "caller_name": "orchestrator",
      "agent_id": null
    }
  ],
  "project_path_hash": "a3f9b2c1",
  "timestamp_utc": "2026-02-19T14:32:15.987654Z"
}
```

### Tier 3 Example (Read from hook)

```json
{
  "session_id": "f7a3c8d1-2b4e-4a5f-9c8d-7e6f5a4b3c2d",
  "caller_type": "hook",
  "caller_name": "UserPromptSubmit"
}
```

**Note**: Tier 3 omits `agent_id`, `caller_chain`, `project_path_hash`, and `timestamp_utc` to minimize overhead.
