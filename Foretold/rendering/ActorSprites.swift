//
//  ActorSprites.swift
//  Foretold
//

// The sprite rig for the two things the art pass replaces first: a body that
// swaps pose with the way it's turned, and the weapon it holds. Every lookup
// is optional, so art can land one file at a time: a body with no art falls
// back to the shape the game has always drawn, and a weapon with no art is
// simply not drawn — which is what the board looked like before the rig.
//
// See ASSET_SPEC.md for the canvas, naming and orientation rules these
// lookups assume.
#if canImport(SpriteKit)
import SpriteKit
#else
import OpenSpriteKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// Which way a body is turned. The artist draws three poses per actor; `side`
/// is drawn facing right and the rig mirrors it for left, so there's no
/// left-facing art to keep in sync.
enum ActorPose: String {
    /// Turned toward the camera — the face is visible. Used when moving or
    /// aiming down the screen, and as the resting pose.
    case front
    /// Turned away — the back of the head. Used when moving or aiming up.
    case back
    /// Profile, drawn facing right. Used for left, right and every diagonal.
    case side
}

/// Texture lookup, naming and the hand/grip geometry that pins a weapon into
/// a body's hand. Namespace only — no instances.
enum Art {

    // MARK: - Lookup

    /// Flip to false to ignore every PNG and draw the shape placeholders, for
    /// A/B-ing new art against the placeholder read.
    nonisolated(unsafe) static var spritesEnabled = true

    /// Name → texture, including the misses (stored as nil) so a lookup for
    /// art that hasn't been drawn yet costs one dictionary hit, not a bundle
    /// search, on every refresh.
    nonisolated(unsafe) private static var cache: [String: SKTexture?] = [:]

    /// The texture for `name`, or nil when the artist hasn't delivered it yet.
    static func texture(_ name: String) -> SKTexture? {
        guard spritesEnabled else { return nil }
        if let cached = cache[name] { return cached }
        let loaded = load(name)
        cache[name] = loaded
        return loaded
    }

    /// True when a named texture is present — used to decide whether a body
    /// can go sprite-based at all (see `ActorNode`).
    static func hasTexture(_ name: String) -> Bool { texture(name) != nil }

    /// Hands the rig a texture under a name, for platforms that can't read an
    /// asset catalog. The web build fetches its PNGs at boot and registers
    /// them here before the scene is built; everywhere else this is unused.
    static func register(_ texture: SKTexture, named name: String) {
        cache[name] = texture
    }

    private static func load(_ name: String) -> SKTexture? {
        #if canImport(AppKit)
        // SKTexture(imageNamed:) happily hands back a placeholder for a name
        // that isn't in the catalog, so ask AppKit first — it answers nil.
        guard NSImage(named: name) != nil else { return nil }
        let texture = SKTexture(imageNamed: name)
        // Art is authored at 256px per tile and drawn at 48 or smaller — a 5×
        // minification, and over 7× on the 34pt HUD icon. Plain bilinear only
        // samples four texels, so at that ratio a thin diagonal edge samples
        // between the lines and crawls: outlines come out visibly wavy, worst
        // of all while a piece is sliding between tiles. Mipmaps give the GPU
        // pre-reduced levels to pick from, which is what actually fixes it.
        //
        // Set here rather than on the sprite because filtering lives on the
        // texture, and every use site (hand, floor drop, HUD icon) shares one.
        texture.usesMipmaps = true
        return texture
        #else
        // OpenSpriteKit has no bundle to search: anything it can resolve was
        // put there by `register`, and an unknown name yields an empty texture.
        let texture = SKTexture(imageNamed: name)
        return texture.size().width > 0 ? texture : nil
        #endif
    }

    // MARK: - Naming

    /// "Tipped Bow" → "tipped-bow". Keeps asset names derivable from the
    /// authored weapon names instead of a second list that can drift.
    static func slug(_ text: String) -> String {
        var slug = ""
        for character in text.lowercased() {
            if character.isLetter || character.isNumber {
                slug.append(character)
            } else if !slug.hasSuffix("-") {
                slug.append("-")
            }
        }
        while slug.hasSuffix("-") { slug.removeLast() }
        return slug
    }

    /// The sprite a weapon is drawn with: held in hand, lying on the floor,
    /// and shown as a HUD icon all read from this. A weapon may also supply a
    /// `-cooldown` variant — a bow with its arrow loosed, a crossbow
    /// mid-crank — shown while the attack is reloading.
    static func weaponTextureName(_ weapon: Weapon, ready: Bool = true) -> String {
        let base = "weapon-\(slug(weapon.name))"
        return ready ? base : "\(base)-cooldown"
    }

