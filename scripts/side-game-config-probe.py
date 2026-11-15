#!/usr/bin/env python3
"""Side-game settings probe (server rulings of 2026-11-15).

  1. GET /round-options serves `sideGames` with the per-match picker's
     settings / settingsComplete for every kind, plus requires18 /
     requires4Players.
  2. POST /matches accepts `sideGameConfigs` keyed by kind; a kind not
     enabled is ignored.
  3. POST /matches/:id/side-game-config REPLACES the stored config, and
     `dropped` follows the three-outcome rule:
       - auto-press OFF with the threshold in the same payload -> []
       - threshold alone, switch absent -> ["autoPressThreshold"]
       - unknown field -> named

Usage: python3 scripts/side-game-config-probe.py
"""
import datetime, json, os, sys, urllib.request

BASE = "https://sticks-golf.vercel.app/api/mobile"


def req(method, path, token=None, body=None):
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
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, raw


TOKEN = json.loads(os.popen(
    'curl -s -X POST %s/auth/login -H "Content-Type: application/json" '
    '-d \'{"identifier":"user123","password":"user1234"}\'' % BASE).read())["token"]
failures = []


def check(name, ok, detail=""):
    print(("PASS " if ok else "FAIL ") + name + (" — " + detail if detail else ""))
    if not ok:
        failures.append(name)


def configs(mid):
    _, picker = req("GET", "/matches/%s/side-games" % mid, TOKEN)
    return {g["kind"]: g for g in picker.get("games", [])}


# ---- 1. round-options schema ----
_, opts = req("GET", "/round-options", TOKEN)
served = {g["kind"]: g for g in opts.get("sideGames") or []}
check("round-options serves sideGames", len(served) >= 10, ", ".join(sorted(served)))
check("requires18 / requires4Players stated",
      served.get("NASSAU", {}).get("requires18") is True
      and served.get("SIXES", {}).get("requires4Players") is True)
check("Stableford and BBB report settingsComplete false",
      served.get("STABLEFORD", {}).get("settingsComplete") is False
      and served.get("BBB", {}).get("settingsComplete") is False)

# ---- 2. inline configs on create ----
_, cat = req("GET", "/courses?q=park", TOKEN)
sched = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=1)
code, created = req("POST", "/matches", TOKEN, {
    "courseName": cat["courses"][0]["name"], "holes": 18, "startingHole": 1,
    "scheduledAt": sched.isoformat(), "scoringMode": "NET", "format": "INDIVIDUAL",
    "players": [{"displayName": "A", "handicap": 5}, {"displayName": "B", "handicap": 9}],
    "sideGames": ["NASSAU", "SKINS"],
    "sideGameConfigs": {
        "NASSAU": {"stake": 5, "autoPress": True, "autoPressThreshold": 3},
        "SKINS": {"pushRule": "NO_CARRY"},
        "SNAKE": {"stake": 2},  # not enabled -> ignored
    },
})
mid = (created.get("match") or created).get("id") if isinstance(created, dict) else None
check("create with sideGameConfigs", code in (200, 201) and mid, "status %s" % code)
if not mid:
    print(created)
    sys.exit(1)

# Served picker schema matches round-options for every kind.
games = configs(mid)
drift = [k for k, g in games.items()
         if k in served and (g.get("settings") != served[k].get("settings")
                             or g.get("settingsComplete") != served[k].get("settingsComplete"))]
check("round-options schema == per-match picker schema", not drift, str(drift))

check("NASSAU config stored inline",
      games["NASSAU"].get("config") == {"stake": 5, "autoPress": True, "autoPressThreshold": 3},
      json.dumps(games["NASSAU"].get("config")))
check("SKINS config stored inline",
      games["SKINS"].get("config") == {"pushRule": "NO_CARRY"},
      json.dumps(games["SKINS"].get("config")))
check("un-enabled SNAKE ignored", not games.get("SNAKE", {}).get("on"),
      json.dumps({k: games.get("SNAKE", {}).get(k) for k in ("on", "config")}))

# ---- 3. replace + dropped ----
def post(config):
    return req("POST", "/matches/%s/side-game-config" % mid, TOKEN, {"kind": "NASSAU", "config": config})

_, r = post({"stake": 5, "autoPress": False, "autoPressThreshold": 3})
check("auto-press OFF with threshold in payload -> dropped []", r.get("dropped") == [], json.dumps(r))

_, r = post({"autoPressThreshold": 4})
check("threshold alone, switch absent -> dropped names it",
      r.get("dropped") == ["autoPressThreshold"], json.dumps(r))
check("replace, not merge (stake gone)", "stake" not in (r.get("config") or {}), json.dumps(r.get("config")))

_, r = post({"stake": 5, "bogus": 1})
check("unknown field named in dropped", "bogus" in (r.get("dropped") or []), json.dumps(r))

print("\ncleanup:", req("DELETE", "/matches/" + mid, TOKEN)[0])
print("\n%s" % ("ALL PASS" if not failures else "FAILURES: %s" % failures))
sys.exit(1 if failures else 0)
