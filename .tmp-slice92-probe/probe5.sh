#!/usr/bin/env bash
# Probe 5: does any payload echo teamHandicapMode? Then delete probes.
set -euo pipefail
BASE="https://sticks-golf.vercel.app/api/mobile"
: "${TOK:?}"
M1=$(sed -n 1p probe-ids.txt); M2=$(sed -n 2p probe-ids.txt)

echo "=== list payload fields ==="
curl -s "$BASE/matches?status=UPCOMING" -H "Authorization: Bearer $TOK" | python3 -c '
import sys, json
ms = json.load(sys.stdin).get("matches") or []
for m in ms:
    if "team" in json.dumps(m).lower() or m.get("format") not in (None, "INDIVIDUAL"):
        print(m.get("format"), sorted(m.keys()))
        break
print("any teamHandicapMode key:", any("teamHandicapMode" in m for m in ms))
'

echo "=== deleting probe rounds ==="
for M in "$M1" "$M2"; do
  code=$(curl -s -o /dev/null -w '%{http_code}' -X DELETE "$BASE/matches/$M" -H "Authorization: Bearer $TOK")
  echo "DELETE $M -> $code"
done
