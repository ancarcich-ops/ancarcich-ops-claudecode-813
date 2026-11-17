# Flyover never loads — `getCursor` TypeError kills the deck.gl render loop

Bug in the sticks-golf web repo (`/embed/hole-flyover`). The iOS app is fine.

## Evidence (2026-11-16, app runtime logs)

```
[Flyover] [embed] webgl renderer: Apple GPU
[Flyover] Embed status: webgl-ok
[Flyover] Page HTML finished loading
[Flyover] [embed] window.onerror: TypeError: this.props.getCursor is not a
  function. (In 'this.props.getCursor(this.cursorState)',
  'this.props.getCursor' is undefined) @ chunks/4676-….js:5789
[Flyover] Embed status: stalled          ← embed's own 6s zero-tiles signal
[Flyover] Watchdog fired after 30.0s (state pageLoaded) — marking failed
```

## Root cause

The map component builds its `Deck` with:

```js
getCursor: f ? () => "crosshair" : void 0
```

`f` = pick/aim mode, false on load, so this passes `getCursor: undefined`
explicitly. deck.gl merges props by spread, so the explicit `undefined`
overwrites the default (`({isDragging}) => isDragging ? "grabbing" : "grab"`).
The first interaction runs deck.gl's `_updateCursor()` →

```
this.props.getCursor(this.cursorState)  → TypeError
```

The exception takes down the render loop: no mesh tile ever paints, the embed
reports `stalled`, the app's 30s watchdog fails the load. This is why the 3D
flyover has "never worked".

## Fix (one line, in the flyover map component)

Only set the cursor prop when picking — otherwise omit it and keep deck.gl's
default:

```js
// before
getCursor: f ? () => "crosshair" : void 0,

// after
...(f ? { getCursor: () => "crosshair" } : {}),
```

Equivalent explicit alternative:

```js
getCursor: f
  ? () => "crosshair"
  : ({ isDragging }) => (isDragging ? "grabbing" : "grab"),
```

Deploy, then verify by loading
`/embed/hole-flyover?teeLat=…&teeLng=…&greenLat=…&greenLng=…&n=1&par=4` in a
desktop browser with devtools open: no `window.onerror`, tiles paint, and the
iOS 3D segment goes from stall → ready within seconds.

## Status (2026-11-16)

- #666 is merged but NOT in the live build: deployment
  `dpl_DYBpC8rApTQPoSTEbauk3CGwMs5p` still serves
  `chunks/9351-97a599b41781dc98.js` (same hash) containing
  `getCursor:f?()=>"crosshair":void 0`. The embed page never passes the aim
  callback, so `f` is always undefined and the bug hits every load.
  Check: did #666 land on the branch Vercel builds, and in the file that
  produces chunk 9351?
- App-side workaround shipped: `FlyoverService.getCursorPatchScript`
  (document-start user script) rewrites that expression in the webpack
  module factory as the chunk registers. It no-ops once the fixed bundle
  is live. It logs "patched getCursor in module …" under `[Flyover]`.

## Second blocker: Google 3D tiles 404 (2026-11-16)

With the getCursor patch applied (verified in headless Chromium against the
live embed: error gone, "patched getCursor in module 99351" logged), the
flyover still stalls because the very first request fails:

    GET https://tile.googleapis.com/v1/3dtiles/root.json?key=<embed key>
    -> 404 {"code":404,"message":"Requested entity was not found.","status":"NOT_FOUND"}

Same result with a direct curl (Referer sticks-golf.vercel.app), so it is the
key/project, not the page. Zero tiles load -> the embed's 6s timer posts
"stalled". Per Google/Cesium reports this 404 means the key's Cloud project
has no active billing account, or Map Tiles API is not enabled for it (or the
key belongs to a different project than the one with Map Tiles enabled).

Fix in Google Cloud Console (project owning the key in the embed bundle):
1. Billing -> project linked to an active billing account (valid card).
2. APIs & Services -> enable "Map Tiles API".
3. Credentials -> key's API restrictions include Map Tiles API; HTTP referrer
   restrictions allow sticks-golf.vercel.app/*. Note the iOS WKWebView sends the
   page's own origin as Referer, so a referrer rule for the site covers the app.
Verify: the curl above returns JSON with a "root" entry instead of 404.

## Correction (2026-11-17): the PR numbers were crossed

#666 is "A round keeps the card it was played on" (stroke-index-per-match) —
it was never the flyover fix. No flyover fix was ever merged in the web repo;
the buggy line is untouched since #552 (August). The real fix is web PR #670
(one line, `getCursor` spread form), opened 2026-11-17, verified in a real
browser with a control run (without a Google key the component returns early
and deck.gl never mounts, so probes must set a dummy key). It was unmerged at
the time of writing — merge and deploy, then verify the live chunk lost
`"crosshair":void 0` (new chunk hash). The app's getCursorPatchScript no-ops
once it ships.

Also confirmed from the app's exact embed URL: the chrome-less embed ships the
site header (sticky, with nav) and two "Sign in" links — wrong furniture inside
the flyover WKWebView. Separate small fix: the embed route should render no
site chrome.

## #670 deployed & verified (2026-11-17)

- Production deployment `dpl_6JDkDf18Z2X95aNcyhWj6egFiD7K` serves
  `9351-1365d8164d595de7.js`: `"crosshair":void 0` count 0; the DeckGL prop is
  now `getCursor: p ? () => "crosshair" : <deck.gl default>` — the spread form.
- Chunk 9351 is no longer referenced by a stable number in the page
  (`9351-933b473e32e625ac.js` from the pre-merge tip was not the deployed hash);
  always read the chunk name out of the embed HTML.
- The harmless sibling (`cursor:` CSS in the minimap, chunk 9483) is not loaded
  by the embed page at all — the false-positive trap doesn't apply to the app's
  embed loads, only to whole-repo greps.
- App-side `getCursorPatchScript` now no-ops by design (pattern absent). Leave
  it in place: it protects against the pattern returning and costs nothing.
- Still open: camera smoothing (docs/flyover-smooth-camera.md) and embed page
  chrome (site header + Sign in render inside the WKWebView).

## Cleanup (2026-11-17): client patch removed

The server fix (#670) is live and confirmed painting 3D meshes, so
`getCursorPatchScript` and its user script were removed from
`FlyoverService.swift` — dead weight; the doc note from the shipped section no
longer applies. Web PR #673 carries the recording's three fixes (dying-page
status suppressed via `pagehide`; camera zoom 16.8→17.4, pitch 55→65; 40-tile
pre-roll). The app-side stale-status guard added the same day stays: it covers
the app's own teardown window regardless of what the embed posts.
