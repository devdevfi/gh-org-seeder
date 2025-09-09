# gh-org-seeder

Deterministic, idempotent seeding tool for GitHub Projects (v2) at the org level.
Primary entrypoint: ./gh-org-seed.sh

## Status (Story E1-S1)
- Status: In Progress
- Start: 2025-09-08
- Size: L
- Points: 3

## What’s implemented in Step 2
- Preflight: version checks and gh auth
- CLI flags parsing and validation
- Seed validation: AJV via npx (primary) with Python fallback
- Sprint window computation from --start-date and highest sprint in gh_seed.json
- Run artifacts in ./.out/<timestamp> including sprints.json and summary.json

## Requirements
- macOS with bash 5.2+ or zsh
- gh CLI v2.78.0+
- python3, jq
- Node+npx optional (for AJV); Python fallback included

## Usage
Run: ./gh-org-seed.sh --help

Example:
./gh-org-seed.sh --start-date "11/05/2025" --seed-file ./seeds/acme --org-name acme-corp --project-name "ACME Delivery" --project-id 1 --org-shortname ACME --sprint-cadence-days 14 --verbose

## Validating locally (this slice)
1. Place your seed file at ./seeds/acme/gh_seed.json
2. Ensure schema exists at ./schema/gh_seed.schema.json (already included)
3. Run:
   ./gh-org-seed.sh --start-date "11/05/2025" --seed-file ./seeds/acme --org-name acme-corp --project-name "ACME Delivery" --project-id 1 --org-shortname ACME --sprint-cadence-days 14
4. Expected:
   - "AJV validation passed" or "Fallback validation passed"
   - ./.out/<timestamp>/sprints.json exists with titles Sprint 1..N and ISO dates on Wednesdays
   - ./.out/<timestamp>/summary.json contains run metadata

## Next steps
Step 3 will create/reuse the org-level Project and upsert fields (Priority, Size, Estimate, Sprint), using the computed sprint windows.
