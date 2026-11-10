#!/usr/bin/env bash
# Probe 12: reactions end-to-end — create round, post scores to make a
# highlight, toggle a hole reaction + a round reaction, read detail.
set -euo pipefail
BASE="https://sticks-golf.vercel.app/api/mobile"
. ./env93.sh
COURSE="Aronimink Golf Club"
R=$(curl -s -X POST "$BASE/matches" -H "Authorization: Bearer $TOK" -H 'Content-Type: application/json' -d "{
  \"courseName\": \"$COURSE\", \"holes\": 18, \"startingHole\": 1,
  \"scheduledAt\": \"2026-11-09T15:00:00.000Z\", \"scoringMode\": \"NET\",
  \"format\": \"INDIVIDUAL\", \"players\": [
    {\"displayName\":\"Me\",\"handicap\":5,\"userId\":\"$ME\"},
    {\"displayName\":\"Probe Partner\",\"handicap\":10,\"userId\":\"$PID\"}
  ]}")
M=$(echo "$R" | python3 -c 'import sys,json;print(json.load(sys.stdin)["match"]["id"])')
echo "MATCH=$M"; printf 'M=%s\n' "$M" > env93b.sh

# seat ids
curl -s "$BASE/matches/$M" -H "Authorization: Bearer $TOK" | python3 -c '
import sys, json
d = json.load(sys.stdin)
print("seat ids:", [(p["displayName"], p["id"]) for p in d["match"]["players"]])
'

# Me posts a 1 on hole 5 (eagle vs par 3? pars may differ) and partner 4.
SEAT_ME=$(curl -s "$BASE/matches/$M" -H "Authorization: Bearer $TOK" | python3 -c 'import sys,json;d=json.load(sys.stdin);print([p["id"] for p in d["match"]["players"] if p["displayName"]=="Me"][0])')
SEAT_P=$(curl -s "$BASE/matches/$M" -H "Authorization: Bearer $TOK" | python3 -c 'import sys,json;d=json.load(sys.stdin);print([p["id"] for p in d["match"]["players"] if p["displayName"]!="Me"][0])')
echo "SEAT_ME=$SEAT_ME SEAT_P=$SEAT_P"
printf 'SEAT_ME=%s\nSEAT_P=%s\n' "$SEAT_ME" "$SEAT_P" >> env93b.sh
curl -s -X POST "$BASE/matches/$M/scores" -H "Authorization: Bearer $TOK" -H 'Content-Type: application/json' \
  -d "{\"hole\":5,\"strokes\":1,\"matchPlayerId\":\"$SEAT_ME\"}" >/dev/null || echo "(scores post failed — check endpoint)"
curl -s -X POST "$BASE/matches/$M/scores" -H "Authorization: Bearer $TOK" -H 'Content-Type: application/json' \
  -d "{\"hole\":5,\"strokes\":4,\"matchPlayerId\":\"$SEAT_P\"}" >/dev/null || true

echo "=== detail after scores: highlights/reactionEmoji/reactions ==="
curl -s "$BASE/matches/$M" -H "Authorization: Bearer $TOK" | python3 -c '
import sys, json
d = json.load(sys.stdin)
m = d["match"]
print("  reactionEmoji:", m.get("reactionEmoji"))
print("  reactions:", m.get("reactions"))
print("  highlights:", json.dumps(m.get("highlights"), indent=1)[:600])
'

echo "=== POST round reaction ==="
curl -s -X POST "$BASE/matches/$M/reactions" -H "Authorization: Bearer $TOK" -H 'Content-Type: application/json' -d '{"emoji":"🔥"}' | python3 -m json.tool
echo "=== POST hole reaction ==="
curl -s -X POST "$BASE/matches/$M/reactions" -H "Authorization: Bearer $TOK" -H 'Content-Type: application/json' \
  -d "{\"emoji\":\"❤️\",\"matchPlayerId\":\"$SEAT_ME\",\"hole\":5}" | python3 -m json.tool
echo "=== toggle again (remove) ==="
curl -s -X POST "$BASE/matches/$M/reactions" -H "Authorization: Bearer $TOK" -H 'Content-Type: application/json' \
  -d "{\"emoji\":\"❤️\",\"matchPlayerId\":\"$SEAT_ME\",\"hole\":5}" | python3 -m json.tool
echo "=== bad: hole without matchPlayerId (expect 400) ==="
curl -s -o /dev/null -w '%{http_code}\n' -X POST "$BASE/matches/$M/reactions" -H "Authorization: Bearer $TOK" -H 'Content-Type: application/json' -d '{"emoji":"🔥","hole":5}'
