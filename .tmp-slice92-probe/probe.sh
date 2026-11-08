#!/usr/bin/env bash
# Slice 92 round 2 probe: team fields on create + PATCH preservation.
# Creates two probe rounds (SCRAMBLE with teamHandicapMode, BOTH with
# teamRules), inspects what the detail payload echoes back, PATCHes the
# BOTH round's tee time only, and verifies teams/rules survive.
# Prints the two match ids to probe-ids.txt for cleanup.
set -euo pipefail
BASE="https://sticks-golf.vercel.app/api/mobile"
: "${TOK:?set TOK first}"
: "${ME:?set ME first}"
: "${PID:?set PID first}"

COURSE=$(curl -s "$BASE/courses?q=a" -H "Authorization: Bearer $TOK" | python3 -c 'import sys,json;print(json.load(sys.stdin)["courses"][0]["name"])')
echo "COURSE=$COURSE"

create() { # $1=format  $2=extra json (with leading comma)
  curl -s -X POST "$BASE/matches" -H "Authorization: Bearer $TOK" -H 'Content-Type: application/json' -d "{
    \"courseName\": \"$COURSE\", \"holes\": 18, \"startingHole\": 1,
    \"scheduledAt\": \"2026-11-09T15:00:00.000Z\", \"scoringMode\": \"NET\",
    \"format\": \"$1\", \"players\": [
      {\"displayName\":\"Me\",\"handicap\":5,\"userId\":\"$ME\",\"team\":\"0\"},
      {\"displayName\":\"Probe Partner\",\"handicap\":10,\"userId\":\"$PID\",\"team\":\"1\"}
    ]$2}"
}

R1=$(create SCRAMBLE ', "teamHandicapMode": "AVG"')
echo "SCRAMBLE create: $(echo "$R1" | head -c 200)"
M1=$(echo "$R1" | python3 -c 'import sys,json;print(json.load(sys.stdin)["match"]["id"])')

R2=$(create BOTH ', "teamRules": ["BEST_BALL","SUM"]')
echo "BOTH create: $(echo "$R2" | head -c 200)"
M2=$(echo "$R2" | python3 -c 'import sys,json;print(json.load(sys.stdin)["match"]["id"])')

printf '%s\n%s\n' "$M1" "$M2" > probe-ids.txt

show() {
  curl -s "$BASE/matches/$1" -H "Authorization: Bearer $TOK" | python3 -c '
import sys, json
d = json.load(sys.stdin)["match"]
for k in ("format", "scoringMode", "teamHandicapMode", "teamRules"):
    print("  ", k, "=", d.get(k))
print("   players:", [(p["displayName"], p.get("team")) for p in d["players"]])
print("   sideGames:", d.get("sideGames"), "configs:", d.get("sideGameConfigs"))
'
}

echo "=== SCRAMBLE detail ($M1) ==="; show "$M1"
echo "=== BOTH detail ($M2) ==="; show "$M2"

echo "=== PATCH tee time only on $M2 ==="
curl -s -X PATCH "$BASE/matches/$M2" -H "Authorization: Bearer $TOK" -H 'Content-Type: application/json' \
  -d '{"scheduledAt":"2026-11-09T16:30:00.000Z"}' >/dev/null
show "$M2"
