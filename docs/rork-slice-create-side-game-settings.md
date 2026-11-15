# Create-step side-game settings — server asks

The iOS create flow now shows each picked game's settings inline (Skins carry / no carry, Nassau stake + auto-press, Snake, Wolf, Sixes, Targets). Findings from live probes on 2026-11-14:

## What the app does today
- Schema: reads `sideGames` from `GET /round-options` if present; otherwise it uses a bundled copy of the per-match picker schema (`GET /matches/:id/side-games` → `games[].settings`).
- Saving: `POST /matches` **ignores** a `sideGameConfigs` body (sent `{SKINS:{pushRule:"NO_CARRY"}}` → stored config null). So the app creates the round, then posts `POST /matches/:id/side-game-config` once per game whose settings changed.

## Asks
1. **Serve the schema pre-match** on `GET /round-options`:
   ```json
   "sideGames": [
     { "kind": "SKINS", "settingsComplete": true,
       "settings": [ { "key": "pushRule", "label": "On tied holes", "type": "choice",
                      "default": "CARRYOVER", "choices": [ ... ] } ] }
   ]
   ```
   Same shape as `games[].settings` / `settingsComplete` on the per-match picker. The app picks it up with no build.
2. **(Optional) Accept `sideGameConfigs` on `POST /matches`**: `{ [kind]: config }`, validated like side-game-config. That would make creation a single request. The app keeps posting configs after creation until this ships.

## Behaviour to know about (not a bug, but undocumented)
`POST /matches/:id/side-game-config` **replaces** the stored config. It does not merge. Posting `{autoPressThreshold: 4}` to a Nassau stored as `{stake:5, autoPress:true, autoPressThreshold:3}` left `{}`. The response still said `dropped: []`, even though the stake and auto-press were discarded. The app now always sends the full config for a game. If merge was the intent, that's a server bug. If replace is the intent, please say so in the endpoint docs, and consider listing discarded-by-dependency keys in `dropped`.

---

## Resolved 2026-11-15 (server shipped all asks; verified live by `scripts/side-game-config-probe.py`, ALL PASS)

- `GET /round-options` serves `sideGames` (same shape as the per-match picker, plus `requires18` / `requires4Players` stated, not applied). The app's bundled schema copy is deleted; blockers read the served flags.
- Stableford and BBB now report `settingsComplete: false` (they carry points tables). The create step says they play the standard table and can be changed from the round, since the app has native editors for both.
- `POST /matches` accepts `sideGameConfigs` keyed by kind. The app now sends picked settings inline on create; edit mode still POSTs per game after PATCH. An unparseable config leaves the game on and unconfigured; kinds that aren't enabled are ignored.
- side-game-config REPLACE is intended and documented. `dropped` now names an unknown field, or a value that asked for something and got nothing. It stays silent for a value meaning "unset", and for a dependent field whose switch is sent off in the same payload.
- Recap: pars indexed by hole number (four call sites, including highlights); front/back split by hole number (front = holes 1–9). `scripts/recap-tenth-probe.py` asserts both — ALL PASS.

---

## Addendum — team rules take options too (2026-11-15, later)

Vegas is unblocked without a new endpoint: `GET /round-options` → `teamRules[]` now carries `options` in the side-game settings shape (VEGAS: stake / birdieFlip / doubleHoles; every other rule: stake). `hasOptions` deliberately stays VEGAS-only so older builds keep working; the app filters nothing — all seven rules are selectable, and each picked rule renders its options inline. The dashed "coming soon" Vegas card is gone.

Wire shape, verified live by `scripts/side-game-config-probe.py` (ALL PASS):
- POST /matches (and PATCH with the full body) takes `teamRules` FLAT: `{"rule":"VEGAS","stake":0.25,"birdieFlip":true,"doubleHoles":"EXPONENTIAL"}`.
- Stored (TEAM_VS_TEAM game config, `rules[]`): Vegas's fields nested — `{"rule":"VEGAS","stake":0.25,"vegas":{"birdieFlip":true,"doubleHoles":"EXPONENTIAL"}}`; `{"rule":"BEST_BALL","stake":1}` stays flat.
- Legacy bare-string entries still accepted. A bare-string entry REPLACES the stored rule object, so it silently drops a stake — the app posts objects whenever it has stored values or touched drafts, bare ids only when it knows nothing.
- App: options ride the same draft → stored → served-default layering as side games; null-default fields (stake) are omitted, never invented as 0.
