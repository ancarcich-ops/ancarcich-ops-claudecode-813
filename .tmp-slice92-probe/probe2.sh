#!/usr/bin/env bash
# Probe round 2: inspect full create response bodies + key-name variants.
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

echo "=== BOTH + teamRules, full response ==="
create BOTH ', "teamRules": ["BEST_BALL","SUM"]' | python3 -m json.tool | head -60

echo "=== SCRAMBLE + teamHandicapMode, full response ==="
create SCRAMBLE ', "teamHandicapMode": "AVG"' | python3 -m json.tool | head -40
