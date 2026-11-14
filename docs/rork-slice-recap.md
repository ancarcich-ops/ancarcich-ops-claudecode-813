# Slice 101 — the post-round recap

Two surfaces, one payload:

1. **A card** that announces itself once when a round goes final.
2. **A Recap tab** on the round screen with the whole thing.

The server computes all of it. The app lays it out. That split is the
point: getting a recap right means naming scores against par, walking
the round's **real routing**, allocating strokes by position rather than
hole number, and making the per-hole swings sum to the actual margin.
Four chances to drift if two clients each do their own.

## The endpoint

`GET /api/mobile/matches/:id/recap` (Bearer)

- **404** when nothing is scored yet — *show no entry point for the
  recap at all in that case.* A recap of nothing is worse than no recap.
- **403** if the caller can't see the round (same gate as the round).
- A spectator gets the first player's card rather than an empty page;
  `seat` says whose recap it is. `history` is null unless it's your own
  seat — "your average here" means nothing about somebody else's round.

### Real payload, from a live-shaped round

An 18 at Rustic Canyon off the **tenth**, scored net, won by one.

```json
{
  "seat": { "matchPlayerId": "seat_you", "displayName": "Seuss.md" },
  "scoringMode": "NET",
  "headline": {
    "score": "92",
    "toPar": "+20",
    "story": "You won by 1 — you picked up 4 over holes 13–15."
  },
  "recap": {
    "mode": "GROSS",
    "totals": {
      "holesScored": 18, "gross": 92, "net": 80,
      "grossToPar": 20, "netToPar": 8,
      "front": { "gross": 48, "net": 42, "toPar": 12 },
      "back":  { "gross": 44, "net": 38, "toPar": 8 }
    },
    "arc": [
      { "hole": 10, "position": 0,  "toPar": 3,  "strokes": 7, "par": 4, "delta": 3 },
      { "hole": 11, "position": 1,  "toPar": 5,  "strokes": 7, "par": 5, "delta": 2 },
      "…one per scored hole, in playing order…",
      { "hole": 9,  "position": 17, "toPar": 20, "strokes": 3, "par": 4, "delta": -1 }
    ],
    "best":  { "from": 6,  "to": 9,  "vsPar": 2, "holes": 4 },
    "worst": { "from": 10, "to": 13, "vsPar": 7, "holes": 4 },
    "distribution": {
      "eaglesOrBetter": 0, "birdies": 1, "pars": 0,
      "bogeys": 14, "doubles": 2, "triplesOrWorse": 1
    },
    "byPar": [
      { "par": 3, "holes": 4,  "avgScore": 4.0,  "avgVsPar": 1.0  },
      { "par": 4, "holes": 10, "avgScore": 5.1,  "avgVsPar": 1.1  },
      { "par": 5, "holes": 4,  "avgScore": 6.25, "avgVsPar": 1.25 }
    ],
    "difficulty": [
      { "label": "Hardest", "holes": 6, "fromIndex": 1,  "toIndex": 6,  "vsPar": 10, "avgVsPar": 1.67 },
      { "label": "Middle",  "holes": 6, "fromIndex": 7,  "toIndex": 12, "vsPar": 6,  "avgVsPar": 1.0  },
      { "label": "Easiest", "holes": 6, "fromIndex": 13, "toIndex": 18, "vsPar": 4,  "avgVsPar": 0.67 }
    ],
    "swings": [
      {
        "opponentName": "JHeacock", "total": 1,
        "comparedHoles": 18, "halved": 11,
        "holes": [
          { "hole": 10, "position": 0, "yourStrokes": 7, "theirStrokes": 5,
            "yourLabel": "Triple bogey", "theirLabel": "Bogey", "swing": -2 },
          "…decided holes, biggest first…"
        ],
        "series": [
          { "hole": 10, "position": 0, "swing": -2, "yourVsPar": 3, "theirVsPar": 1 },
          "…every compared hole, in playing order…"
        ]
      }
    ]
  },
  "netRecap": { "…": "same shape, scored net. null on a gross round" },
  "history": null,
  "historyLabel": null
}
```

## 1. The card

Fires **once per person per round**, when the round goes final. It's the
only thing in this feature that interrupts anybody, so it earns that two
ways:

- **Once per person, not once per view.** A card that reappears every
  time you check a score is one people learn to dismiss without reading
  — and then the time it matters, they dismiss that too. The web keys it
  off local storage per round; do the equivalent. If it shows once more
  on a second device, nothing is harmed.
- **Headline only.** Score, `toPar`, the one sentence, a way through to
  the Recap tab. The four sections live in the tab; repeating them here
  makes it a page on top of a page.

Contents: `headline.score` big, `headline.toPar` beside it (red over
par, green under, muted at level), `headline.story` underneath, a small
arc chart, and chips for the ends of the scale only — birdies and
blow-ups. "14 bogeys" is a statistic, not a highlight.

Tapping outside dismisses. It must never trap anyone between them and
their scorecard.

## 2. The Recap tab

Default to it on a finished round — once a round is final the recap is
what people came to read; the scorecard is a reference you go looking
for. While a round is live it's the other way round.

### Where the match was won

From `recap.swings`. The selector picks the opponent; the list is already
sorted **nearest finish first**, because the closest match is the one
people argue about — land on `swings[0]`.

Show the margin (`total`), then `holes` as rows: hole number, "your X v
their Y" from the labels, and the swing. `halved` goes at the bottom as
"N holes tied". `series` is every compared hole in playing order — you
don't need it to render the list; it's there for a chart if you want one.

