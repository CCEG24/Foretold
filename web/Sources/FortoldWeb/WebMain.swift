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

@_cdecl("getCanvasWidth")
func getCanvasWidth() -> Int32 { Int32(CanvasConfig.width) }

@_cdecl("getCanvasHeight")
func getCanvasHeight() -> Int32 { Int32(CanvasConfig.height) }

/// Reflect startup progress and failures in the page's #status box so problems
/// are visible without DevTools. Previously a failed WebGPU init only wrote a
/// console.error (invisible unless the URL has ?log), leaving the board
/// silently blank behind a stale "setup() called" message.
private func setStatus(_ text: String, error: Bool = false) {
    guard let el = JSObject.global.document.getElementById("status").object else { return }
    el["textContent"] = JSValue.string(JSString(text))
    el["className"] = JSValue.string(JSString(error ? "err" : ""))
    el["hidden"] = JSValue.boolean(false)
}

/// The board is rendering — clear the status box so it doesn't sit over the game.
private func hideStatus() {
    guard let el = JSObject.global.document.getElementById("status").object else { return }
    el["hidden"] = JSValue.boolean(true)
}

@_cdecl("setup")
func setup() {
    JavaScriptEventLoop.installGlobalExecutor()
    Task { await start() }
}

@MainActor
private func start() async {
    let document = JSObject.global.document
    guard let canvas = document.getElementById("canvas").object else {
        _ = JSObject.global.console.error("FortoldWeb: canvas #canvas not found")
        setStatus("FortoldWeb: canvas #canvas not found — the page layout looks broken.", error: true)
        return
    }

    setStatus("Requesting WebGPU device…")
    let renderer = SKRenderer(canvas: canvas)
    do {
        try await renderer.initialize()
    } catch {
        let detail = String(describing: error)
        _ = JSObject.global.console.error("FortoldWeb: SKRenderer.initialize failed: \(detail)")
        setStatus("Couldn't start the WebGPU renderer (\(detail)). This browser accepted the WebGPU API but can't allocate a GPU device — update Chrome or use another WebGPU-capable browser.", error: true)
        return
    }
    renderer.resize(width: CanvasConfig.width, height: CanvasConfig.height)
    setStatus("WebGPU renderer ready — building the scene…")

    let scene = GameScene(size: CGSize(width: CanvasConfig.width, height: CanvasConfig.height))
    scene.scaleMode = .aspectFit
    renderer.scene = scene

    let view = SKView()
    scene.didMove(to: view)
    skRenderer = renderer
    gameScene = scene

    // Route browser pointer/keyboard/wheel events into GameScene's shared handlers.
    installInput(scene: scene, canvas: canvas,
                 width: Double(CanvasConfig.width), height: Double(CanvasConfig.height))

    let startTime = JSObject.global.performance.now().number ?? 0
    var frames = 0
    var readyAnnounced = false
    let callback = JSClosure { _ in
        if let cb = animationCallback {
            _ = JSObject.global.requestAnimationFrame!(cb)
        }
        let now = JSObject.global.performance.now().number ?? 0
        skRenderer?.update(atTime: (now - startTime) / 1000.0)
        skRenderer?.render()

        // A successful initialize() doesn't guarantee the first frames present.
        // If the renderer is persistently failing, say so instead of leaving a
        // blank board behind a "ready" message; once a few frames go clean, hide
        // the status box so the board is unobstructed.
        if !readyAnnounced {
            frames += 1
            if let failure = skRenderer?.lastRenderError {
                readyAnnounced = true
                setStatus("WebGPU frames are failing (\(String(describing: failure))) — the board can't be presented in this browser.", error: true)
            } else if frames >= 10 {
                readyAnnounced = true
                hideStatus()
            }
        }
        return .undefined
    }
    animationCallback = callback
    _ = JSObject.global.requestAnimationFrame!(callback)
}
