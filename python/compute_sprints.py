#!/usr/bin/env python3
"""
compute_sprints.py

Usage:
  python3 compute_sprints.py --start-date "MM/DD/YYYY" --cadence 14 --seed /path/to/gh_seed.json
Prints a JSON array of { "title": "Sprint N", "startDate": "YYYY-MM-DD", "duration": <int> }.

- Sprints start on the next Wednesday on/after --start-date.
- Count is derived from the highest `sprint` value in seed. If none, prints [].
"""
import argparse, json, sys
from datetime import datetime, timedelta

def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--start-date", required=True, help='MM/DD/YYYY')
    p.add_argument("--cadence", type=int, required=True, help='Sprint length in days')
    p.add_argument("--seed", required=True, help='Path to gh_seed.json to derive sprint count')
    return p.parse_args()

def next_wednesday(dt: datetime) -> datetime:
    # Monday=0, Tuesday=1, Wednesday=2
    days_ahead = (2 - dt.weekday()) % 7
    return dt + timedelta(days=days_ahead)

def load_max_sprint(seed_path: str) -> int:
    try:
        with open(seed_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except Exception as e:
        print(f"ERROR: failed reading seed file {seed_path}: {e}", file=sys.stderr)
        return 0
    max_sprint = 0
    issues = data.get('issues', [])
    if isinstance(issues, list):
        for it in issues:
            try:
                s = it.get('sprint', None)
                if isinstance(s, str) and s.isdigit():
                    s = int(s)
                if isinstance(s, int) and s > 0:
                    max_sprint = max(max_sprint, s)
            except Exception:
                continue
    return max_sprint

def main():
    args = parse_args()
    try:
        start = datetime.strptime(args.start_date, "%m/%d/%Y")
    except ValueError:
        print("ERROR: --start-date must be in MM/DD/YYYY format", file=sys.stderr)
        sys.exit(2)
    if args.cadence <= 0:
        print("ERROR: --cadence must be > 0", file=sys.stderr)
        sys.exit(2)

    n = load_max_sprint(args.seed)
    if n <= 0:
        print("[]")
        return

    first = next_wednesday(start)
    out = []
    for i in range(1, n + 1):
        sd = first + timedelta(days=(i - 1) * args.cadence)
        out.append({
            "title": f"Sprint {i}",
            "startDate": sd.strftime("%Y-%m-%d"),
            "duration": args.cadence
        })
    print(json.dumps(out, indent=2))

if __name__ == "__main__":
    main()
