package conformance.conformance_test

import rego.v1

import data.conformance.conformance

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

# Every path a conformant rego-policy repository must contain.
_ok_paths := [
	"README.md", "AGENTS.md", "CLAUDE.md", "LICENSE", "NOTICE",
	"CHANGELOG.md", "CITATION.cff", "CONTRIBUTING.md", "SECURITY.md",
	".gitignore", ".markdownlint-cli2.yaml", "commitlint.config.js", "lefthook.yml",
	".github/CODEOWNERS", ".github/dependabot.yml", ".github/PULL_REQUEST_TEMPLATE.md",
	".github/workflows/ci.yml", ".github/workflows/commitlint.yml",
	".github/workflows/pages.yml", ".github/ISSUE_TEMPLATE/config.yml",
	"docs/agents/conventions.md", "docs/agents/citation.md",
	"docs/agents/glossary.md", "docs/agents/enforcement.md",
	"scripts/check-sanitization.sh", "scripts/pulse.sh",
	"conformance/conformance.rego",
	".github/workflows/validate-branch-name.yml",
	".github/workflows/validate-branch-tier.yml",
	".github/workflows/validate-linked-issue.yml",
	".github/workflows/trust-dial-gate.yml",
	".github/workflows/trust-dial-outcome.yml",
	".github/workflows/blast-radius-pulse.yml",
	".github/workflows/blast-radius-outcome.yml",
	"audit/trust-dial-state.json",
	"audit/decision-trace.jsonl",
	"audit/blast-radius.jsonl",
	"conformance/affects.json",
	"conformance/blast_radius.rego",
	"conformance/blast_radius_test.rego",
	"docs/adr/ADR-002-blast-radius-pulse.md",
]

_ok_files := [{"path": p, "size": 100} | some p in _ok_paths]

_ok_dirs := [
	".github", ".github/workflows", ".github/ISSUE_TEMPLATE",
	"docs", "docs/agents", "scripts", "conformance", "audit",
]

_ok_input := {
	"repo": "example",
	"owner": "jonathan-kellerai",
	"artifact_type": "rego-policy",
	"files": _ok_files,
	"dirs": _ok_dirs,
	"branches": ["main"],
	"file_meta": {
		"AGENTS.md": {"line_count": 99, "first_content_line": "# AGENTS.md", "tail": "tier-2 pointers"},
		"CLAUDE.md": {"line_count": 34, "first_content_line": "@AGENTS.md", "tail": "claude notes"},
		"README.md": {"line_count": 200, "first_content_line": "# Example", "tail": "### For agents\nstart at AGENTS.md"},
		".gitignore": {"line_count": 10, "lines": [".claude/", ".claude-tmp/", ".DS_Store", "node_modules/"]},
	},
	"ci_uses": ["open-policy-agent/setup-opa@v2.4.0", "opa check", "opa test", "data.conformance.trust_dial.decision"],
	"policy_digest": "",
}

# Drop one path from the conformant file list.
_drop(path) := [f | some f in _ok_files; f.path != path]

# True when some deny entry carries the given rule id.
_fires(result, rule) if {
	some d in result
	d.rule == rule
}

# ---------------------------------------------------------------------------
# Happy path
# ---------------------------------------------------------------------------

test_conformant_input_allows if {
	conformance.allow with input as _ok_input
}

test_conformant_input_no_errors if {
	count(conformance.errors) == 0 with input as _ok_input
}

test_conformant_input_no_warnings if {
	count(conformance.warnings) == 0 with input as _ok_input
}

# ---------------------------------------------------------------------------
# Structural error rules
# ---------------------------------------------------------------------------

test_missing_required_file if {
	bad := object.union(_ok_input, {"files": _drop("README.md")})
	result := conformance.deny with input as bad
	_fires(result, "required_file")
	not conformance.allow with input as bad
}

test_missing_required_dir if {
	bad := object.union(_ok_input, {"dirs": [d | some d in _ok_dirs; d != "scripts"]})
	_fires(conformance.deny, "required_dir") with input as bad
}

