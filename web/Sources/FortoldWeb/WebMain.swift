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
    // Match the mac layout (wide board + side HUD columns).
    static let width = 1680
    static let height = 900
}

private var animationCallback: JSClosure?
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
    _ = JSObject.global.console.log(
        "FortoldWeb: \(Int(fps.rounded())) fps [art \(WebArt.registered)] | per frame — update \(ms(WebFrameStats.updateTotal / frames)),"
        + " render \(ms(WebFrameStats.renderTotal / frames))"
        + " | this second — \(WebFrameStats.inputEvents) hovers costing \(ms(WebFrameStats.inputTotal)),"
        + " unaccounted \(ms(elapsed - accounted))"
    )
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
    renderer.resize(width: CanvasConfig.width, height: CanvasConfig.height)

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
