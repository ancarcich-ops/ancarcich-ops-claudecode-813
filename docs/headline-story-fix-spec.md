# Headline story: fix "X won by N" copy and player choice

From the Quivira round (Nov 20): the recap's `headline.story` said
**"Parian won by 8 — they picked up 6 over holes 15 through 2."** while the feed
card's WINNER chip said **T-Bone +15**. Both were true but the sentence reads like
Parian won the round. Two fixes in the server's headline-story generator:

## 1. Copy — say who lost

The story is seat-relative (it lives on "YOUR ROUND", under the seat's own score),
but "X won by N" omits the seat. Always name both sides:

- `"Parian beat you by 8 — they picked up 6 over holes 15 through 2."`
- When the seat is ahead: `"You beat Parian by 8 — you picked up 6 over holes …"`
- Never "X won" / "Y lost" alone. The margin text under the WHERE-THE-MATCH-WAS-WON
  chips ("Parian finished 8 ahead of you across 18 holes.") is already unambiguous —
  match that voice.

## 2. Player choice — don't lead with a non-winner

For Seuss.md's seat the generator picked Parian (8 ahead of you, biggest run: 6
strokes over holes 15→2) when T-Bone was BOTH the round winner (+15 vs Parian's
+18) AND ahead of the seat by more (11). At minimum, when the round winner also
beat the seat, the story should feature the winner. Proposed order:

1. If the seat won the round: their own story (existing behavior).
2. Else the round winner, if they finished ahead of the seat — "T-Bone won the
   round by 11 over you; their run came at holes 12 through 17."
3. Else (winner finished behind the seat — e.g. net scoring surprises): the player
   who beat the seat by the most, with the fix-1 copy.

The "biggest single run against the seat" angle (what picked Parian) can stay as
the stretch detail, not the subject.
