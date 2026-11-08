#!/usr/bin/env bash
# Probe 6: does the server now ECHO teamHandicapMode / teamRules on
# GET /matches/:id? If yes, edit mode can prefill the handicap picker.
# Probe rounds are deleted at the end.
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
echo "M1=$M1 M2=$M2"

show() {
  curl -s "$BASE/matches/$1" -H "Authorization: Bearer $TOK" | python3 -c '
import sys, json
d = json.load(sys.stdin)
m = d["match"]
print("   match.teamHandicapMode =", m.get("teamHandicapMode"))
print("   match.teamRules =", m.get("teamRules"))
print("   resp.sideGameConfigs:", json.dumps(d.get("sideGameConfigs"))[:400])
'
}

echo "=== SCRAMBLE $M1 (want teamHandicapMode = AVG) ==="; show "$M1"
echo "=== BOTH $M2 (want teamRules echoed or config) ==="; show "$M2"

# PATCH the scramble round's tee time only, re-check echo + persistence.
echo "=== PATCH tee time on $M1 ==="
curl -s -X PATCH "$BASE/matches/$M1" -H "Authorization: Bearer $TOK" -H 'Content-Type: application/json' \
  -d '{"scheduledAt":"2026-11-09T17:30:00.000Z"}' >/dev/null
show "$M1"

echo "=== cleanup ==="
for M in "$M1" "$M2"; do
  code=$(curl -s -o /dev/null -w '%{http_code}' -X DELETE "$BASE/matches/$M" -H "Authorization: Bearer $TOK")
  echo "DELETE $M -> $code"
done
