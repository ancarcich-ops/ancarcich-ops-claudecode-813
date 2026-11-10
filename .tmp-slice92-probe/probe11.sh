#!/usr/bin/env bash
# Slices 93-95 probe: push-prefs shape, reactions on list + detail,
# round-templates, round-options supportEmail.
set -euo pipefail
BASE="https://sticks-golf.vercel.app/api/mobile"
LOGIN=$(curl -s -X POST "$BASE/auth/login" -H 'Content-Type: application/json' \
  -d '{"identifier":"user123","password":"user1234"}')
TOK=$(echo "$LOGIN" | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')
ME=$(echo "$LOGIN" | python3 -c 'import sys,json;print(json.load(sys.stdin)["user"]["id"])')
PID=cmw631k8n000efx6u9kr3qb9g
echo "TOK=${TOK:0:8}... ME=$ME"
printf 'TOK=%s\nME=%s\nPID=%s\n' "$TOK" "$ME" "$PID" > env93.sh

echo "=== GET /me/push-prefs ==="
curl -s "$BASE/me/push-prefs" -H "Authorization: Bearer $TOK" | python3 -m json.tool

echo "=== GET /round-templates ==="
curl -s "$BASE/round-templates" -H "Authorization: Bearer $TOK" | python3 -c '
import sys, json
d = json.load(sys.stdin)
ts = d.get("templates", [])
print("count:", len(ts))
print(json.dumps(ts[0], indent=1)[:700] if ts else "(empty)")
'

echo "=== GET /round-options: supportEmail + keys ==="
curl -s "$BASE/round-options" -H "Authorization: Bearer $TOK" | python3 -c '
import sys, json
d = json.load(sys.stdin)
print("supportEmail:", d.get("supportEmail"))
print("keys:", sorted(d.keys()))
'

echo "=== GET /matches: reactions on summary? ==="
curl -s "$BASE/matches" -H "Authorization: Bearer $TOK" | python3 -c '
import sys, json
ms = json.load(sys.stdin).get("matches", [])
print("matches:", len(ms))
for m in ms[:3]:
    print("  ", m.get("courseName")[:30], "reactions=", m.get("reactions"))
'
