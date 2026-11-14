#!/usr/bin/env python3
"""Slice 101 spectator probe: creator is NOT a player. The recap seat must
fall back to the first player's card, with no history section."""
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


TOKEN = json.loads(os.popen(
    'curl -s -X POST %s/auth/login -H "Content-Type: application/json" '
    '-d \'{"identifier":"user123","password":"user1234"}\'' % BASE).read())["token"]

code, cat = req("GET", "/courses?q=park", TOKEN)
course = cat["courses"][0]["name"]
pars = [4, 5, 3, 4, 4, 5, 3, 4, 5, 4, 4, 3, 5, 4, 3, 5, 4, 4]
sched = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=2)

code, created = req("POST", "/matches", TOKEN, {
    "courseName": course, "holes": 9, "startingHole": 1,
    "scheduledAt": sched.isoformat(),
    "scoringMode": "GROSS", "format": "STROKE",
    "players": [
        {"displayName": "Spectated A", "handicap": 5.0},
        {"displayName": "Spectated B", "handicap": 9.0},
    ],
}, expect_error=True)
assert code in (200, 201), (code, created)
mid = created["id"] if "id" in created else created["match"]["id"]
print("match:", mid, "(creator not among players)")

req("POST", "/matches/%s/pars" % mid, TOKEN, {"pars": pars[:9]})
code, det = req("GET", "/matches/" + mid, TOKEN, expect_error=True)
players = (det.get("players") if "players" in det else det.get("match", {}).get("players")) or []
pids = [p["id"] for p in players]
for i, pid in enumerate(pids):
    for h in range(1, 10):
        req("POST", "/matches/%s/score" % mid, TOKEN,
            {"matchPlayerId": pid, "hole": h, "strokes": pars[h - 1] + (i if h % 2 else 0)})
print("9 holes x 2 scored")
code, r = req("POST", "/matches/%s/complete" % mid, TOKEN, expect_error=True)
print("complete:", code)

code, recap = req("GET", "/matches/%s/recap" % mid, TOKEN, expect_error=True)
print("recap:", code)
if code == 200:
    body = recap.get("recap") or {}
    print("seat:", recap.get("seat"), "history:", recap.get("history"),
          "historyLabel:", recap.get("historyLabel"))
    print("headline:", json.dumps(recap.get("headline"))[:200])
    print("totals grossToPar:", (body.get("totals") or {}).get("grossToPar"),
          "| last arc toPar:", (body.get("arc") or [{}])[-1].get("toPar"))
print("cleanup:", req("DELETE", "/matches/" + mid, TOKEN, expect_error=True)[0])
