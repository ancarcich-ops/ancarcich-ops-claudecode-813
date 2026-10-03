# Turn alert with score: deploy checklist (sticks-golf Vercel repo)

**Goal:** the "At the turn" push should show the player's front-nine score.

**Today (live):**
> **At the turn**
> Tj made the turn

**After this change:**
> **At the turn**
> Tj made the turn in 39 (+3) at Rustic Canyon

Even par shows `(E)`, under par shows `(-2)`. No iOS release is needed. The
app shows whatever title and body the server sends.

---

## 1. Find the current sender

In the `sticks-golf` repo, search for the live wording:

```
grep -rn "made the turn" .
grep -rn "At the turn" .
```

The match is usually in the `POST /api/mobile/matches/:id/score` handler, or
in a push helper it calls. Note which case applies:

- **A.** It calls `notifyFrontNine(...)` from our push package (`lib/push/pushEvents.js` or similar). Go to step 2A.
- **B.** It builds its own APNs payload inline. Go to step 2B.

## 2A. The repo uses our push package

1. Replace the repo's copy of `pushEvents.js` with
   `backend/push/lib/pushEvents.js` from the Sticks project. Only
   `notifyFrontNine` changed. Every other sender is unchanged.
2. Update the call site in the score route so the score is passed in:

```js
if (holes1to9AllScored) {
  waitUntil(notifyFrontNine({
    matchId, matchPlayerId, actorUserId, playerName, courseName,
    roundHoles,               // 9 or 18. 9-hole rounds are skipped.
    frontStrokes, frontPars,  // arrays for holes 1–9, in hole-number order
    // OR pass totals instead:
    // frontTotal: 39, frontToPar: 3,
  }));
}
```

If neither the totals nor the arrays are passed, the sender **skips the push**
and logs `[push] front_nine skipped … no score passed`. A turn alert with no
score is never sent.

## 2B. The repo has its own inline sender

Keep its existing code and change two things:

1. **Body:**
   ```js
   const toPar = frontTotal - frontPar;
   const toParText = toPar === 0 ? "E" : toPar > 0 ? `+${toPar}` : `${toPar}`;
   body: `${playerName} made the turn in ${frontTotal} (${toParText}) at ${courseName}`
   ```
2. **9-hole guard:** don't send the turn alert when the round is 9 holes. On a
   9-hole round, hole 9 is the finish, and "Final scores" already covers it.

Leave the title as `At the turn`. Leave the payload fields `type: "front_nine"`
and `matchId` as they are, because the app uses them to open the round when the
push is tapped.

## 3. Compute the front nine correctly

- Use holes **1–9 by hole number**. Don't use the first 9 holes played: a
  `scoreOrder` / shotgun start can begin on hole 10, and that's still the back
  nine.
- Use **gross** strokes (raw strokes, before handicap). This matches "Final scores".
- Use the par of the tees being played for each hole.
- Fire only when all of holes 1–9 have strokes, once per player. Our package
  enforces this with `push_events_sent` key `f9-<matchPlayerId>`.

## 4. Deploy and verify

1. Deploy to Vercel.
2. Run a test round with two accounts:
   - **Account A** plays the round and posts holes 1–9.
   - **Account B** is signed in on a *different* phone, follows A (or shares
     a group with A), and is **not** seated in the round. Players in the round
     never get its alerts.
3. When A posts hole 9, B should get:
   `At the turn` / `A made the turn in NN (±N) at <Course>`.
4. Check the Vercel function logs for the score route:
   - `[push] front_nine sent=1 …` means it was delivered.
   - `[push] front_nine skipped … no score passed` means the score isn't
     being passed in (go back to step 2).
   - No `[push]` line at all means the call site isn't running. Check the
     `holes1to9AllScored` condition.
5. Run a 9-hole round. B should get **only** "Final scores", with no turn alert.

---

## Related: follow-request pushes not arriving

A follow request recently produced no push. While you're in the repo:

- [ ] `POST /api/mobile/follows` with `action=request` calls
      `notifyFollowRequest(...)` when the target does **not** auto-accept.
- [ ] `action=accept`, and any auto-accepted request, calls `notifyFollowAccept(...)`.
- [ ] Vercel env has `APNS_KEY`, `APNS_KEY_ID` and `APNS_TEAM_ID` set for Production.
- [ ] After a test request, the logs show `[push] follow_request sent=1`.
      `sent=0` means the target has no registered device token. They should
      open the app signed in, with notifications allowed.
