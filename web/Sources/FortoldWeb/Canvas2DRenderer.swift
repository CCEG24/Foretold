//
//  Canvas2DRenderer.swift
//  FortoldWeb — Canvas 2D presenter for the OpenSpriteKit node tree (WASM only)
//
//  OpenSpriteKit's only browser presenter is its WebGPU path, which rules out
//  Firefox, older Safari, managed machines with GPU acceleration disabled, and
//  anything behind a blocklisted driver. Foretold's scene is flat 2D: solid
//  and textured sprites, filled/stroked paths, and text — everything the
//  plain <canvas> 2D context has done for fifteen years.
//
//  So the frame cycle is split in two:
//    - `SKRenderer.update(atTime:)` keeps running the SpriteKit update loop
//      (scene.update, SKActions, callbacks). That part never touches the GPU.
//    - This class replaces `SKRenderer.render()`: it walks the node tree in
//      z-order (the same ordering `SKRenderer.renderToCGImage` uses) and draws
//      each node with Canvas 2D calls.
//
//  Only public OpenSpriteKit API is read (position/rotation/scale/alpha,
//  sprite texture/size/anchor/color, shape path/fill/stroke, label text/font/
//  alignment), so the engine deps stay pinned and unpatched for this.
//
//  Coordinates: SpriteKit is y-up with the origin bottom-left; canvas is y-down
//  top-left. The base transform flips Y once; images and text (which must not
//  be drawn upside down) re-flip locally when they're emitted.

import OpenSpriteKit
import JavaScriptKit

/// A 2×3 affine in Canvas `setTransform(a, b, c, d, e, f)` layout:
/// x' = a·x + c·y + e,  y' = b·x + d·y + f.
private struct Affine {
    var a: Double, b: Double, c: Double, d: Double, e: Double, f: Double

    static let identity = Affine(a: 1, b: 0, c: 0, d: 1, e: 0, f: 0)
    /// Mirrors Y about the local origin — turns a y-up frame into y-down.
    static let flipY = Affine(a: 1, b: 0, c: 0, d: -1, e: 0, f: 0)

    /// `self` applied first, then `outer`.
    func then(_ outer: Affine) -> Affine {
        Affine(
            a: a * outer.a + b * outer.c,
            b: a * outer.b + b * outer.d,
            c: c * outer.a + d * outer.c,
            d: c * outer.b + d * outer.d,
            e: e * outer.a + f * outer.c + outer.e,
            f: e * outer.b + f * outer.d + outer.f
        )
    }

    /// SpriteKit's node transform: scale, then rotate, then translate.
    static func node(position: CGPoint, rotation: CGFloat, xScale: CGFloat, yScale: CGFloat) -> Affine {
        let cs = Double(cos(rotation)), sn = Double(sin(rotation))
        let sx = Double(xScale), sy = Double(yScale)
        return Affine(
            a: sx * cs, b: sx * sn,
            c: -sy * sn, d: sy * cs,
            e: Double(position.x), f: Double(position.y)
        )
    }
}

@MainActor
final class Canvas2DRenderer {

    /// The scene to draw. Set by the bootstrap after `didMove(to:)`.
    var scene: SKScene?

    private let canvas: JSObject
    private let ctx: JSObject
    private let sceneWidth: Double
    private let sceneHeight: Double

    /// Backing-store size in device pixels and the scene→pixel transform.
    private var pixelWidth: Double = 0
    private var pixelHeight: Double = 0
    private var base = Affine.identity

    // Last-set context state, so unchanged styles don't cross the JS bridge
    // again. Property sets are the bulk of the per-node cost.
    private var lastFillStyle = ""
    private var lastStrokeStyle = ""
    private var lastFont = ""
    private var lastLineWidth = -1.0
    private var lastLineCap = ""
    private var lastLineJoin = ""
    private var lastAlpha = -1.0
    private var lastTextAlign = ""
    private var lastTextBaseline = ""

    /// Decoded textures as offscreen canvases, keyed by texture identity. The
    /// texture itself is retained alongside so its identifier can't be recycled
    /// onto a different texture while the entry is alive.
    private var textureCache: [ObjectIdentifier: (texture: SKTexture, canvas: JSObject?)] = [:]
    /// Tinted variants (colorBlendFactor > 0), keyed by texture + colour.
    private var tintCache: [String: JSObject] = [:]
    /// `Path2D` objects for shape paths, keyed by path identity.
    private var pathCache: [ObjectIdentifier: (path: CGPath, path2D: JSObject)] = [:]

