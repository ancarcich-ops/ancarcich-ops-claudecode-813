# Slice 99 — edit side games mid-round

## The ask

"Why does the app not let you edit games and round settings mid-match
like the website does?"

Half of that is already available and unbuilt; the other half isn't
available to anyone.

A round has two kinds of settings, and they have never had the same
rule:

| | changeable | web | mobile API |
|---|---|---|---|
| **Side games** — which are on, and their settings | until the round is final | yes | **yes, always has been** |
| **Scoring** — scoring mode, handicaps, which group it's posted in | until the round is final | yes | **yes, new — see slice 100** |
| **The card** — course, holes, players, format | before the round starts only | no | no |

Nothing moves a stroke in the first two rows. They change how the
strokes already logged are **counted**, which is exactly what you need
on the 4th when you realise the round was set up gross and the group
plays net. The third row is locked because changing it re-scores holes
already played against a card they weren't played on.

So **the server has never blocked the app from editing side games
mid-round.** The endpoints are there and have been. There just isn't a
screen. That's this slice.

## What the screen is

The web's version, for reference: a list of games, each a checkbox with
a name and one line of explanation, with per-game settings revealed
underneath when the game is on (Skins shows "Carry over / No carry").
Above the list, when the round is underway: *"Round's underway. You can
add or remove side games here — scores recompute from the strokes
already logged."*

Build that. Reach it from the live round screen.

## Endpoints

### Read the picker — `GET /api/mobile/matches/:id/side-games` (new)

Added for this slice. Don't hard-code the game list: the eligibility
rules live on the server so a rule change reaches the app without a
build, and the app can never offer a game the scorer will refuse. Same
reasoning as `/api/mobile/round-options`.

```json
{
  "editable": true,
  "reason": null,
  "games": [
    {
      "kind": "SKINS",
      "label": "Skins",
      "blurb": "Low net wins the hole; ties carry over.",
      "on": true,
      "eligible": true,
      "ineligibleReason": null,
      "locked": false,
      "config": { "pushRule": "CARRYOVER" },
      "settings": [
        {
          "key": "pushRule",
          "label": "On tied holes",
          "type": "choice",
          "default": "CARRYOVER",
          "choices": [
            { "value": "CARRYOVER", "label": "Carry over",
              "blurb": "Skin rolls to the next hole." },
            { "value": "NO_CARRY", "label": "No carry",
              "blurb": "Tied hole pays nothing; reset to 1." }
          ]
        }
      ],
      "settingsComplete": true
    }
  ]
}
```

- **`editable: false`** — show the list read-only and show `reason`. It's
  false once the round is final, and for anyone who isn't the round's
  creator.
- **`eligible: false`** — render the row disabled with
  `ineligibleReason` ("Needs 18 holes", "Needs exactly 4 players"). Don't
  hide it; the web shows it greyed so people can see the game exists and
  why they can't have it.
- **`locked: true`** — only ever Team vs team, and only once it has teams
  assigned. The POST deliberately preserves that row because the team
  assignments can't be rebuilt from this screen. **Render the toggle
  disabled.** If you let it be unchecked it will appear to work and then
  come back on after the round trip.
- **`config`** — the game's current settings as stored, or null.
- **`settings`** — the fields this game takes. **Render controls from
  this, never from a guessed field name.** Types are `choice` (fixed
  values, each with a label and often a blurb), `boolean`, `number` and
  `money`. A number field may carry `dependsOn`, naming a boolean that
  has to be on for it to mean anything. An empty list means the game has
  no settings.
- **`settingsComplete: false`** — this game has settings that need more
  than a flat form (Match's per-player strokes, Team vs team's rules).
  Show "set this up on the web" rather than an empty panel.

On a scramble the list contains only Snake, because a scramble already
plays as teams. Server handles that; just render what comes back.

### Write which games are on — `POST /api/mobile/matches/:id/side-games`

```json
{ "kinds": ["SKINS", "SNAKE"] }
```

**This is a full replacement, not a delta.** Send every kind that should
be on. Anything absent is deleted. Send the complete list from your local
state each time.

Returns `{ "ok": true, "kinds": [...] }` — the kinds that are actually on
afterwards. **Reconcile against that**, don't assume your request stuck:
the server drops Nassau on a 9-hole round and re-adds a configured Team
vs team, so what comes back can legitimately differ from what you sent.

Errors: `403` not the creator, `400` round is final.

### Write a game's settings — `POST /api/mobile/matches/:id/side-game-config`

```json
{ "kind": "SKINS", "config": { "pushRule": "NO_CARRY" } }
```

**Use the field names from `settings`.** An earlier version of this
brief invented `carryOver` for Skins; the real field is `pushRule`. The
server dropped the unknown key, stored `{}` and answered **200**, so the
setting silently did nothing and nothing looked wrong. That can't happen
now — see the errors below — but it is why the schema is served rather
than written down here.

Returns `{ "ok": true, "kind", "config": { ... }, "dropped": [...] }`.
`config` is what is actually stored afterwards, as an object.
**`dropped` names any keys that didn't survive** — treat a non-empty
`dropped` as a bug in your request, not a warning to ignore.

Covers Skins, Wolf, Match, Sixes, Targets, Stableford, BBB, Snake,
Nassau and Team vs team.

Errors: `403` not the creator, `400` round is final, `400` that game
isn't on for this round — turn it on first, and `400 unknown_settings`
when **none** of the keys you sent apply, with `known` listing the ones
that do.

