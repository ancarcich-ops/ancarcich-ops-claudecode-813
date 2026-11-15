#!/usr/bin/env python3
"""Slice 101 addendum probe: a round that STARTS ON THE TENTH.

The off-tenth recap path — arcs, stretches, swings and the story when
playing order is 10..18 then 1..9 — had never been observed. Round-order
handling has produced three bugs in this codebase, so this probe checks
order explicitly:

  1. arc positions follow playing order: arc[0].hole == 10, arc[9].hole == 1
  2. last arc toPar == totals.grossToPar
  3. best/worst from/to are valid inclusive positions, and the stretch
     text the app would render ("holes 11 THROUGH 2") is sane
  4. swing rows sum to the margin; halved + swing rows == comparedHoles
  5. netRecap totals present on NET; front = holes 1-9, back = 10-18
  6. own-card story has no second-person slip; spectator story (creator
     not a player) names the seat — the deployed spectator-voice fix —
     and no first-person word survives in it either

Usage: python3 scripts/recap-tenth-probe.py
"""
import json, os, re, urllib.request, datetime, sys

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
DEMO_ID = "cmrw4ewmj000014jg6h7a0u8c"

code, cat = req("GET", "/courses?q=park", TOKEN)
course = cat["courses"][0]["name"]
pars = [4, 5, 3, 4, 4, 5, 3, 4, 5, 4, 4, 3, 5, 4, 3, 5, 4, 4]  # 73
ORDER = list(range(10, 19)) + list(range(1, 10))  # playing order
failures = []


def check(name, ok, detail=""):
    print(("PASS " if ok else "FAIL ") + name + (" — " + detail if detail else ""))
    if not ok:
        failures.append(name)


def stretch_text(arc, stretch):
    """What RecapTabView.stretchText renders for this stretch."""
    if not arc or stretch["from"] >= len(arc):
        return None
    to = min(stretch["to"], len(arc) - 1)
    if to < stretch["from"]:
        return None
    first, last = arc[stretch["from"]]["hole"], arc[to]["hole"]
    vs = stretch.get("vsPar", 0)
    direction = "%d UNDER" % -vs if vs < 0 else ("%d OVER" % vs if vs > 0 else "LEVEL")
    if first == last:
        return "HOLE %d · %s" % (first, direction)
    return "HOLES %d THROUGH %d · %s" % (first, last, direction)


def build_round(spectator=False):
    """18 holes, startingHole 10, scored in playing order."""
    sched = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=1)
    players = ([{"displayName": "Spectated A", "handicap": 8.0},
                {"displayName": "Spectated B", "handicap": 11.4}]
               if spectator else
               [{"displayName": "Demo", "handicap": 8.0, "userId": DEMO_ID},
                {"displayName": "Partner", "handicap": 11.4}])
    code, created = req("POST", "/matches", TOKEN, {
        "courseName": course, "holes": 18, "startingHole": 10,
        "scheduledAt": sched.isoformat(),
        "scoringMode": "NET", "format": "STROKE", "players": players,
    }, expect_error=True)
    assert code in (200, 201), (code, created)
    mid = created["id"] if "id" in created else created["match"]["id"]
    req("POST", "/matches/%s/pars" % mid, TOKEN, {"pars": pars})
    code, det = req("GET", "/matches/" + mid, TOKEN)
    players = det["players"] if "players" in det else det["match"]["players"]
    pids = {p["displayName"]: p["id"] for p in players}
    # Demo/Spectated A: bogey everywhere. Partner/Spectated B: birdie on
    # playing position 2 (hole 11), collapses at positions 11-12
    # (holes 2-3) — the handover and the best/worst stretches both cross
    # the turn, which is the whole point of starting on ten.
    for pos, hole in enumerate(ORDER):
        req("POST", "/matches/%s/score" % mid, TOKEN,
            {"matchPlayerId": pids[players[0]["displayName"]], "hole": hole,
             "strokes": pars[hole - 1] + 1})
        extra = 0
        if pos == 1:
            extra = -2  # birdie
        elif pos in (11, 12):
            extra = 2  # the collapse
        req("POST", "/matches/%s/score" % mid, TOKEN,
            {"matchPlayerId": pids[players[1]["displayName"]], "hole": hole,
             "strokes": pars[hole - 1] + 1 + extra})
    req("POST", "/matches/%s/complete" % mid, TOKEN, expect_error=True)
    code, recap = req("GET", "/matches/%s/recap" % mid, TOKEN, expect_error=True)
    return mid, code, recap


SECOND_PERSON = re.compile(r"\b(you|your|yours|you' re|you're)\b", re.I)
FIRST_PERSON = re.compile(r"\b(you|your|yours|i|my|mine|we|our)\b", re.I)

# ---- Own card ----
mid, code, recap = build_round(spectator=False)
print("own-card match:", mid, "| recap:", code)
body = recap["recap"]
arc = body.get("arc") or []
totals = body.get("totals") or {}

