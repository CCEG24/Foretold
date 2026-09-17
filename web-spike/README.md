# Foretold web spike — OpenSpriteKit → WASM → Render

A throwaway spike whose **only** job is to prove the toolchain chain works end to
end before porting Foretold's real `GameScene`:

```
Swift 6.4 + wasm SDK → OpenSpriteKit → WebGPU → Render static site
```

Success = a rotating cyan square + a label rendered on a Render-hosted page.

It lives outside the `Foretold/` Xcode folder on purpose, so it never leaks into
the mac app target (that folder is a synchronized filesystem group).

## Files

| File | Purpose |
|---|---|
| `Package.swift` | Executable target depending on OpenSpriteKit via **local path**. |
| `fetch-deps.sh` | Clones OpenSpriteKit + its OpenCore* siblings into `Deps/`. |
| `Sources/HelloScene/main.swift` | Minimal scene (grounded) + browser bootstrap (draft). |
| `Web/index.html` | Canvas + WASM loader shell. |
| `build.sh` | Builds to WASM, assembles `dist/`. |
| `render.yaml` | Render static-site config with COOP/COEP + wasm MIME. |

## Run it

You do **not** need Render to test — Render is only the final public deploy.
Iterate locally; the only requirement is a static server that sets the COOP/COEP
cross-origin-isolation headers.

```bash
# 0. Toolchain — OpenSpriteKit needs Swift 6.4. Use swiftly:
curl -O https://download.swift.org/swiftly/darwin/swiftly.pkg && \
  installer -pkg swiftly.pkg -target CurrentUserHomeDirectory && \
  ~/.swiftly/bin/swiftly init --quiet-shell-followup && \
  . "${SWIFTLY_HOME_DIR:-$HOME/.swiftly}/env.sh" && hash -r
swiftly install 6.4
swiftly use     6.4

# 1. wasm SDK — first-party from swift.org (6.4 ships one; no swiftwasm fork needed):
swift sdk install \
  https://download.swift.org/swift-6.4.0-release/wasm-sdk/swift-6.4.0-RELEASE/swift-6.4.0-RELEASE_wasm.artifactbundle.tar.gz \
  --checksum f07b7be3c586d92d7a07051fc6d303b87ebea67eadc40640ba59d5a8b79aa86d
swift sdk list   # installs TWO sdks (full + Embedded Swift); build.sh picks the full one

# 2. Build + serve:
cd web-spike
./fetch-deps.sh     # checkout OpenSpriteKit + siblings into Deps/
./build.sh          # build wasm reactor + JS glue, assemble dist/
npx http-server dist -p 8000 -c-1 --cors \
  -H 'Cross-Origin-Opener-Policy: same-origin' \
  -H 'Cross-Origin-Embedder-Policy: require-corp'
# open http://localhost:8000 in a WebGPU-capable browser
```

### Generating the JS glue

`app.js` / `runtime.mjs` are **not** hand-written — JavaScriptKit's `PackageToJS`
plugin emits them from the built `.wasm` reactor. `build.sh` invokes it via
`swift package … js -o dist`. That loader fetches the wasm, sets up the WASI
shim, instantiates, and calls `instance.exports.setup()` (same flow as megaman's
`app.js`). `Web/index.html` supplies the `<canvas id="canvas">` the renderer
binds to.

## ⚠️ Known unknowns this spike exists to resolve

Discovered while scaffolding — resolve these as you go; each is a real blocker,
not a formality:

1. **Local-path dependencies.** OpenSpriteKit's `Package.swift` references
   `../OpenCoreGraphics`, `../OpenCoreAnimation`, `../OpenCoreImage`,
   `../OpenImageIO`, `../OpenFoundation`. It is **not** consumable as a plain
   `.package(url:)` — you must check the siblings out next to it (`fetch-deps.sh`).
2. **Sibling repos all exist (verified).** `git ls-remote` confirms all six
   (`OpenSpriteKit`, `OpenCoreGraphics`, `OpenCoreAnimation`, `OpenCoreImage`,
   `OpenImageIO`, `OpenFoundation`) are public, so `fetch-deps.sh` should
   populate `Deps/` cleanly. Remaining risk is only whether their `main`
   branches resolve together against one toolchain — verify at first build.
3. **Browser bootstrap — now grounded in `1amageek/megaman`.** That's a full
   OpenSpriteKit game shipping to WASM, so `main.swift` here mirrors its real
   pattern: a WASI-reactor executable exporting `setup()`/`getCanvasWidth()`/
   `getCanvasHeight()` via `@_cdecl`, `SKRenderer(canvas:)` +
   `try await initialize()` + `resize()`, `scene.didMove(to: SKView())`, and a
   `requestAnimationFrame` loop calling `update(atTime:)` + `render()`. Still
   verify at build — API signatures could drift.
4. **Toolchain: needs Swift 6.4 — RESOLVED.** OpenSpriteKit's `Package.swift` is
   `swift-tools-version:6.4.0`, which for a while meant a `main-snapshot-<date>`
   toolchain plus a date-matched swiftwasm SDK, because 6.4 hadn't shipped. Swift
   6.4 is now released and ships a first-party wasm SDK from swift.org, so both
   halves of that workaround are gone: pin `swiftly install 6.4` and the release
   SDK above. No more snapshot pruning breaking CI, and the same compiler builds
   the mac target (Xcode 27 = Swift 6.4) and the web target.
5. **No build on Render.** Render's build image won't have this toolchain, so build
   locally / in CI and let Render serve a prebuilt `dist/`.
6. **Text rendering.** OpenSpriteKit flags typographic-shaping gaps in software
   rendering — the `SKLabelNode` here is also a smoke test for that.

## Why a spike first

Foretold's game logic is already platform-agnostic and the SpriteKit surface it
uses is tiny, so the *port* is low-risk. The *toolchain* is where the surprises
live. Proving it on ~50 lines is far cheaper than discovering item #2 above
halfway through porting a 4,800-line scene.