    /// The texture for a weapon in a given state. Weapons that never drew a
    /// cooldown variant just keep showing their ready art.
    static func weaponTexture(_ weapon: Weapon, ready: Bool = true) -> SKTexture? {
        if !ready, let reloading = texture(weaponTextureName(weapon, ready: false)) {
            return reloading
        }
        return texture(weaponTextureName(weapon))
    }

    /// The player's body sprites are "player-front" / "-back" / "-side".
    static let playerBodyID = "player"

    /// Enemy bodies are "enemy-<archetype>"; an armed bomber gets its own set
    /// so the lit fuse can be drawn rather than faked with a tint.
    static func bodyID(for archetype: Archetype, armed: Bool = false) -> String {
        let name: String
        switch archetype {
        case .fighter: name = "fighter"
        case .berserker: name = "berserker"
        case .swift: name = "swift"
        case .bomber: name = armed ? "bomber-armed" : "bomber"
        case .shieldbearer: name = "shieldbearer"
        case .reaver: name = "reaver"
        case .juggernaut: name = "juggernaut"
        case .boss: name = "boss"
        case .summoner: name = "summoner"
        case .bombardier: name = "bombardier"
        }
        return "enemy-\(name)"
    }

    static func bodyTextureName(_ bodyID: String, pose: ActorPose) -> String {
        "\(bodyID)-\(pose.rawValue)"
    }

    /// The best texture available for a body's pose. A set lands one pose at a
    /// time, so a miss falls through the other poses before giving up: the
    /// alternative is a body that blinks back to its placeholder every time it
    /// turns a way that hasn't been drawn yet, which reads as a bug rather than
    /// as missing art. A profile standing in for a front view is the better
    /// half-finished state.
    static func bodyTexture(_ bodyID: String, pose: ActorPose) -> SKTexture? {
        for candidate: ActorPose in [pose, .front, .side, .back] {
            if let texture = texture(bodyTextureName(bodyID, pose: candidate)) { return texture }
        }
        return nil
    }

    // MARK: - Projectiles

    /// Ammo in flight. `arrow` and `shell` are the two that matter; the rest
    /// are optional upgrades that fall back to the plain arrow, so the artist
    /// can draw one arrow now and specialise later.
    enum ProjectileArt {
        /// Any plain bolt — bow, crossbow, grapple line.
        case arrow
        /// Tipped Bow: leaves burning ground where it passes.
        case fireArrow
        /// Serrated Bow: leaves a bleed on whoever it hits.
        case barbedArrow
        /// Concussion Bow: blunt-tipped, dazes on impact.
        case bluntArrow
        /// Cannon and Explosive Crossbow: bursts where its flight ends.
        case cannonball
        /// A lobbed grenade or flask, arcing between tiles.
        case shell

        var textureName: String {
            switch self {
            case .arrow: return "projectile-arrow"
            case .fireArrow: return "projectile-arrow-fire"
            case .barbedArrow: return "projectile-arrow-barbed"
            case .bluntArrow: return "projectile-arrow-blunt"
            case .cannonball: return "projectile-cannonball"
            case .shell: return "projectile-shell"
            }
        }

        /// What stands in when this one hasn't been drawn. The shell is its
        /// own thing — an arrow would read as the wrong attack entirely.
        var fallback: ProjectileArt? {
            switch self {
            case .arrow, .shell: return nil
            default: return .arrow
            }
        }

        /// Arrows point where they're flying, so their art is authored
        /// pointing right and rotated to the flight angle. A lobbed shell is
        /// a tumbling object with no heading, so it's drawn as it lies.
        var rotatesToFlight: Bool { self != .shell }
    }

    /// Which ammo a bolt reads as. A `Bolt` doesn't carry the weapon that
    /// fired it, so this goes by what the shot does — which is what the art
    /// would be showing anyway.
    static func ammo(for bolt: Bolt) -> ProjectileArt {
        if bolt.impactBlastRadius > 0 { return .cannonball }
        if bolt.lingering != nil { return .fireArrow }
        if bolt.affliction != nil { return .barbedArrow }
        if bolt.stun > 0 { return .bluntArrow }
        return .arrow
    }