    /// The failure reason when the 2D context can't be created — the page shows it.
    enum Failure: Error, CustomStringConvertible {
        case noContext
        var description: String { "canvas.getContext('2d') returned null" }
    }

    init(canvas: JSObject, sceneWidth: Int, sceneHeight: Int) throws {
        self.canvas = canvas
        self.sceneWidth = Double(sceneWidth)
        self.sceneHeight = Double(sceneHeight)
        // `alpha: false` lets the browser skip compositing the canvas against
        // the page; the scene paints every pixel anyway.
        let options = JSObject.global.Object.function!.new()
        options.alpha = .boolean(false)
        guard let context = canvas.getContext!("2d", options).object else {
            throw Failure.noContext
        }
        self.ctx = context
        resizeBackingStore()
    }

    // MARK: - Sizing

    /// Sizes the backing store to the canvas's CSS box × devicePixelRatio (capped
    /// at 2 — the board is authored at 1680×900 and 4× that is just memory), and
    /// rebuilds the scene→pixel transform. Cheap to call every frame.
    func resizeBackingStore() {
        let rect = canvas.getBoundingClientRect!()
        var cssW = rect.width.number ?? sceneWidth
        var cssH = rect.height.number ?? sceneHeight
        if cssW <= 0 || cssH <= 0 { cssW = sceneWidth; cssH = sceneHeight }
        let dpr = min(2.0, max(1.0, JSObject.global.devicePixelRatio.number ?? 1))
        let pw = (cssW * dpr).rounded(), ph = (cssH * dpr).rounded()
        if pw != pixelWidth || ph != pixelHeight {
            pixelWidth = pw
            pixelHeight = ph
            canvas.width = .number(pw)
            canvas.height = .number(ph)
            // Resizing resets all context state.
            resetStyleCache()
        }
        // aspectFit: uniform scale, letterboxed and centred.
        let k = min(pixelWidth / sceneWidth, pixelHeight / sceneHeight)
        let offX = (pixelWidth - sceneWidth * k) / 2
        let offY = (pixelHeight - sceneHeight * k) / 2
        base = Affine(a: k, b: 0, c: 0, d: -k, e: offX, f: pixelHeight - offY)
    }

    private func resetStyleCache() {
        lastFillStyle = ""; lastStrokeStyle = ""; lastFont = ""
        lastLineWidth = -1; lastLineCap = ""; lastLineJoin = ""
        lastAlpha = -1; lastTextAlign = ""; lastTextBaseline = ""
    }

    // MARK: - Frame

    private struct Item {
        let node: SKNode
        let z: CGFloat
        let alpha: CGFloat
        let transform: Affine
        let order: Int
    }

    func render() {
        guard let scene else { return }
        resizeBackingStore()

        // Background: cover the whole backing store (letterbox included), so
        // the bars match the scene rather than showing stale pixels.
        _ = ctx.setTransform!(1, 0, 0, 1, 0, 0)
        setAlpha(1)
        setFill(css(scene.backgroundColor))
        _ = ctx.fillRect!(0, 0, pixelWidth, pixelHeight)

        var items: [Item] = []
        items.reserveCapacity(512)
        // The scene's own position/anchor don't contribute in SpriteKit; its
        // children are placed directly in scene space.
        for child in scene.children.sorted(by: { $0.zPosition < $1.zPosition }) {
            collect(child, z: 0, alpha: CGFloat(scene.alpha), parent: base, into: &items)
        }
        items.sort { lhs, rhs in
            lhs.z != rhs.z ? lhs.z < rhs.z : lhs.order < rhs.order
        }

        for item in items {
            draw(item)
        }
    }

    private func collect(_ node: SKNode, z: CGFloat, alpha: CGFloat, parent: Affine, into items: inout [Item]) {
        guard !node.isHidden, node.alpha > 0 else { return }
        let nodeZ = z + node.zPosition
        let nodeAlpha = alpha * node.alpha
        let world = Affine.node(position: node.position, rotation: node.zRotation,
                                xScale: node.xScale, yScale: node.yScale).then(parent)
        items.append(Item(node: node, z: nodeZ, alpha: nodeAlpha, transform: world, order: items.count))
        // Children carry the parent's accumulated z; siblings at equal z keep
        // insertion order (stable sort by zPosition).
        let children = node.children
        if children.isEmpty { return }
        let sorted = children.count > 1 ? children.sorted(by: { $0.zPosition < $1.zPosition }) : children
        for child in sorted {
            collect(child, z: nodeZ, alpha: nodeAlpha, parent: world, into: &items)
        }
    }

