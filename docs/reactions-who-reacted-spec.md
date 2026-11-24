# Who-reacted: reaction identities endpoint

The mobile app's reaction rows (round page + feed cards, slice 93) show tallies only —
`{ emoji, count, mine }`. There is no way to see WHO reacted. This spec adds one
read-only endpoint so the iOS round page can open a "who reacted" sheet.

Agreed design: identities live ONLY here, behind a tap. List/detail payloads keep
tallies-only so they never grow with reactor lists. Feed cards are dropping their
reaction rows entirely (product call, Nov 24) — the sheet lives on the round page.

## Endpoint

```
GET /api/mobile/matches/:id/reactions?target=<targetKey>
Authorization: Bearer <token>
```

`target` is the same key the detail payload already uses in its `reactions` map:

- `round` — the round-level row
- `hole:<matchPlayerId>:<hole>` — one scored hole's row (e.g. `hole:abc123:7`)

## Response

```json
{
  "ok": true,
  "target": "round",
  "tallies": [
    {
      "emoji": "🔥",
      "count": 3,
      "mine": true,
      "users": [
        {
          "id": "usr_123",
          "handle": "T-Bone",
          "displayName": "T-Bone",
          "avatarUrl": "https://…/avatar.jpg",
          "at": "2026-11-24T20:14:00.000Z"
        }
      ]
    }
  ]
}
```

Rules:

- `tallies` covers every emoji with count > 0 on that target, same numbers as the
  detail payload's tally for the same target (they must agree).
- `users` is ALL reactors of that emoji, newest reaction first (`at` descending).
- `handle`, `avatarUrl`, `at` are optional — omit rather than null-padding; the
  app tolerates missing fields. `id` and `displayName` are required.
- `mine` matches the caller's own reaction, same meaning as everywhere else.

## Errors

Standard error shape `{ "error": string }`:

- `401` — no/expired token (app signs out).
- `404` — unknown match id, or unknown target key (bad player/hole pair). Message
  shown verbatim is fine.
- `403` — same access rule as `GET /matches/:id`: anyone who can see the round can
  see who reacted; spectators included. A hidden/private round keeps its existing
  visibility rules — no change.

## Client behavior (already shipped in iOS 2.1.1)

- Long-press a used chip (count > 0) on the round page's reaction row or a
  highlights row → sheet titled "Reacted", opened emoji's group pinned first.
- Tap still toggles the caller's own reaction; only long-press opens the sheet.
- The sheet shows loading, then groups per emoji with avatars + names; a failure
  shows the server message with a retry. Unused chips (count 0) do nothing on
  long-press.
- The account's "Show reactions" display pref (slice 96) hides the rows entirely,
  so the sheet is unreachable while reactions are hidden — no extra check needed.

## Not in scope

- Reaction timestamps in the sheet beyond ordering (no relative-time labels yet).
- Push payload changes: reaction pushes keep saying "someone reacted" — identity
  is one tap away on the round page once the sheet lands.
- Web parity: the web app can adopt the endpoint later; not blocking.
