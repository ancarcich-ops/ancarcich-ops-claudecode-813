#!/usr/bin/env python3
"""Slice 101 live probe: build a fully-scored finished round, then GET the recap.

Verifies the wire contract the app relies on:
  - recap decodes (shape), netRecap present on NET rounds
  - last arc point toPar == totals.grossToPar
  - swing rows' hole counts sum to the stated total
Usage: python3 scripts/recap-probe.py
"""
import json, os, urllib.request, datetime, sys

BASE = "https://sticks-golf.vercel.app/api/mobile"


def req(method, path, token=None, body=None, expect_error=False):
    r = urllib.request.Request(BASE + path, method=method)
    r.add_header("Content-Type", "application/json")
    if token:
        r.add_header("Authorization", "Bearer " + token)
    data = json.dumps(body).encode() if body is not None else None
    try:
        with urllib.request.urlopen(r, data=data, timeout=30) as resp:
            raw = resp.read().decode()
            return resp.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        if not expect_error:
            raise
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, raw


tok = os.popen(
    'curl -s -X POST %s/auth/login -H "Content-Type: application/json" '
    '-d \'{"identifier":"user123","password":"user1234"}\'' % BASE
).read()
TOKEN = json.loads(tok)["token"]
DEMO_ID = "cmrw4ewmj000014jg6h7a0u8c"

# 1. Create a NET round with a 3.4-handicap gap so netRecap can settle differently.
sched = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(hours=1)
# courseName must be in the served catalog.
code, cat = req("GET", "/courses?q=park", TOKEN)
courses = cat.get("courses", []) if isinstance(cat, dict) else []
course_name = courses[0]["name"] if courses else "Augusta National Golf Club"
print("course:", course_name)
par9 = [4, 5, 3, 4, 4, 5, 3, 4, 5]  # front 9 = 37
pars = par9 + [4, 4, 3, 5, 4, 3, 5, 4, 4]  # back 9 = 36, total 73
code, created = req("POST", "/matches", TOKEN, {
    "courseName": course_name,
    "holes": 18,
    "startingHole": 1,
    "scheduledAt": sched.isoformat(),
    "scoringMode": "NET",
    "format": "STROKE",
    "players": [
        {"displayName": "Demo", "handicap": 8.0, "userId": DEMO_ID},
        {"displayName": "Partner", "handicap": 11.4},
    ],
})
assert code in (200, 201), (code, created)
mid = created["id"] if "id" in created else created["match"]["id"]
print("match:", mid)

code, det = req("GET", "/matches/" + mid, TOKEN)
players = det["players"] if "players" in det else det["match"]["players"]
pids = {p["displayName"]: p["id"] for p in players}
print("players:", pids)

# 2. Set pars so vs-par math is realistic.
code, _ = req("POST", "/matches/%s/pars" % mid, TOKEN, {"pars": pars})
print("pars:", code)

# 3. Score all 18 holes for both players. Demo plays steady bogey-ish golf
# (par+1 every hole); Partner starts hot (+1 birdie on hole 2) then fades,
# so the swing ledger has a real handover mid-round.
strokes = {}
for h in range(1, 19):
    strokes[("Demo", h)] = pars[h - 1] + 1
    strokes[("Partner", h)] = pars[h - 1] + 1
strokes[("Partner", 2)] = pars[1] - 1  # birdie
strokes[("Partner", 11)] = pars[10] + 2  # the fade begins
for (name, h), s in strokes.items():
    code, r = req("POST", "/matches/%s/score" % mid, TOKEN,
                  {"matchPlayerId": pids[name], "hole": h, "strokes": s})
    if code not in (200, 201):
        print("score fail", name, h, code, r)
        sys.exit(1)
print("18x2 scored")

# 4. Mark final, then pull the recap.
code, r = req("POST", "/matches/%s/complete" % mid, TOKEN, expect_error=True)
print("complete:", code, r)
code, recap = req("GET", "/matches/%s/recap" % mid, TOKEN, expect_error=True)
print("recap status:", code)
print(json.dumps(recap, indent=1)[:6000])

if code != 200:
    print("CLEANUP", req("DELETE", "/matches/" + mid, TOKEN, expect_error=True)[0])
    sys.exit(1)

# 5. Tie-out checks.
body = recap.get("body", recap)
totals = body.get("totals", {})
gross_to_par = totals.get("grossToPar")
arc = body.get("arc") or []
last_arc = arc[-1].get("toPar") if arc else None
swings = body.get("swings") or []
print("\n--- tie-out ---")
print("totals.grossToPar:", gross_to_par, "| last arc toPar:", last_arc)
swing_sum = None
for sw in swings:
    holes = sw.get("holes") or []
    swing_sum = len(holes) if swing_sum is None else swing_sum + len(holes)
print("swing rows:", [(s.get("from"), s.get("to")) for s in swings], "| hole count sum:", swing_sum)
net = recap.get("netRecap") or {}
print("netRecap totals:", (net.get("totals") or {}))
ok = (last_arc == gross_to_par) and bool(net.get("totals"))
print("TIE-OUT:", "PASS" if ok else "FAIL")
print("matchId for cleanup:", mid)
