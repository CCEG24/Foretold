# OpenSpriteKit / OpenCoreAnimation — upstream issues

Bugs found porting a real SpriteKit game (Foretold) to WASM via OpenSpriteKit.
Each is currently worked around by a local patch in `web/patches/` applied by
`web-spike/fetch-deps.sh`. Filing these upstream (github.com/1amageek) is the path
off the vendored fork. Repro context: Swift `main-snapshot-2026-09-10`, wasm SDK
`…-2026-09-10-a-wasm32-unknown-wasip1`, Chrome/WebGPU.

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