## Things that will bite

**Turning a game on mid-round is not a no-op.** Scores recompute from
every stroke already logged, so enabling Skins on the 14th hole
back-fills thirteen holes of skins. That's intended and it's what the web
tells people in that one-line caption. Keep the caption — it's the
difference between a feature and a surprise.

**Settle-up changes under people's feet.** Flipping Skins carry-over
mid-round rewrites who's winning what. Worth a confirm on destructive-ish
changes to a game that's already scoring, though that's a design call
rather than a server constraint.

**The creator check is real.** Everyone can see the round; only the
creator can change its games. Fetch `editable` and lay the screen out
accordingly rather than letting a non-creator tap a toggle and collect a
403.

## Acceptance

- Open a live round you created with Skins on. The screen lists all ten
  games, Skins checked, carry-over visible under it.
- Turn Snake on, back out, reopen: still on. Check the round's scoring —
  a 3-putt already logged should count.
- Turn Skins off and on again; the skins leaderboard recomputes from the
  strokes already there.
- On a 9-hole round, Nassau and Sixes are visible but disabled with a
  reason.
- On a round you did **not** create, the list is read-only with the
  reason shown.
- On a finished round, read-only with "This round is final."
- On a round with teams assigned, Team vs team is checked and its toggle
  is disabled.

## Not in this slice

- **Round scoring mid-round** (scoring mode, handicaps, posted group).
  That's its own screen and its own endpoint — see slice 100 below. Both
  screens are reachable from the live round; keep them separate, as the
  web does, because one re-counts strokes and the other re-ranks games.
- Picking teams for Team vs team from the app. The POST preserves an
  existing configured row but can't build one — that's its own slice.

---

# Slice 100 — edit round scoring mid-round

The other half of the same question, and the half that really was
missing on the server. The web has a **Round settings** card on the live
round screen: posted-in, Net/Gross, and each player's handicap, with the
caption *"Change these any time — scores already logged stay put and
every leaderboard recalculates. Course, holes and players are locked
once the round starts."*

The app had no route for it: the only mobile endpoint touching round
settings was `PATCH /matches/:id`, which is `UPCOMING`-only — correctly,
because it also edits the card. The scoring half now has its own
endpoint.

### `POST /api/mobile/matches/:id/scoring`

Every field optional; send only what changed.

```json
{
  "scoringMode": "NET",
  "groupId": "public",
  "handicaps": [{ "matchPlayerId": "...", "handicap": 10.8 }]
}
```

Returns `{ "ok": true, "scoringMode", "groupId", "handicaps": [...] }` —
the state afterwards. Reconcile against it.

Rules, shared with the web action so they can't drift:

- **Creator only** (`403`), and refused once the round is `COMPLETED`
  (`400` — "Reopen the round before changing its scoring").
- **Handicaps go by `matchPlayerId`, not by position.** The web posts a
  parallel array because it renders the roster on the same page. An app
  holding a list from an earlier fetch could have a stale order, and a
  misaligned array hands one player another's handicap and re-scores
  both. Send the ids.
- **A blank handicap leaves the stored one alone.** It is not scratch.
  Send `""` or omit the row to mean "unchanged".
- **An unrecognised `scoringMode` changes nothing** rather than
  defaulting — a typo must not re-score the round.
- **A scramble locks to gross** whatever you send.
- **`groupId`** takes a group id, or `"public"`/`null` to clear it. A
  group you're not in silently falls back to public rather than erroring,
  so a bad group never throws away the scoring change you came to make.

### Things that will bite

**This re-counts the whole round immediately.** Switching Net → Gross on
the 12th re-ranks every leaderboard from the strokes already logged.
That's the point, and it's why the web shows that caption. Keep it.

**Changing a handicap mid-round is a settle-up change.** Worth a confirm.

**Odds re-price on save.** Expect the market numbers to move.

### Acceptance

- Live round set up Gross: switch to Net, leaderboards recalculate, the
  logged strokes don't change.
- Edit one player's handicap; only that player's net scores move.
- Leave a handicap box blank and save: that player's handicap is
  unchanged, **not** zero.
- On a round you didn't create: read-only.
- On a finished round: refused with the reopen message.
- Course, holes and players stay locked — if those are editable on your
  screen mid-round, that's a bug.

## Addendum — dropped semantics fixed, money clears with 0 (Nov 14)

Two corrections, both server-side, both shipped and deployed:

**`dropped` now means "this game has no such setting", not "a value
didn't end up stored."** The original meaning broke two ordinary
requests: clearing a money field reported the key as dropped, and
turning Nassau's auto-press off 400'd (the parser stores `autoPress`
only when true, so every key looked dropped). The app's guard — error
on non-empty `dropped` — was written against the corrected meaning and
is right as is.

**A money field cleared to 0 IS a clear.** Verified live on all four
(SNAKE/NASSAU/SIXES stake, TARGETS ante): every parser stores a stake
only above zero, so `0`, `null` and omitting the key land on the same
stored config. The app's number field sends 0 on clear, by design.
The served descriptors now state this in the type and the blurbs.

**`dependsOn` stays in sync by construction** — the server drops a
dependent field whenever its boolean is off, and the app hides it in
that same state. If a dependent field is ever added server-side that
isn't dropped, the two would diverge silently; check that pairing when
touching either side.
