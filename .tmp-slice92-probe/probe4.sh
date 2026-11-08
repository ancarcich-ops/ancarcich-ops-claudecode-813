#!/usr/bin/env bash
# Probe 4: parse the RESPONSE-level side games/configs for the BOTH round.
set -euo pipefail
BASE="https://sticks-golf.vercel.app/api/mobile"
: "${TOK:?}"
M2=$(sed -n 2p probe-ids.txt)
M1=$(sed -n 1p probe-ids.txt)

show() {
  curl -s "$BASE/matches/$1" -H "Authorization: Bearer $TOK" | python3 -c '
import sys, json
d = json.load(sys.stdin)
print("   sideGames:", json.dumps(d.get("sideGames"))[:400])
print("   sideGameConfigs:", json.dumps(d.get("sideGameConfigs"))[:800])
print("   sideGameEvents kinds:", [e.get("gameKind") for e in d.get("sideGameEvents", [])])
'
}
echo "=== BOTH $M2 side games ==="; show "$M2"
echo "=== SCRAMBLE $M1 side games ==="; show "$M1"