    private func draw(_ item: Item) {
        // Order matters: SKLabelNode and SKShapeNode are siblings under SKNode,
        // SKSpriteNode too — but check the concrete leaf types before anything
        // that might be a superclass in future engine versions.
        if let label = item.node as? SKLabelNode {
            drawLabel(label, item)
        } else if let shape = item.node as? SKShapeNode {
            drawShape(shape, item)
        } else if let sprite = item.node as? SKSpriteNode {
            drawSprite(sprite, item)
        }
        // Plain SKNode / SKScene / SKEffectNode containers draw nothing themselves.
    }

    // MARK: - Sprites

    private func drawSprite(_ sprite: SKSpriteNode, _ item: Item) {
        let size = sprite.size
        guard size.width > 0, size.height > 0 else { return }
        let w = Double(size.width), h = Double(size.height)
        let ax = Double(sprite.anchorPoint.x), ay = Double(sprite.anchorPoint.y)

        if let texture = sprite.texture, let image = canvasImage(for: texture) {
            // Images draw y-down: flip the local frame and place the top edge
            // at the sprite's top (scene y = h·(1−ay)).
            setTransform(Affine.flipY.then(item.transform))
            setAlpha(Double(item.alpha))
            let x = -w * ax, y = -h * (1 - ay)
            _ = ctx.drawImage!(image, x, y, w, h)
            if sprite.colorBlendFactor > 0, sprite.color.alpha > 0,
               let tinted = tintedImage(for: texture, base: image, color: sprite.color) {
                setAlpha(Double(item.alpha) * min(1, Double(sprite.colorBlendFactor)))
                _ = ctx.drawImage!(tinted, x, y, w, h)
            }
            return
        }

        // Untextured sprite: a solid quad in the sprite's colour.
        guard sprite.color.alpha > 0 else { return }
        setTransform(item.transform)
        setAlpha(Double(item.alpha))
        setFill(css(sprite.color))
        _ = ctx.fillRect!(-w * ax, -h * ay, w, h)
    }

    /// The texture decoded into an offscreen canvas, or nil when it has no
    /// pixels (OpenSpriteKit hands back empty textures for unknown names).
    private func canvasImage(for texture: SKTexture) -> JSObject? {
        let key = ObjectIdentifier(texture)
        if let cached = textureCache[key] { return cached.canvas }
        let built = buildCanvas(from: texture)
        if textureCache.count > 256 { textureCache.removeAll(keepingCapacity: true) }
        textureCache[key] = (texture, built)
        return built
    }

    private func buildCanvas(from texture: SKTexture) -> JSObject? {
        guard let image = texture.cgImage(), let data = image.data,
              image.width > 0, image.height > 0 else { return nil }
        let width = image.width, height = image.height
        let bytesPerRow = image.bytesPerRow
        let premultiplied: Bool
        switch image.alphaInfo {
        case .premultipliedLast, .premultipliedFirst: premultiplied = true
        default: premultiplied = false
        }
        let alphaFirst: Bool
        switch image.alphaInfo {
        case .premultipliedFirst, .first, .noneSkipFirst: alphaFirst = true
        default: alphaFirst = false
        }
        guard image.bitsPerPixel == 32, bytesPerRow >= width * 4 else { return nil }

        // Repack into tightly-packed straight-alpha RGBA, which is what
        // ImageData expects.
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        data.withUnsafeBytes { (src: UnsafeRawBufferPointer) in
            guard let base = src.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            var dst = 0
            for y in 0..<height {
                var s = y * bytesPerRow
                for _ in 0..<width {
                    var r: UInt8, g: UInt8, b: UInt8
                    let a: UInt8
                    if alphaFirst {
                        a = base[s]; r = base[s + 1]; g = base[s + 2]; b = base[s + 3]
                    } else {
                        r = base[s]; g = base[s + 1]; b = base[s + 2]; a = base[s + 3]
                    }
                    if premultiplied, a > 0, a < 255 {
                        let inv = 255.0 / Double(a)
                        r = UInt8(min(255, Double(r) * inv))
                        g = UInt8(min(255, Double(g) * inv))
                        b = UInt8(min(255, Double(b) * inv))
                    }
                    rgba[dst] = r; rgba[dst + 1] = g; rgba[dst + 2] = b; rgba[dst + 3] = a
                    dst += 4
                    s += 4
                }
            }
        }

        let pixels = JSUInt8ClampedArray(rgba)
        let imageData = JSObject.global.ImageData.function!.new(pixels.jsObject, width, height)
        let offscreen = JSObject.global.document.createElement!("canvas").object!
        offscreen.width = .number(Double(width))
        offscreen.height = .number(Double(height))
        guard let octx = offscreen.getContext!("2d").object else { return nil }
        _ = octx.putImageData!(imageData, 0, 0)
        return offscreen
    }

