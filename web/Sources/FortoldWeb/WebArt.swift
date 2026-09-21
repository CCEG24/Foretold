//
//  WebArt.swift
//  FortoldWeb — sprite loading for the browser (WASM only)
//
//  The mac build reads its art out of an asset catalog. There isn't one here:
//  OpenSpriteKit's SKTexture(imageNamed:) searches Bundle.main, which traps
//  under WASI. So the page ships the PNGs next to the wasm, this fetches them
//  at boot, and hands each one to `Art.register` — the same cache the rig
//  reads. Anything that fails to load just stays a placeholder shape.

import OpenSpriteKit
import OpenFoundation
import JavaScriptKit

enum WebArt {

    /// Where build.sh drops the sprites, and the manifest listing them.
    private static let directory = "assets"
    private static let manifest = "assets/manifest.json"

    /// How many sprites are live, so the per-second frame log can say whether
    /// it's measuring a run with art or without.
    nonisolated(unsafe) static var registered = 0

    /// Every texture that loaded, kept for the prewarm pass below.
    nonisolated(unsafe) private static var loaded: [SKTexture] = []

    /// Fetches every sprite named in the manifest and registers it with the
    /// rig. Returns how many landed. Never throws: art is optional by design,
    /// so a missing manifest or a bad file costs a placeholder, not a scene.
    ///
    /// Must finish before the scene is built — `ActorNode` reads the cache as
    /// it constructs each body, and nothing re-reads it afterwards.
    static func preload() async -> (loaded: Int, failed: Int) {
        // ?noart (or #noart) skips the whole thing, so one build can be
        // compared with and without sprites — the quickest way to tell a cost
        // that comes from the textures from one that comes from the scene.
        let query = JSObject.global.location.search.string ?? ""
        let hash = JSObject.global.location.hash.string ?? ""
        if query.contains("noart") || hash.contains("noart") {
            log("skipped (noart)")
            registered = 0
            return (0, 0)
        }
        guard let names = await manifestNames() else { return (0, 0) }
        var loaded = 0
        var failed = 0
        for name in names {
            if let texture = await texture(named: name) {
                Art.register(texture, named: name)
                Self.loaded.append(texture)
                loaded += 1
                registered = loaded
            } else {
                failed += 1
                log("couldn't load \(name)")
            }
        }
        return (loaded, failed)
    }

    // MARK: - Prewarming

    /// Draws every loaded sprite once, off the back of the loading screen.
    ///
    /// A texture costs its upload and its mipmap chain the first time the
    /// renderer actually draws it, not when it's decoded — which is why the
    /// first seconds of play stuttered while the board's art warmed up. Doing
    /// it here moves that cost behind the loader, where a stall is just a
    /// slightly longer wait.
    ///
    /// The sprites are laid across the canvas rather than parked off-screen:
    /// anything outside the frame may be culled, and a culled sprite is never
    /// uploaded, which would defeat the whole exercise.
    @MainActor
    static func prewarm(in scene: SKScene, renderer: SKRenderer) {
        guard !loaded.isEmpty else { return }
        let warmup = SKNode()
        warmup.zPosition = -1_000    // behind the board, and gone before the first real frame
        let side: CGFloat = 48       // about the size the board draws them at
        let columns = max(1, Int(scene.size.width / side))
        for (index, texture) in loaded.enumerated() {
            let sprite = SKSpriteNode(texture: texture, color: .clear,
                                      size: CGSize(width: side, height: side))
            sprite.position = CGPoint(
                x: side / 2 + CGFloat(index % columns) * side,
                y: side / 2 + CGFloat(index / columns) * side
            )
            warmup.addChild(sprite)
        }
        scene.addChild(warmup)
        renderer.update(atTime: 0)
        renderer.render()
        warmup.removeFromParent()
    }

    // MARK: - Fetching

    /// The sprite names the page shipped, or nil when there's no manifest —
    /// which is the normal state of a build with no art in it yet.
    private static func manifestNames() async -> [String]? {
        guard let body = await fetchText(manifest) else { return nil }
        guard let parsed = try? JSObject.global.JSON.object?.parse?(body),
              let count = parsed.length.number else {
            log("manifest isn't a JSON array")
            return nil
        }
        return (0..<Int(count)).compactMap { parsed[$0].string }
    }

    private static func texture(named name: String) async -> SKTexture? {
        guard let bytes = await fetchBytes("\(directory)/\(name).png") else { return nil }
        // The fork decodes the PNG itself (OpenImageIO behind CGImageSource).
        return SKTexture(imageData: Data(bytes))
    }

    private static func fetchText(_ path: String) async -> String? {
        guard let response = await fetch(path) else { return nil }
        guard let promise = response.text?().object.flatMap(JSPromise.init(_:)),
              let value = try? await promise.value else { return nil }
        return value.string
    }

    private static func fetchBytes(_ path: String) async -> [UInt8]? {
        guard let response = await fetch(path) else { return nil }
        guard let promise = response.arrayBuffer?().object.flatMap(JSPromise.init(_:)),
              let buffer = try? await promise.value,
              let constructor = JSObject.global.Uint8Array.function else { return nil }
        let view = JSTypedArray<UInt8>(unsafelyWrapping: constructor.new(buffer))
        var bytes = [UInt8](repeating: 0, count: view.length)
        bytes.withUnsafeMutableBufferPointer { view.copyMemory(to: $0) }
        return bytes
    }

    /// A fetch that answers nil for anything but a 200 — a static host serves
    /// index.html for unknown paths, so a missing file arrives as HTML rather
    /// than as an error, and would otherwise decode into nonsense.
    private static func fetch(_ path: String) async -> JSObject? {
        guard let fetchFunction = JSObject.global.fetch.function else { return nil }
        guard let promise = fetchFunction(path).object.flatMap(JSPromise.init(_:)),
              let value = try? await promise.value,
              let response = value.object,
              response.ok.boolean == true else { return nil }
        return response
    }

    private static func log(_ message: String) {
        _ = JSObject.global.console.warn("FortoldWeb art: \(message)")
    }
}
