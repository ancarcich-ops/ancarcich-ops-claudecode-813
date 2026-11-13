# Reactions v2 — new emoji set + game-scoped 🐍

Spec for the sticks-golf server. The iOS app needs **no changes** for the emoji
swap: it renders the server's `reactionEmoji` array in order and posts back
whatever emoji it rendered (see `Models/Reactions.swift`, `ReactionRow.swift`).
The only iOS-side change made alongside this spec is the *fallback* set used
when `reactionEmoji` is missing from the payload.

---

## 1. Flat v2 set (ship this first)

Render order, left to right — hot/repeat reactions first, per picker ergonomics:

| # | Emoji | Meaning | Replaces |
|---|-------|---------|----------|
| 1 | ❤️    | love it | —        |
| 2 | 🔥    | hot play / on a run | — |
| 3 | 😂    | hilarious / banter | — |
| 4 | 👏    | respect / well played | — |
| 5 | 💀    | blow-up hole, brutal beat | 😬 (ambiguous) |
| 6 | 🍺    | beers on you / post-round banter | new |

Optional 7th: 💰 — "that cost you money" (wagers, skins). Include only if the
picker row is measured at 7 wide on a 41mm watch-class width and a small phone
(320pt class); otherwise hold for v3.

Skipped deliberately: 🐥 🦅 ⛳ shot celebrations — the highlights strip already
celebrates specific shots; card reactions should be about the story.

### Server changes

1. `reactionEmoji` (detail payload) and the card-payload equivalent become
   `["❤️","🔥","😂","👏","💀","🍺"]`.
2. Reaction write validation: accept the new set. **Keep accepting `😬` on
   writes** for one release (old clients still installed) or map `😬 → 💀` on
   read for older clients.
3. Existing `😬` rows: either keep rendering them for old client versions and
   let them age out, or run a one-time migration `😬 → 💀` (counts merge).
   Migration preferred — clean read path afterwards.

### Acceptance

- GET a match detail as the demo account returns the new list in order.
- POST `🍺` to the Pebble Beach live round round-trips; count increments.
- An old `😬` reaction still renders on a client pinned to the old list
  (until migrated).

---

## 2. Game-scoped reactions (the delighter)

Goal: a reaction that only exists where it makes sense, so the picker itself
signals that the app understands the game being played.

### v2.1: 🐍 for Snake rounds only

Snake = the group's snake token passes to whoever three-putts; last one
holding it at the end owes the pot. A 🐍 reaction on a Snake round means
"you've got the snake now" — the joke every Snake group already makes.

Rules:

1. `reactionEmoji` stays flat **plus** scoped entries appended at the end:
   `base: ["❤️","🔥","😂","👏","💀","🍺"]`, scoped: `["🐍"]` when the match
   includes a Snake side game, else not present.
2. Server computes scoping from the match's game config — no client signal
   needed. If more than one scoped game applies later, order scoped emoji
   after base, server-defined.
3. Write validation: reject 🐍 on matches without Snake (409 with
   `{"error":"reaction_not_valid_for_match"}`); old clients that cached the
   list degrade gracefully (the POST fails, optimistic count reverts — the
   iOS pending-reaction path already reverts on failure).
4. Card payloads (feed) use the same scoped list per match, so the feed picker
   row differs per card. This is fine: the row is laid out per-card already.

### Later candidates (same mechanism, don't build yet)

- 💰 on matches with a wager/skins game ("skins paid")
- 🎩 on Nassau (the press/dinner-jacket banter) — only if a group actually
  asks; scope creep is the risk. Ship 🐍, watch usage, then decide.

### iOS behavior (already compatible, verified against current code)

- Picker row renders `reactionEmoji` in server order; scoped emoji appears as
  the last bubble automatically.
- Reaction counts/summary rows render whatever the server returns — unknown
  emoji need no client registration.
- `Reaction.fallbackEmojiSet` (used only if the server omits `reactionEmoji`)
  updated to `["❤️","🔥","😂","👏","💀","🍺"]` in this repo alongside this spec.

### Acceptance

- Sunken Gardens seeded round (Snake present): detail + card payloads include
  🐍 after the base five/six.
- Pebble Beach (no Snake): no 🐍.
- POST 🐍 to Pebble Beach → 409; POST 🐍 to Sunken Gardens → round-trips.

---

## 3. Verification plan (post-deploy)

1. Fresh token: `POST /api/mobile/auth/login {"identifier":"user123","password":"user1234"}`.
2. `GET` both live rounds' detail; diff `reactionEmoji`.
3. POST each new emoji once on the demo account, confirm round-trip and
   ordering, then delete the probe reactions so the demo feed stays clean.
4. In the iOS simulator: open the feed, confirm picker row shows 💀/🍺 (and
   🐍 only on the Snake card), tap one, confirm optimistic bump + server echo.
