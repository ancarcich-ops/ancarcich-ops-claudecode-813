#!/usr/bin/env bash
# Live contract check for slices 93 (reactions), 94 (templates), 95 (support email).
# Mirrors the exact calls the iOS app makes. Reaction toggles are done in
# pairs (add then remove) so the demo round ends where it started.
set -u
API=https://sticks-golf.vercel.app/api/mobile

TOK=$(curl -s -X POST "$API/auth/login" -H 'Content-Type: application/json' \
  -d '{"identifier":"user123","password":"user1234"}' | python3 -c 'import sys,json;print(json.load(sys.stdin).get("token",""))')
[ -z "$TOK" ] && { echo "LOGIN FAILED"; exit 1; }
H=(-H "Authorization: Bearer $TOK" -H 'Content-Type: application/json')
echo "login ok"

echo; echo "== 95: round-options supportEmail"
curl -s "${H[@]}" "$API/round-options" | python3 -c 'import sys,json;d=json.load(sys.stdin);print("supportEmail =",repr(d.get("supportEmail")))'

echo; echo "== 94: round-templates"
curl -s "${H[@]}" "$API/round-templates" | python3 -c 'import sys,json;d=json.load(sys.stdin);t=d.get("templates");print("templates count =",len(t) if isinstance(t,list) else t);print(json.dumps(t[:1],indent=1) if t else "")'

echo; echo "== 93: match list reactions"
MID=$(curl -s "${H[@]}" "$API/matches" | python3 -c '
import sys,json
d=json.load(sys.stdin); ms=d.get("matches",[])
print("matches:",len(ms),"| with reactions key:",sum(1 for m in ms if "reactions" in m),file=sys.stderr)
if ms: print("first reactions:",json.dumps(ms[0].get("reactions")),file=sys.stderr)
print(ms[0]["id"] if ms else "")')
echo "using match $MID"
[ -z "$MID" ] && exit 1

echo; echo "== 93: detail reactionEmoji / reactions / highlights"
curl -s "${H[@]}" "$API/matches/$MID" | python3 -c '
import sys,json
d=json.load(sys.stdin); m=d.get("match",d)
print("reactionEmoji =",m.get("reactionEmoji"))
r=m.get("reactions") or {}
print("reaction targets =",list(r.keys())[:5])
h=m.get("highlights") or []
print("highlights =",len(h)); print(json.dumps(h[:1],indent=1) if h else "")'

echo; echo "== 93: toggle round reaction (add, then remove)"
for i in 1 2; do
  curl -s -X POST "${H[@]}" "$API/matches/$MID/reactions" -d '{"emoji":"🔥"}'; echo
done

echo; echo "== 93: hole without matchPlayerId must 400"
curl -s -o /dev/null -w "status %{http_code}\n" -X POST "${H[@]}" "$API/matches/$MID/reactions" -d '{"emoji":"🔥","hole":1}'
