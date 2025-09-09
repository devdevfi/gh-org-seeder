#!/usr/bin/env bash
set -euo pipefail

ORG="${1:-}"
[[ -n "$ORG" ]] || { echo "Usage: $0 <org>" >&2; exit 2; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TS="$(date +%Y%m%dT%H%M%S)"
OUT="$ROOT/.out/${TS}-integrations"
mkdir -p "$OUT"

echo "Org: $ORG" | tee "$OUT/context.txt"

# Token scopes (prove we didn't elevate beyond 'project')
gh api -H "Accept: application/vnd.github+json" -I /user \
  | awk -F': ' 'tolower($1)=="x-oauth-scopes"{print $2}' \
  | tee "$OUT/token_scopes.txt"

# Installed GitHub Apps at the org
gh api "orgs/$ORG/installations" --paginate > "$OUT/installations.json"
jq -r '
  .installations[] |
  [.id, .app.slug, .app.name, (if .suspended_by then "suspended" else "active" end)] |
  @tsv' "$OUT/installations.json" \
  | sed $'s/\t/ | /g' \
  | tee "$OUT/installed_apps.txt"

# Quick Azure Boards flag
if jq -e '.installations[] | select(.app.slug=="azure-boards")' "$OUT/installations.json" >/dev/null; then
  echo "Azure Boards is installed (or requested)." | tee -a "$OUT/installed_apps.txt"
fi

# Org audit log — azure-related activity (installs/permission changes)
gh api "orgs/$ORG/audit-log?per_page=100&phrase=azure" > "$OUT/audit_azure.json" || true
jq -r '
  .[] |
  [.action, .created_at, .actor, (.metadata.app_slug // ""), (.metadata.permission // ""), (.metadata.old_permission // "")] |
  @tsv' "$OUT/audit_azure.json" \
  | sed $'s/\t/ | /g' \
  | tee "$OUT/audit_azure.txt"

# Org audit log — Actions permission changes (often toggled for Copilot setup)
gh api "orgs/$ORG/audit-log?per_page=100&phrase=actions%20permission" > "$OUT/audit_actions_perm.json" || true
jq -r '
  .[] |
  [.action, .created_at, .actor, (.metadata.permission_setting // ""), (.metadata.repository // ""), (.metadata.workflow_repository // "")] |
  @tsv' "$OUT/audit_actions_perm.json" \
  | sed $'s/\t/ | /g' \
  | tee "$OUT/audit_actions_perm.txt"

echo "Wrote artifacts to: $OUT"