    static func texture(_ art: ProjectileArt) -> SKTexture? {
        texture(art.textureName) ?? art.fallback.flatMap { texture($0.textureName) }
    }

    // MARK: - Facing

    /// The pose a facing resolves to, and whether it's drawn mirrored — nil
    /// meaning "however it's mirrored now". Straight up and down carry no
    /// lateral information, so turning to face the camera (or away) shouldn't
    /// also swing the weapon hand across the body: the front and back poses
    /// keep whichever side the actor was already turned to.
    ///
    /// Diagonals take the side pose: the weapon is held horizontally, so a
    /// profile reads truer than a front-on body for an angled swing.
    static func pose(for direction: Direction) -> (pose: ActorPose, mirrored: Bool?) {
        let step = direction.unitStep
        if step.x == 0 { return (step.y > 0 ? .back : .front, nil) }
        return (.side, step.x < 0)
    }

    // MARK: - Geometry

    /// The footprint these hand offsets are quoted against: a rank-and-file
    /// enemy, half a tile across. Bigger bodies scale from it.
    static let referenceFootprint: CGFloat = 0.5

    /// Where the hand sits on the body, as a fraction of a tile from the
    /// body's centre, for a right-facing actor of reference size. Mirrored
    /// with the pose, and scaled by `handScale` for bodies of other sizes.
    static func hand(pose: ActorPose) -> CGPoint {
        switch pose {
        case .side: return CGPoint(x: 0.20, y: -0.03)
        case .front: return CGPoint(x: 0.22, y: -0.05)
        case .back: return CGPoint(x: 0.22, y: -0.02)
        }
    }

    /// How far out the hand moves for a body of `footprint` tiles. A boss is
    /// 0.85 of a tile across against a fighter's 0.5, so a fixed offset would
    /// bury its weapon in its chest; the hand rides out with the body instead.
    static func handScale(footprint: CGFloat) -> CGFloat {
        max(0.5, footprint / referenceFootprint)
    }

    /// How much bigger the weapon itself is drawn in that hand. Damped
    /// against the body scale — a juggernaut should swing something visibly
    /// heavier than a fighter's, without a boss brandishing a sprite twice
    /// the size of the tile it stands on.
    static func weaponScale(footprint: CGFloat) -> CGFloat {
        handScale(footprint: footprint).squareRoot()
    }

    /// Per-weapon grip overrides, in tile fractions from the sprite canvas's
    /// centre. The formula below reads a weapon's reach as haft length, which
    /// is right for anything swung and wrong for anything drawn or thrown: a
    /// bow is held at the middle of its limb however far it shoots, and a
    /// flask sits in the palm. A weapon whose art wants a different balance
    /// point gets one line here rather than a redraw.
    nonisolated(unsafe) static var gripOverrides: [String: CGPoint] = [
        // Measured off the delivered art: the hilt sits low-left of centre,
        // because the blade is drawn running up to the top-right corner.
        Weapon.sword.name: CGPoint(x: -0.18, y: -0.105),
        Weapon.bow.name: CGPoint(x: -0.06, y: 0),
        Weapon.tippedBow.name: CGPoint(x: -0.06, y: 0),
        Weapon.serratedBow.name: CGPoint(x: -0.06, y: 0),
        Weapon.concussionBow.name: CGPoint(x: -0.06, y: 0),
        Weapon.crossbow.name: CGPoint(x: -0.10, y: 0),
        Weapon.explosiveCrossbow.name: CGPoint(x: -0.10, y: 0),
        Weapon.cannon.name: CGPoint(x: -0.10, y: 0),
        Weapon.grapple.name: CGPoint(x: -0.10, y: 0),
        Weapon.grenade.name: CGPoint(x: 0, y: 0),
        Weapon.poisonPotion.name: CGPoint(x: 0, y: 0),
        Weapon.keg.name: CGPoint(x: 0, y: 0),
        Weapon.vortex.name: CGPoint(x: 0, y: 0),
    ]

    /// The point on the weapon art the hand closes around, in tile fractions
    /// from the canvas centre (art is authored pointing right). Longer hafts
    /// are gripped further back so the reach reads from the silhouette.
    static func grip(for weapon: Weapon) -> CGPoint {
        if let override = gripOverrides[weapon.name] { return override }
        return CGPoint(x: -min(0.30, 0.10 + 0.04 * CGFloat(reach(of: weapon))), y: 0)
    }