    /// The texture with `color` multiplied in, alpha preserved — drawn on top of
    /// the untinted image at `colorBlendFactor` opacity to approximate
    /// SpriteKit's blend. Only the tinted state of a handful of sprites ever
    /// hits this, so the cache stays tiny.
    private func tintedImage(for texture: SKTexture, base: JSObject, color: SKColor) -> JSObject? {
        let key = "\(ObjectIdentifier(texture).hashValue)|\(css(color))"
        if let cached = tintCache[key] { return cached }
        let width = base.width.number ?? 0, height = base.height.number ?? 0
        guard width > 0, height > 0 else { return nil }
        let offscreen = JSObject.global.document.createElement!("canvas").object!
        offscreen.width = .number(width)
        offscreen.height = .number(height)
        guard let octx = offscreen.getContext!("2d").object else { return nil }
        _ = octx.drawImage!(base, 0, 0)
        octx.globalCompositeOperation = .string("multiply")
        octx.fillStyle = .string(css(SKColor(red: color.red, green: color.green, blue: color.blue, alpha: 1)))
        _ = octx.fillRect!(0, 0, width, height)
        octx.globalCompositeOperation = .string("destination-in")
        _ = octx.drawImage!(base, 0, 0)
        if tintCache.count > 128 { tintCache.removeAll(keepingCapacity: true) }
        tintCache[key] = offscreen
        return offscreen
    }

    // MARK: - Shapes

    private func drawShape(_ shape: SKShapeNode, _ item: Item) {
        guard let path = shape.path else { return }
        let fills = shape.fillColor.alpha > 0
        let strokes = shape.strokeColor.alpha > 0 && shape.lineWidth > 0
        guard fills || strokes else { return }
        let path2D = path2D(for: path)

        setTransform(item.transform)
        setAlpha(Double(item.alpha))
        if fills {
            setFill(css(shape.fillColor))
            _ = ctx.fill!(path2D)
        }
        if strokes {
            setStroke(css(shape.strokeColor))
            setLineWidth(Double(shape.lineWidth))
            setLineCap(shape.lineCap)
            setLineJoin(shape.lineJoin)
            _ = ctx.stroke!(path2D)
        }
    }

    private func path2D(for path: CGPath) -> JSObject {
        let key = ObjectIdentifier(path)
        if let cached = pathCache[key], cached.path === path { return cached.path2D }
        let p = JSObject.global.Path2D.function!.new()
        path.applyWithBlock { elementPointer in
            let element = elementPointer.pointee
            switch element.type {
            case .moveToPoint:
                let pt = element.points![0]
                _ = p.moveTo!(Double(pt.x), Double(pt.y))
            case .addLineToPoint:
                let pt = element.points![0]
                _ = p.lineTo!(Double(pt.x), Double(pt.y))
            case .addQuadCurveToPoint:
                let c = element.points![0], e = element.points![1]
                _ = p.quadraticCurveTo!(Double(c.x), Double(c.y), Double(e.x), Double(e.y))
            case .addCurveToPoint:
                let c1 = element.points![0], c2 = element.points![1], e = element.points![2]
                _ = p.bezierCurveTo!(Double(c1.x), Double(c1.y), Double(c2.x), Double(c2.y),
                                     Double(e.x), Double(e.y))
            case .closeSubpath:
                _ = p.closePath!()
            }
        }
        // Transient paths (per-turn telegraph lines, hit flashes) churn through
        // here; bound the cache rather than let it track every path ever made.
        if pathCache.count > 1024 { pathCache.removeAll(keepingCapacity: true) }
        pathCache[key] = (path, p)
        return p
    }

    // MARK: - Labels

    private func drawLabel(_ label: SKLabelNode, _ item: Item) {
        guard let text = label.text, !text.isEmpty else { return }
        let color = label.fontColor ?? .white
        guard color.alpha > 0 else { return }
        let fontSize = label.fontSize
        guard fontSize > 0 else { return }

        let font = CATextMetrics.cssFont(name: label.fontName, size: fontSize)
        setFont(font)

        // Line layout: explicit breaks always split; word-wrap only when the
        // label is multi-line and has a wrapping width, as on SpriteKit.
        var lines: [String] = []
        let wrapWidth = label.numberOfLines != 1 ? Double(label.preferredMaxLayoutWidth) : 0
        for paragraph in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if wrapWidth > 0 {
                lines.append(contentsOf: wrap(String(paragraph), width: wrapWidth))
            } else {
                lines.append(String(paragraph))
            }
        }
        if label.numberOfLines > 0, lines.count > label.numberOfLines {
            lines = Array(lines.prefix(label.numberOfLines))
        }

