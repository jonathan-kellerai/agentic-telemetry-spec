# Backward Compatibility

> **Goal**: Preserve existing metadata shapes while migrating to DGM standard. No breaking changes.

---

## The Problem: Three Existing Metadata Shapes

Today only 3 of 18 Claude Code tools carry metadata, each with different shapes:

| Tool | Current Metadata Shape |
|------|----------------------|
| `AskUserQuestion` | `{ source: string }` |
| `TaskCreate` | `{ metadata: object }` (arbitrary user data) |
| `TaskUpdate` | `{ metadata: object }` (arbitrary user data) |

**Challenge**: We cannot break existing callers. All new DGM fields must be **optional** and **additive**.

---

## Solution 1: TaskCreate/TaskUpdate Collision — Nested `_dgm` Key

`TaskCreate` and `TaskUpdate` already use `metadata` as an **arbitrary user data object** for tracking task-specific context. DGM fields **MUST nest under `_dgm` key** to avoid collision:

### Task Tool Metadata Nesting Pattern

```json
{
  "metadata": {
    "_dgm": {
      "source": "skill:feature-dev:feature-dev",
      "provenance": { /* ... */ },
      "koth": { /* ... */ },
      "decision": { /* ... */ },
      "_compat": {
        "schema_version": "1.0.0",
        "is_legacy_compat": false
      }
    },
    "custom_field": "user-defined value",
    "another_field": 42
  }
}
```

**Critical constraint**: Task tools preserve user's arbitrary `metadata` keys at the top level. DGM metadata lives **exclusively** under `metadata._dgm`.

---

## Solution 2: Legacy Source Preservation — `_compat.legacy_source`

`AskUserQuestion` currently emits `{ source: string }` where `source` is a freeform string like `"remember"`, `"skill:feature-dev"`, or `"main"`.

**Migration path**:

1. Parse legacy `source` string into structured `source` field (e.g., `"remember"` → `"hook:remember"`)
2. Preserve original raw value in `_compat.legacy_source`
3. Mark as migrated via `_compat.migrated_from`

### Example: Migrating Legacy AskUserQuestion Metadata

**Before (legacy)**:
```json
{
  "source": "remember"
}
```

**After (DGM 1.0.0)**:
```json
{
  "source": "hook:remember",
  "provenance": {
    "session_id": "123e4567-e89b-12d3-a456-426614174000",
    "agent_id": null,
    "caller_type": "hook",
    "caller_name": "remember",
    "caller_chain": []
  },
  "_compat": {
    "schema_version": "1.0.0",
    "legacy_source": "remember",
    "migrated_from": {
      "tool_name": "AskUserQuestion",
      "old_schema_version": "0.9.0",
      "migration_date": "2026-02-19T10:30:00Z"
    },
    "is_legacy_compat": false
  }
}
```

---

## Additive-Only Policy

**RULE**: No existing field can ever be removed or changed in a breaking way.

- New fields are **always optional**
- Existing fields preserve their type and semantics
- Deprecated fields remain parseable indefinitely
- Schema version bumps (`1.0.0` → `1.1.0`) signal additive changes only
- Breaking changes require a **new major version** (`1.x.x` → `2.0.0`) and parallel schema support

---

## `is_legacy_compat` Flag

**Purpose**: Distinguish "old caller hasn't adopted DGM yet" from "Tier 3 tool intentionally uses minimal metadata".

| Scenario | `is_legacy_compat` | Interpretation |
|----------|-------------------|----------------|
| Pre-DGM caller (no `_dgm` block) | `true` | Old caller — not yet migrated |
| Tier 3 tool (only `source` + `provenance`) | `false` | Intentionally minimal — DGM-compliant |
| Tier 1/2 tool (full metadata) | `false` | Fully adopted DGM standard |

Telemetry uses this flag to filter analytics:
- `is_legacy_compat=true` → Exclude from KOTH ELO updates (unreliable provenance)
- `is_legacy_compat=false` → Include in all analytics pipelines

---

## Migration Roadmap

### Phase 1: Tier 1 Tools (Full Metadata)
**Tools**: `AskUserQuestion`, `Task`, `Skill`

**Strategy**:
1. Wrap existing metadata parsers with migration shim
2. Detect legacy shape → populate `_compat.migrated_from`
3. Emit full DGM metadata with all 5 goal fragments
4. Set `is_legacy_compat=false` after migration

