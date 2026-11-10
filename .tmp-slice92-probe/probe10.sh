#!/usr/bin/env bash
# Probe 10: does a SCRAMBLE round accept teamRules and spin the
# team-vs-team game? Compare with BOTH.
set -euo pipefail
BASE="https://sticks-golf.vercel.app/api/mobile"
TOK=$(curl -s -X POST "$BASE/auth/login" -H 'Content-Type: application/json' \
  -d '{"identifier":"user123","password":"user1234"}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')
ME=cmrw4ewmj000014jg6h7a0u8c
PID=cmw631k8n000efx6u9kr3qb9g
COURSE="Aronimink Golf Club"

create() { # $1=format  $2=extra json (leading comma)
  curl -s -X POST "$BASE/matches" -H "Authorization: Bearer $TOK" -H 'Content-Type: application/json' -d "{
    \"courseName\": \"$COURSE\", \"holes\": 18, \"startingHole\": 1,
    \"scheduledAt\": \"2026-11-09T15:00:00.000Z\", \"scoringMode\": \"NET\",
    \"format\": \"$1\", \"players\": [
      {\"displayName\":\"Me\",\"handicap\":5,\"userId\":\"$ME\",\"team\":\"0\"},
      {\"displayName\":\"Probe Partner\",\"handicap\":10,\"userId\":\"$PID\",\"team\":\"1\"}
    ]$2}"
}

R=$(create SCRAMBLE ', "teamRules": ["BEST_BALL","SUM"]')
M=$(echo "$R" | python3 -c 'import sys,json;print(json.load(sys.stdin)["match"]["id"])')
echo "SCRAMBLE+rules round: $M"
curl -s "$BASE/matches/$M" -H "Authorization: Bearer $TOK" | python3 -c '
import sys, json
d = json.load(sys.stdin)
m = d["match"]
print("   format =", m.get("format"), "| uiFormat =", m.get("uiFormat"))
print("   sideGames:", [g.get("kind") for g in d.get("sideGames") or []])
print("   sideGameConfigs:", json.dumps(d.get("sideGameConfigs"))[:300])
'
code=$(curl -s -o /dev/null -w '%{http_code}' -X DELETE "$BASE/matches/$M" -H "Authorization: Bearer $TOK")
echo "DELETE $M -> $code"
