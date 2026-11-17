# Flyover: don't reveal or fly until the view is actually loaded

Status: implemented in web PR #678 (not yet deployed as of 2026-11-17; the live flyover chunk is still #673's `9351-a23e82928fbad6c1.js`).

Deviations from this spec, agreed:
- The starvation stat is `"Tiles Loading"` (loaders.gl 4.4.3), not `"Tiles In Loading"`. Confirmed in the live bundle's loaders.gl constants.
- The camera-snap pre-fetch (section 3) was not built: HolePreview3D also runs in HoleStudyMode/OnCourseMode on the web, where the snap would be visible. Revisit (with a second invisible viewport) only if hole 11 is still soft at the green after the gate.
- Verified off-device: no tiles → `stalled`, camera never moves. NOT verified: the refined path and the 5 s cap (no tiles load without the key). The next device recording's `view refined in NNNms` / `reveal cap hit at 5000ms` lines settle it.

Original spec: Web repo only. **No app change is needed**, because the app already keeps its "LOADING 3D VIEW" overlay up until the embed posts `ready`. If `ready` is posted later, the reveal happens later.

## What the device recording shows (2026-11-17, holes 10 → 11)

- The app side is fine. The dying page's tile aborts were ignored (`Ignoring embed status from the previous page`), and there was no 2D fallback flash.
- `ready` came only about 95–150 ms after the page finished loading, on both holes. That is much too early for the tiles to have refined.
- Hole 10 was revealed blurry and sharpened over about 1 s while the camera was already moving.
- Hole 11 (par 3, 187 yds) was revealed as coarse, blurry rooftops and **stayed blurry for the remaining ~8 s**, with the camera barely moving. From the user's side, it "goes before it loads".

## Cause, in the live #673 code (chunk `9351-a23e82928fbad6c1.js`)

```js
onTileLoad: () => { P.current += 1; j(e => e || true); ... }   // j = setLoaded → w
useEffect(() => { w && R("ready") }, [w, R])                    // ready on the FIRST tile
...
setTimeout(() => {
  if (!w) { rAF(fly); return }                                  // 6 s with no tiles → fly anyway
  poll: if (P.current >= 40 || elapsed >= 2500) rAF(fly)         // 40 tiles of ANY detail
}, w ? 400 : 6000)
```

1. **`ready` fires on the first tile.** The first tiles are always the coarsest LODs (root and near-root), so the app reveals a smeared scene.
2. **The 40-tile pre-roll counts tiles, not detail.** Those 40 tiles are mostly coarse ancestors on the way down the tree. On a short hole, or with the HTTP cache warm, 40 arrives quickly while the leaves you actually see are still pending. The 2.5 s cap then starts the flight regardless.
3. **The flight starts with zero tiles after 6 s** (the `!w` branch).
4. **Tiles keep refining while the camera moves.** Every frame changes the viewport, so loaders.gl re-selects tiles and drops queued requests that are now off-screen. That fits hole 11 never sharpening. This is inferred, not proven: it could also just be Google's photogrammetry over those houses. The gate below fixes the first case and makes the second one obvious.

## The fix: one "view is loaded" gate drives both the reveal and the flight

### 1. Know when the current view is refined

Tile3DLayer gives you the loaders.gl `Tileset3D`:

```ts
const tilesetRef = useRef<Tileset3D | null>(null)
<Tile3DLayer
  onTilesetLoad={(ts) => { tilesetRef.current = ts }}
  onTileLoad={() => { P.current += 1 }}
  ...
/>
```

Tileset3D reports when nothing is pending for the current view. Check the exact API on your loaders.gl version; in 3.x/4.x it's `tileset.isLoaded()`, which is true when there are no pending or requested tiles for the last traversal. As a fallback, `tileset.stats` exposes the request and pending counts.

```ts
function viewIsRefined() {
  const ts = tilesetRef.current
  return !!ts && P.current > 0 && ts.isLoaded()
}
```

Require it to hold for **2 consecutive checks about 150 ms apart**. `isLoaded()` can be briefly true between traversal passes.

### 2. Gate `ready` and the flight on it, at the starting pose

- Keep the camera parked on the opening pose (tee, pitch 65, zoom 17.4) until the gate passes.
- Poll every 100 ms:
  - When `viewIsRefined()` passes (stable), post **`ready`**, wait **250 ms** (the app fades its overlay out), then start the rAF flight.
  - **Cap: 5 s from the first tile.** If it hasn't refined by then, post `ready` and fly anyway, so a slow network never leaves a spinner up forever.
- Delete the `w ? 400 : 6000` kickoff and the `!w → fly immediately` branch.
- Delete the 40-tile threshold. `P.current` only feeds the stall check now.
- If **no tile has loaded by 6 s**, post `stalled` (as today) and **do not fly**. Flying over an empty scene is pointless; the app's 30 s watchdog and fallback handle the dead case.

### 3. Pre-warm the green so the flight doesn't outrun refinement

The tee view is now sharp, but the flight still arrives at tiles nobody has requested. Do both of the following; they're cheap:

- **Pre-fetch along the path.** Before posting `ready`, briefly select tiles for the mid-point and green poses. Either render one frame at each pose under the overlay and then snap back to the tee (the overlay is still up, so nothing is visible), or, if you prefer not to touch the visible camera, give Tile3DLayer a second, invisible viewport via a `views` array. The snap approach is simpler. Count it toward the same 5 s cap.
- **Ease off when starved.** During the flight, if pending requests exceed a threshold (for example `tileset.stats.get('Tiles In Loading').count > 12`, or whatever name your version exposes), advance the flight clock at 0.35× until it drops. The camera slows for a beat instead of flying into mush. Keep it subtle; never fully stop.

### 4. Keep the existing pieces

- pagehide suppression and the AbortError ignore from #673 stay as they are.
- `webgl-ok` / `webgl-unavailable` / `stalled` / `error` semantics are unchanged.

## Status contract (unchanged names, new timing)

- `ready`: the opening view is refined, or the 5 s cap was hit. The app reveals on this.
- `stalled`: no tiles by 6 s. Soft; the app keeps waiting until its 30 s watchdog.
- `error`: hard failure. The app shows the 2D fallback.

## Done when

- [ ] On device, a hole switch shows the spinner a little longer (typically 0.5–2 s) and then reveals an already-sharp tee view. No visible blur-to-sharp pop on the reveal.
- [ ] The flight never starts before `ready`.
- [ ] With no tiles (key or billing broken), it posts `stalled` at 6 s and the camera does not move.
- [ ] Hole 11 at Torrey Pines (the par 3 in the recording) is sharp at the green when the flight lands. If it's still soft after landing and sitting idle for 3 s, that's Google's data for that spot, not us. Note it and move on.
- [ ] Add a console log line for each gate outcome (`refined in 1240ms` / `cap hit at 5000ms`). The app already captures embed console output, so the next recording tells us which path ran.
