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
