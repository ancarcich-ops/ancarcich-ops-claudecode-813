#!/usr/bin/env bash
# Probe 7: confirm uiFormat / teamHandicapMode / teamAllowance echo on
# GET /matches/:id. Probe rounds deleted at the end.
set -euo pipefail
BASE="https://sticks-golf.vercel.app/api/mobile"
: "${TOK:?}"; : "${ME:?}"; : "${PID:?}"
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

R1=$(create SCRAMBLE ', "teamHandicapMode": "AVG"')
M1=$(echo "$R1" | python3 -c 'import sys,json;print(json.load(sys.stdin)["match"]["id"])')
R2=$(create BOTH ', "teamRules": ["BEST_BALL","SUM"]')
M2=$(echo "$R2" | python3 -c 'import sys,json;print(json.load(sys.stdin)["match"]["id"])')
R3=$(create INDIVIDUAL '')
M3=$(echo "$R3" | python3 -c 'import sys,json;print(json.load(sys.stdin)["match"]["id"])')
echo "M1=$M1 M2=$M2 M3=$M3"

show() {
  curl -s "$BASE/matches/$1" -H "Authorization: Bearer $TOK" | python3 -c '
import sys, json
m = json.load(sys.stdin)["match"]
print("   format =", m.get("format"), "| uiFormat =", m.get("uiFormat"),
      "| teamHandicapMode =", m.get("teamHandicapMode"),
      "| teamAllowance =", m.get("teamAllowance"))
'
}
echo "=== SCRAMBLE+AVG $M1 ==="; show "$M1"
echo "=== BOTH $M2 ==="; show "$M2"
echo "=== INDIVIDUAL $M3 ==="; show "$M3"

echo "=== cleanup ==="
for M in "$M1" "$M2" "$M3"; do
  code=$(curl -s -o /dev/null -w '%{http_code}' -X DELETE "$BASE/matches/$M" -H "Authorization: Bearer $TOK")
  echo "DELETE $M -> $code"
done
