#!/usr/bin/env bash
# gh-org-seed.sh — Org-level GitHub Projects (v2) seeder (Step 1 skeleton)

set -euo pipefail

# Colors + logging
BLUE="\033[0;34m"; GREEN="\033[0;32m"; YELLOW="\033[1;33m"; RED="\033[0;31m"; NC="\033[0m"
log_info()    { echo -e "${BLUE}ℹ ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠️${NC}  $1"; }
log_error()   { echo -e "${RED}✗${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${SCRIPT_DIR}/.out/$(date +%Y%m%dT%H%M%S)"
mkdir -p "${OUT_DIR}"

VERBOSE=0
DRY_RUN=0
YES=0
VISIBILITY="internal"
SPRINT_CADENCE_DAYS=14

usage() {
  cat <<USAGE
Usage: ./gh-org-seed.sh \\
  --start-date "MM/DD/YYYY" \\
  --seed-file <dir> \\
  --org-name <org> \\
  --project-name <string> \\
  --project-id <number> \\
  [--org-shortname <SHORT>] \\
  [--sprint-cadence-days <int>] \\
  [--visibility internal|private] \\
  [--dry-run] [--yes] [--verbose] \\
  [--help]

Example:
  ./gh-org-seed.sh --start-date "11/05/2025" --seed-file ./seeds/acme \\
    --org-name acme-corp --project-name "ACME Delivery" --project-id 1 \\
    --org-shortname ACME --sprint-cadence-days 14
USAGE
}

START_DATE=""
SEED_DIR=""
ORG_NAME=""
PROJECT_NAME=""
PROJECT_ID=""
ORG_SHORTNAME=""

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
  :
  # Step 2 will implement: gh/git/python3/jq version checks and auth scopes
}

main() {
  parse_args "$@"
  log_info "Bootstrap skeleton ready. Step 2 will add preflight and validation."
  usage
}

main "$@"
