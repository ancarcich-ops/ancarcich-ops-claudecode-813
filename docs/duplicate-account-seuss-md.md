# Case-colliding usernames — "Seuss.md" vs "seuss.md"

Spec for the sticks-golf server. Found 2026-11-16.

## Evidence

`GET /users/search?q=seuss` returns two separate accounts:

- `cmpqojorp0000wo1oncg3d8wb` — **Seuss.md** (capital S). Has the avatar; the
  seat in Torrey Pines (`cmwj0iqck0001mv1aa2it9cub`) links to it. This is the
  real account with 18+ rounds.
- `cmrwezt5f0000zkwd0nq4gxj6` — **seuss.md** (lowercase). 0 rounds, no avatar.

`GET /users/Seuss.md/stats` and `GET /users/seuss.md/stats` BOTH return
`targetUserId: cmrwezt5f…` (the empty one). The lookup is case-insensitive
but the uniqueness constraint is case-sensitive, so the real account's
profile is unreachable by username.

`GET /users/<id>/stats` → 404 "Player not found." (no id lookup exists).

## Fixes, in order

1. **Data:** merge or remove the empty `seuss.md` (`cmrwezt5f…`). Check it
   owns no seats, follows, group memberships or sessions first; if it does,
   re-point them to `cmpqojorp…` before deleting.
2. **Find the rest:**
   `SELECT lower(username), count(*) FROM "User" GROUP BY 1 HAVING count(*) > 1;`
   Every row is an account whose profile is hijacked the same way.
3. **Prevent:** make usernames unique case-insensitively (a unique index on
   `lower(username)`, or `citext`), and reject sign-ups / renames that collide.
4. **Resolve by id:** let `GET /users/:idOrUsername/stats` accept a user id
   (ids are cuid-shaped, usernames can't collide with that format). Exact-case
   username match should win over case-insensitive.
5. **Creator payload:** include `createdBy: { id, username, displayName }` on
   `GET /matches/:id` (`match.creator` is currently null).

## What the app does now (shipped)

- Profile links from round seats and "Created by" carry the seat's `userId`.
- Linked to the signed-in user's own id → straight to their Stats tab, no
  username lookup.
- The server resolves the name to a different account than the link meant →
  the profile shows "This player's profile can't be opened right now —
  another account has a near-identical username." instead of a stranger's
  empty stats.
- Once (4) ships, the app can request by id directly; the username lookup
  becomes the fallback.

## Shipped & verified (2026-11-16)

- Server #667 deployed: id lookup live, `Seuss.md` resolves to the real
  account, `createdBy.id` present. All three probed live and confirmed.
- App: decodes `createdBy.id` (`createdById`); creator link uses it,
  falling back to the exact-username seat. Profile loads fetch by
  userId first, username on 404 (pre-#667 servers); mismatch guard kept.
- User tested on device: own-creator link routes to Stats tab; other
  players' profiles load by id. Working.
- The "near-identical username" error is now effectively unreachable;
  left in as a guard for servers without id lookup.
