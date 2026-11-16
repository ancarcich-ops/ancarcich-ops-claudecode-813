# Claim-seat eligibility — stop offering every seat to every spectator

Spec for the sticks-golf server. iOS change shipped alongside: the claim card
now says the seats were added by name (`Views/ClaimSeatCard.swift`), but the
real fix is server-side eligibility.

---

## 1. The problem

`GET /matches/:id` returns `canClaimSeat: true` to **any** signed-in caller who
isn't already in the round, whenever at least one player seat has
`userId == nil` (added by name). The app renders one "I'm {name}" pill per
unlinked seat.

So a pure spectator — someone browsing a stranger's or a groupmate's round —
is asked "Played in this round?" with pills claiming *other people's* names.
Beyond the noise, it invites false claims: nothing stops viewer A from
claiming viewer B's seat.

Live example: demo round `cmwi4pa720005o4xqleyw2vf5` (Sand Canyon, by BigPeas)
has `Austin` and `Phil1` as ghost seats. Every signed-in visitor gets
"I'm Austin / I'm Phil1".

## 2. Proposed rule

`canClaimSeat` is `true` only when at least one unlinked seat is a **plausible
claim** for the caller. Two signals, in increasing looseness:

**Phase 1 — name match (ship this).** Normalize both sides (lowercase, trim,
strip non-alphanumerics). A seat matches when any token of
`seat.displayName` equals any token of the caller's display name or username,
or one is a prefix of the other with length ≥ 3 ("Phil" ↔ "Phill1" →
prefix of "phil"). Nicknames are out of scope; exact-ish matching only.

**Phase 2 — shared circle (behind a flag, evaluate after phase 1 ships).**
Also offer seats when the caller shares a group with the round's creator.
This is the "I played in Ben's round but got typed in as 'Steve-o'" case.
Risk: re-introduces noise for large groups; that's why it's a flag.

### Payload

Keep the boolean for back-compat and add the per-seat offer:

```jsonc
{
  "canClaimSeat": true,             // = claimableSeatIds is non-empty
  "claimableSeatIds": ["mp_12"]     // subset of players[].id the caller may claim
}
```

Old clients ignore `claimableSeatIds` and show all pills whenever
`canClaimSeat` is true — so set the boolean from the new rule. A name-matched
viewer on an old build still sees their pill (plus the others — acceptable);
a spectator on an old build sees nothing, which is the point.

The iOS client will move to rendering pills from `claimableSeatIds` when the
key exists (small follow-up in `ClaimSeatCard.swift`; falls back to
`userId == nil` filtering when absent, e.g. old cached payloads).

## 3. Rules the claim endpoint should keep or gain

- `POST /matches/:id/claim-seat` (whatever its real path is) must re-check
  eligibility server-side against the same rule — the GET is advice, the
  endpoint is the gate.
- One seat per round per caller (already enforced, keep).
- A claim by an account that already has a seat in the round → 409, unchanged.
- **Un-claim window:** allow the round creator to unlink a mistaken claim for
  24h after it happens. Name matching will occasionally match the wrong
  "Austin"; the creator is the cheapest correction path.
- Log claims (who claimed which seat) — the false-claim rate tells us whether
  phase 2 is safe.

## 4. Non-goals

- No email/phone verification loop — the claim is an honor-system feature for
  friendly rounds; stats aren't money.
- No client-side name matching — the app renders what the server offers; a
  rule change must reach old builds.
