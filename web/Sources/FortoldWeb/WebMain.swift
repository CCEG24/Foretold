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
        return
    }

    let renderer = SKRenderer(canvas: canvas)
    do {
        try await renderer.initialize()
    } catch {
        _ = JSObject.global.console.error("FortoldWeb: SKRenderer.initialize failed: \(String(describing: error))")
        return
    }
    renderer.resize(width: CanvasConfig.width, height: CanvasConfig.height)

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
    let callback = JSClosure { _ in
        if let cb = animationCallback {
            _ = JSObject.global.requestAnimationFrame!(cb)
        }
        let now = JSObject.global.performance.now().number ?? 0
        skRenderer?.update(atTime: (now - startTime) / 1000.0)
        skRenderer?.render()
        return .undefined
    }
    animationCallback = callback
    _ = JSObject.global.requestAnimationFrame!(callback)
}
