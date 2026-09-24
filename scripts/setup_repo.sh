#!/usr/bin/env bash
# One-time GitHub setup for this repo. Run it yourself — it changes settings on
# github.com, so it asks before it writes anything.
#
#   ./scripts/setup_repo.sh --dry-run   show what would change, touch nothing
#   ./scripts/setup_repo.sh             apply it
#
# What it does:
#   1. verifies the ANTHROPIC_API_KEY secret exists (the review gate needs it)
#   2. sets squash-only merges and auto-delete of merged branches
#   3. creates/updates the "main" branch ruleset from .github/rulesets/main.json,
#      which requires a PR and a passing "Claude review" check before merging
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

dry_run=0
[ "${1:-}" = "--dry-run" ] && dry_run=1

command -v gh >/dev/null 2>&1 || { echo "error: gh not found (brew install gh)" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "error: not logged in (gh auth login)" >&2; exit 1; }

repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
ruleset_file=".github/rulesets/main.json"
[ -f "${ruleset_file}" ] || { echo "error: ${ruleset_file} not found" >&2; exit 1; }

echo "repository: ${repo}"
echo

# --- 1. the API key the gate runs on ------------------------------------------
if gh secret list --repo "${repo}" | grep -q '^ANTHROPIC_API_KEY'; then
  echo "[ok]   secret ANTHROPIC_API_KEY is set"
else
  echo "[todo] secret ANTHROPIC_API_KEY is NOT set — the Claude review gate cannot run."
  echo "       Set it with:"
  echo "         gh secret set ANTHROPIC_API_KEY --repo ${repo}"
  echo "       (paste the key from https://console.anthropic.com/settings/keys)"
fi
echo

# --- 2. merge settings --------------------------------------------------------
echo "[plan] squash-only merges, delete branch on merge"

# --- 3. branch ruleset --------------------------------------------------------
existing_id="$(gh api "repos/${repo}/rulesets" --jq '.[] | select(.name=="main") | .id' 2>/dev/null || true)"
if [ -n "${existing_id}" ]; then
  echo "[plan] update existing ruleset 'main' (id ${existing_id}) from ${ruleset_file}"
else
  echo "[plan] create ruleset 'main' from ${ruleset_file}"
fi
echo "       required checks: $(python3 -c '
import json
d = json.load(open(".github/rulesets/main.json"))
for r in d["rules"]:
    if r["type"] == "required_status_checks":
        print(", ".join(c["context"] for c in r["parameters"]["required_status_checks"]))
')"
echo

if [ "${dry_run}" -eq 1 ]; then
  echo "dry run — nothing was changed"
  exit 0
fi

read -r -p "Apply these changes to ${repo}? [y/N] " answer
case "${answer}" in
  [yY]|[yY][eE][sS]) ;;
  *) echo "aborted"; exit 0 ;;
esac

gh api -X PATCH "repos/${repo}" \
  -F allow_squash_merge=true \
  -F allow_merge_commit=false \
  -F allow_rebase_merge=false \
  -F delete_branch_on_merge=true \
  --silent
echo "[done] merge settings updated"

if [ -n "${existing_id}" ]; then
  gh api -X PUT "repos/${repo}/rulesets/${existing_id}" --input "${ruleset_file}" --silent
  echo "[done] ruleset 'main' updated"
else
  gh api -X POST "repos/${repo}/rulesets" --input "${ruleset_file}" --silent
  echo "[done] ruleset 'main' created"
fi

echo
echo "main is now protected. Direct pushes are rejected; open a PR instead:"
echo "  ./scripts/dev.sh branch my-change"
echo "  ./scripts/dev.sh pr"
echo
echo "Note: required status checks only start blocking once GitHub has seen each"
echo "check run at least once — the first PR after this is what registers them."
