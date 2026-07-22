# Sticks — watchOS App Design Handoff

Purpose: this doc describes the **current** design of the Sticks Apple Watch app so you (Claude Code) can propose new design directions. It covers what's on screen, the design language, the data available, and the hard constraints any redesign must respect.

---

## 1. Product context

Sticks is a social golf app (group matches, live scoring, side games, odds). The watch app is a **glanceable on-course companion**:

- Shows live GPS yardages to the green (front / center / back) for the current hole.
- Lets the wearer switch holes and enter **their own** score from the wrist.
- Everything is proxied through the paired iPhone. The watch is deliberately a "dumb terminal" — **no networking, no auth, no course database on the watch**.
- While a round is live, the watch runs a golf workout session so the app stays frontmost on wrist-raise for the entire round (this is core UX — the wearer should never have to relaunch it mid-round).
- The iPhone auto-launches the watch app when Sticks opens on the phone.

## 2. Design language (shared with iPhone/web)

The brand is "old money golf club": cream, deep green, gold, muted red, serif numerals.

### Color tokens (watch variants, tuned for the black watch background)

| Token | Value | Use |
|---|---|---|
| `sticksGreenBright` | rgb(0.45, 0.76, 0.56) | Brand green lifted for legibility on black — course name, accents, spinners |
| `sticksGreen` | #285E45 | Deep accent green — birdie, score CTA background |
| `sticksGold` | #A9762A | Eagle+, "overall score" value, stale warning |
| `sticksDanger` | #9A2B26 | Over-par red, error text |
| `sticksCream` | #EDE7DB | Text on green/gold fills |

### Par-relative score color system (`WatchScoreStyle`)

Score colors match the phone/web "ScoreStyle" language:

- Eagle or better (score − par ≤ −2): gold background, cream text
- Birdie (−1): deep green background, cream text
- Par (0): green at 50% opacity, white text
- Bogey (+1): danger red at 60% opacity, white text
- Double+ (≥ +2): full danger red, white text

Relative labels: `ACE` (score == 1), `ALBATROSS`, `EAGLE`, `BIRDIE`, `PAR`, `BOGEY`, `DOUBLE`, `TRIPLE`, then `+N`.

### Typography

- **Big numerals** (yardage, strokes, to-par): system **serif** design, semibold/bold, monospaced digits, `contentTransition(.numericText())` for animated changes.
  - Center yardage: 52pt serif semibold (the hero element)
  - Front/back yardage: 20pt serif semibold
  - Overall to-par: 22pt serif bold, gold
  - Stroke count in score entry: 46pt serif semibold
- **Captions / labels**: small (9–11pt), semibold/bold, UPPERCASE, generous kerning (1–1.6). e.g. `YDS TO CENTER`, `OVERALL SCORE`, `HOLE 7 · PAR 4`.
- Wordmark on the resting screen: "Sticks" 22pt serif semibold.
- Background is pure black everywhere except the score-entry sheet (full-bleed par-relative color).

## 3. Screens (current)

### 3.1 Resting state (no live round) — `ContentView.noRound`

Centered vertical stack:

- `flag.fill` SF Symbol, 26pt bold, brand green
- "Sticks" wordmark (22pt serif)
- Secondary caption: "Open a round on your iPhone to see live yardages here." (12pt, centered)

### 3.2 Round glance (main screen) — `RoundGlanceView`

A single scrollable column on black, top to bottom:

1. **Course name** — uppercase, 11pt semibold, kerned, brand green, 1 line with scale-down.
2. **Hole switcher** — `‹  HOLE 7 · PAR 4  ›`. Chevrons are 32×32 circular buttons (white 12% fill). Tapping switches the hole **on the phone**; the label updates optimistically ("HOLE 8" without par, since par arrives with the reply), a click haptic plays, chevrons disable while in flight, and the change reverts on failure. Chevrons disable at round bounds (index 0 / totalHoles−1).
3. **Center yardage (hero)** — 52pt serif number, or `—` if unknown. Replaced by a green spinner while a hole switch is pending. Dims to 35% opacity when stale.
4. **Status line** (one of, in priority order):
   - Transient command error, red bold 9pt (e.g. `CAN'T REACH IPHONE`), auto-dismisses after 2.5s with a failure haptic.
   - `OPEN STICKS ON IPHONE` in gold when the snapshot is stale (> 3 minutes old — a TimelineView re-checks every 15s).
   - Default: `YDS TO CENTER` in secondary gray.
5. **Front / Back flanks** — side-by-side pairs (`FRONT` / `BACK` caption over 20pt serif number), dimmed when stale or pending.
6. **Score button** (only if the wearer has a seat in the match; spectators never see it) — a capsule pill:
   - No score yet: `+ SCORE` on deep green.
   - Scored: `5 BOGEY` (number + relative label) with the par-relative background color.
   - Tap opens the score entry sheet.
