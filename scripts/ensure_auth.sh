#!/usr/bin/env bash
# ensure_auth.sh — verify GH token scopes and org membership/role

set -euo pipefail

ensure_scopes_and_org_perms() {
  local org="$1"
  local want_delete_repo="$2"   # "1" or "0"
  local out_dir="$3"

  # Try to refresh required scopes (no-op if already granted)
  gh auth refresh -s project >/dev/null 2>&1 || true
  if [[ "$want_delete_repo" == "1" ]]; then
    gh auth refresh -s delete_repo >/dev/null 2>&1 || true
  fi

  # Capture token scopes from response headers
  {
    echo "# Response headers from GET /user"
    gh api -i user
  } > "${out_dir}/oauth_headers.txt" 2>/dev/null || true

  # Extract the scopes line (normalize CRLF)
  local scopes
  scopes="$(tr -d '\r' < "${out_dir}/oauth_headers.txt" | awk -F': ' 'tolower($1)=="x-oauth-scopes"{print $2}')"
  echo "${scopes:-}" > "${out_dir}/oauth_scopes.txt"

  # Resolve current login (for CODEOWNERS later too)
  local login
  login="$(gh api user --jq .login 2>/dev/null || echo "")"
  [[ -n "$login" ]] && echo "$login" > "${out_dir}/caller.login"

  # If org provided, try to detect your role (admin/owner/member)
  if [[ -n "$org" ]]; then
    local role="unknown"
    role="$(gh api "orgs/${org}/memberships/${login}" --jq .role 2>/dev/null || echo "unknown")"
    jq -n --arg org "$org" --arg login "$login" --arg role "$role" \
      '{org:$org, login:$login, role:$role, scopes: input}' \
      "${out_dir}/oauth_scopes.txt" > "${out_dir}/auth_summary.json" 2>/dev/null || true

    if [[ "$role" != "admin" && "$role" != "owner" ]]; then
      echo "WARN: Your role in org '${org}' is '${role}'. Creating org Projects (v2) generally requires admin/owner. You can still run with --dry-run or use a pre-created project." \
        | tee -a "${out_dir}/auth.warnings"
    fi
  fi
}
