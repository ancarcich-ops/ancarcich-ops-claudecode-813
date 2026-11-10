#!/usr/bin/env bash
# Probe 9: round-options — what exactly is the "Teams" format?
set -euo pipefail
BASE="https://sticks-golf.vercel.app/api/mobile"
TOK=$(curl -s -X POST "$BASE/auth/login" -H 'Content-Type: application/json' \
  -d '{"identifier":"user123","password":"user1234"}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')
curl -s "$BASE/round-options" -H "Authorization: Bearer $TOK" | python3 -c '
import sys, json
d = json.load(sys.stdin)
for f in d.get("roundFormats", []):
    print("FORMAT", f.get("id"), "| usesTeams:", f.get("usesTeams"), "| min:", f.get("minPlayers"))
    print("   label:", f.get("label"))
    print("   blurb:", f.get("blurb"))
print()
for r in d.get("teamRules", []):
    print("RULE", r.get("id"), "| options:", r.get("hasOptions"), "|", r.get("label"))
'
