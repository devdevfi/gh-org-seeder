#!/usr/bin/env bash
# gh-org-seed.sh — Org-level GitHub Projects (v2) seeder
# Step 2: Preflight, flags validation, seed validation (AJV primary, Python fallback),
# and Sprint window computation artifact.

set -euo pipefail

# Colors + logging helpers
BLUE="\033[0;34m"; GREEN="\033[0;32m"; YELLOW="\033[1;33m"; RED="\033[0;31m"; NC="\033[0m"
log_info()    { echo -e "${BLUE}ℹ ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠️${NC}  $1"; }
log_error()   { echo -e "${RED}✗${NC} $1"; }
die()         { log_error "$1"; exit "${2:-1}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TS="$(date +%Y%m%dT%H%M%S)"
OUT_DIR="${SCRIPT_DIR}/.out/${TS}"
mkdir -p "${OUT_DIR}" "${OUT_DIR}/schema"

VERBOSE=0
DRY_RUN=0
YES=0
VISIBILITY="internal"
SPRINT_CADENCE_DAYS=14

usage() {
  cat <<'USAGE'
Usage: ./gh-org-seed.sh \
  --start-date "MM/DD/YYYY" \
  --seed-file <dir> \
  --org-name <org> \
  --project-name <string> \
  --project-id <number> \
  [--org-shortname <SHORT>] \
  [--sprint-cadence-days <int>] \
  [--visibility internal|private] \
  [--dry-run] [--yes] [--verbose] \
  [--help]

Example:
  ./gh-org-seed.sh --start-date "11/05/2025" --seed-file ./seeds/acme \
    --org-name acme-corp --project-name "ACME Delivery" --project-id 1 \
    --org-shortname ACME --sprint-cadence-days 14
USAGE
}

# Flag vars
START_DATE=""
SEED_DIR=""
ORG_NAME=""
PROJECT_NAME=""
PROJECT_ID=""
ORG_SHORTNAME=""

enable_verbose() {
  if [[ "$VERBOSE" == "1" ]]; then
    set -x
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --start-date) START_DATE="${2:-}"; shift 2 ;;
      --seed-file) SEED_DIR="${2:-}"; shift 2 ;;
      --org-name) ORG_NAME="${2:-}"; shift 2 ;;
      --project-name) PROJECT_NAME="${2:-}"; shift 2 ;;
      --project-id) PROJECT_ID="${2:-}"; shift 2 ;;
      --org-shortname) ORG_SHORTNAME="${2:-}"; shift 2 ;;
      --sprint-cadence-days) SPRINT_CADENCE_DAYS="${2:-}"; shift 2 ;;
      --visibility) VISIBILITY="${2:-}"; shift 2 ;;
      --dry-run) DRY_RUN=1; shift ;;
      --yes) YES=1; shift ;;
      --verbose) VERBOSE=1; shift ;;
      --help|-h) usage; exit 0 ;;
      *) log_error "Unknown flag: $1"; usage; exit 2 ;;
    esac
  done
}

check_prereqs() {
  log_info "Tool versions"
  { gh --version || true; } | tee -a "${OUT_DIR}/versions.log"
  { git --version || true; } | tee -a "${OUT_DIR}/versions.log"
  { python3 --version || true; } | tee -a "${OUT_DIR}/versions.log"
  { jq --version || true; } | tee -a "${OUT_DIR}/versions.log"
  { node --version || true; } | tee -a "${OUT_DIR}/versions.log" || true
  { npx --version || true; } | tee -a "${OUT_DIR}/versions.log" || true

  command -v gh >/dev/null || die "gh CLI not found"
  command -v git >/dev/null || die "git not found"
  command -v python3 >/dev/null || die "python3 not found"
  command -v jq >/dev/null || log_warning "jq not found (recommended)"
  # Node is optional; only needed for ajv-cli
  if ! gh auth status >/dev/null 2>&1; then
    die "gh auth status failed. Run 'gh auth login' with a token that has 'project' scope."
  fi
}

