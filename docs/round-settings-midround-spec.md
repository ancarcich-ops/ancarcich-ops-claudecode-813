# Round settings mid-round — mobile parity spec

The web's round detail menu offers **Round settings** on a live round; the iOS
app only shows it while the round is upcoming with no scores, because the
mobile API rejects every edit once a round starts. This spec proposes the
server contract so iOS can match the web.

---

## Probe evidence (live, 2026-11-13)

Created a probe round as the demo account, posted one score (round went
IN_PROGRESS), then PATCHed `/api/mobile/matches/:id` one field at a time.
**Every field returns `{"error":"Only rounds that haven't started can be
edited."}`** once the round is live:

`scheduledAt` · `scoringMode` · `format` · `holes` · `startingHole` ·
`courseName` · `sideGames` (a separate endpoint exists for that and works —
`POST /matches/:id/side-games`) · `players`

(Probe round deleted afterwards; nothing persisted.)

## Proposed server contract

Extend `PATCH /api/mobile/matches/:id` to accept a **mid-round subset** for
the creator, keeping scorecard identity locked:

Allowed once started (recomputable without corrupting the card):

| Field | Notes |
|---|---|
| `scheduledAt` | Tee time; cosmetic, feeds the header |
| `scoringMode` | NET/GROSS switch; standings recompute from stored gross |
| `players[].displayName` | Rename a seat |
| `players[].handicap` | Course/course-hole handicaps recompute; net strokes on scored holes re-derive |
| `players[].teeName` / `teeGender` | Wrong-tee fix; re-derives handicap strokes |

Still rejected once started (400, current message is fine):

`courseName` · `holes` · `startingHole` · `format` — these change the
scorecard itself, not values on it.

Response shape unchanged from the upcoming-round PATCH.

**Please confirm against the web's Round settings screen** — it's the source
of truth for what's allowed mid-round. If the web also locks some of the
"allowed" rows above, mirror that; if it edits more, tell me and I'll add it.

## iOS plan once the contract lands

1. New "Round settings" menu item in the detail actions menu — creator,
   IN_PROGRESS (joins Mark final / Delete round).
2. Opens the existing CreateMatchView edit mode (it already PATCHes) with a
   reduced field set when live: course/holes/format/starting-hole pickers
   disabled, tee time + scoring mode + seat names/handicaps/tees editable.
3. Acceptance: rename a seat and flip NET→GROSS on the demo-created live
   round; standings and header re-derive; an unscored-hole par unchanged.
