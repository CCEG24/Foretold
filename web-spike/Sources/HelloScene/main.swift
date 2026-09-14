//
//  main.swift
//  HelloScene — OpenSpriteKit → WASM de-risk spike
//
//  Renders a single rotating shape + a label in the browser via WebGPU. If this
//  shows up on a page, the whole toolchain is proven and Foretold's GameScene
//  can follow the same path.
//
//  The bootstrap below mirrors the working reference game 1amageek/megaman
//  (Sources/WasmApp/main.swift): a WASI-reactor executable that exports setup()
//  via @_cdecl, grabs the <canvas>, drives an SKRenderer, and pumps a
//  requestAnimationFrame loop. The scene itself uses only confirmed OpenSpriteKit
//  API (SKScene / SKShapeNode / SKLabelNode / SKColor / SKAction).

#if canImport(SpriteKit)
import SpriteKit          // lets the scene compile on macOS for a quick sanity check
#else
import OpenSpriteKit
import JavaScriptKit
import JavaScriptEventLoop
#endif

// MARK: - Scene (shared, platform-agnostic)

final class HelloScene: SKScene {
    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1.0)

        let side = min(size.width, size.height) * 0.25
        let box = SKShapeNode(rectOf: CGSize(width: side, height: side), cornerRadius: 8)
        box.fillColor = SKColor(red: 0.35, green: 0.85, blue: 0.95, alpha: 1.0)
        box.strokeColor = .white
        box.lineWidth = 3
        box.position = CGPoint(x: size.width / 2, y: size.height / 2)
        box.run(.repeatForever(.rotate(byAngle: .pi * 2, duration: 3)))
        addChild(box)

        let label = SKLabelNode(text: "OpenSpriteKit → WASM ✓")
        label.fontName = "HelveticaNeue-Bold"
        label.fontSize = 28
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: size.width / 2, y: size.height * 0.2)
        addChild(label)
    }
}

// MARK: - Browser bootstrap (WASM only — mirrors megaman)

#if !canImport(SpriteKit)

private enum CanvasConfig {
    static let width = 800
    static let height = 600
}

// Held for the lifetime of the app so the closure/renderer aren't deallocated.
private var animationCallback: JSClosure?
private var skRenderer: SKRenderer?

@_cdecl("getCanvasWidth")
func getCanvasWidth() -> Int32 { Int32(CanvasConfig.width) }

@_cdecl("getCanvasHeight")
func getCanvasHeight() -> Int32 { Int32(CanvasConfig.height) }

/// Entry point the JS loader calls after instantiating the wasm reactor.
@_cdecl("setup")
func setup() {
    JavaScriptEventLoop.installGlobalExecutor()
    Task { await start() }
}

@MainActor
private func start() async {
    let document = JSObject.global.document
    guard let canvas = document.getElementById("canvas").object else {
        _ = JSObject.global.console.error("HelloScene: canvas #canvas not found")
        return
    }

    let renderer = SKRenderer(canvas: canvas)
    do {
        try await renderer.initialize()
    } catch {
        _ = JSObject.global.console.error("HelloScene: SKRenderer.initialize failed: \(String(describing: error))")
        return
    }
    renderer.resize(width: CanvasConfig.width, height: CanvasConfig.height)

    let scene = HelloScene(size: CGSize(width: CanvasConfig.width, height: CanvasConfig.height))
    scene.scaleMode = .aspectFit
    renderer.scene = scene

    // SKRenderer drives rendering, but the scene still expects a didMove(to:) to
    // build its node tree — same handshake megaman uses.
    let view = SKView()
    scene.didMove(to: view)
    skRenderer = renderer

    let startTime = JSObject.global.performance.now().number ?? 0
    let callback = JSClosure { _ in
        // Re-arm before updating so a trap mid-frame can't kill the loop.
        if let cb = animationCallback {
            _ = JSObject.global.requestAnimationFrame!(cb)
        }
        let now = JSObject.global.performance.now().number ?? 0
        let t = (now - startTime) / 1000.0
        skRenderer?.update(atTime: t)
        skRenderer?.render()
        return .undefined
    }
    animationCallback = callback
    _ = JSObject.global.requestAnimationFrame!(callback)
}
#endif
