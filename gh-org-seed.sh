#!/usr/bin/env bash
# gh-org-seed.sh — Org-level GitHub Projects (v2) seeder
# Slice: ensure org Project exists, upsert fields (Priority/Size/Estimate) and Sprint iterations

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
USAGE
}

# Flag vars
START_DATE=""
SEED_DIR=""
ORG_NAME=""
PROJECT_NAME=""
PROJECT_ID=""
ORG_SHORTNAME=""

enable_verbose() { [[ "$VERBOSE" == "1" ]] && set -x || true; }

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
  gh auth status >/dev/null 2>&1 || die "gh auth status failed. Run 'gh auth login' with token having 'project' scope."
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

# --- helpers ---
CMDS_LOG="${OUT_DIR}/commands.log"
run_mut() {
  # mutation wrapper: log & optionally skip on dry-run
  echo "$*" >> "$CMDS_LOG"
  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[dry-run] $*"
  else
    eval "$@"
  fi
}

# --- slice from previous step ---
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
  python3 "${SCRIPT_DIR}/python/validate_seed.py" "$SEED_JSON" > "${OUT_DIR}/validate_fallback.json" 2> "${OUT_DIR}/validate_fallback.err" || {
    log_error "Fallback validation failed; see ${OUT_DIR}/validate_fallback.err"; exit 3; }
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

# --- new slice: Project + Fields + Iterations ---
ensure_project() {
  log_info "Ensuring org project exists or creating it if missing"
  local view_json="${OUT_DIR}/project.view.json"
  set +e
  gh project view "$PROJECT_ID" --owner "$ORG_NAME" --format json > "$view_json" 2> "${OUT_DIR}/project.view.err"
  local rc=$?
  set -e
  if [[ $rc -ne 0 || ! -s "$view_json" ]]; then
    log_warning "Project number $PROJECT_ID not found under '$ORG_NAME'. Searching by title: '$PROJECT_NAME'"
    gh project list --owner "$ORG_NAME" --format json > "${OUT_DIR}/project.list.json" || true
    local found_number
    found_number=$(jq -r --arg t "$PROJECT_NAME" '.projects[]? | select(.title==$t) | .number' "${OUT_DIR}/project.list.json" 2>/dev/null || echo "")
    if [[ -n "$found_number" && "$found_number" != "null" ]]; then
      log_warning "Title exists with number $found_number; using that instead of provided $PROJECT_ID"
      PROJECT_ID="$found_number"
      gh project view "$PROJECT_ID" --owner "$ORG_NAME" --format json > "$view_json"
    else
      log_info "Creating project '$PROJECT_NAME' for owner '$ORG_NAME'"
      run_mut "gh project create --owner \"$ORG_NAME\" --title \"$PROJECT_NAME\" > \"${OUT_DIR}/project.create.out\" 2> \"${OUT_DIR}/project.create.err\""
      # refresh list and pick up new number
      gh project list --owner "$ORG_NAME" --format json > "${OUT_DIR}/project.list.post.json"
      PROJECT_ID=$(jq -r --arg t "$PROJECT_NAME" '.projects[] | select(.title==$t) | .number' "${OUT_DIR}/project.list.post.json")
      [[ -n "$PROJECT_ID" && "$PROJECT_ID" != "null" ]] || die "Failed to resolve created project number for '$PROJECT_NAME'"
      gh project view "$PROJECT_ID" --owner "$ORG_NAME" --format json > "$view_json"
      log_success "Created project '$PROJECT_NAME' → number $PROJECT_ID"
    fi
  else
    log_success "Found project number $PROJECT_ID under '$ORG_NAME'"
  fi

  PROJECT_NODE_ID=$(jq -r '.id' "$view_json")
  [[ -n "$PROJECT_NODE_ID" && "$PROJECT_NODE_ID" != "null" ]] || die "Could not resolve project node ID"
  echo "{\"project_number\":\"$PROJECT_ID\",\"project_node_id\":\"$PROJECT_NODE_ID\"}" > "${OUT_DIR}/project.ids.json"
}

field_id_by_name() {
  local name="$1"
  jq -r --arg n "$name" '.fields[] | select(.name==$n) | .id' "${OUT_DIR}/fields.json"
}

option_id_by_name() {
  local field="$1"; local opt="$2"
  jq -r --arg f "$field" --arg o "$opt" '.fields[] | select(.name==$f) | .options[]? | select(.name==$o) | .id' "${OUT_DIR}/fields.json"
}

refresh_fields() {
  gh project field-list "$PROJECT_ID" --owner "$ORG_NAME" --format json > "${OUT_DIR}/fields.json"
}

ensure_single_select_field() {
  local fname="$1"; shift
  local opts_csv="$1"; shift
  local fid
  fid=$(field_id_by_name "$fname" || true)
  if [[ -z "$fid" || "$fid" == "null" ]]; then
    log_info "Creating SINGLE_SELECT field '$fname' with options: $opts_csv"
    run_mut "gh project field-create \"$PROJECT_ID\" --owner \"$ORG_NAME\" --name \"$fname\" --data-type \"SINGLE_SELECT\" --single-select-options \"$opts_csv\" > \"${OUT_DIR}/field.create.$fname.out\" 2> \"${OUT_DIR}/field.create.$fname.err\""
    refresh_fields
    fid=$(field_id_by_name "$fname" || true)
    [[ -n "$fid" && "$fid" != "null" ]] || die "Failed to create field '$fname'"
    log_success "Field '$fname' created (id=$fid)"
  else
    log_success "Field '$fname' exists (id=$fid)"
    # Option reconciliation note: gh CLI lacks granular option-upsert; full replacement isn't exposed.
    # We warn if expected options missing.
    IFS=',' read -r -a expected <<< "$opts_csv"
    for opt in "${expected[@]}"; do
      local oid
      oid=$(option_id_by_name "$fname" "$opt" || true)
      [[ -n "$oid" && "$oid" != "null" ]] || log_warning "Field '$fname' missing option '$opt' (will continue)"
    done
  fi
}