7. **Overall score** — `OVERALL SCORE` caption over the running to-par (`+3` / `E` / `−1`, or `—` before any hole is scored), 22pt serif bold in gold.

### 3.3 Score entry (sheet) — `WatchScoreEntryView`

Full-screen sheet whose **entire background is the par-relative color** for the currently selected stroke count (live — turning the crown from 4 to 6 on a par 4 animates green → red).

- Top caption: `HOLE 7 · PAR 4` (11pt, 75% opacity of text color).
- Center row: `−` / `4` / `+` — 34×34 circular ± buttons (white 18% fill) flanking a 46pt serif stroke count.
- Below: the relative label (`BIRDIE`, `BOGEY`…) 13pt heavy, kerned.
- Digital Crown also adjusts strokes (1–20, haptic detents).
- Error message line (if a send failed), then:
- **CONFIRM** button — full-width white capsule, black heavy kerned text; becomes `RETRY` after a failure, spinner while sending (5s max — the command layer enforces a timeout so the spinner can never hang).
- Success: success haptic + auto-dismiss. Failure: failure haptic + inline message.

## 4. Data available on the watch (`RoundSnapshot`)

This is **all** the watch knows — anything a new design shows must come from these fields (or require a phone-side change, which is fair game to propose but call it out):

```swift
struct RoundSnapshot {
    var courseName: String
    var hole: Int            // display number
    var holeIndex: Int       // 0-based round index (setHole command space)
    var par: Int
    var frontYds: Int?       // yardages to green (nil = unknown/no GPS)
    var centerYds: Int?
    var backYds: Int?
    var holesScored: Int
    var totalHoles: Int
    var myToPar: Int?        // wearer's running to-par
    var isSeated: Bool       // false = spectator, no score entry
    var myScore: Int?        // wearer's score on the CURRENT hole
    var updatedAt: Date      // staleness anchor
}
```

Commands the watch can send to the phone (5s timeout, reply carries a fresh snapshot):

- `setHole(index:)` — switch the current hole
- `sendScore(hole:strokes:)` — post the wearer's score

Notably **not** available today: other players' scores, match standings/sticks, side-game state, hole maps/shapes, distances to hazards, shot tracking. Proposing designs that need these is welcome — just flag the new snapshot fields/commands required.

## 5. Hard constraints for any redesign

1. **Dumb terminal** — no networking on the watch; everything flows through WatchConnectivity. New data = new snapshot fields; new actions = new commands.
2. **Staleness is a first-class state** — yardages older than 3 minutes must visibly degrade (currently: dim + gold `OPEN STICKS ON IPHONE`). Never present stale GPS numbers as live.
3. **Optimistic UI with honest failure** — hole switches show instantly but revert on failure; score sends never leave an infinite spinner (5s cap), always haptic on success/failure.
4. **Spectator gating** — `isSeated == false` hides score entry entirely.
5. **Glanceability** — the center yardage is the hero; the wearer is mid-swing-decision. Sub-second read of "how far" is the whole job.
6. **Small screens** — designs must work from 40mm up; current layout is a single scrollable column.
7. **Brand consistency** — serif monospaced-digit numerals, kerned uppercase captions, the cream/green/gold/red palette, par-relative color language identical to phone/web.
8. **Digital Crown** — score entry supports crown input; keep crown affordances in any new score UI.
9. **Haptics everywhere** — click on hole switch, success/failure on score send. Preserve or extend.
10. **Workout keep-alive** — the app stays frontmost during rounds via a golf workout session; designs can assume the app is the watch face's replacement for 4+ hours, so consider battery (black backgrounds are good on OLED) and always-on dimmed states.

## 6. File map (for reference)

```
ios/SticksWatch/
├── SticksWatchApp.swift        # @main; activates session, workout keep-alive
├── WatchAppDelegate.swift      # launch-for-workout handoff from phone
├── ContentView.swift           # routes: snapshot → RoundGlanceView, else resting state
├── RoundGlanceView.swift       # main round screen
├── WatchScoreEntryView.swift   # score stepper sheet
├── WatchScoreStyle.swift       # par-relative color + label mapping
├── Theme.swift                 # color tokens
├── RoundSnapshot.swift         # wire model (mirrored in phone app — keep identical)
├── PhoneSessionService.swift   # WatchConnectivity: snapshot merge + commands
└── WorkoutKeepAliveService.swift # golf workout session for frontmost persistence
```

## 7. What to explore (open brief)

Ideas the team is open to — treat as inspiration, not requirements:

- Richer round context: match standings, who's winning sticks, side-game status at a glance.
- Complications / Smart Stack widget showing hole + yardage.
- A hole-progress ring or 18-dot round tracker.
- Better always-on / wrist-down dimmed presentation.
- Crown-driven hole switching on the main screen.
- Celebration moments (birdie/eagle animations + haptic patterns).