### Phase 2: Tier 2 Tools (Partial Metadata)
**Tools**: `Bash`, `Write`, `Edit`, `SendMessage`, `EnterPlanMode`, `ExitPlanMode`

**Strategy**:
1. Add `source` + `provenance` + `koth` + `decision` fields
2. Set `_compat.schema_version="1.0.0"`
3. Omit `experiment` fragment (not applicable)

### Phase 3: Tier 3 Tools (Minimal Metadata)
**Tools**: `Read`, `Glob`, `Grep`, `WebSearch`, `TaskCreate`, `TaskUpdate`, etc.

**Strategy**:
1. Add only `source` + `provenance`
2. Set `_compat.schema_version="1.0.0"`
3. **Task tools**: nest DGM fields under `metadata._dgm` key
4. Keep metadata payload minimal (avoid token bloat on high-frequency tools)

---

## Version Gating

**Schema version** (`_compat.schema_version`) gates future migration logic:

```python
def parse_metadata(raw_metadata: dict) -> Metadata:
    compat = raw_metadata.get("_compat", {})
    version = compat.get("schema_version", "0.0.0")

    if version < "1.0.0":
        # Legacy pre-DGM format — apply migration shim
        return migrate_legacy(raw_metadata)
    elif version >= "2.0.0":
        # Future breaking change — use new parser
        return parse_v2(raw_metadata)
    else:
        # Current 1.x.x format
        return parse_v1(raw_metadata)
```

**Semver rules**:
- Patch bumps (`1.0.0` → `1.0.1`): Bug fixes, no schema change
- Minor bumps (`1.0.0` → `1.1.0`): Additive fields (e.g., new optional `_compat.migration_notes` field)
- Major bumps (`1.0.0` → `2.0.0`): Breaking changes (e.g., rename `source` to `caller_id`)

---

## Verification: Using `unified-activity.schema.json`

The existing telemetry schema at `~/.claude/configs/claude-code-schema/unified-activity.schema.json` validates **top-level event records**. DGM metadata appears **nested inside tool-specific fields**.

### Validation Strategy

1. **Extend unified-activity.schema.json** to support optional `_dgm` nested object on tool records:

```json
{
  "properties": {
    "tool": { "type": "string" },
    "phase": { "type": "string" },
    "_dgm": {
      "$ref": "base-metadata.schema.json",
      "description": "Optional DGM metadata for tools that emit it"
    }
  }
}
```

2. **Extract and validate** DGM metadata separately:

```python
# Validate top-level event structure
jsonschema.validate(event_record, unified_activity_schema)

# If tool emits DGM metadata, validate nested block
if "_dgm" in event_record or "metadata" in tool_input:
    dgm_metadata = extract_dgm_metadata(event_record)
    jsonschema.validate(dgm_metadata, base_metadata_schema)
```

3. **Backward compat test suite**:

```python
# Test 1: Legacy AskUserQuestion metadata still validates
legacy_record = {"source": "remember"}
assert validate_dgm_with_migration(legacy_record)

# Test 2: TaskCreate user metadata unaffected by _dgm nesting
task_metadata = {
    "_dgm": {"source": "skill:x", "provenance": {...}},
    "user_field": "custom"
}
assert task_metadata["user_field"] == "custom"  # No collision

# Test 3: is_legacy_compat distinguishes old vs Tier 3
old_caller = {"source": "main", "_compat": {"is_legacy_compat": True}}
tier3_tool = {"source": "agent:x", "provenance": {...}, "_compat": {"is_legacy_compat": False}}
assert old_caller != tier3_tool  # Analytics filters correctly
```

---

## Summary

| Concern | Solution |
|---------|----------|
| TaskCreate/TaskUpdate collision | Nest DGM under `metadata._dgm` key |
| Legacy `source` string | Preserve in `_compat.legacy_source` |
| Detect old vs Tier 3 callers | Use `is_legacy_compat` flag |
| Breaking changes | Additive-only policy + semver gating |
| Verification | Extend `unified-activity.schema.json` with optional `_dgm` ref |

**Migration order**: Tier 1 → Tier 2 → Tier 3, with each tier setting `schema_version="1.0.0"` to signal DGM compliance.
