# Personal best — 18-hole rounds only

Spec for the sticks-golf server, `GET /stats` and `GET /users/:username/stats`.

## Rule

A personal best is a **completed 18-hole round**. 9-hole (and partial) rounds
never count toward it.

## Server changes

- `stats.bestRound`: pick the lowest `vsPar` among completed rounds where the
  caller scored all 18 holes. Ties → lower gross, then most recent. Keep
  shipping `holesPlayed` (always 18 under this rule). No qualifying round →
  `bestRound: null`.
- `stats.courseRecords[]`: keep 9-hole records (a course you've only played 9
  of still deserves a row), but always include `matchId` and `holesPlayed` on
  every record. The app uses `matchId` to put the gold medal on the same round
  the BEST cell shows.

## What the app already does (shipped)

- BEST cell hides any `bestRound` whose `holesPlayed` isn't 18 (shows "—"
  until the server sends a qualifying one).
- Course bests: the medal goes on the record whose `matchId` matches
  `bestRound.matchId`; without that, on the lowest gross among 18-hole records.
  9-hole records never get the medal.

## Why

The two cards disagreed: BEST ranks by score vs par, the medal ranked by bare
lowest gross across all records — so a 9-hole 42 out-medaled an 18-hole 83.
