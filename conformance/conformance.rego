# METADATA
# title: OSS repository structure conformance
# description: |
#   Validates a repository's file and directory structure against the OSS
#   publication standard. Consumes a repo-structure.json snapshot as `input`
#   and the conformance manifest (data.json) as `data`. Emits a structured
#   `deny` set; `error`-severity entries block CI.
package conformance.conformance

import rego.v1

# ---------------------------------------------------------------------------
# Data shortcuts (the conformance manifest, data.json)
# ---------------------------------------------------------------------------

_schema := data.schema

_content := data.content_assertions

_integrity := data.policy_integrity

_trust_dial := data.trust_dial_manifest

# ---------------------------------------------------------------------------
# Input shortcuts (the repo-structure.json snapshot)
# ---------------------------------------------------------------------------

# Set of every file path present in the repository.
_paths := {f.path | some f in input.files}

# Set of every directory present in the repository.
_dirs := {d | some d in input.dirs}

# ---------------------------------------------------------------------------
# Sentinel-guarded access — distinguishes an absent key from a falsy value.
# ---------------------------------------------------------------------------

_sentinel := {"__absent__": true}

_get(obj, key) := object.get(obj, key, _sentinel)

_present(obj, key) if object.get(obj, key, _sentinel) != _sentinel

# ---------------------------------------------------------------------------
# deny — the structured violation set.
# Each entry: {"rule": str, "severity": "error"|"warning", "field": str, "msg": str}
# ---------------------------------------------------------------------------

# -- data sanity: the conformance manifest must be loaded --------------------
deny contains entry if {
	not data.schema
	entry := {
		"rule": "data_sentinel",
		"severity": "error",
		"field": "data.schema",
		"msg": "conformance manifest not loaded: data.schema is absent",
	}
}

# -- required root files -----------------------------------------------------
deny contains entry if {
	some required in _schema.required_files
	not required in _paths
	entry := {
		"rule": "required_file",
		"severity": "error",
		"field": required,
		"msg": sprintf("required file missing: %s", [required]),
	}
}

# -- required directories ----------------------------------------------------
deny contains entry if {
	some required in _schema.required_dirs
	not required in _dirs
	entry := {
		"rule": "required_dir",
		"severity": "error",
		"field": required,
		"msg": sprintf("required directory missing: %s", [required]),
	}
}

# -- required .github files --------------------------------------------------
deny contains entry if {
	some required in _schema.required_github_files
	not required in _paths
	entry := {
		"rule": "required_github_file",
		"severity": "error",
		"field": required,
		"msg": sprintf("required .github file missing: %s", [required]),
	}
}

# -- required agent docs (Tier-2) -------------------------------------------
deny contains entry if {
	some required in _schema.required_agent_docs
	not required in _paths
	entry := {
		"rule": "required_agent_doc",
		"severity": "error",
		"field": required,
		"msg": sprintf("required agent doc missing: %s", [required]),
	}
}

# -- required scripts --------------------------------------------------------
deny contains entry if {
	some required in _schema.required_scripts
	not required in _paths
	entry := {
		"rule": "required_script",
		"severity": "error",
		"field": required,
		"msg": sprintf("required script missing: %s", [required]),
	}
}

# -- artifact type must be a known value ------------------------------------
deny contains entry if {
	not input.artifact_type in _schema.artifact_types
	entry := {
		"rule": "artifact_type_known",
		"severity": "error",
		"field": "input.artifact_type",
		"msg": sprintf("unknown artifact_type %v; must be one of %v", [input.artifact_type, _schema.artifact_types]),
	}
}

# -- the artifact directory must exist --------------------------------------
deny contains entry if {
	input.artifact_type in _schema.artifact_types
	cfg := _schema.artifact_type_files[input.artifact_type]
	expected_dir := object.get(input, "artifact_dir", cfg.default_dir)
	not expected_dir in _dirs
	entry := {
		"rule": "artifact_dir",
		"severity": "error",
		"field": expected_dir,
		"msg": sprintf("artifact directory missing for type %v: %s", [input.artifact_type, expected_dir]),
	}
}