ensure_fields() {
  log_info "Ensuring custom fields (Priority, Size, Estimate)"
  refresh_fields || true
  ensure_single_select_field "Priority" "FIRE,High,Medium,Low,Nice to Have"
  ensure_single_select_field "Size" "XS,S,M,L,XL"
  ensure_single_select_field "Estimate" "1,2,3"

  # Capture IDs and option maps
  refresh_fields
  jq -n \
    --argjson fields "$(cat "${OUT_DIR}/fields.json")" \
    '{
      priority: {
        id: ($fields.fields[]|select(.name=="Priority")|.id),
        options: ($fields.fields[]|select(.name=="Priority")|.options|map({name, id}) )
      },
      size: {
        id: ($fields.fields[]|select(.name=="Size")|.id),
        options: ($fields.fields[]|select(.name=="Size")|.options|map({name, id}) )
      },
      estimate: {
        id: ($fields.fields[]|select(.name=="Estimate")|.id),
        options: ($fields.fields[]|select(.name=="Estimate")|.options|map({name, id}) )
      },
      status: {
        id: ($fields.fields[]|select(.name=="Status")|.id),
        options: ($fields.fields[]|select(.name=="Status")|.options|map({name, id}) )
      }
    }' > "${OUT_DIR}/project_fields.json"
  log_success "Wrote field map → ${OUT_DIR}/project_fields.json"
}

ensure_iterations() {
  log_info "Ensuring Iteration field 'Sprint' and configuring windows"
  refresh_fields || true
  local sprint_field_id
  sprint_field_id=$(field_id_by_name "Sprint" || true)

  if [[ -z "$sprint_field_id" || "$sprint_field_id" == "null" ]]; then
    log_info "Creating iteration field 'Sprint' via GraphQL"
    # Create iteration field
    local create_q
    create_q='mutation($pid:ID!){ createProjectV2Field(input:{projectId:$pid, dataType:ITERATION, name:"Sprint"}){ projectV2Field { id name } } }'
    if [[ "$DRY_RUN" == "1" ]]; then
      log_info "[dry-run] gh api graphql createProjectV2Field Sprint"
    else
      gh api graphql -f query="$create_q" -F pid="$PROJECT_NODE_ID" > "${OUT_DIR}/sprint.create.json"
    fi
    refresh_fields
    sprint_field_id=$(field_id_by_name "Sprint" || true)
    [[ -n "$sprint_field_id" && "$sprint_field_id" != "null" ]] || die "Failed to create 'Sprint' iteration field"
    log_success "Iteration field 'Sprint' created (id=$sprint_field_id)"
  else
    log_success "Iteration field 'Sprint' exists (id=$sprint_field_id)"
  fi

  # Build iteration configuration payload from sprints.json
  local start_iso
  start_iso=$(jq -r '.[0].startDate' "${OUT_DIR}/sprints.json")
  local dur="$SPRINT_CADENCE_DAYS"
  local cfg_json="${OUT_DIR}/iteration.cfg.json"
  jq -n \
    --arg start "$start_iso" \
    --argjson duration "$dur" \
    --slurpfile S "${OUT_DIR}/sprints.json" \
    '{ startDate: $start, duration: $duration, iterations: ($S[0] | map({title:.title})) }' > "$cfg_json"

  log_info "Updating 'Sprint' iteration configuration (start=$start_iso, duration=$dur)"
  local update_q
  update_q='mutation($pid:ID!, $fid:ID!, $cfg:ProjectV2IterationFieldConfigurationInput!){
    updateProjectV2Field(input:{ projectId:$pid, fieldId:$fid, iterationConfiguration:$cfg }) {
      projectV2Field { id name }
    }
  }'
  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[dry-run] gh api graphql updateProjectV2Field iterationConfiguration with $(jq -c . "$cfg_json")"
  else
    gh api graphql -f query="$update_q" -F pid="$PROJECT_NODE_ID" -F fid="$sprint_field_id" --raw-field cfg="$(cat "$cfg_json")" > "${OUT_DIR}/sprint.update.json"
  fi

  # Persist Sprint field id
  jq --arg id "$sprint_field_id" '. + { sprint: { id: $id } }' "${OUT_DIR}/project_fields.json" > "${OUT_DIR}/project_fields.tmp" && mv "${OUT_DIR}/project_fields.tmp" "${OUT_DIR}/project_fields.json"
  log_success "Sprint configuration applied (or planned in dry-run)"
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
    --arg project_node_id "$PROJECT_NODE_ID" \
    --argjson sprint_count "$sprint_count" \
    '{run: {org:$org, project:{name:$project_name, number:$project_id, node_id:$project_node_id}, start_date:$start_date, cadence_days:($cadence|tonumber), seed:$seed, out_dir:$out_dir, sprint_count:$sprint_count}}' \
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

  ensure_project
  ensure_fields
  ensure_iterations

  summarize "$SEED_JSON"

  log_success "Slice complete: project ensured, fields upserted, Sprint iterations configured."
  log_info "Artifacts: ${OUT_DIR}"
}

main "$@"
