#!/usr/bin/env bash
# scan-repo-structure.sh — emit a repo-structure.json snapshot for the
# OSS governance library conformance standard (conformance/conformance.rego).
#
# Read-only. Prints JSON to stdout. Tracked files only (git ls-files) when the
# target is a git repo; falls back to a filesystem walk otherwise.
set -euo pipefail

artifact_type=""
artifact_dir=""
root=""
while [ "$#" -gt 0 ]; do
	case "${1:-}" in
	--artifact-type) artifact_type="${2:-}"; shift 2 ;;
	--artifact-dir) artifact_dir="${2:-}"; shift 2 ;;
	--root) root="${2:-}"; shift 2 ;;
	-h | --help)
		echo "usage: scan-repo-structure.sh [--artifact-type T] [--artifact-dir D] [--root PATH]"
		exit 0
		;;
	*)
		echo "scan-repo-structure: unknown argument: ${1:-}" >&2
		exit 2
		;;
	esac
done

[ -n "$root" ] || root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$root"

is_git=0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 && is_git=1

# artifact type / dir: CLI flag wins, else the .kellerai-oss.json marker.
marker=".kellerai-oss.json"
if [ -f "$marker" ]; then
	[ -n "$artifact_type" ] || artifact_type="$(jq -r '.artifact_type // empty' "$marker" 2>/dev/null || true)"
	[ -n "$artifact_dir" ] || artifact_dir="$(jq -r '.artifact_dir // empty' "$marker" 2>/dev/null || true)"
fi

# repo slug from the origin remote, if any.
repo="$(basename "$root")"
owner=""
remote="$(git config --get remote.origin.url 2>/dev/null || true)"
case "$remote" in
*github.com*)
	trimmed="${remote#*github.com}"
	trimmed="${trimmed#:}"
	trimmed="${trimmed#/}"
	trimmed="${trimmed%.git}"
	owner="${trimmed%%/*}"
	[ "${trimmed#*/}" != "$trimmed" ] && repo="${trimmed##*/}"
	;;
esac

sha256() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | awk '{print $1}'
	else
		shasum -a 256 "$1" | awk '{print $1}'
	fi
}

first_content_line() {
	awk 'NF==0{next} /^[[:space:]]*<!--/{next} {print; exit}' "$1"
}

meta_file() {
	local f="$1"
	if [ ! -f "$f" ]; then
		echo "null"
		return
	fi
	local lc fcl tl
	lc="$(awk 'END{print NR+0}' "$f")"
	fcl="$(first_content_line "$f")"
	tl="$(tail -n 15 "$f")"
	jq -n --argjson lc "$lc" --arg fcl "$fcl" --arg tl "$tl" \
		'{line_count: $lc, first_content_line: $fcl, tail: $tl}'
}

gitignore_meta() {
	local f=".gitignore"
	if [ ! -f "$f" ]; then
		echo "null"
		return
	fi
	local lc
	lc="$(awk 'END{print NR+0}' "$f")"
	awk 'NF==0{next} /^[[:space:]]*#/{next} {gsub(/^[ \t]+|[ \t]+$/,""); print}' "$f" |
		jq -R -s --argjson lc "$lc" \
			'{line_count: $lc, lines: (split("\n") | map(select(length > 0)))}'
}

tmp_files="$(mktemp)"
tmp_branches="$(mktemp)"
tmp_ci="$(mktemp)"
trap 'rm -f "$tmp_files" "$tmp_branches" "$tmp_ci"' EXIT

if [ "$is_git" -eq 1 ]; then
	git ls-files
else
	find . -type f -not -path './.git/*' | sed 's|^\./||'
fi | LC_ALL=C sort -u >"$tmp_files"

if [ "$is_git" -eq 1 ]; then
	git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null |
		sed 's|^origin/||' | grep -v '^HEAD$' | LC_ALL=C sort -u >"$tmp_branches" || true
fi
[ -s "$tmp_branches" ] || echo "main" >"$tmp_branches"

: >"$tmp_ci"
if [ -d ".github/workflows" ]; then
	for wf in .github/workflows/*.yml .github/workflows/*.yaml; do
		[ -f "$wf" ] && cat "$wf" >>"$tmp_ci"
	done
fi

policy_digest=""
[ -f "conformance/conformance.rego" ] && policy_digest="$(sha256 conformance/conformance.rego)"

jq -n \
	--arg repo "$repo" \
	--arg owner "$owner" \
	--arg atype "$artifact_type" \
	--arg adir "$artifact_dir" \
	--arg digest "$policy_digest" \
	--rawfile files "$tmp_files" \
	--rawfile branches "$tmp_branches" \
	--rawfile ci "$tmp_ci" \
	--argjson fm_agents "$(meta_file AGENTS.md)" \
	--argjson fm_claude "$(meta_file CLAUDE.md)" \
	--argjson fm_readme "$(meta_file README.md)" \
	--argjson fm_gitignore "$(gitignore_meta)" \
	'
	($files | split("\n") | map(select(length > 0))) as $paths
	| {
	    repo: $repo,
	    owner: $owner,
	    artifact_type: $atype,
	    files: ($paths | map({path: .})),
	    dirs: ([$paths[] | split("/") as $p | range(1; ($p | length)) as $i | ($p[0:$i] | join("/"))] | unique),
	    branches: ($branches | split("\n") | map(select(length > 0))),
	    file_meta: ({
	      "AGENTS.md": $fm_agents,
	      "CLAUDE.md": $fm_claude,
	      "README.md": $fm_readme,
	      ".gitignore": $fm_gitignore
	    } | with_entries(select(.value != null))),
	    ci_uses: ($ci | split("\n") | map(select(length > 0))),
	    policy_digest: $digest
	  }
	| . + {artifact_dir: (if $adir != "" then $adir
	         else ({"json-schema":"schemas","markdown-spec":"specs","rego-policy":"conformance","rag-config":"configs"}[$atype] // "")
	         end)}
	'