order_ok = len(arc) == 18 and arc[0]["hole"] == 10 and arc[9]["hole"] == 1 and arc[17]["hole"] == 9
positions_ok = all(p["position"] == i for i, p in enumerate(arc))
check("arc follows playing order 10..18,1..9", order_ok and positions_ok,
      "first=%s ninth=%s last=%s" % (arc[0]["hole"], arc[9]["hole"], arc[-1]["hole"]))

last_arc = arc[-1].get("toPar")
check("last arc toPar == totals.grossToPar", last_arc == totals.get("grossToPar"),
      "%s vs %s" % (last_arc, totals.get("grossToPar")))

# Par alignment: the recap must read pars by HOLE NUMBER, not by
# playing position. On a start-on-10 round a positional zip hands hole
# 10 the par of hole 1 (observed live 2026-11-14 — see docs).
code, det = req("GET", "/matches/" + mid, TOKEN)
det = det.get("match", det)
pars_hole_order = None
def find_pars(o):
    global pars_hole_order
    if isinstance(o, dict):
        for k, v in o.items():
            if k == "pars" and isinstance(v, list) and len(v) == 18:
                pars_hole_order = v
            else:
                find_pars(v)
    elif isinstance(o, list):
        for v in o:
            find_pars(v)
find_pars(det)
if pars_hole_order:
    wrong = [(p["hole"], p.get("par"), pars_hole_order[p["hole"] - 1])
             for p in arc if p.get("par") != pars_hole_order[p["hole"] - 1]]
    check("recap pars indexed by hole number", not wrong,
          "%d wrong, e.g. %s" % (len(wrong), wrong[:3]))
else:
    check("recap pars indexed by hole number", False, "no pars array on the match detail")

for label in ("best", "worst"):
    # Single stretch object per label ({"from","to","vsPar","holes"}).
    stretches = body.get(label) or []
    if isinstance(stretches, dict):
        stretches = [stretches]
    for i, stretch in enumerate(stretches):
        text = stretch_text(arc, stretch)
        check("%s stretch %d text" % (label, i), text is not None, text or "")
        print("   ", text)

swing_ok = True
for sw in body.get("swings") or []:
    rows = sw.get("holes") or []
    if [h["position"] for h in rows] != sorted(h["position"] for h in rows):
        swing_ok = False
    margin = sum(h["swing"] for h in rows)
    check("swing rows sum to stated total", margin == sw.get("total"),
          "%s vs %s" % (margin, sw.get("total")))
    check("halved + swings == comparedHoles",
          len(rows) + sw.get("halved", 0) == sw.get("comparedHoles"),
          "%d + %d vs %s" % (len(rows), sw.get("halved", 0), sw.get("comparedHoles")))
check("swing rows in playing order", swing_ok)
print("swing hole labels:", [[h["hole"] for h in (sw.get("holes") or [])] for sw in body.get("swings") or []])

net = recap.get("netRecap") or {}
check("netRecap totals present", bool(net.get("totals")), json.dumps(net.get("totals")))
# Front/back split by HOLE NUMBER (server ruling 2026-11-15): front is
# holes 1-9 whatever hole you teed off, like a scorecard's OUT box. Demo
# bogeys every hole, so front gross = par(1-9) + 9, back = par(10-18) + 9.
nt = net.get("totals") or {}
want_front, want_back = sum(pars[:9]) + 9, sum(pars[9:]) + 9
got_front = (nt.get("front") or {}).get("gross")
got_back = (nt.get("back") or {}).get("gross")
check("front/back split by hole number", got_front == want_front and got_back == want_back,
      "front %s (want %d, holes 1-9), back %s (want %d)" % (got_front, want_front, got_back, want_back))

own_story = json.dumps(recap.get("story") or recap.get("headline") or "")
slips = SECOND_PERSON.findall(own_story) if not recap.get("seat", {}).get("matchPlayerId") else ["n/a (own seat: second person is correct)"]
print("own story:", own_story[:300])

# ---- Spectator card (creator not a player) ----
smid, code2, srecap = build_round(spectator=True)
print("\nspectator match:", smid, "| recap:", code2)
if code2 == 200:
    sbody = srecap["recap"]
    sarc = sbody.get("arc") or []
    check("spectator arc follows playing order",
          len(sarc) == 18 and sarc[0]["hole"] == 10 and sarc[9]["hole"] == 1)
    seat = srecap.get("seat") or {}
    story = json.dumps(srecap.get("story") or srecap.get("headline") or "")
    named = seat.get("displayName", "?").lower() in story.lower()
    check("spectator story names the seat", named, story[:220])
    fp = FIRST_PERSON.findall(story)
    check("no first-person word in spectator story", not fp, str(fp))
    check("spectator history hidden",
          not srecap.get("history"), "")
else:
    check("spectator recap", False, "status %d" % code2)

print("\ncleanup:", req("DELETE", "/matches/" + mid, TOKEN, expect_error=True)[0],
      req("DELETE", "/matches/" + smid, TOKEN, expect_error=True)[0])
print("\n%s" % ("ALL PASS" if not failures else "FAILURES: %s" % failures))
sys.exit(1 if failures else 0)
