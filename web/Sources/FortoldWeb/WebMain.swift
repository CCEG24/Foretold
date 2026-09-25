//
//  WebMain.swift
//  FortoldWeb — browser entry point (WASM only)
//
//  Presents the real GameScene through OpenSpriteKit's SKRenderer, mirroring the
//  proven spike bootstrap (see web-spike). Input isn't wired yet — that's the
//  DOM→GameInput adapter step; this first gets the actual board rendering.

import OpenSpriteKit
import JavaScriptKit
import JavaScriptEventLoop

private enum CanvasConfig {
    // Match the mac layout (wide board + side HUD columns). These are logical
    // points — the scene's coordinate space — not the canvas backing store,
    // which is this times the contents scale below.
    static let width = 1680
    static let height = 900

    /// Ceiling on device-pixels-per-point.
    ///
    /// The board is drawn to fit the window, so on a large retina display the
    /// honest ratio can climb past 3 — a 5040×2700 backing store, with every
    /// viewport-sized cache sized to match. 2× is where the sharpness stops
    /// being visible and the memory starts to be; past it the browser's own
    /// upscale is a fine trade.
    static let maxContentsScale: Double = 2

    /// Render this many times the screen's pixels and let the browser shrink it.
    ///
    /// The WebGPU renderer has no multisampling, so every shape edge, circle and
    /// stroke comes out hard-stepped where SpriteKit on the Mac smooths it — that
    /// jaggedness reads as "low resolution" even at 1:1 pixels. Oversampling and
    /// letting the browser filter it down is antialiasing by brute force: 4× the
    /// pixels at 2, bounded by `maxContentsScale`. `?ss=1` in the URL turns it
    /// off to compare. Stopgap until the renderer does MSAA itself.
    nonisolated(unsafe) static let supersample: Double = {
        // Plain stdlib parsing — no Foundation string search on the wasm side.
        let query = (JSObject.global.location.search.string ?? "").dropFirst()   // drop "?"
        for pair in query.split(separator: "&") where pair.hasPrefix("ss=") {
            if let value = Double(pair.dropFirst(3)), value >= 1, value.isFinite {
                return value
            }
        }
        return 2
    }()
}

/// Device pixels per scene point, for the canvas as the page lays it out now.
///
/// The canvas's CSS box is what the player actually sees (`min(100vw, …)` in
/// index.html), so the physical pixels across it are `cssWidth × devicePixelRatio`.
/// Spreading those over the scene's logical width gives the scale at which the
/// renderer should rasterize to land exactly one texel per screen pixel.
private func canvasContentsScale(_ canvas: JSObject) -> CGFloat {
    let rect = canvas.getBoundingClientRect!()
    let cssWidth = rect.width.number ?? 0
    let ratio = JSObject.global.devicePixelRatio.number ?? 1
    guard cssWidth > 0, ratio > 0, cssWidth.isFinite, ratio.isFinite else { return 1 }
    let ideal = cssWidth * ratio / Double(CanvasConfig.width)
    return CGFloat(min(ideal * CanvasConfig.supersample, CanvasConfig.maxContentsScale))
}

/// The backing width the current scale asks for, used to ignore resize events
/// that wouldn't change a single pixel — a reconfigure drops the depth texture
/// and every viewport-sized cache, so it isn't free.
private func backingWidth(for scale: CGFloat) -> Int {
    Int((Double(CanvasConfig.width) * Double(scale)).rounded())
}

private var animationCallback: JSClosure?
/// Held for the page's lifetime: a JSClosure handed to `addEventListener` and
/// then released fires into freed memory.
private var retainedResizeClosure: JSClosure?
/// The contents scale currently applied to the renderer. File-scope rather than
/// captured, so the resize callback isn't mutating a local across an escaping
/// boundary. Single-threaded wasm, so unsafe global state is fine.
nonisolated(unsafe) private var appliedContentsScale: CGFloat = 1
private var skRenderer: SKRenderer?
private var gameScene: GameScene?
private var didAnnounceFirstFrame = false