test_missing_github_file if {
	bad := object.union(_ok_input, {"files": _drop(".github/CODEOWNERS")})
	_fires(conformance.deny, "required_github_file") with input as bad
}

test_missing_agent_doc if {
	bad := object.union(_ok_input, {"files": _drop("docs/agents/glossary.md")})
	_fires(conformance.deny, "required_agent_doc") with input as bad
}

test_missing_script if {
	bad := object.union(_ok_input, {"files": _drop("scripts/check-sanitization.sh")})
	_fires(conformance.deny, "required_script") with input as bad
}

test_unknown_artifact_type if {
	bad := object.union(_ok_input, {"artifact_type": "not-a-type"})
	_fires(conformance.deny, "artifact_type_known") with input as bad
}

test_missing_artifact_dir if {
	bad := object.union(_ok_input, {"dirs": [d | some d in _ok_dirs; d != "conformance"]})
	_fires(conformance.deny, "artifact_dir") with input as bad
}

test_claude_md_bad_import if {
	bad := object.union(_ok_input, {"file_meta": {"CLAUDE.md": {"first_content_line": "# CLAUDE.md"}}})
	_fires(conformance.deny, "claude_md_import") with input as bad
}

test_gitignore_missing_pattern if {
	bad := object.union(_ok_input, {"file_meta": {".gitignore": {"lines": [".claude/", "node_modules/"]}}})
	_fires(conformance.deny, "gitignore_coverage") with input as bad
}

test_forbidden_branch if {
	bad := object.union(_ok_input, {"branches": ["main", "master"]})
	_fires(conformance.deny, "forbidden_branch") with input as bad
}

# ---------------------------------------------------------------------------
# Warning rules
# ---------------------------------------------------------------------------

test_agents_md_too_long if {
	bad := object.union(_ok_input, {"file_meta": {"AGENTS.md": {"line_count": 300}}})
	result := conformance.deny with input as bad
	_fires(result, "agents_md_length")
	conformance.allow with input as bad
}

test_claude_md_too_long if {
	bad := object.union(_ok_input, {"file_meta": {"CLAUDE.md": {"line_count": 120}}})
	_fires(conformance.deny, "claude_md_length") with input as bad
}

test_readme_missing_footer if {
	bad := object.union(_ok_input, {"file_meta": {"README.md": {"tail": "plain closing text"}}})
	_fires(conformance.deny, "readme_agent_footer") with input as bad
}

test_primary_validator_not_wired if {
	bad := object.union(_ok_input, {"ci_uses": ["actions/checkout@v4"]})
	_fires(conformance.deny, "primary_validator_wired") with input as bad
}

# ---------------------------------------------------------------------------
# Policy self-integrity
# ---------------------------------------------------------------------------

test_policy_integrity_mismatch if {
	bad := object.union(_ok_input, {"policy_digest": "wrong-digest"})
	result := conformance.deny with input as bad
		with data.policy_integrity as {"algorithm": "sha256", "expected_digest": "right-digest"}
	_fires(result, "policy_integrity")
}

test_policy_integrity_match_passes if {
	good := object.union(_ok_input, {"policy_digest": "matching-digest"})
	result := conformance.deny with input as good
		with data.policy_integrity as {"algorithm": "sha256", "expected_digest": "matching-digest"}
	not _fires(result, "policy_integrity")
}

test_policy_integrity_skipped_when_no_digest if {
	good := object.union(_ok_input, {"policy_digest": ""})
	result := conformance.deny with input as good
		with data.policy_integrity as {"algorithm": "sha256", "expected_digest": "some-digest"}
	not _fires(result, "policy_integrity")
}

test_policy_integrity_manifest_missing if {
	result := conformance.deny with input as _ok_input
		with data.policy_integrity as {"algorithm": "sha256"}
	_fires(result, "policy_integrity_manifest")
}

# ---------------------------------------------------------------------------
# Data sanity
# ---------------------------------------------------------------------------

test_data_sentinel_fires_without_schema if {
	result := conformance.deny with input as _ok_input with data.schema as false
	_fires(result, "data_sentinel")
}
