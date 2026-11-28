# Scorecard screenshot import: server spec

The iOS app lets a player import a round they played with another app
(18Birdies, Arccos, GHIN, Golfshot, a photo of a paper card…) by picking
1–3 screenshots of its scorecard. The server reads each image with a
vision-capable model and returns structured holes, pars and per-player
scores. The app shows an editable review grid and then saves the round
with the **existing** endpoints (`POST /matches`, `/score`, `/pars`,
`/complete`), so nothing else on the server needs to change.

The AI key lives only on the server. The app never calls a model directly.

## Endpoint

`POST /api/mobile/imports/scorecard`

- Auth: the usual `Authorization: Bearer <token>`. Return 401 when missing or invalid.
- Body: raw JPEG bytes, `Content-Type: image/jpeg`. This is the same pattern as `POST /me/avatar`.
- Size: the client downscales to at most 2400 px on the long edge at quality 0.8, usually 300 KB–1 MB. Reject anything over **6 MB** with 413.
- One image per request. When the user picks several screenshots (often front 9 and back 9), the app sends one request per image in parallel and merges the results by hole number and player name.
- Client timeout is 60 s. Keep the model call well under that.
- Don't store the image. Read it, discard it, and return JSON.

## Response (200)

```json
{
  "ok": true,
  "source": "18birdies",
  "course": {
    "name": "Quivira Golf Club",
    "matchedCourseId": "quivira-golf-club",
    "matchedCourseName": "Quivira Golf Club"
  },
  "date": "2026-11-10",
  "roundHoles": 18,
  "holes": [
    { "number": 1, "par": 4 },
    { "number": 2, "par": 4 },
    { "number": 3, "par": 3 }
  ],
  "players": [
    {
      "name": "Mike S.",
      "scores": [
        { "hole": 1, "strokes": 5 },
        { "hole": 2, "strokes": 4 },
        { "hole": 3, "strokes": null, "uncertain": true }
      ],
      "total": 84,
      "isLikelyMe": false
    }
  ],
  "warnings": ["Only holes 1–9 are visible. Add a screenshot of the back nine."]
}
```

Field rules. The client decodes everything tolerantly, so missing keys are fine and `null` is better than a guess.

- `source`: `"18birdies" | "arccos" | "ghin" | "golfshot" | "paper" | "other"`. Display only.
- `course.name`: the course name as printed on the image, or `null`.
- `course.matchedCourseId` / `matchedCourseName`: optional. Run the same lookup `GET /courses?q=` uses with `course.name` and return a hit only when it is unambiguous. When several courses match equally ("Torrey Pines" → North and South), return neither. The app pre-selects a returned match. Without one, it pre-fills the course search with `course.name` so the user picks.
- `date`: `YYYY-MM-DD` when the image shows one, else `null`. The app defaults to today.
- `roundHoles`: 9 or 18 when the card makes it clear, else `null`.
- `holes`: only the holes **visible in this image**, using absolute hole numbers (1–18). `par` is 3–6 or `null`.
- `players[].scores`: one entry per visible hole. `strokes` is 1–15 or `null` when unreadable or blank (a picked-up hole, for example).
  - Set `uncertain: true` when the model isn't confident. The app highlights those cells for the user to check.
- `players[].total`: the printed total, if any. The app shows a mismatch hint when the hole scores don't add up to it. Don't "fix" scores to match.
- `players[].isLikelyMe`: true when the row is visibly the app owner's ("You", the highlighted row, the only player on an Arccos card). Otherwise false. The app also matches against the user's Sticks display name.
- `warnings`: short, human-readable strings that are shown verbatim, for example cut-off columns, blurry digits, or a stats screen instead of a scorecard.
- Up to 8 players.

## Errors

Every error uses the usual `{ "error": "<message>" }` body. The app shows the message as-is, so write it for a golfer.

- **400**: the body is empty or not an image. "That file isn't an image."
- **401**: the token is missing or invalid.
- **413**: the image is too large. "That image is too large. Try a regular screenshot."
- **422**: no scorecard was found. "Couldn't find a scorecard in that screenshot. Try the scorecard view, not the stats page."
- **429**: rate limited. "You've imported a lot of scorecards. Try again in a few minutes."
- **503**: no AI key is configured or the model is down. "Scorecard reading is unavailable right now. You can still enter the scores by hand."

## Rate limit

Allow 20 images per user per hour. That's generous for a few imports with a retry or two, and caps cost.

The limiter fails open: if its counter errors, the request goes through. Log every such failure loudly so it can't stay open unnoticed, and keep the per-request caps (one image, 6 MB) as the cost backstop.

## Model and prompt guidance

- Use any vision model with structured or JSON output. Ask for exactly the schema above and validate it before returning. Hand-written guards match the rest of the repo; no validation library is needed. When a single value is out of range (strokes 1–15, par 3–6), set it to `null` with `uncertain: true` instead of rejecting the whole response. Never clamp it, because clamping invents a score. Retry only when the overall shape is wrong, or when a hole number falls outside 1–18.
  - On a validation failure, retry once, then return 422.
- System prompt essentials:
  - "You are reading a golf scorecard screenshot. Extract only what is visible. Never invent or infer scores. Unreadable means null with uncertain: true."
  - "Hole numbers are absolute (1–18). A back-nine card starts at 10."
  - "Ignore putts, fairways, GIR, handicap/net rows, stroke-index rows, yardage rows and Stableford points. Use the gross strokes row only."
  - "OUT/IN/TOT columns are totals, not holes."
- Layout hints worth putting in the prompt:
  - **18Birdies**: horizontal card, holes across the top, a Par row, then one row per player. Front and back nine are often separate screens. Circles and squares around numbers are birdie/bogey markers, not digits.
  - **Arccos**: usually a single player. The round summary shows a 1–9 / 10–18 grid with par and score. Shot-level stats screens are not scorecards, so return 422 for those.
  - **GHIN**: hole-by-hole score list for a posted score, with a single player.
  - **Paper cards** (photos): rotated or perspective-skewed. Handwriting is the main source of uncertainty, so be liberal with `uncertain`.

## Optional follow-up: bulk scores

Saving an 18-hole, 4-player import makes 72 `POST /matches/:id/score` calls. The app runs 6 at a time, which takes a few seconds. A bulk endpoint would make this a single call:

`POST /api/mobile/matches/:id/scores`

```json
{ "scores": [ { "matchPlayerId": "…", "hole": 1, "strokes": 5 } ] }
```

- Same auth and permission rules as `/score`.
- Validate every entry and write them in one transaction.
- Return `{ "ok": true, "count": 72 }`.
- Fire the round's derived recomputes (odds, highlights, side games) once at the end, not per score.

The app doesn't depend on it today. Once it ships, the client can switch over with a small change.

## Verify against

Using the demo account (user123):

1. POST an 18Birdies scorecard screenshot. Expect 200, the right players and scores, and `matchedCourseId` set when the course is in the catalog.
2. POST a stats or putting screenshot. Expect 422 with the message above.
3. POST 0 bytes. Expect 400.
