#!/usr/bin/env bash
# check-sanitization.sh — fail if a tracked file contains an internal-only term.
#
# The denylist is base64-encoded so this script — which is itself published —
# never spells the forbidden terms in plaintext, and GitHub code search does not
# index them. The list is decoded only in memory, at runtime.
#
# Regenerate the denylist with:
#   printf 'term-one\nterm-two\n' | base64
set -euo pipefail

# Base64-encoded, newline-separated list of forbidden fixed-string patterns.
DENYLIST_B64="am9uYXRoYW5zX21hY2Jvb2sKODRkNjliYmEtCi9Vc2Vycy9qb25hdGhhbnMK"

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$root"

fail=0
count=0
while IFS= read -r pattern; do
	[ -z "$pattern" ] && continue
	count=$((count + 1))
	if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
		matches="$(git grep -n -I --fixed-strings -e "$pattern" -- . ':!scripts/check-sanitization.sh' 2>/dev/null || true)"
	else
		matches="$(grep -rnI --fixed-strings -e "$pattern" --exclude-dir=.git --exclude='check-sanitization.sh' . 2>/dev/null || true)"
	fi
	if [ -n "$matches" ]; then
		echo "SANITIZATION VIOLATION — internal term #${count} found:"
		echo "$matches"
		fail=1
	fi
done < <(printf '%s' "$DENYLIST_B64" | base64 --decode)

if [ "$fail" -ne 0 ]; then
	echo "check-sanitization: FAIL — internal terms must be removed before publication."
	exit 1
fi
echo "check-sanitization: OK (${count} patterns checked, 0 matches)."