### The round

`totals`, then the **arc chart** (below), then `best` and `worst`.

### Scoring

`distribution` as a row of counts — **only the ones that happened.** A
row of zeroes is noise. Then `byPar` as a small table.

### Hard holes vs easy

`difficulty` as three diverging bars from a centre line, with
`avgVsPar` printed beside each. Caption: *"The card ranks its holes 1 to
18 by difficulty — 1 is the hardest. This is your average against par in
each third."* Empty array when the course has no stroke index — hide the
section.

### Against your history here

`history` + `historyLabel`, only when both are non-null.

## The arc chart

`recap.arc` is cumulative strokes against par, one point per scored
hole, in playing order.

**ABOVE PAR IS UP.** The line follows the number it draws: `+20` belongs
at the top. I got this backwards on the web first time and it had to be
flipped — a round that plunged downward as it got worse read as falling
off a cliff. Match the match-card sparkline, which has always done it
this way.

- Dashed reference line at par, labelled.
- One dot per hole. Those are the data; the line between them is only
  joining them.
- **Don't let a smoothed curve overshoot.** If you smooth, use monotone
  cubic — a plain Catmull-Rom spline bulges past its endpoints and
  invents a birdie between two pars. Straight segments are fine and
  honest if that's easier.
- Highlight `best` and `worst` as segments on the line. **Draw `worst`
  dashed, not merely red** — green against red is the pair the commonest
  colourblindness can't separate (ΔE 6.5 for deuteranopia), so it needs a
  second cue.
- **Put the hole readout under the chart, not floating over it.** As a
  tooltip it escapes the card at the top edge, and on a phone it appears
  exactly under the thumb that summoned it. A fixed line underneath is
  always legible and can carry the legend when nothing is selected, so
  it costs no extra height.

`x` labels come from `hole`, which off the tenth runs 10 … 18, 1 … 9.
Don't sort them.

## Language

The web went through two rounds of correction on this. Please match it.

- **Never "gross" and "net" as bare words.** The app's own vocabulary is
  **"Straight up"** and **"Handicap"**. "Figures are gross, this round
  was scored net" is confusing to most people.
- **"Tied", not "halved."**
- **Watch an ambiguous `+`.** On one screen `+2` meant *two ahead of your
  opponent* while `+16` meant *sixteen over par*, side by side. Label
  them or separate them.

## Gross and net

`recap` is **always gross** — it's what people say out loud and it
doesn't move when somebody edits a handicap weeks later. On a net round
(`scoringMode !== "GROSS"`), `netRecap` carries the settled figures.

**Where the two disagree about who won, print the settled result beside
the gross one.** Do not hide it behind a toggle. A recap that implies
somebody won a match they lost is worse than no recap. The web prints
the gross margin and then, beside it, "with handicaps: you won by 6".

## Acceptance

- Finish a round: the card appears once. Dismiss, reopen the round — it
  does not come back. Re-install or clear storage and it may; that's fine.
- A round **off the tenth**: the arc's x-axis reads 10 … 18, 1 … 9, and
  any stretch crossing the turn is named "17 through 2", never "17–2".
- A round where gross and net disagree on the winner: both results are
  visible without tapping anything.
- A course with no stroke index: the difficulty section is absent, not
  empty.
- A round with nothing scored: no recap entry point at all (the endpoint
  404s).
- A round you're only watching: it renders, shows whose card it is, and
  has no history section.
- Numbers tie out: the last `arc` point's `toPar` equals
  `totals.grossToPar`, and the swing rows sum to the stated margin. If
  they ever don't, that's a server bug — tell me rather than patching
  around it.

## Not in this slice

- A share image. Same payload when we want it.
- Hole-level reactions inside the recap. The feed and round screens own
  those.

---

## Verification addendum (2026-11-14, slice 101)

Verified live against a fully-scored finished probe round (NET, 2 players, 18 holes):

- **Tie-out holds.** Last arc `toPar` == `totals.grossToPar` (18 == 18); swing rows' holes
  (−2, +1) sum to the stated total (−1); `halved` 16 + 2 swings == 18 compared holes.
- **Best/worst `from`/`to` are INCLUSIVE arc positions** — the live all-bogeys round returns
  `{"from":1,"to":4,"holes":4}`, and the spec sample (`from:6, to:9, holes:4` over positions
  0…17) confirms it. An earlier draft of this addendum said "half-open"; that was wrong.
  App renders `arc[from].hole … arc[to].hole` — "holes 2 through 5 · 4 over" on the probe.
- **Spectator seat** (creator not a player): recap returns 200, `seat` falls back to the first
  player, `history`/`historyLabel` absent. Tie-out holds (grossToPar 0 == last arc 0).
  **Server bug:** the spectator headline story speaks in second person — `"You won by 5 —
  Spectated B dropped 2 shots over holes 1–3."` — for a seat that isn't the caller. The spec's
  "SEUSS.MD'S ROUND" naming is the caller-side fix; the story text is server-authored and
  should switch to the named seat on the server.
- **`history` is null on a first round at a course** (own seat included) — app hides the
  section; nothing to fix client-side.
- **`difficulty` came back `[]`** on a catalog course probed by name — app renders nothing
  when empty, per spec.
- On-sim (rented iPhone): headline card fires once on first open of the final round
  ("FINAL — PARK CITY GOLF COURSE", 91, +18, story, compact arc), does not return after
  dismissal; the Recap tab defaults on that first open, Scorecard on subsequent opens;
  settled line reads "83 (+10)" (net 83 / netToPar +10 from `netRecap.totals`).