/// Report the real outcome to the page.
///
/// `setup()` returns the instant it spawns its Task, so JS cannot tell whether
/// rendering actually began — every interesting failure (no WebGPU adapter, no
/// canvas) happens later, on a Task the caller's try/catch can't observe. The
/// page installs `foretoldReady`/`foretoldFailed` for us to call instead, so a
/// blank canvas reports a cause rather than "setup() called".
private func report(failure message: String) {
    _ = JSObject.global.console.error("FortoldWeb: \(message)")
    if let fn = JSObject.global.foretoldFailed.function {
        _ = fn(message)
    }
}

/// Names the step about to run, for the page's watchdog.
///
/// `report(failure:)` only covers failures Swift can observe. A JavaScript
/// exception crossing the wasm boundary (a browser rejecting a WebGPU
/// configuration, say) unwinds the instance instead, so nothing gets reported
/// and the page can only say "neither callback fired". Naming each step before
/// it runs lets the watchdog point at the one that never finished.
private func stage(_ name: String) {
    if let fn = JSObject.global.foretoldStage.function {
        _ = fn(name)
    }
}

/// Where a second of wall-clock actually goes. Splitting the frame into the
/// scene's update, the WebGPU render, the hover handling that runs between
/// frames, and whatever's left tells us which one to chase — "9 fps with a
/// 9ms render" only means the cost is somewhere none of those numbers looked.
enum WebFrameStats {
    nonisolated(unsafe) static var frames = 0
    nonisolated(unsafe) static var updateTotal = 0.0
    nonisolated(unsafe) static var renderTotal = 0.0
    nonisolated(unsafe) static var inputTotal = 0.0
    nonisolated(unsafe) static var inputEvents = 0
    nonisolated(unsafe) static var windowStart = 0.0

    /// Matches index.html's own `?log` switch.
    nonisolated(unsafe) static let logging: Bool =
        (JSObject.global.location.search.string ?? "").contains("log")

    static func recordInput(_ milliseconds: Double) {
        guard logging else { return }
        inputTotal += milliseconds
        inputEvents += 1
    }

    static func reset(at now: Double) {
        frames = 0
        updateTotal = 0
        renderTotal = 0
        inputTotal = 0
        inputEvents = 0
        windowStart = now
    }
}

private func reportFrameTiming(update: Double, render: Double, at now: Double) {
    if WebFrameStats.windowStart == 0 { WebFrameStats.windowStart = now }
    WebFrameStats.frames += 1
    WebFrameStats.updateTotal += update
    WebFrameStats.renderTotal += render
    let elapsed = now - WebFrameStats.windowStart
    guard elapsed >= 1000 else { return }
    // Diagnostics only, same as the page's own chatter: a player's console
    // shouldn't fill with frame stats. Add ?log to the URL to see them.
    guard WebFrameStats.logging else {
        WebFrameStats.reset(at: now)
        return
    }

    let frames = Double(WebFrameStats.frames)
    let fps = frames / (elapsed / 1000)
    // Everything the second was spent on that isn't ours: browser compositing,
    // GC, the wasm/JS boundary, or simply waiting on the display.
    let accounted = WebFrameStats.updateTotal + WebFrameStats.renderTotal + WebFrameStats.inputTotal
    func ms(_ value: Double) -> String { "\(Double(Int(value * 10)) / 10)ms" }
    // Rewritten in place in the page's corner box rather than logged: a line
    // a second buried everything else in the console.
    if let box = JSObject.global.document.getElementById("fps").object {
        _ = box.classList.add("show")   // idempotent; the box stays hidden without ?log
        box.textContent = .string(
            "\(Int(fps.rounded())) fps · \(Double(Int(appliedContentsScale * 100)) / 100)×"
            + "\nupdate \(ms(WebFrameStats.updateTotal / frames))"
            + "  render \(ms(WebFrameStats.renderTotal / frames))"
            + "\n\(WebFrameStats.inputEvents) hovers \(ms(WebFrameStats.inputTotal))"
            + "  other \(ms(elapsed - accounted))"
            + "\nart \(WebArt.registered)"
        )
    }
    WebFrameStats.reset(at: now)
}

private func reportFirstFrame() {
    guard !didAnnounceFirstFrame else { return }
    didAnnounceFirstFrame = true
    if let fn = JSObject.global.foretoldReady.function {
        _ = fn()
    }
}

@_cdecl("getCanvasWidth")
func getCanvasWidth() -> Int32 { Int32(CanvasConfig.width) }