validate_flags() {
  [[ -n "$START_DATE" ]]      || die "Missing required: --start-date"
  [[ -n "$SEED_DIR" ]]        || die "Missing required: --seed-file"
  [[ -n "$ORG_NAME" ]]        || die "Missing required: --org-name"
  [[ -n "$PROJECT_NAME" ]]    || die "Missing required: --project-name"
  [[ -n "$PROJECT_ID" ]]      || die "Missing required: --project-id"
  [[ "$PROJECT_ID" =~ ^[0-9]+$ ]] || die "--project-id must be a number"
  [[ "$START_DATE" =~ ^[0-1][0-9]/[0-3][0-9]/[0-9]{4}$ ]] || die "--start-date must be MM/DD/YYYY"
  SEED_JSON="${SEED_DIR%/}/gh_seed.json"
  [[ -f "$SEED_JSON" ]] || die "Seed file not found at $SEED_JSON"
  echo "$SEED_JSON" > "${OUT_DIR}/seed.path"
}

validate_seed() {
  local SEED_JSON="$1"
  local SCHEMA="${SCRIPT_DIR}/schema/gh_seed.schema.json"
  [[ -f "$SCHEMA" ]] || die "Schema not found at $SCHEMA"

  log_info "Validating seed with AJV (primary) or Python fallback"
  if command -v npx >/dev/null 2>&1; then
    set +e
    npx --yes ajv-cli -s "$SCHEMA" -d "$SEED_JSON" > "${OUT_DIR}/ajv.out" 2> "${OUT_DIR}/ajv.err"
    local rc=$?
    set -e
    if [[ $rc -eq 0 ]]; then
      log_success "AJV validation passed"
      cp "$SCHEMA" "${OUT_DIR}/schema/gh_seed.schema.json"
      return 0
    else
      log_warning "AJV validation failed or Node missing; falling back to Python (${OUT_DIR}/ajv.err)"
    fi
  else
    log_warning "npx not found; using Python fallback"
  fi

  # Python fallback
  python3 "${SCRIPT_DIR}/python/validate_seed.py" "$SEED_JSON" > "${OUT_DIR}/validate_fallback.json" 2> "${OUT_DIR}/validate_fallback.err" || {
    log_error "Fallback validation failed; see ${OUT_DIR}/validate_fallback.err"
    exit 3
  }
  log_success "Fallback validation passed"
  cp "$SCHEMA" "${OUT_DIR}/schema/gh_seed.schema.json"
}

compute_iterations() {
  local SEED_JSON="$1"
  log_info "Computing Sprint windows from start date and seed max sprint"
  python3 "${SCRIPT_DIR}/python/compute_sprints.py" \
    --start-date "$START_DATE" \
    --cadence "$SPRINT_CADENCE_DAYS" \
    --seed "$SEED_JSON" > "${OUT_DIR}/sprints.json"
  local count
  count=$(jq 'length' "${OUT_DIR}/sprints.json" 2>/dev/null || echo "0")
  log_success "Computed ${count} sprint window(s) → ${OUT_DIR}/sprints.json"
}

summarize() {
  local SEED_JSON="$1"
  local sprint_count
  sprint_count=$(jq 'length' "${OUT_DIR}/sprints.json" 2>/dev/null || echo "0")
  jq -n \
    --arg start_date "$START_DATE" \
    --arg cadence "$SPRINT_CADENCE_DAYS" \
    --arg seed "$SEED_JSON" \
    --arg out_dir "$OUT_DIR" \
    --arg org "$ORG_NAME" \
    --arg project_name "$PROJECT_NAME" \
    --arg project_id "$PROJECT_ID" \
    --argjson sprint_count "$sprint_count" \
    '{run: {org:$org, project:{name:$project_name, number:$project_id}, start_date:$start_date, cadence_days:($cadence|tonumber), seed:$seed, out_dir:$out_dir, sprint_count:$sprint_count}}' \
    > "${OUT_DIR}/summary.json"
  log_success "Wrote summary → ${OUT_DIR}/summary.json"
}

main() {
  parse_args "$@"
  enable_verbose
  check_prereqs
  validate_flags

  local SEED_JSON="${SEED_DIR%/}/gh_seed.json"
  validate_seed "$SEED_JSON"
  compute_iterations "$SEED_JSON"
  summarize "$SEED_JSON"

  log_success "Step 2 slice complete: preflight, validation, and sprint computation are working."
  log_info "Next step will create or reuse the org-level Project and upsert fields."
}

main "$@"
