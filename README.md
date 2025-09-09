# gh-org-seeder

Deterministic, idempotent seeding tool for GitHub Projects (v2) at the org level.
Primary entrypoint: ./gh-org-seed.sh

## Status (Story E1-S1)
- Status: In Progress
- Start: 2025-09-08
- Size: L
- Points: 3

## Quick start
Run: ./gh-org-seed.sh --help

## Environment
- macOS + zsh/bash 5.2+
- gh CLI v2.78.0+
- jq, python3, git

## Next step
Step 2 will add preflight checks, flag parsing, and seed validation.

## Usage

```bash
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
```