        setTransform(Affine.flipY.then(item.transform))
        setAlpha(Double(item.alpha))
        setFill(css(color))
        switch label.horizontalAlignmentMode {
        case .left: setTextAlign("left")
        case .center: setTextAlign("center")
        case .right: setTextAlign("right")
        }

        let lineHeight = Double(fontSize) * 1.2
        let count = lines.count
        // In the flipped local frame, +y is down. Compute where line 0 sits.
        switch label.verticalAlignmentMode {
        case .baseline:
            // The last line's baseline is the node origin.
            setTextBaseline("alphabetic")
            for (index, line) in lines.enumerated() {
                let y = -Double(count - 1 - index) * lineHeight
                _ = ctx.fillText!(line, 0, y)
            }
        case .center, .top, .bottom:
            setTextBaseline("middle")
            let total = Double(count) * lineHeight
            let top: Double
            switch label.verticalAlignmentMode {
            case .top: top = 0
            case .bottom: top = -total
            default: top = -total / 2
            }
            for (index, line) in lines.enumerated() {
                let y = top + (Double(index) + 0.5) * lineHeight
                _ = ctx.fillText!(line, 0, y)
            }
        }
    }

    /// Greedy word wrap with the context's current font.
    private func wrap(_ paragraph: String, width: Double) -> [String] {
        if paragraph.isEmpty { return [""] }
        var lines: [String] = []
        var current = ""
        for word in paragraph.split(separator: " ", omittingEmptySubsequences: true) {
            let candidate = current.isEmpty ? String(word) : current + " " + String(word)
            if measure(candidate) > width, !current.isEmpty {
                lines.append(current)
                current = String(word)
            } else {
                current = candidate
            }
        }
        lines.append(current)
        return lines
    }

    private func measure(_ text: String) -> Double {
        ctx.measureText!(text).width.number ?? 0
    }

    // MARK: - Context state (deduplicated)

    private func setTransform(_ t: Affine) {
        _ = ctx.setTransform!(t.a, t.b, t.c, t.d, t.e, t.f)
    }

    private func setAlpha(_ alpha: Double) {
        let clamped = min(1, max(0, alpha))
        if clamped != lastAlpha { lastAlpha = clamped; ctx.globalAlpha = .number(clamped) }
    }

    private func setFill(_ style: String) {
        if style != lastFillStyle { lastFillStyle = style; ctx.fillStyle = .string(style) }
    }

    private func setStroke(_ style: String) {
        if style != lastStrokeStyle { lastStrokeStyle = style; ctx.strokeStyle = .string(style) }
    }

    private func setFont(_ font: String) {
        if font != lastFont { lastFont = font; ctx.font = .string(font) }
    }

    private func setLineWidth(_ width: Double) {
        if width != lastLineWidth { lastLineWidth = width; ctx.lineWidth = .number(width) }
    }

    private func setLineCap(_ cap: CGLineCap) {
        let value: String
        switch cap {
        case .butt: value = "butt"
        case .round: value = "round"
        case .square: value = "square"
        }
        if value != lastLineCap { lastLineCap = value; ctx.lineCap = .string(value) }
    }

    private func setLineJoin(_ join: CGLineJoin) {
        let value: String
        switch join {
        case .miter: value = "miter"
        case .round: value = "round"
        case .bevel: value = "bevel"
        }
        if value != lastLineJoin { lastLineJoin = value; ctx.lineJoin = .string(value) }
    }

    private func setTextAlign(_ align: String) {
        if align != lastTextAlign { lastTextAlign = align; ctx.textAlign = .string(align) }
    }

    private func setTextBaseline(_ baseline: String) {
        if baseline != lastTextBaseline { lastTextBaseline = baseline; ctx.textBaseline = .string(baseline) }
    }

    /// `rgba(r, g, b, a)` for a scene colour.
    private func css(_ color: SKColor) -> String {
        func channel(_ v: CGFloat) -> Int { Int((min(1, max(0, Double(v))) * 255).rounded()) }
        let alpha = min(1, max(0, Double(color.alpha)))
        return "rgba(\(channel(color.red)),\(channel(color.green)),\(channel(color.blue)),\(alpha))"
    }
}