@_cdecl("getCanvasHeight")
func getCanvasHeight() -> Int32 { Int32(CanvasConfig.height) }

@_cdecl("setup")
func setup() {
    JavaScriptEventLoop.installGlobalExecutor()
    Task { await start() }
}

@MainActor
private func start() async {
    stage("canvas")
    let document = JSObject.global.document
    guard let canvas = document.getElementById("canvas").object else {
        report(failure: "canvas #canvas not found")
        return
    }

    stage("renderer-init")
    let renderer = SKRenderer(canvas: canvas)
    do {
        try await renderer.initialize()
    } catch {
        report(failure: "SKRenderer.initialize failed: \(String(describing: error))")
        return
    }
    // The scene stays 1680×900 points; only the backing store follows the
    // display. Without this the canvas rendered 1680×900 pixels and the browser
    // stretched them over the (usually larger, usually retina) CSS box, which
    // is what made the whole board look soft.
    appliedContentsScale = canvasContentsScale(canvas)
    renderer.resize(width: CanvasConfig.width, height: CanvasConfig.height,
                    contentsScale: appliedContentsScale)
    if WebFrameStats.logging {
        _ = JSObject.global.console.log(
            "FortoldWeb: \(CanvasConfig.width)×\(CanvasConfig.height) pt at"
            + " \(Double(Int(appliedContentsScale * 100)) / 100)× →"
            + " \(backingWidth(for: appliedContentsScale))px backing"
        )
    }

    // Sprites have to be in the rig's cache before the scene is built: each
    // body reads it once as it's constructed. No manifest = no art, and the
    // board draws the shapes it always did.
    stage("assets")
    let art = await WebArt.preload()
    _ = JSObject.global.console.log("FortoldWeb: \(art.loaded) sprites loaded, \(art.failed) failed")

    stage("scene")
    let scene = GameScene(size: CGSize(width: CanvasConfig.width, height: CanvasConfig.height))
    scene.scaleMode = .aspectFit
    renderer.scene = scene

    let view = SKView()
    scene.didMove(to: view)
    skRenderer = renderer
    gameScene = scene

    // Pay for the texture uploads here, while the loading screen is still up,
    // rather than in the first seconds of play.
    stage("prewarm")
    WebArt.prewarm(in: scene, renderer: renderer)

    // Route browser pointer/keyboard/wheel events into GameScene's shared handlers.
    stage("input")
    installInput(scene: scene, canvas: canvas,
                 width: Double(CanvasConfig.width), height: Double(CanvasConfig.height))

    // Resizing the window changes the CSS box the board fills, and dragging it
    // to another display changes devicePixelRatio — both change how many real
    // pixels the same 1680×900 points get. Re-scale when the backing store
    // would actually come out a different size; the scene itself never moves.
    let resized = JSClosure { _ in
        let scale = canvasContentsScale(canvas)
        guard backingWidth(for: scale) != backingWidth(for: appliedContentsScale) else {
            return .undefined
        }
        appliedContentsScale = scale
        skRenderer?.resize(width: CanvasConfig.width, height: CanvasConfig.height,
                           contentsScale: scale)
        // Nothing else to do: the next frame redraws the whole layer tree into
        // the new backing store, and cached text textures are keyed by pixel
        // size, so they miss at the new scale and re-rasterize on demand.
        return .undefined
    }
    retainedResizeClosure = resized
    _ = JSObject.global.addEventListener!("resize", resized)

    stage("first-frame")
    let startTime = JSObject.global.performance.now().number ?? 0
    let callback = JSClosure { _ in
        if let cb = animationCallback {
            _ = JSObject.global.requestAnimationFrame!(cb)
        }
        let now = JSObject.global.performance.now().number ?? 0
        let frameStart = now
        skRenderer?.update(atTime: (now - startTime) / 1000.0)
        let updated = JSObject.global.performance.now().number ?? 0
        skRenderer?.render()
        let finished = JSObject.global.performance.now().number ?? 0
        reportFrameTiming(update: updated - frameStart, render: finished - updated, at: finished)
        reportFirstFrame()
        return .undefined
    }
    animationCallback = callback
    _ = JSObject.global.requestAnimationFrame!(callback)
}
