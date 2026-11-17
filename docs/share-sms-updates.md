# Share link: "Text me updates" never sends anything you can see

Status: spec. Web/server repo only; the app is not involved (the SMS signup lives on the public `/r/<token>` page).

## What happened (2026-11-17, device)

- Seuss.md, Torrey Pines, thru 2. Signed up on the share page and got "You're subscribed. Updates will arrive as the round progresses."
- No text arrived.

## Probably working as designed — but that's the problem

The page's own copy says texts go out **when the player makes the turn and when the round wraps up**. Thru 2, neither has happened, so no text is expected yet. To the subscriber this is indistinguishable from "broken": they just typed their number and got silence.

I can't see the server or the SMS provider from the app side, so I can't confirm whether sends work at all. Check these in order.

## 1. Send a confirmation text immediately on subscribe (required anyway)

Carrier/CTIA rules expect an opt-in confirmation message the moment someone subscribes. It also proves the pipe works.

> Sticks: You'll get updates on Seuss.md's round at Torrey Pines — at the turn and when they finish. Msg freq varies (2–3/round). Msg & data rates may apply. Reply HELP for help, STOP to opt out.

- Send synchronously in the subscribe handler. If the provider returns an error, **don't** show "You're subscribed" — show "Couldn't text that number" with the provider's reason logged server-side.
- Dedupe: re-subscribing the same number to the same share doesn't send a second confirmation.

## 2. Verify the provider can actually deliver

- Log the provider's message SID and status for every send. Check the provider console for the test number: `delivered`, `undelivered`, or `failed`, and the error code.
- **US 10DLC registration:** unregistered long-code traffic to US numbers is blocked by carriers (Twilio error 30034 and similar). If the sending number isn't attached to an approved A2P 10DLC campaign (or a verified toll-free number), every send silently fails at the carrier. This is the most likely cause if sends are attempted but nothing arrives.
- Trial accounts can only text verified numbers.

## 3. Confirm the trigger points fire

- "Made the turn": fires once when the shared player's score for the 9th hole of the round (relative to `startingHole`) is saved. Not on hole 9 literally — a shotgun start on 10 makes the turn after 18.
- "Round wrapped up": fires once when the match goes `COMPLETED`.
- Each subscriber gets each event at most once. Stopped/revoked share → no further sends.
- Add a server log line per trigger (`sms turn fired for share X, N subscribers`) so it's checkable without a phone.

## Done when

- [ ] Subscribing sends the confirmation text within seconds; the test phone receives it.
- [ ] Provider console shows `delivered` for it.
- [ ] Playing through hole 9 sends the turn text; finishing sends the final text.
- [ ] A bad number shows an inline error instead of "You're subscribed".
- [ ] STOP replies unsubscribe (provider-level opt-out is honored and the subscriber is marked inactive).