# -- AGENTS.md length cap ----------------------------------------------------
deny contains entry if {
	meta := _get(input.file_meta, "AGENTS.md")
	meta != _sentinel
	meta.line_count > _content.agents_md_max_lines
	entry := {
		"rule": "agents_md_length",
		"severity": "warning",
		"field": "AGENTS.md",
		"msg": sprintf("AGENTS.md is %d lines; the standard caps it at %d", [meta.line_count, _content.agents_md_max_lines]),
	}
}

# -- CLAUDE.md length cap ----------------------------------------------------
deny contains entry if {
	meta := _get(input.file_meta, "CLAUDE.md")
	meta != _sentinel
	meta.line_count > _content.claude_md_max_lines
	entry := {
		"rule": "claude_md_length",
		"severity": "warning",
		"field": "CLAUDE.md",
		"msg": sprintf("CLAUDE.md is %d lines; the standard caps it at %d", [meta.line_count, _content.claude_md_max_lines]),
	}
}

# -- CLAUDE.md must import AGENTS.md as its first content line --------------
deny contains entry if {
	meta := _get(input.file_meta, "CLAUDE.md")
	meta != _sentinel
	meta.first_content_line != _content.claude_md_first_content_line
	entry := {
		"rule": "claude_md_import",
		"severity": "error",
		"field": "CLAUDE.md",
		"msg": sprintf("CLAUDE.md first content line is %v; the standard requires %v", [meta.first_content_line, _content.claude_md_first_content_line]),
	}
}

# -- README must carry the agent-pointer footer -----------------------------
deny contains entry if {
	meta := _get(input.file_meta, "README.md")
	meta != _sentinel
	not contains(meta.tail, _content.readme_agents_footer_marker)
	entry := {
		"rule": "readme_agent_footer",
		"severity": "warning",
		"field": "README.md",
		"msg": sprintf("README.md is missing the %v agent-pointer footer", [_content.readme_agents_footer_marker]),
	}
}

# -- .gitignore must cover the required staging patterns --------------------
deny contains entry if {
	meta := _get(input.file_meta, ".gitignore")
	meta != _sentinel
	some pattern in _schema.gitignore_required_patterns
	not pattern in {l | some l in meta.lines}
	entry := {
		"rule": "gitignore_coverage",
		"severity": "error",
		"field": pattern,
		"msg": sprintf(".gitignore does not cover required pattern: %s", [pattern]),
	}
}

# -- no forbidden branch (default branch must be main) ----------------------
deny contains entry if {
	some branch in input.branches
	branch in _schema.forbidden_branches
	entry := {
		"rule": "forbidden_branch",
		"severity": "error",
		"field": branch,
		"msg": sprintf("forbidden branch present: %s — the default branch must be main", [branch]),
	}
}

# -- the artifact type's primary validator must be wired into CI ------------
deny contains entry if {
	input.artifact_type in _schema.artifact_types
	cfg := _schema.artifact_type_files[input.artifact_type]
	not _validator_referenced(cfg.primary_validator)
	entry := {
		"rule": "primary_validator_wired",
		"severity": "warning",
		"field": cfg.primary_validator,
		"msg": sprintf("no CI workflow references the primary validator %v for artifact type %v", [cfg.primary_validator, input.artifact_type]),
	}
}

_validator_referenced(validator) if {
	some line in input.ci_uses
	contains(line, validator)
}

# -- the trust-dial gate must be wired into a CI workflow ------------------
# Whitepaper enforcement: a repo may not merely *contain* the gate workflow,
# it must *wire* it (a CI step evaluates data.conformance.trust_dial.*).
# Reuses the input.ci_uses aggregation already populated by
# scan-repo-structure.sh (the same mechanism primary_validator_wired uses).
deny contains entry if {
	_present(_trust_dial, "gate_workflow")
	gate := _trust_dial.gate_workflow
	gate in _paths
	not _ci_references("data.conformance.trust_dial")
	entry := {
		"rule": "trust_dial_wired",
		"severity": "error",
		"field": gate,
		"msg": "trust-dial gate workflow present but no CI step evaluates the verdict policy (expected data.conformance.trust_dial reference in .github/workflows)",
	}
}

