# Flyover: land the getCursor fix + smooth the tee→green camera

Two changes, same component, one PR. No app update needed. The iOS app's
client-side patch turns itself off once fix 1 is live.

Find the component: search the web repo for `"google-3d-tiles"` or
`onRequest2D`. It's the 3D hole flyover with props
`{ hole, height, onRequest2D, hideHud, aim, onAim, from }`. The waypoint builder
(the function returning 4 view states with `transitionDuration` 0 / 2400 / 3600 / 2400)
lives in the same module.

---

## 1. Get the #666 fix into the live build

The live site still serves the buggy code. Chunk `9351-97a599b41781dc98.js` kept
the **same hash** across the #667 deploy, which means the merged source change
never reached the file that gets built.

Check, in order:
1. `git log --oneline -5 -- <flyover component file>` on the branch Vercel
   builds (Vercel → Project → Settings → Git → Production Branch). Is 4df0aac there?
2. `grep -rn "getCursor" src/ app/ components/`. You should find exactly one
   hit, and it must look like this:

   ```tsx
   <DeckGL
     ...
     {...(onAim ? { getCursor: () => "crosshair" } : {})}
   />
   ```

   Not `getCursor={onAim ? () => "crosshair" : undefined}`. An explicit
   `undefined` overwrites deck.gl's default and crashes the render loop.
   If #666 edited a different copy of the component (a duplicate or an older
   file), fix this one.
3. After deploying, confirm: the live chunk containing `google-3d-tiles` has a
   **new hash** and no longer contains `"crosshair":void 0`.

---

## 2. Smooth the camera

### Why it stutters now
- The flight is **3 separate transitions**, started by `setTimeout` at
  2400 ms / 6000 ms. Each one is linear (constant speed, no easing), so speed
  changes abruptly at every handoff.
- Timers and transitions drift apart. If a leg runs late, the next timer
  interrupts it mid-move. That's the visible "lurch".
- Zoom yo-yos 18.6 → 18.2 → 18.4 and pitch 70 → 68 → 64. These are small
  reversals your eye reads as wobble.

### The fix: one continuous, eased flight driven by requestAnimationFrame

Replace the `setTimeout` chain with one rAF loop that computes the camera
from a single eased progress value. Keep the existing waypoints. Interpolate
through them smoothly instead of hopping between them.

```ts
const easeInOutCubic = (t: number) =>
  t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;

// Catmull-Rom through the waypoints. p in [0,1] spans the whole path.
function sampleCamera(wps: Waypoint[], p: number) {
  const segs = wps.length - 1;
  const x = Math.min(p * segs, segs - 1e-6);
  const i = Math.floor(x), t = x - i;
  const p0 = wps[Math.max(i - 1, 0)], p1 = wps[i],
        p2 = wps[i + 1], p3 = wps[Math.min(i + 2, segs)];
  const cr = (a: number, b: number, c: number, d: number) =>
    0.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t * t +
           (-a + 3 * b - 3 * c + d) * t * t * t);
  const k = (key: keyof Waypoint) =>
    cr(p0[key] as number, p1[key] as number, p2[key] as number, p3[key] as number);
  return {
    longitude: k("longitude"), latitude: k("latitude"),
    zoom: k("zoom"), pitch: k("pitch"),
    bearing: p1.bearing, // constant tee→green bearing already
    transitionDuration: 0,
  };
}

useEffect(() => {
  if (error) return;
  const wps = waypointsRef.current.slice(1); // skip the static start pose
  const DURATION = 8400;                    // same total as today
  let raf = 0, start = 0, cancelled = false;

  const frame = (now: number) => {
    if (cancelled) return;
    if (!start) start = now;
    const p = easeInOutCubic(Math.min((now - start) / DURATION, 1));
    setViewState(sampleCamera(wps, p));
    if (p < 1) raf = requestAnimationFrame(frame);
  };

  const kickoff = setTimeout(() => {
    raf = requestAnimationFrame(frame);
  }, tilesReady ? 400 : 6000);

  cancelFlightRef.current = () => {
    cancelled = true; clearTimeout(kickoff); cancelAnimationFrame(raf);
  };
  return () => cancelFlightRef.current?.();
}, [tilesReady, error]);
```

Keep what already works. User drag/rotate still calls `cancelFlightRef.current()`
from `onViewStateChange` (same as today's cancel). The ready/stalled/error
status posts to the app stay untouched.

### Also flatten the yo-yo
In the waypoint builder, make zoom and pitch move in one direction only:

| waypoint      | zoom (now → new) | pitch (now → new) |
|---------------|------------------|-------------------|
| behind tee    | 18.6 → **18.6**  | 70 → **70**       |
| midpoint      | 18.2 → **18.5**  | 68 → **67**       |
| near green    | 18.4 → **18.4**  | 64 → **64**       |

### Optional, if it still hitches on older phones
Tile decoding during the flight causes stutter on its own. Add a short
pre-roll so the start of the hole is loaded before the camera moves. Start the
loop when ~40 tiles have loaded (`tileCountRef.current >= 40`) or 2.5 s after
`tilesReady`, whichever comes first.

---

## Done when
- The live chunk has no `"crosshair":void 0`.
- Tee→green plays as one continuous move: gentle start, steady middle,
  gentle stop, no lurches at ~2.4 s or ~6 s.
- Dragging during the flight still takes over immediately.
- The app still gets `ready`. Test Torrey Pines hole 1 on the phone.

## Device recording, 2026-11-17 (holes 2 → 1, Torrey Pines)

Log-correlated with the app:

1. **Hole switch poisons the next load.** Tearing down hole 2's page aborts
   its in-flight tile fetches; `onTileError` fires with `Load failed` and the
   dying page posts `status: "error"` 23 ms AFTER the hole-1 page's
   navigation started. The app's guard (`state != .ready`) doesn't cover it —
   state is `.loading` — so it marked hole 1 failed and flashed the
   "3D DIDN'T LOAD" fallback until the real `ready` arrived 350 ms later.
   App-side fixed (ignore statuses before the new document's didFinish).
   Web-side fix in the same spirit: in `onTileError`, ignore aborted fetches
   (`error.name === "AbortError"` / `Load failed` when `document.visibilityState`
   is unloading or the component unmounted) — a dying page should post
   nothing.
2. **The flight reads as flat ground-hugging pan, not a flyover.** Zoom
   18.5+ at pitch 64–70 is ~100 m altitude: the camera skims the ground, so
   mid-flight frames look like a 2D map with no horizon. Suggest starting
   higher and tilting through the flight, e.g. zoom 16.8 → 17.4 with pitch
   55 → 65, so the green approach reads as descent.
3. **Blur mid-flight.** Tiles at the flight's zoom need more detail than the
   stream delivers during 8.4 s; frames show mosaic blur until the flight
   ends. The pre-roll from the section above (wait for ~40 tiles) plus a
   slightly lower target zoom (≤17.4) keeps detail ahead of the camera.

## Follow-up

Reveal and flight timing ("goes before it loads"): see `docs/flyover-reveal-gate.md`.
