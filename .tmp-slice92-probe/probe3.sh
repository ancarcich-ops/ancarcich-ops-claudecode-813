#!/usr/bin/env bash
# Probe 3: raw detail dumps of the fresh rounds + PATCH survival test on
# the SCRAMBLE round (the exact checklist case).
set -euo pipefail
BASE="https://sticks-golf.vercel.app/api/mobile"
: "${TOK:?}"; : "${ME:?}"; : "${PID:?}"
ids=($(cat probe-ids.txt 2>/dev/null || true))
M1=${ids[0]:-}; M2=${ids[1]:-}
echo "M1=$M1 M2=$M2"

dump() {
  curl -s "$BASE/matches/$1" -H "Authorization: Bearer $TOK" | python3 -c '
import sys, json
d = json.load(sys.stdin)["match"]
print("  top-level keys:", sorted(d.keys()))
for k in ("format", "teamHandicapMode", "teamRules"):
    print("  ", k, "=", d.get(k))
print("   players:", [(p["displayName"], p.get("team")) for p in d["players"]])
for gk in ("sideGames", "sideGameConfigs"):
    print("  ", gk, "=", d.get(gk))
'
}

echo "=== BOTH round $M2 raw ==="; dump "$M2"
echo "=== SCRAMBLE round $M1 raw ==="; dump "$M1"

if [ -n "$M1" ]; then
  echo "=== PATCH tee time only on SCRAMBLE $M1 ==="
  curl -s -X PATCH "$BASE/matches/$M1" -H "Authorization: Bearer $TOK" -H 'Content-Type: application/json' \
    -d '{"scheduledAt":"2026-11-09T17:00:00.000Z"}' >/dev/null
  dump "$M1"
fi
