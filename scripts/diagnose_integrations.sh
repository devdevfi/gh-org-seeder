#!/usr/bin/env bash
set -euo pipefail

ORG="${1:-}"
[[ -n "$ORG" ]] || { echo "Usage: $0 <org>" >&2; exit 2; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TS="$(date +%Y%m%dT%H%M%S)"
OUT="$ROOT/.out/${TS}-integrations"
mkdir -p "$OUT"

echo "Org: $ORG" | tee "$OUT/context.txt"

# 1) Token scopes — use -i (include headers), not -I
#    Keep run resilient: never fail the whole script on a single call
set +e
gh api -i /user > "$OUT/user_headers.txt" 2> "$OUT/user_headers.err"
scopes="$(awk -F': ' 'tolower($1)=="x-oauth-scopes"{print $2}' "$OUT/user_headers.txt" | tr -d '\r')"
echo "${scopes:-<unavailable>}" > "$OUT/token_scopes.txt"
set -e

# 2) Installed GitHub Apps at the org (Azure Boards slug is `azure-boards`)
set +e
gh api -H "Accept: application/vnd.github+json" "orgs/$ORG/installations" --paginate > "$OUT/installations.json" 2> "$OUT/installations.err"
ins_rc=$?
set -e

if [[ $ins_rc -eq 0 ]] && jq -e '.installations' "$OUT/installations.json" >/dev/null 2>&1; then
  jq -r '.installations[] | [.id, .app.slug, .app.name, (if .suspended_by then "suspended" else "active" end)] | @tsv' "$OUT/installations.json" \
    | sed $'s/\t/ | /g' > "$OUT/installed_apps.txt"
  if jq -e '.installations[] | select(.app.slug=="azure-boards")' "$OUT/installations.json" >/dev/null 2>&1; then
    echo "Azure Boards is installed (or pending)" >> "$OUT/installed_apps.txt"
  fi
else
  echo "<no installations payload>" > "$OUT/installed_apps.txt"
fi

# 3) Org audit log — azure-related activity (installs/permission changes)
set +e
gh api "orgs/$ORG/audit-log?per_page=100&phrase=azure" > "$OUT/audit_azure.json" 2> "$OUT/audit_azure.err"
az_rc=$?
set -e
if [[ $az_rc -eq 0 ]] && jq -e 'type=="array"' "$OUT/audit_azure.json" >/dev/null 2>&1; then
  jq -r '.[] | [.action, .created_at, .actor, (.metadata.app_slug // ""), (.metadata.permission // ""), (.metadata.old_permission // "")] | @tsv' "$OUT/audit_azure.json" \
    | sed $'s/\t/ | /g' > "$OUT/audit_azure.txt"
else
  echo "<no audit results or not accessible>" > "$OUT/audit_azure.txt"
fi

# 4) Org audit log — Actions permission changes (often toggled for Copilot setup)
set +e
gh api "orgs/$ORG/audit-log?per_page=100&phrase=actions%20permission" > "$OUT/audit_actions_perm.json" 2> "$OUT/audit_actions_perm.err"
act_rc=$?
set -e
if [[ $act_rc -eq 0 ]] && jq -e 'type=="array"' "$OUT/audit_actions_perm.json" >/dev/null 2>&1; then
  jq -r '.[] | [.action, .created_at, .actor, (.metadata.permission_setting // ""), (.metadata.repository // ""), (.metadata.workflow_repository // "")] | @tsv' "$OUT/audit_actions_perm.json" \
    | sed $'s/\t/ | /g' > "$OUT/audit_actions_perm.txt"
else
  echo "<no audit results or not accessible>" > "$OUT/audit_actions_perm.txt"
fi

echo "Wrote artifacts to: $OUT"
