# Slice 98 — the countdown tick rate

> **Corrected after the fact.** The first version of this document
> claimed the per-second countdown was an accessibility bug and that a
> VoiceOver user "cannot work" the screen. That was my inference, not a
> measurement, and the evidence since does not support it. The
> correction is below, before the parts that still stand — a brief that
> gets read top-down shouldn't hand somebody the wrong reason first.

## What I claimed, and what turned out to be true

**The claim.** A walkthrough couldn't open the Individual-and-Team round
because taps and snapshots timed out. I said the cause was the live
countdown re-rendering once a second, that this invalidated the
accessibility tree, and that a screen-reader user would hit the same
wall — focus dropped mid-sentence, a live region re-announcing the row
on every tick.

**What the evidence says.** Two things since, both from the simulator:

1. The timeouts kept happening **on a static screen**, after the looping
   animations were changed to settle. An app relaunch cleared it.
2. The animations in question change **opacity and position, not
   labels** — which a screen reader generally doesn't care about.

So the stall looks like instance flakiness in the tooling, not animation
churn, and the mechanism I described for VoiceOver — text changing
underneath a reader — isn't what these loops do.

I conflated two different problems that have different causes and
different fixes:

| | caused by | who it affects | status |
|---|---|---|---|
| A tool waiting for the app to go quiet | motion | automation | **not the cause here** |
| A reader being interrupted | changing *text* | people | **not demonstrated** |

**Nobody has actually run VoiceOver on this.** That question is still
open, and this document should not be read as having answered it.

## What still stands

The tick-rate change was worth making, on its own merits rather than the
ones I gave:

**Tick at the granularity you display, not faster.** The pill shows a
coarse figure — "in 3h 20m", "tomorrow", "in 12m". If the smallest
displayed unit is a minute, a 1 Hz timer does 59 pointless re-renders a
minute, none of them changing a pixel. That's battery and wakeups for
nothing.

**Endless motion is a real problem for motion sensitivity**, regardless
of what any tool does with it.

Neither reason depends on the accessibility question, which is why the
change was still right.

The web has had the tick rate right since it shipped
(`src/components/match-card/StatusPill.tsx`):

```ts
const id = setInterval(() => setNow(Date.now()), 60_000);
```

If the display drops to seconds inside the last minute, switch the
interval then and only then — not for the three hours before it.

Also still worth doing, as plain hygiene rather than as a fix for
anything:

1. Put the timer in the smallest component that shows the text, so a
   tick re-renders a `<Text>` and not the round card or the list row.
2. Give the pill a **stable** accessibility label carrying the tee time
   rather than the ticking figure — `accessibilityLabel="Tee time 4:25
   PM"`. The exact time is more useful to a screen-reader user than a
   countdown that's stale the moment it's spoken.
3. Don't put it in an `accessibilityLiveRegion`. Nothing here is urgent
   enough to interrupt someone.

## Status

**Done and behaving.** The pulse-then-hold change shipped; the ticker
scrolls one pass and rests, confirmed by screenshots three minutes apart
being identical.

**Still open:** a VoiceOver ear-check on the feed. That's the only thing
that answers the question I got ahead of myself on. It needs hardware
and a person, not a simulator.

## The label this was blocking

The round header's **"INDIVIDUAL AND TEAM"**. The server side is
verified end to end against a real database — a round stored as
`format: INDIVIDUAL` with a `TEAM_VS_TEAM` side game serves
`uiFormat: "BOTH"`, and a plain one serves `"INDIVIDUAL"`:

```
INDIVIDUAL + TEAM_VS_TEAM side game   sideGames loaded: 1  -> BOTH
INDIVIDUAL, no side game              sideGames loaded: 0  -> INDIVIDUAL
```

So `uiFormat` arriving at the app is right. What's still unconfirmed is
what the app *draws* for the `BOTH` branch — a one-second check on a
device.

Reminder on the contract, since it has caused this exact confusion
before: **`format` alone cannot tell you a round is Individual-and-Team.**
"BOTH" is never stored. Read `uiFormat` from the payload; don't
re-derive the format from the `format` column.
