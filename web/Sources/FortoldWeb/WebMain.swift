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

    stage("scene")
    let scene = GameScene(size: CGSize(width: CanvasConfig.width, height: CanvasConfig.height))
    scene.scaleMode = .aspectFit
    renderer.scene = scene

    let view = SKView()
    scene.didMove(to: view)
    skRenderer = renderer
    gameScene = scene

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
        skRenderer?.update(atTime: (now - startTime) / 1000.0)
        skRenderer?.render()
        reportFirstFrame()
        return .undefined
    }
    animationCallback = callback
    _ = JSObject.global.requestAnimationFrame!(callback)
}