_ci_references(needle) if {
	some line in input.ci_uses
	contains(line, needle)
}

# -- policy self-integrity: the live policy digest must match the manifest --
# Only enforced when a digest was captured (i.e. the scanned repo carries the
# policy file). Consumer repos that call the centralized workflow have no
# vendored policy, so policy_digest is empty and this check is skipped.
deny contains entry if {
	_present(_integrity, "expected_digest")
	_integrity.expected_digest != "PENDING"
	input.policy_digest != ""
	input.policy_digest != _integrity.expected_digest
	entry := {
		"rule": "policy_integrity",
		"severity": "error",
		"field": "conformance/conformance.rego",
		"msg": "conformance policy digest does not match the manifest — conformance.rego has been modified without refreezing data.policy_integrity.expected_digest",
	}
}

# -- policy self-integrity: the manifest field must not be removed ----------
deny contains entry if {
	not _present(_integrity, "expected_digest")
	entry := {
		"rule": "policy_integrity_manifest",
		"severity": "error",
		"field": "data.policy_integrity.expected_digest",
		"msg": "policy integrity manifest missing: data.policy_integrity.expected_digest must be present",
	}
}

# -- affects manifest must cover every tracked file in pulse scope ----------
# The blast-radius pulse is only honest if the manifest is complete: an
# unreachable file is a silent gap. This rule asserts that every tracked file
# under the in-scope directories (conformance/, template/, scripts/, docs/agents/)
# is reachable from at least one conformance/affects.json entry — either as a
# when_changed match or as an affects match. The manifest is loaded via the
# `data.blast_radius.affects` JSON document (conformance/affects.json).
deny contains entry if {
	some path in _paths
	_in_pulse_scope(path)
	count(data.blast_radius.affects) > 0
	not _reachable_from_affects(path)
	entry := {
		"rule": "affects_manifest_complete",
		"severity": "error",
		"field": path,
		"msg": sprintf(
			"file %v is in pulse scope but is not reachable from any conformance/affects.json entry — add a when_changed or affects glob that covers it",
			[path],
		),
	}
}

_in_pulse_scope(path) if startswith(path, "conformance/")

_in_pulse_scope(path) if startswith(path, "template/")

_in_pulse_scope(path) if startswith(path, "scripts/")

_in_pulse_scope(path) if startswith(path, "docs/agents/")

_reachable_from_affects(path) if {
	some entry in data.blast_radius.affects
	_affects_glob_match(_affects_strip_subtarget(entry.when_changed), path)
}

_reachable_from_affects(path) if {
	some entry in data.blast_radius.affects
	some pattern in entry.affects
	_affects_glob_match(pattern, path)
}

_affects_strip_subtarget(pattern) := before if {
	contains(pattern, "#")
	before := split(pattern, "#")[0]
}

_affects_strip_subtarget(pattern) := pattern if {
	not contains(pattern, "#")
}

_affects_glob_match(pattern, path) if {
	glob.match(pattern, ["/"], path)
}

_affects_glob_match(pattern, path) if {
	not contains(pattern, "*")
	pattern == path
}

# ---------------------------------------------------------------------------
# Surface rules
# ---------------------------------------------------------------------------

# Every violation, errors and warnings alike.
violations := deny

# Error-severity violations only — these block CI.
errors := {d | some d in deny; d.severity == "error"}

# Warning-severity violations — reported but non-blocking.
warnings := {d | some d in deny; d.severity == "warning"}

# A repository conforms when it has zero error-severity violations.
default allow := false

allow if count(errors) == 0

# Compact result summary for CI output.
summary := {
	"allow": allow,
	"total": count(deny),
	"errors": count(errors),
	"warnings": count(warnings),
}
