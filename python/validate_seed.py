#!/usr/bin/env python3
"""
validate_seed.py
Lightweight fallback validator when Node/ajv-cli is unavailable.

Checks:
- JSON parses and is an object
- org.name, org.shortname present and non-empty strings
- project.title present and non-empty string
- repos is an array; each item has non-empty name
- issues is an array; each item has unique key and non-empty title
- Optional checks/warnings for priority/estimate/size values
Exit codes:
- 0 on success
- 3 on validation error
"""
import json, sys, collections

PRIORITY_OPTS = {"FIRE","High","Medium","Low","Nice to Have"}
SIZE_OPTS = {"XS","S","M","L","XL"}
ESTIMATE_OPTS = {"1","2","3"}

def err(msg):
    print(f"ERROR: {msg}", file=sys.stderr)

def warn(msg):
    print(f"WARNING: {msg}", file=sys.stderr)

def to_str(x):
    return str(x) if x is not None else ""

def main():
    if len(sys.argv) != 2:
        err("usage: validate_seed.py /path/to/gh_seed.json")
        sys.exit(3)
    path = sys.argv[1]
    try:
        with open(path, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except Exception as e:
        err(f"failed to parse JSON: {e}")
        sys.exit(3)
    if not isinstance(data, dict):
        err("top-level must be an object")
        sys.exit(3)

    org = data.get("org") or {}
    if not isinstance(org, dict) or not to_str(org.get("name")).strip():
        err("org.name is required")
        sys.exit(3)
    if not to_str(org.get("shortname")).strip():
        err("org.shortname is required")
        sys.exit(3)

    project = data.get("project") or {}
    if not isinstance(project, dict) or not to_str(project.get("title")).strip():
        err("project.title is required")
        sys.exit(3)

    repos = data.get("repos", [])
    if not isinstance(repos, list):
        err("repos must be an array")
        sys.exit(3)
    repo_names = set()
    for i, r in enumerate(repos, 1):
        if not isinstance(r, dict) or not to_str(r.get("name")).strip():
            err(f"repos[{i}] missing name")
            sys.exit(3)
        repo_names.add(r["name"])

    issues = data.get("issues", [])
    if not isinstance(issues, list):
        err("issues must be an array")
        sys.exit(3)
    keys = set()
    for i, it in enumerate(issues, 1):
        if not isinstance(it, dict):
            err(f"issues[{i}] must be an object")
            sys.exit(3)
        key = to_str(it.get("key")).strip()
        title = to_str(it.get("title")).strip()
        if not key:
            err(f"issues[{i}] missing key")
            sys.exit(3)
        if key in keys:
            err(f"issues[{i}] duplicate key '{key}'")
            sys.exit(3)
        keys.add(key)
        if not title:
            err(f"issues[{i}] missing title")
            sys.exit(3)
        pr = it.get("priority")
        if pr is not None and to_str(pr) not in PRIORITY_OPTS:
            warn(f"issues[{i}] priority '{pr}' not in {sorted(PRIORITY_OPTS)}")
        est = it.get("estimate")
        if est is not None and to_str(est) not in ESTIMATE_OPTS:
            warn(f"issues[{i}] estimate '{est}' not in {sorted(ESTIMATE_OPTS)}")
        sz = it.get("size")
        if sz is not None and to_str(sz) not in SIZE_OPTS:
            warn(f"issues[{i}] size '{sz}' not in {sorted(SIZE_OPTS)}")
        wr = it.get("work_repo")
        if wr is not None and to_str(wr) and wr not in repo_names:
            warn(f"issues[{i}] work_repo '{wr}' not found in repos list")

    print(json.dumps({
        "ok": True,
        "org": org.get("name"),
        "project": project.get("title"),
        "repo_count": len(repo_names),
        "issue_count": len(issues)
    }))
    sys.exit(0)

if __name__ == "__main__":
    main()