    /// How far the weapon strikes, in tiles — stands in for haft length, and
    /// so for how far back the grip sits.
    static func reach(of weapon: Weapon) -> Int {
        if weapon.thrown != nil { return 1 }
        guard let pattern = weapon.attackPattern else { return 1 }
        let tiles = pattern.offsets.map { max(abs($0.x), abs($0.y)) }.max() ?? 1
        // A bow's pattern runs the width of the board; the object in the hand
        // doesn't, so cap what the silhouette has to express.
        return min(tiles, 4)
    }

}

/// A combatant on the board: the player or one enemy. Holds a body that swaps
/// pose with its facing and up to two weapons pinned to its hands.
///
/// The node itself never rotates and stays anchored on the tile centre, so the
/// scene can keep moving, scaling and fading it exactly as it did the bare
/// shape it replaces — and children hung off it (stun stars, shield plank) sit
/// in an unrotated frame.
final class ActorNode: SKNode {

    /// Asset prefix for this actor's body poses ("player", "enemy-fighter").
    private var bodyID: String
    private let tileSize: CGFloat

    /// Drawn while the pose sprites are missing; kept around so art can land
    /// for some archetypes and not others.
    private let placeholder: SKShapeNode
    /// The pose sprite, created only once there's art to put in it.
    private var bodySprite: SKSpriteNode?

    /// One per hand: the primary weapon, and the sidearm a boss carries. Each
    /// is positioned at the hand and mirrored with the pose; the art hangs off
    /// it offset by its grip, so the holder's origin *is* the grip point.
    private let primaryHolder = SKNode()
    private let secondaryHolder = SKNode()
    /// What each hand currently holds, weapon *and* readiness, so a reload
    /// swaps the art without rebuilding the hand on every refresh.
    private var primaryHeld: String?
    private var secondaryHeld: String?

    private(set) var pose: ActorPose = .front
    private(set) var mirrored = false

    /// The placeholder's authored colours, so a damage flash can be undone by
    /// setting the fill back to what it started as.
    private let baseFill: SKColor
    private let baseStroke: SKColor

    /// How much of a tile this body covers. Drives where its hand sits and
    /// how big the weapon in it is drawn, so a juggernaut doesn't hold a
    /// fighter's dagger halfway inside its own chest.
    private let footprint: CGFloat

    /// - Parameters:
    ///   - bodyID: asset prefix for the pose sprites.
    ///   - tileSize: one board tile in points; all art is authored tile-sized.
    ///   - footprint: the body's width as a fraction of a tile (0.5 for a
    ///     rank-and-file enemy, 0.85 for the boss).
    ///   - placeholder: the shape the game drew before there was art. Owned by
    ///     the rig from here on.
    init(bodyID: String, tileSize: CGFloat, footprint: CGFloat, placeholder: SKShapeNode) {
        self.bodyID = bodyID
        self.tileSize = tileSize
        self.footprint = footprint
        self.placeholder = placeholder
        self.baseFill = placeholder.fillColor
        self.baseStroke = placeholder.strokeColor
        super.init()
        addChild(placeholder)
        addChild(primaryHolder)
        addChild(secondaryHolder)
        applyPose()
    }

