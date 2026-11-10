#!/usr/bin/env bash
# Probe 8: course-search distanceMi across query shapes. LA origin
# (demo account's area) vs no origin.
set -euo pipefail
BASE="https://sticks-golf.vercel.app/api/mobile"
TOK=$(curl -s -X POST "$BASE/auth/login" -H 'Content-Type: application/json' \
  -d '{"identifier":"user123","password":"user1234"}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')

show() {
  python3 -c '
import sys, json
d = json.load(sys.stdin)
for c in d.get("courses", [])[:8]:
    print("   %-42s %s" % (c["name"][:42], c.get("distanceMi")))
'
}

echo "=== ?q=pebble (no origin) ==="
curl -s "$BASE/courses?q=pebble" -H "Authorization: Bearer $TOK" | show
echo "=== ?q=pebble&lat=34.05&lng=-118.25 (LA origin) ==="
curl -s "$BASE/courses?q=pebble&lat=34.05&lng=-118.25" -H "Authorization: Bearer $TOK" | show
echo "=== ?lat=34.05&lng=-118.25 (nearby LA) ==="
curl -s "$BASE/courses?lat=34.05&lng=-118.25" -H "Authorization: Bearer $TOK" | show
echo "=== ?q=rustic (no origin) ==="
curl -s "$BASE/courses?q=rustic" -H "Authorization: Bearer $TOK" | show
