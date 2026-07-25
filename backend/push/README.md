# Sticks push notifications — Vercel backend package

Drop-in implementation of `docs/push-notifications-backend-handoff.md` for the
`sticks-golf` Vercel repo. Zero new dependencies for APNs delivery (raw HTTP/2 +
ES256 JWT via `node:http2` / `node:crypto`); the only package needed is `pg`
(skip it if you swap `lib/db.js` for your existing Prisma/Drizzle client).

## Install

1. Copy folders into the backend repo root:
   - `api/mobile/me/*` → your `api/mobile/me/` (Vercel file-based routes)
   - `lib/*` → e.g. `lib/push/` (fix the relative imports in `api/` if you
     nest them differently)
2. Run `migrations/001_push.sql` against the database.
3. `npm i pg` (only if you keep the default `lib/db.js`).
4. Vercel env vars:
   - `APNS_KEY` — full contents of the `.p8` (paste as-is; `\n` escapes OK)
   - `APNS_KEY_ID` — 10-char key id
   - `APNS_TEAM_ID` — Apple Developer team id
   - `DATABASE_URL` — if using the default `lib/db.js`

## Adapt these two files (marked `ADAPT` in code)

- `lib/auth.js` — `getUserIdFromRequest` assumes a `sessions(token, user_id)`
  table. Point it at the same Bearer-token lookup the other `/api/mobile`
  routes use.
- `lib/audience.js` — the fanout SQL assumes:
  `match_players(id, match_id, user_id)`, `matches(id, group_id, tee_time,
  status)`, `follows(follower_id, followee_id, state='accepted')`,
  `group_members(group_id, user_id)`. Adjust names here only; nothing else
  touches the schema.

## Wire the event senders into existing routes

Send AFTER responding, with `waitUntil` so delivery never blocks or fails the
request:

```js
import { waitUntil } from "@vercel/functions";
import {
  notifyRoundStart,
  notifyScoreHighlight,
  notifyFrontNine,
  notifyRoundFinal,
  notifyFollowRequest,
  notifyFollowAccept,
} from "../lib/push/pushEvents.js";

// POST /matches/:id/score — after saving the score:
res.status(200).json({ ok: true });
if (isFirstScoreOfMatch) {
  waitUntil(notifyRoundStart({ matchId, actorUserId, playerName, courseName, seatCount }));
}
if (strokes != null && strokes <= par - 1) {
  waitUntil(notifyScoreHighlight({ matchId, matchPlayerId, actorUserId, playerName, courseName, hole, par, strokes }));
}
if (holes1to9AllScored) {
  waitUntil(notifyFrontNine({ matchId, matchPlayerId, actorUserId, playerName, courseName, frontTotal, frontToPar }));
}

// POST /matches/:id/complete — on the first transition to COMPLETED:
waitUntil(notifyRoundFinal({ matchId, actorUserId, courseName, results }));
// results: [{ name, total, toPar }] per seat, best first

// POST /follows action=request (target does NOT auto-accept):
waitUntil(notifyFollowRequest({ targetUserId, requesterUserId, requesterUsername, pendingCount }));

// POST /follows action=accept (incl. auto-accept):
waitUntil(notifyFollowAccept({ requesterUserId, accepterUserId, accepterUsername }));
```

Notes:

- `notifyRoundStart` / `notifyFrontNine` / `notifyRoundFinal` carry their own
  fire-once guards (`push_events_sent`), so calling them on every score post is
  safe.
- Audience rules (never the actor, never seated players, prefs, the 24h
  abandoned-round rule, follower∪group dedupe) are enforced inside the senders.
- Dead tokens (410 / `BadDeviceToken`) are pruned automatically after each send.
- All senders are fail-soft — they log and never throw into the request path.

## Endpoints added

- `POST   /api/mobile/me/push-token` — upsert, reassigns on account switch
- `DELETE /api/mobile/me/push-token/:token` — idempotent sign-out cleanup
- `GET    /api/mobile/me/push-prefs` — defaults to all-true when no row
- `POST   /api/mobile/me/push-prefs` — full replace

All use the standard Bearer auth + `{ "error": string }` error shape.

## Sandbox vs production

Each token row stores its `environment` (the app sends `sandbox` for debug
builds, `production` for TestFlight/App Store). `lib/apns.js` routes each token
to the matching APNs host automatically — one `.p8` key serves both.