    // Apple's SKNode is NSCoding; OpenSpriteKit's isn't (and the web build has
    // no NSCoder), so the unused requirement is satisfied only where it exists.
    #if canImport(SpriteKit)
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }
    #endif

    // MARK: - Facing

    /// Turns the body to `direction`; nil leaves it as it stands, so an actor
    /// that neither moves nor swings keeps looking where it last looked.
    func face(_ direction: Direction?) {
        guard let direction else { return }
        let resolved = Art.pose(for: direction)
        // A facing with no lateral component leaves the mirror alone.
        let newMirror = resolved.mirrored ?? mirrored
        guard resolved.pose != pose || newMirror != mirrored else { return }
        pose = resolved.pose
        mirrored = newMirror
        applyPose()
    }

    /// Swaps the body art — an armed bomber is a different sprite set, not a
    /// tint on the calm one.
    func setBodyID(_ id: String) {
        guard id != bodyID else { return }
        bodyID = id
        applyPose()
    }

    private func applyPose() {
        // Fall back a pose at a time, then to the placeholder shape. A set with
        // only one pose drawn shows it for every facing.
        let texture = Art.bodyTexture(bodyID, pose: pose)

        if let texture {
            let sprite: SKSpriteNode
            if let existing = bodySprite {
                sprite = existing
            } else {
                sprite = SKSpriteNode(texture: nil, color: .clear,
                                      size: CGSize(width: tileSize, height: tileSize))
                sprite.zPosition = 0
                addChild(sprite)
                bodySprite = sprite
            }
            sprite.texture = texture
            sprite.isHidden = false
            sprite.xScale = mirrored ? -1 : 1
            placeholder.isHidden = true
        } else {
            bodySprite?.isHidden = true
            placeholder.isHidden = false
        }

        layOutWeapons()
    }

    // MARK: - Weapons

    /// Puts `weapon` in the main hand and `secondary` (a boss's cannon) in the
    /// other. Passing nil empties the hand. `ready` is false while the attack
    /// is on cooldown, which picks the weapon's reloading art if it has any.
    func hold(_ weapon: Weapon?, ready: Bool = true,
              secondary: Weapon? = nil, secondaryReady: Bool = true) {
        let primaryKey = weapon.map { "\($0.name)|\(ready)" }
        if primaryKey != primaryHeld {
            primaryHeld = primaryKey
            build(weapon, ready: ready, in: primaryHolder)
        }
        let secondaryKey = secondary.map { "\($0.name)|\(secondaryReady)" }
        if secondaryKey != secondaryHeld {
            secondaryHeld = secondaryKey
            build(secondary, ready: secondaryReady, in: secondaryHolder)
        }
        layOutWeapons()
    }

    /// Builds one hand's contents. A weapon with no art yet holds nothing —
    /// the board looks the way it did before the rig landed, rather than
    /// sprouting stand-in shapes next to the real sprites.
    private func build(_ weapon: Weapon?, ready: Bool, in holder: SKNode) {
        holder.removeAllChildren()
        guard let weapon, let texture = Art.weaponTexture(weapon, ready: ready) else { return }

        // Bigger bodies carry bigger weapons, so the art scales with them —
        // and the grip offset has to scale by the same factor, since it's
        // quoted against the sprite's own canvas.
        let scale = Art.weaponScale(footprint: footprint)
        let sprite = SKSpriteNode(texture: texture, color: .clear,
                                  size: CGSize(width: tileSize * scale, height: tileSize * scale))
        // The holder sits on the hand, so shift the art until its grip point
        // lands there.
        let grip = Art.grip(for: weapon)
        sprite.position = CGPoint(x: -grip.x * tileSize * scale, y: -grip.y * tileSize * scale)
        holder.addChild(sprite)
    }

    /// Re-pins both hands after a pose change: hand position, mirroring, and
    /// whether the weapon passes in front of the body or behind it.
    private func layOutWeapons() {
        let reference = Art.hand(pose: pose)
        let reach = Art.handScale(footprint: footprint)
        let hand = CGPoint(x: reference.x * reach, y: reference.y * reach)
        let flip: CGFloat = mirrored ? -1 : 1
        // Facing away, the weapon is on the far side of the body.
        let depth: CGFloat = pose == .back ? -1 : 1

        primaryHolder.position = CGPoint(x: hand.x * tileSize * flip, y: hand.y * tileSize)
        primaryHolder.xScale = flip
        primaryHolder.zPosition = depth

        // The off hand: same height, mirrored across the body's centre, and
        // always behind it so the two don't fight for the same silhouette.
        secondaryHolder.position = CGPoint(x: -hand.x * tileSize * flip * 0.7, y: hand.y * tileSize)
        secondaryHolder.xScale = flip
        secondaryHolder.zPosition = -1
    }

    // MARK: - Tinting

    /// The body's fill. Tints the pose sprite when there is one and repaints
    /// the placeholder otherwise, so damage flashes work either way; setting
    /// it back to the colour it started with clears the tint.
    var bodyFillColor: SKColor {
        get { placeholder.fillColor }
        set {
            placeholder.fillColor = newValue
            guard let bodySprite else { return }
            if newValue == baseFill {
                bodySprite.colorBlendFactor = 0
            } else {
                bodySprite.color = newValue
                bodySprite.colorBlendFactor = 0.7
            }
        }
    }

    /// The placeholder's outline. Sprites have their outline drawn in, so this
    /// only moves the placeholder — the armed-bomber sprite set carries the
    /// same warning in its art.
    var bodyStrokeColor: SKColor {
        get { placeholder.strokeColor }
        set { placeholder.strokeColor = newValue }
    }

    /// Puts both colours back the way they were authored.
    func clearTint() {
        bodyFillColor = baseFill
        bodyStrokeColor = baseStroke
    }
}
