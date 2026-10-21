#!/usr/bin/env bash
# preflight.sh — pre-work environment check for this repository.
#
# Closes IC-1 (output directories created before work begins) and IC-7
# (publication readiness). Read-only except for `mkdir -p` of the declared
# artifact directory. Run it before phase work and from the agentic-gates CI
# job. Exits non-zero with a one-line remediation on any failure.
set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

marker=".kellerai-oss.json"
if [ ! -f "$marker" ]; then
	echo "preflight: conformance marker $marker is missing" >&2
	exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
	echo "preflight: jq is required but is not on PATH" >&2
	exit 1
fi

artifact_dir="$(jq -r '.artifact_dir // empty' "$marker")"
if [ -z "$artifact_dir" ]; then
	echo "preflight: artifact_dir is not set in $marker" >&2
	exit 1
fi

# IC-1 — ensure the declared artifact directory exists before any phase work.
mkdir -p "$artifact_dir"

# IC-7 — publication readiness: core governance files must be present.
missing=0
for f in README.md AGENTS.md CLAUDE.md LICENSE NOTICE CHANGELOG.md lefthook.yml; do
	if [ ! -f "$f" ]; then
		echo "preflight: required file missing: $f" >&2
		missing=1
	fi
done
if [ "$missing" -ne 0 ]; then
	echo "preflight: repository is not publication-ready" >&2
	exit 1
fi

echo "preflight: OK — artifact directory '$artifact_dir' present; governance files present"
