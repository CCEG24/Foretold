# OpenSpriteKit / OpenCoreAnimation — upstream issues

Bugs found porting a real SpriteKit game (Foretold) to WASM via OpenSpriteKit.
Each is currently worked around by a local patch in `web/patches/` applied by
`web-spike/fetch-deps.sh`. Filing these upstream (github.com/1amageek) is the path
off the vendored fork. Repro context: Swift `main-snapshot-2026-09-10`, wasm SDK
`…-2026-09-10-a-wasm32-unknown-wasip1`, Chrome/WebGPU — except issue #9, which
only reproduces in Firefox.

---

## 1. [OpenCoreAnimation] CATextLayer renders nothing when bounds are empty (no Canvas2D auto-measure)

**Repo:** OpenCoreAnimation · **File:** `Sources/OpenCoreAnimation/CAWebGPURenderer.swift` (`renderText`)

`renderText` early-returns when `configuration.bounds.size` is zero:
```swift
let logicalSize = configuration.bounds.size
guard logicalSize.width > 0, logicalSize.height > 0 else { return }
```
But `SKLabelNode.updateLayerBounds()` intentionally leaves `bounds = .zero` for
auto-measured (non-wrapped) text, and the code comments + repo docs state the
renderer will "auto-measure text using Canvas2D" in that case. It doesn't — so
**every default `SKLabelNode` renders invisibly**, with no error (the failure is
swallowed by `recordTextRenderFailure`).

**Repro:** add an `SKLabelNode(text: "Hello")` (no `preferredMaxLayoutWidth`) → nothing draws.

**Expected:** when bounds is empty, measure the text via the same Canvas2D
`ctx.measureText` path already used elsewhere, size the texture + quad to the
measured size, and render.

---

## 2. [OpenCoreAnimation] Any layer with opacity < 1 renders the whole frame black (group-opacity offscreen path)

**Repo:** OpenCoreAnimation · **File:** `Sources/OpenCoreAnimation/CAWebGPURenderer.swift` + `CALayer.allowsGroupOpacity`

`CALayer.allowsGroupOpacity` defaults to `true`. When a layer's effective opacity
drops below 1, the renderer takes the offscreen group-opacity compositing path
(`requiresOffscreenRoot = … && values.allowsGroupOpacity && opacity < 1`). In the
WebGPU backend that path composites to **black** — so any fade/opacity animation
blanks the entire frame until opacity returns to 1.

**Repro:** run `SKAction.fadeAlpha(to: 0.5, duration: 1)` on any node → screen goes
black for the duration. A `repeatForever` fade makes the whole scene flicker black.

**Workaround:** default `allowsGroupOpacity = false` (simple per-layer alpha).

**Expected:** the offscreen group-opacity composite should produce the blended
result, not black.

---

## 3. [OpenSpriteKit] `nodes(at:)` returns nothing for nodes with `isUserInteractionEnabled == false`

**Repo:** OpenSpriteKit · **File:** `Sources/OpenSpriteKit/SKNode.swift` (`nodes(at:)`)

```swift
if node.isUserInteractionEnabled && node._contentBounds.contains(point) {
    results.append(...)
}
```
`isUserInteractionEnabled` defaults to `false`. Per SpriteKit, `nodes(at:)` returns
**all** nodes whose bounds contain the point; `isUserInteractionEnabled` gates
*event delivery*, not this query. As written, name-based hit-testing
(`scene.nodes(at: p).compactMap(\.name)`) — a very common UI pattern — returns
nothing, so buttons/menus are dead.

**Repro:** add an unnamed-interaction `SKSpriteNode` with a `name`; `nodes(at:)` at
its center returns `[]`.

**Fix:** drop the `isUserInteractionEnabled` condition (keep the bounds test).

---

## 4. [OpenSpriteKit] `SKColor` is missing `withAlphaComponent(_:)`

**Repo:** OpenSpriteKit · **File:** `Sources/OpenSpriteKit/SKColor.swift`

UIKit/AppKit colors provide `withAlphaComponent(_:)`, widely used in SpriteKit
code. OpenSpriteKit's `SKColor` doesn't, so shared code fails to compile on WASM.

**Fix:** add
```swift
extension SKColor {
    func withAlphaComponent(_ a: CGFloat) -> SKColor {
        SKColor(red: red, green: green, blue: blue, alpha: a)
    }
}
```

---

## 5. [OpenSpriteKit] `SKLabelNode` ignores alignment modes when positioning (never sets layer anchorPoint)

**Repo:** OpenSpriteKit · **File:** `Sources/OpenSpriteKit/SKLabelNode.swift`

`SKNode` sets `layer.anchorPoint = (0.5, 0.5)` and `SKLabelNode` never overrides it,
so `horizontalAlignmentMode` / `verticalAlignmentMode` have no effect on where text
renders — every label is centered on its position. Left-aligned labels near an edge
run off-screen; top/bottom-aligned labels sit wrong.

