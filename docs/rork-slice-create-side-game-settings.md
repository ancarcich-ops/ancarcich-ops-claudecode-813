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
