# Remote Push Notifications — Backend Handoff

The iOS app (slice 71) now registers for APNs, uploads its device token,
exposes per-category preference toggles, and deep-links notification taps.
This document is the server-side contract the `sticks-golf.vercel.app`
backend needs to implement to start sending pushes.

Bundle ID (APNs topic): `app.rork.ofo2zt4lcp6hi4ceu1jsm`

---

## 1. APNs credentials

Use token-based auth (an `.p8` key — never expires, works for sandbox and
production simultaneously):

1. Apple Developer portal → Certificates, Identifiers & Profiles → Keys →
   create a key with **Apple Push Notifications service (APNs)** enabled.
2. Download the `.p8` once and store it as a Vercel env secret.
3. Env vars needed server-side:
   - `APNS_KEY` — contents of the `.p8` file
   - `APNS_KEY_ID` — the 10-char key id
   - `APNS_TEAM_ID` — the Apple Developer team id
   - Topic header is the bundle id above.

Hosts:
- Production: `https://api.push.apple.com`
- Sandbox: `https://api.sandbox.push.apple.com`

Route by the token's stored `environment` field (see below). On HTTP 410
(`Unregistered`) or 400 with reason `BadDeviceToken`, delete the token row.

Recommended library (Node): `@parse/node-apn`, or raw HTTP/2 with a JWT
(ES256 signed with the `.p8`, refreshed every ~50 min).

## 2. Storage

`push_tokens`
- `token` (text, primary key) — hex APNs device token
- `user_id` (fk → users)
- `platform` (text, `"ios"`)
- `environment` (text, `"sandbox" | "production"`)
- `app_version` (text, nullable)
- `updated_at`

A token moving to a different `user_id` on upsert is normal (shared
device, account switch) — always reassign.

`push_prefs` (or columns on users), all booleans defaulting `true`:
`round_starts`, `birdies_and_better`, `front_nine_scores`,
`final_scores`, `follow_requests`.

## 3. New endpoints (Bearer auth like all `/api/mobile` routes)

### POST /api/mobile/me/push-token
Body: `{ "token": string, "platform": "ios", "environment": "sandbox"|"production", "appVersion"?: string }`
Upsert keyed on `token`, assign to the caller. → `{ "ok": true }`

### DELETE /api/mobile/me/push-token/:token
Delete the row if it belongs to the caller (idempotent — 200 even if
already gone). → `{ "ok": true }`
Called at sign-out so a signed-out device never receives pushes.

### GET /api/mobile/me/push-prefs
→ `{ "prefs": { "roundStarts": bool, "birdiesAndBetter": bool, "frontNineScores": bool, "finalScores": bool, "followRequests": bool } }`

### POST /api/mobile/me/push-prefs
Body: the full prefs object (same shape). Replace and return `{ "ok": true }`.

## 4. Notification payload contract (what the app expects)

Custom keys sit at the payload root, next to `aps`:

```json
{
  "aps": {
    "alert": { "title": "…", "body": "…" },
    "sound": "default",
    "thread-id": "<matchId>"
  },
  "type": "round_start | score_highlight | front_nine | round_final | follow_request | follow_accept",
  "matchId": "<id, for round events>",
  "userId": "<id of the actor, optional>"
}
```

Headers per request:
- `apns-topic: app.rork.ofo2zt4lcp6hi4ceu1jsm`
- `apns-push-type: alert`
- `apns-priority: 10`
- `apns-collapse-id`: see per-event notes (dedupes rapid-fire updates)

Tap routing in the app: any payload with `matchId` opens that round's
detail; `follow_request` / `follow_accept` opens the People screen.

## 5. Events, audiences, and copy

General rules for every event:
- **Never notify the actor** (the player who posted the score, etc.).
- **Never notify players seated in the round** for score events — they
  are watching the round live.
- Respect the recipient's pref for that category, and skip users with
  no registered tokens.
- Audience for round events = (accepted followers of each seated,
  account-linked player) ∪ (members of the round's group, if any),
  minus seated players. Respect the abandoned-round rule: no pushes for
  rounds live > 24h past tee time.
- Send one push per recipient per event (dedupe when someone is both a
  follower and a group member).

### round_start — pref `roundStarts`
Trigger: the first score of the match is posted (status flips to
IN_PROGRESS). Fire once per match (guard with a flag/exists check).
- Title: `Round starting` / Body: `Tj teed off at Rustic Canyon` (add
  `with 3 others` when multiple seats).
- `apns-collapse-id: start-<matchId>`

### score_highlight (birdie or better) — pref `birdiesAndBetter`
Trigger: POST /matches/:id/score where `strokes <= par - 1` for that hole.
Classify: `strokes == 1` → ace; `par - strokes`: 1 → birdie, 2 → eagle,
3+ → albatross.
- Title: `Birdie 🐦` (or `Eagle`, `Albatross`, `ACE 🎯`)
- Body: `Tj birdied hole 7 at Rustic Canyon`
- `apns-collapse-id: hl-<matchPlayerId>-<hole>` — a corrected score
  replaces the earlier alert instead of double-notifying. If the
  correction drops below birdie, just don't send (accept the stale one).

### front_nine — pref `frontNineScores`
Trigger: a player's 9th front-nine hole score lands (holes 1–9 all have
strokes). Fire once per match player.
- Title: `Made the turn`
- Body: `Tj out in 39 (+3) at Rustic Canyon`
- `apns-collapse-id: f9-<matchPlayerId>`

### round_final — pref `finalScores`
Trigger: POST /matches/:id/complete (idempotent — only on the first
transition to COMPLETED).
- Title: `Final scores`
- Body: single player `Tj shot 82 (+10) at Rustic Canyon`; multiple
  `Rustic Canyon final: Tj 82, Mike 88` (cap at ~3 names, then `+2 more`).
- `apns-collapse-id: final-<matchId>`

### follow_request — pref `followRequests` (recipient = target user)
Trigger: POST /follows action=request when the target does NOT
auto-accept.
- Title: `Follow request` / Body: `@tj wants to follow you`
- Include `"userId"` of the requester. May set `"aps": { "badge": <pending count> }`.

### follow_accept — pref `followRequests` (recipient = original requester)
Trigger: action=accept, or an auto-accepted request.
- Title: `Request accepted` / Body: `@mike accepted your follow request`

## 6. Sending checklist

1. Resolve audience → filter by pref → load tokens.
2. Group tokens by `environment`, send to the matching APNs host.
3. Delete rows on 410/`BadDeviceToken`; log other failures, never throw
   into the request path — send async after responding to the client
   (e.g. `waitUntil` on Vercel).

## 7. App-side status (already shipped in slice 71)

- `aps-environment` entitlement added; the publish flow syncs the Push
  Notifications capability onto the App ID at the next build.
- Auto-prompts once after the welcome flow; Settings → NOTIFICATIONS has
  enable/`Open iOS Settings` states + the five toggles.
- Token uploads on every signed-in launch (rotation-safe); DELETE on
  sign-out; `environment` is `sandbox` for debug builds, `production`
  for TestFlight/App Store.
- Foreground pushes show a banner and refresh the feeds; taps deep-link
  (cold launch included).
- Until the endpoints above exist, the app fails soft (logs, retries
  next launch) — safe to ship in either order.