**Repro:** `label.horizontalAlignmentMode = .left; label.position = CGPoint(x: 10, y: …)`
→ text centers on x=10 and clips off the left edge.

**Fix:** map alignment → `layer.anchorPoint` (left→x0, center→0.5, right→x1;
bottom/baseline→y0-ish, center→0.5, top→y1) whenever alignment changes.

> Related: the width heuristic behind auto-sizing (`estimatedTextSize`,
> `0.6·fontSize`/char) under-measures bold/caps and causes truncation ("FORETOLD"
> → "foret…"). A real Canvas2D measurement (see issue #1) removes the guesswork.
>
> **Our fix:** `estimatedTextSize()` now measures with Canvas2D via a new
> `CATextMetrics.measuredWidth` (see issue #8) instead of guessing, including
> greedy word-wrap line counting and `\n` paragraphs. Measuring in `SKLabelNode`
> rather than only in the renderer also fixes callers that lay out from
> `label.frame.width`.

---

## 6. [OpenSpriteKit / OpenCoreAnimation] No HiDPI / `contentsScale` support — blurry on retina

**Repo:** OpenSpriteKit (`SKRenderer.resize`) → OpenCoreAnimation (`CAWebGPURenderer.resize` / projection)

`resize(width:height:)` sets both `canvas.width/height` (the backing buffer) **and**
the orthographic projection (`renderTarget.viewportSize`) to the same values. There
is no notion of `devicePixelRatio` / `contentsScale`: to fill the scene you must
resize to the scene's logical size, so on a 2× display the browser upscales a 1×
buffer → everything is soft. Resizing to `logical×dpr` instead just maps the scene
into a corner (projection extent grew but scene coords didn't).

**Repro:** any scene on a retina/HiDPI display renders blurry; there's no API to
render at device resolution.

**Expected:** an SKView/SKRenderer `contentsScale` (or auto `devicePixelRatio`)
that renders the backing at `logical×scale` while keeping scene coordinates in
logical points, and rasterizes text/CATextLayer at that scale.

---

## 7. [OpenSpriteKit] Children of sized nodes (SKSpriteNode/SKShapeNode) are offset by anchorPoint × parentSize

**Repo:** OpenSpriteKit · **File:** `Sources/OpenSpriteKit/SKSpriteNode.swift` (`updateLayerBounds`)

A node's child at position `(0,0)` should render at the parent's position (its
anchor point). But `SKSpriteNode` sets `layer.bounds = CGRect(origin: .zero, size:
size)` with `anchorPoint = (0.5,0.5)`, so the child sublayer's coordinate origin is
the parent's **bounds corner**, not its anchor — every child is shifted by
`anchorPoint × parentSize` (e.g. half a sprite down-left). Plain `SKNode` containers
are fine (zero bounds); only sized nodes (sprites, and shapes with bounds) are
affected.

**Repro:** add a small `SKSpriteNode` as a child of a larger one at `.zero` → it
renders at the parent's corner, not its center. Same for a label child of an
`SKShapeNode` button, and for `nodes(at:)` hit regions of shape buttons (clicks land
offset).

**Expected:** child coordinates relative to the parent's anchor point (SpriteKit
semantics) — i.e. the parent's content/sublayer coordinate origin should account for
`anchorPoint × bounds.size`.

---

## 8. [OpenCoreAnimation] Font names are passed to CSS as-is — PostScript names don't resolve, and weight/style are dropped

**Repo:** OpenCoreAnimation · **Files:** `Rendering/CATextRenderConfiguration.swift` (`cssFontFamily`), `CAWebGPURenderer.swift` (`renderText`)

The renderer builds its Canvas2D font as:

```swift
ctx.font = .string("\(configuration.fontSize)px \(configuration.cssFontFamily)")
```

where `cssFontFamily` is just the quoted `CATextLayer.font` string. Two problems:

1. **SpriteKit/CoreText name fonts by PostScript name** — `"HelveticaNeue-Bold"`,
   `"Baskerville-Italic"`. Those are not CSS *families* (the family is
   `"Helvetica Neue"`), so matching is unreliable and typically falls back to a
   default font with different metrics.
2. **Weight and style are never emitted.** Even when the family resolves, there is
   no `bold` / `italic` in the shorthand, so `-Bold` and `-Italic` faces render as
   regular.

Combined effect: text is drawn in the wrong face at the wrong width, so it
overflows or gets truncated inside its layer, and every metric derived from it is
off.

**Repro:** a label with `fontName = "HelveticaNeue-Bold"` renders non-bold, in a
fallback face, and measures wider/narrower than the layer reserved.

**Fix (implemented locally):** a `CATextMetrics.cssFont(name:size:)` that splits the
PostScript name into family + weight + style and emits a proper shorthand —
`HelveticaNeue-Bold` @15 → `700 15.0px "Helvetica Neue", "HelveticaNeue-Bold", sans-serif`
(camelCase → spaced family; `Thin/Light/Medium/Semibold/Bold/Black…` → numeric
weights, compound names matched before their substrings; `Italic`/`Oblique` → style;
original name kept as a secondary family for engines that do resolve PostScript
names; generic family last). The same helper is reused for measurement so layout
and rasterization agree.

---

## 9. [OpenCoreAnimation + swift-webgpu] The hardcoded `rgba16float` canvas kills the whole wasm instance in Firefox

**Repo:** OpenCoreAnimation · **File:** `Sources/OpenCoreAnimation/CAWebGPURenderer.swift`
(`initialize`, `configureCanvas`) — and swift-webgpu `Sources/SwiftWebGPU/GPUCanvasContext.swift`

`initialize()` hardcodes the canvas format:

```swift
// Float16 storage is required to preserve values above SDR white until
// browser presentation.
preferredFormat = .rgba16float
```

`rgba16float` is a legal canvas format per spec, but Firefox hasn't implemented it
and `configure()` raises a **TypeError** for it
(<https://bugzilla.mozilla.org/show_bug.cgi?id=1834395>). swift-webgpu's
`configure(_:)` calls through JavaScriptKit's *non-throwing* path
(`jsObject.configure!(…)`), so that exception isn't an error the caller can see —
it unwinds the WebAssembly instance. The `Task` running `initialize()` dies
mid-flight, every `await` after it is abandoned, and the host page gets no
callback at all: not success, not failure, just silence. Any app that reports its
boot outcome from Swift therefore looks *hung* rather than broken, which is the
expensive part — the actual cause never reaches a log.

**Repro:** load any OpenSpriteKit scene in Firefox 141+ on Windows (WebGPU on,
adapter acquired). `SKRenderer.initialize()` never returns and never throws.

**Expected:** `configureCanvas()` already returns `Bool`, which promises the caller
a recoverable failure — it can't deliver one while the underlying call is
non-throwing. A format the browser doesn't implement should be a `false`, not an
instance teardown.

**Fix (implemented locally):** swift-webgpu gains `configureThrowing(_:)`
(`try jsObject.throwing.configure!(…)`), `configureCanvas()` catches and returns
`false`, and `initialize()` retries once with `gpu.preferredCanvasFormat` before
giving up. Every pipeline targets `preferredFormat` and the readback path already
handles both 8- and 16-bit widths, so the fallback is a complete configuration —
just standard-dynamic-range only. Worth considering upstream whether float16
should be requested at all when nothing in the tree asks for extended range.

> Related: Firefox reports no `toneMapping` from `getConfiguration()`, which the
> existing `supportsExtendedDynamicRangeOutput` probe already reads correctly as
> "no EDR" — that part degrades cleanly.

---

## 10. [OpenCoreAnimation] Image contents are re-converted on every snapshot, defeating the texture cache

**Repo:** OpenCoreAnimation · **Files:** `Sources/OpenCoreAnimation/CARenderSnapshot.swift`
(`captureImageContents`) + `CALayer.swift`

`captureImageContents` reuses a layer's existing storage only when
`_committedImageContentsStorage` is set — and that field is populated solely by
the committed *animation* evaluator. A plain layer with a `CGImage` in
`contents` therefore takes the other branch every time:

```swift
} else if let contents = layer.contents {
    storage = try CGImageTextureStorageConverter.convert(contentsImage)
```

Each conversion allocates a fresh `CGImageTextureStorage`, and with it a fresh
`CacheIdentity` — which is exactly the key the renderer uses for its
constant-time texture lookups (`TexturedCacheKey.committedImage`). So every
snapshot that isn't served by `staticValues` re-uploads and re-mipmaps every
image in the tree, even though not one pixel changed.

**Repro:** a scene with a handful of `SKSpriteNode`s carrying textures, plus
anything that dirties one unrelated layer each frame (changing one small
sprite's colour is enough). Idle holds 60fps because the snapshot reuses
`staticValues`; the moment something is dirty it drops to single digits. In
Foretold, seven 256×256 sprites and one tile changing colour on mouse hover cost
~100ms per frame — and the cost is invisible in CPU frame timing, because it
lands in the GPU queue.

**Expected:** the conversion is a pure function of the `CGImage`, so it should
be cached for as long as `contents` is unchanged. `CALayer` already bumps
`_contentsAssignmentGeneration` and clears `_committedImageContentsStorage` in
the `contents` setter, so the invalidation point exists.

**Fix (implemented locally):** `CALayer` gains `_contentsStorageCache`, set when
`captureImageContents` converts and consulted before converting. It's cleared by
the `contents` setter and carried across the copy-init and — importantly — onto
the presentation layer, which is the one actually snapshotted each frame.
