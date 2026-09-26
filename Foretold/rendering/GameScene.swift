//
//  GameScene.swift
//  Foretold
//

// SpriteKit on Apple platforms; the OpenSpriteKit shim (WebGPU) on WASM/web.
// The scene-graph API surface is identical, so the body below is shared.
#if canImport(SpriteKit)
import SpriteKit
#else
import OpenSpriteKit
#endif
// AppKit supplies NSEvent (input), NSFont/NSColor/NSAttributedString (text).
// The web target replaces these with DOM-backed equivalents, so anything that
// touches them is guarded on canImport(AppKit).
#if canImport(AppKit)
import AppKit
#endif

/// Renders the board and turns mouse/keyboard input into turn decisions.
/// All game rules live in GameState; this class only draws and animates.
class GameScene: SKScene {

    private var state = GameState()

    private let boardNode = SKNode()
    private var tileNodes: [GridPosition: SKSpriteNode] = [:]
    /// What each tile's colour was last computed from, so a repaint that would
    /// land on the same colour is skipped entirely. Cleared for any tile
    /// painted directly (a flash, a blocked spawn) so the next refresh
    /// restores it.
    ///
    /// This has to hold *every* input `tileColor` reads — anything missing here
    /// is a change the cache can't see. The biome was once left out, so a new
    /// level's floor only showed up tile by tile as highlights passed over it.
    private struct TileAppearance: Equatable {
        let isLegalTarget: Bool
        let isPlannedAttack: Bool
        let isEnemyThreat: Bool
        let hazardDamage: Int?
        let isThrowRange: Bool
        let isSpawnTelegraph: Bool
        let isPlannedDestination: Bool
        let isPlannedTarget: Bool
        let isHovered: Bool
        let biome: Biome
    }
    private var tileAppearances: [GridPosition: TileAppearance] = [:]
    /// The same idea for crumbling walls, which carry their telegraph in their
    /// own colour because the wall covers its tile.
    private enum WallTint { case base, attack, breach }
    private var wallTints: [GridPosition: WallTint] = [:]
    private var playerNode: ActorNode!
    private var enemyNodes: [Int: ActorNode] = [:]
    private var obstacleNodes: [GridPosition: SKNode] = [:]
    private var spikeNodes: [GridPosition: SKNode] = [:]
    private var teleporterNodes: [GridPosition: SKShapeNode] = [:]
    private var terrainNodes: [GridPosition: SKNode] = [:]
    private var planArrowNode: SKShapeNode?
    private var enemyPlanArrowNodes: [SKShapeNode] = []
    private var enemyInfoLabel: SKLabelNode?
    private var goButton: SKShapeNode!
    /// Bottom-left status: health/armor pip rows and the ultimate charge bar.
    private let healthBarNode = SKNode()
    private let armorBarNode = SKNode()
    private let ultimateBarNode = SKNode()
    private var dodgeChipLabel: SKLabelNode!
    private var afflictionLabel: SKLabelNode!
    /// The cold, on its own row under the ult bar. Kept out of
    /// `afflictionLabel` because frostbite *causes* a stun: the two would
    /// otherwise appear on the same line at the same moment, which is exactly
    /// when each needs to be read separately.
    private var freezeLabel: SKLabelNode!
    private var itemsLabel: SKLabelNode!
    private var scoreLabel: SKLabelNode!
    /// The pact row (boon + curse) as separate colored, hoverable pieces.
    private var pactHUD: SKNode!
    private var pactTooltip: SKLabelNode?
    private var pactTooltipMod: RunModifier?
    /// The strip the pact row occupies, in scene coordinates. Empty until the
    /// row is built, which is exactly when there's nothing to hover.
    private var pactHoverBounds: CGRect = .zero
    private var buffsLabel: SKLabelNode!
    /// The held-buffs row's resting colour, named so `flashBuffsRow` can always
    /// restore it rather than reading a possibly mid-flash value back.
    private static let buffsLabelColor = SKColor(red: 0.65, green: 0.85, blue: 0.65, alpha: 1.0)
    private var spawnMarkerNodes: [SKNode] = []
    private var weaponDropNodes: [SKNode] = []
    private var cacheNodes: [GridPosition: SKNode] = [:]
    /// Lob shell beads, keyed by projectile id — persistent so the resolve
    /// phase can glide them along their arc.
    private var lobNodes: [Int: SKNode] = [:]
    /// Where each airborne lob will land, for the landing dive animation.
    private var lobTargets: [Int: CGPoint] = [:]
    /// Bolt slivers, keyed by bolt id — persistent so the resolve phase can
    /// glide them along their flight.
    private var boltNodes: [Int: SKNode] = [:]
    private var weaponButton: SKShapeNode!
    private var weaponLabel: SKLabelNode!
    private var weaponSubLabel: SKLabelNode!
    private var weaponButtonIcon: SKSpriteNode!
    private var tileSize: CGFloat = 0

    private var hoveredTile: GridPosition?
    /// Hazard tiles (and their damage) as they looked before the current
    /// resolve; kept tinted through the animation phases so expired pools only
    /// visually dissipate at the end of the turn.
    private var heldHazardTiles: [GridPosition: Int]?
    /// True while the resolve phase animates; input is ignored until planning resumes.
    private var isResolving = false
    /// Sprite state held back during the resolve. The model resolves the whole
    /// turn in one go before a single frame animates, so without this every
    /// body turns and every weapon empties on the first frame — a bow would
    /// look spent while its arrow is still on the string. Each field is
    /// released on the beat that earns it.
    private struct ResolveHold {
        /// Weapon readiness as it stood before the turn resolved; released to
        /// the live value when that actor's attack plays.
        var playerWeaponReady: Bool
        var enemyWeaponReady: [Int: Bool] = [:]
        var enemySecondaryReady: [Int: Bool] = [:]
        /// The facing each actor is drawn with right now: along the move while
        /// they walk, onto their aim when they strike. Missing = leave it be.
        var playerFacing: Direction?
        var enemyFacing: [Int: Direction] = [:]
        /// The drafted aims, applied at the attack beat.
        var playerAim: Direction?
        var enemyAim: [Int: Direction] = [:]
        /// The drafted moves, applied when that actor starts walking.
        var enemyMoveFacing: [Int: Direction] = [:]
    }
    private var resolveHold: ResolveHold?

    /// Fraction of the smaller scene dimension the board occupies; the margin
    /// below the board leaves room for the GO button and HUD.
    private let boardScale: CGFloat = 0.8
    /// Max gap between R presses for a mid-run restart.
    private static let restartDoubleTapWindow: TimeInterval = 0.45
    private var lastRestartKeyTime: TimeInterval = 0
    /// The run's pact: empty, or exactly one boon + one curse. Persisted across
    /// runs and applied when the next run is generated.
    private var activeModifiers: Set<RunModifier> {
        get { Set(Defaults.standard.stringArray(forKey: "activeModifiers")?.compactMap(RunModifier.init(rawValue:)) ?? []) }
        set { Defaults.standard.set(newValue.map(\.rawValue).sorted(), forKey: "activeModifiers") }
    }
    /// The pact rolled for the current draft — remembered so toggling the pact
    /// off and on re-applies the same bargain rather than dodging the reroll cap.
    private var draftedPact: Set<RunModifier> = []
    /// Rerolls left this draft. The reroll button is the only way to a new pact.
    private static let maxPactRerolls = 3
    private var pactRerollsRemaining = maxPactRerolls
    /// Dev: forces the boon / curse halves of the next rolled pact (nil = random).
    private var devForcedPactBoon: RunModifier?
    private var devForcedPactCurse: RunModifier?
    // The dev panel cycles these one click at a time, so authored order makes a
    // named boon a hunt through the whole list. Sort by label for the panel
    // only — the live pools stay as authored, since gameplay draws from them.
    private var devPactBoons: [RunModifier] { RunModifier.boons.sorted { $0.title < $1.title } }
    private var devPactCurses: [RunModifier] { RunModifier.curses.sorted { $0.title < $1.title } }
    private var devLevelBoons: [Buff] { Buff.all.sorted { $0.name < $1.name } }
    /// A fresh pact: one boon paired with one curse. Either half can be pinned
    /// via the dev panel.
    private func rolledPact() -> Set<RunModifier> {
        guard let boon = devForcedPactBoon ?? RunModifier.boons.randomElement(),
              let curse = devForcedPactCurse ?? RunModifier.curses.randomElement() else { return [] }
        return [boon, curse]
    }
    /// The level-up boon chooser; input is captive while it's up.
    private var buffChoiceOverlay: SKNode?
    /// Floating "E · pick up" prompt above the weapon the player is standing on.
    private var pickupHintLabel: SKLabelNode?
    /// Set when this resolve's kills finished charging the ultimate; announced
    /// once the animations wrap up.
    private var pendingUltimateReadyToast = false
    /// Set when a boon was dug out this turn. The HUD row it landed in isn't
    /// repainted until the resolve finishes, so the flash that points at it has
    /// to wait for that repaint or it draws the eye to a row not yet showing
    /// the boon.
    private var pendingBuffRowFlash: SKColor?
    /// While false (early resolve phases), freshly painted pools stay hidden:
    /// the arrow that paints a trail must visibly cross the tiles first.
    private var revealLiveHazards = true
    /// Best score across runs, persisted in UserDefaults.
    private var highScore: Int {
        get { Defaults.standard.integer(forKey: "highScore") }
        set { Defaults.standard.set(newValue, forKey: "highScore") }
    }
    /// Elite trophies claimed across runs (by weapon name); once claimed they
    /// join every future run's weapon pool.
    private var claimedTrophyNames: Set<String> {
        get { Set(Defaults.standard.stringArray(forKey: "claimedTrophies") ?? []) }
        set { Defaults.standard.set(Array(newValue).sorted(), forKey: "claimedTrophies") }
    }
    /// Milestone weapons earned across runs (by weapon name).
    private var unlockedWeaponNames: Set<String> {
        get { Set(Defaults.standard.stringArray(forKey: "unlockedWeapons") ?? []) }
        set { Defaults.standard.set(Array(newValue).sorted(), forKey: "unlockedWeapons") }
    }
    /// Lifetime credited-kill tallies that gate the milestones.
    private var lifetimeTallies: [String: Int] {
        get { (Defaults.standard.dictionary(forKey: "lifetimeTallies") as? [String: Int]) ?? [:] }
        set { Defaults.standard.set(newValue, forKey: "lifetimeTallies") }
    }
    /// Lifetime tallies as they stood when this run began; the run's own
    /// tallies are folded on top after every turn.
    private var tallyBaseline: [String: Int] = [:]
    /// The launch title screen; input is captive while it's up.
    private var titleOverlay: SKNode?
    /// The settings overlay (natural scrolling, keybinds); modal while up.
    private var settingsOverlay: SKNode?
    /// The action currently listening for its next keypress to rebind (nil = not
    /// capturing).
    private var rebindingAction: KeyAction?

    /// A gameplay key the player can remap in settings. Each maps a keyCode.
    private enum KeyAction: String, CaseIterable {
        case resolve, swap, pickup, ultimate, restart
        var title: String {
            switch self {
            case .resolve: return "resolve turn"
            case .swap: return "swap weapon"
            case .pickup: return "pick up weapon"
            case .ultimate: return "omen (ultimate)"
            case .restart: return "restart run"
            }
        }
        /// The out-of-the-box keyCode (Space, Tab, E, F, R).
        var defaultCode: UInt16 {
            switch self {
            case .resolve: return 0x31
            case .swap: return 0x30
            case .pickup: return 0x0E
            case .ultimate: return 0x03
            case .restart: return 0x0F
            }
        }
    }

    /// Whether the wheel scrolls the side dropdowns "naturally" (content follows
    /// the fingers). Persisted so it survives launches.
    private var naturalScrolling: Bool {
        get { Defaults.standard.bool(forKey: "naturalScrolling") }
        set { Defaults.standard.set(newValue, forKey: "naturalScrolling") }
    }
    /// Fast-forwards every turn animation (sets the scene's action speed high) so
    /// resolutions resolve near-instantly. Persisted.
    private var skipAnimations: Bool {
        get { Defaults.standard.bool(forKey: "skipAnimations") }
        set { Defaults.standard.set(newValue, forKey: "skipAnimations") }
    }
    /// Whether a mid-run restart needs the double-tap confirmation (default on).
    /// Off = R restarts instantly at any time.
    private var confirmRestart: Bool {
        get { Defaults.standard.object(forKey: "confirmRestart") as? Bool ?? true }
        set { Defaults.standard.set(newValue, forKey: "confirmRestart") }
    }
    /// Whether picking a boon takes two clicks/presses (select, then confirm).
    private var confirmBoonChoice: Bool {
        get { Defaults.standard.bool(forKey: "confirmBoonChoice") }
        set { Defaults.standard.set(newValue, forKey: "confirmBoonChoice") }
    }
    /// Whether starting a run from the draft needs a confirming second press.
    private var confirmStartRun: Bool {
        get { Defaults.standard.bool(forKey: "confirmStartRun") }
        set { Defaults.standard.set(newValue, forKey: "confirmStartRun") }
    }
    /// Whether the SKView's FPS / node-count overlays are shown (default on).
    private var showFPS: Bool {
        get { Defaults.standard.object(forKey: "showFPS") as? Bool ?? true }
        set { Defaults.standard.set(newValue, forKey: "showFPS") }
    }
    /// Timestamp of the last "begin run" press awaiting its confirming repeat.
    private var lastStartConfirmTime: TimeInterval = 0
    /// The boon awaiting a confirming second click (nil = none pending).
    private var pendingBuffIndex: Int?
    /// Player keybind overrides, keyed by KeyAction.rawValue → keyCode. Missing
    /// entries fall back to the action's default.
    private var keyBindings: [String: Int] {
        get { Defaults.standard.dictionary(forKey: "keyBindings") as? [String: Int] ?? [:] }
        set { Defaults.standard.set(newValue, forKey: "keyBindings") }
    }
    /// The keyCode currently bound to an action (override or default).
    private func boundCode(for action: KeyAction) -> UInt16 {
        if let raw = keyBindings[action.rawValue] { return UInt16(raw) }
        return action.defaultCode
    }
    /// Human-readable name for a keyCode, for the settings list.
    private func keyName(_ code: UInt16) -> String {
        switch code {
        case 0x31: return "Space"
        case 0x24: return "Return"
        case 0x30: return "Tab"
        case 0x35: return "Esc"
        case 0x33: return "Delete"
        case 0x7B: return "←"
        case 0x7C: return "→"
        case 0x7D: return "↓"
        case 0x7E: return "↑"
        default:
            // Letter/number keys carry a stable code; map the common ones.
            let letters: [UInt16: String] = [
                0x00: "A", 0x0B: "B", 0x08: "C", 0x02: "D", 0x0E: "E", 0x03: "F",
                0x05: "G", 0x04: "H", 0x22: "I", 0x26: "J", 0x28: "K", 0x25: "L",
                0x2E: "M", 0x2D: "N", 0x1F: "O", 0x23: "P", 0x0C: "Q", 0x0F: "R",
                0x01: "S", 0x11: "T", 0x20: "U", 0x09: "V", 0x0D: "W", 0x07: "X",
                0x10: "Y", 0x06: "Z",
                0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x17: "5",
                0x16: "6", 0x1A: "7", 0x1C: "8", 0x19: "9", 0x1D: "0",
            ]
            return letters[code] ?? "key \(code)"
        }
    }
    /// The right column's pages, switched by the nav bar. HOME shows the
    /// title overlay instead of a page.
    private enum HUDPage {
        case board, milestones
    }
    private var hudPage: HUDPage = .board
    private let boardPageNode = SKNode()
    private let milestonesPageNode = SKNode()
    private var navTabLabels: [String: SKLabelNode] = [:]
    private let playerColor = SKColor(red: 0.35, green: 0.85, blue: 0.95, alpha: 1.0)
    private let armorFlashColor = SKColor(red: 0.65, green: 0.75, blue: 0.95, alpha: 1.0)
    private static let goButtonName = "goButton"
    private static let weaponButtonName = "weaponButton"
    /// Prophecies that "explain" the ultimate, delivered by an oracle who is
    /// trying very hard to sound mystical and not quite managing it. Each "|"
    /// toggles the voice — grand script, deflated plain type, grand again —
    /// so a line can lose its nerve, rally, and collapse twice.
    private static let ultimateChatter = [
        "hearken! the heavens shall...| um. basically the sky is going to land on them. verily.",
        "lo, a great doom approaches, borne on wings of...| it's fire. it's a lot of fire.",
        "the stars align!| well. most of them. enough. close your eyes anyway.",
        "i have consulted the bones.| the bones said 'ka-boom'. i don't make the rules.",
        "thus spake the void: 'run'.| then something i couldn't make out. probably also 'run'.",
        "behold: a second sun!| brief. localized. do not behold it directly, actually.",
        "an omen! doom shall rain from...| above, i want to say? yes. above. definitely above.",
        "as foretold in the elder scrolls.| not those ones. legally distinct ones.",
        "so it is written.| in pencil, but still. |so it lands.",
    ]
    /// The same oracle, reaching for each omen in turn. Smite gets the original
    /// sky-falls patter; the others needed their own, since "doom shall rain
    /// from above" reads oddly when nothing is falling and the enemies have
    /// merely stopped moving.
    private static func omenChatter(for omen: Omen) -> [String] {
        switch omen {
        case .smite: return ultimateChatter
        case .detonation: return [
            "i foresee a great unbinding!| the barrels. i mean the barrels. all of them at once.",
            "the powder hears me.| we have an arrangement. |mostly it just wants to go off.",
            "thus spake the void: 'stand back'.| unusually practical of it, i thought.",
        ]
        case .stillness: return [
            "time itself shall...| pause. briefly. |like a held breath, but for enemies.",
            "behold, the great hush!| nobody moves. nobody swings. it's quite peaceful actually.",
            "i have stopped the hour.| don't ask how. |don't ask for how long either.",
        ]
        case .quickening: return [
            "the hour quickens!| your hands, specifically. the rest of you is unchanged.",
            "swing freely, chosen one.| the waiting is suspended. |the consequences are not.",
            "i have consulted the bones.| the bones said 'again'. and then 'again'.",
        ]
        }
    }

    /// Prophecies for the level's gatekeeper stomping in, same oracle.
    private static let eliteChatter = [
        "dark portents gather! something huge this way...| comes? cometh? it's coming.",
        "i foresaw this!| definitely | slay the big one and the road shall, |um, open. mystically.",
        "hark! the gate walks in flesh most foul!| yes, the massive one. kill that.",
    ]
    private static let weaponButtonSize = CGSize(width: 208, height: 56)
    private static let weaponIconSize: CGFloat = 34
    /// The icon's centre, measured in from the button's left edge.
    private static let weaponIconInset: CGFloat = 22

    /// The column the weapon button's two labels get to use. They're centred
    /// in it, so with no art they sit across the whole button as before, and
    /// once a weapon's sprite exists they shift right to clear it.
    ///
    /// Without this the labels centre on the full width and simply overlap the
    /// icon — which went unnoticed while every weapon was a placeholder, since
    /// there was nothing under the text to collide with.
    private static func weaponTextColumn(hasIcon: Bool) -> (centerX: CGFloat, width: CGFloat) {
        let half = weaponButtonSize.width / 2
        let padding: CGFloat = 8
        let left = hasIcon
            ? -half + weaponIconInset + weaponIconSize / 2 + padding
            : -half + padding
        let right = half - padding
        return ((left + right) / 2, right - left)
    }

    // MARK: - Setup

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(white: 0.10, alpha: 1.0)
        applyAnimationSpeed()
        applyDebugOverlays()
        state = makeRunState()
        setUpScene()
        showTitleScreen()

        #if canImport(AppKit)
        // Keyboard events only reach the scene when the SKView is first responder.
        view.window?.makeFirstResponder(view)

        // SKView doesn't track mouse movement by default; needed for hover highlighting.
        let trackingArea = NSTrackingArea(
            rect: view.bounds,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: view,
            userInfo: nil
        )
        view.addTrackingArea(trackingArea)
        #endif
    }

    /// Builds every node from the current state; also used to restart after game over.
    private func setUpScene() {
        setUpBoard()
        setUpPlayer()
        setUpEnemies()
        setUpObstacles()
        setUpTerrain()
        setUpTeleporters()
        setUpSpikes()
        setUpHUD()
        setUpGoButton()
        setUpControlsLegend()
        updateEnemyPlanArrows()
        updateSpawnMarkers()
        updateWeaponDropNodes()
        updateCacheNodes()
        updatePickupHint()
        refreshTileHighlights()
    }

    private func setUpBoard() {
        boardNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(boardNode)

        let boardSide = min(size.width, size.height) * boardScale
        tileSize = boardSide / CGFloat(max(state.columns, state.rows))

        for x in 0..<state.columns {
            for y in 0..<state.rows {
                let position = GridPosition(x: x, y: y)
                let tile = SKSpriteNode(color: .black, size: CGSize(width: tileSize - 2, height: tileSize - 2))
                tile.position = point(for: position)
                boardNode.addChild(tile)
                tileNodes[position] = tile
            }
        }
    }

    private func setUpPlayer() {
        // The cyan disc is the stand-in body; once player-front/back/side art
        // lands the rig hides it and poses the sprite instead. Either way the
        // equipped weapon is drawn in the hand.
        let placeholder = SKShapeNode(circleOfRadius: tileSize * 0.32)
        placeholder.fillColor = playerColor
        placeholder.strokeColor = .white
        placeholder.lineWidth = 2
        playerNode = ActorNode(bodyID: Art.playerBodyID, tileSize: tileSize,
                               footprint: 0.65, placeholder: placeholder)
        playerNode.zPosition = 10
        playerNode.position = point(for: state.playerPosition)
        playerNode.hold(state.equippedWeapon, ready: playerWeaponIsReady)
        boardNode.addChild(playerNode)
    }

    private func setUpEnemies() {
        for enemy in state.enemies {
            addEnemyNode(for: enemy)
        }
    }

    /// The placeholder art per archetype — a rotated square that differs by size
    /// and colour. Shared by the board sprites and the ENEMIES index so the two
    /// never drift apart.
    private func enemyStyle(_ archetype: Archetype) -> (fill: SKColor, stroke: SKColor, lineWidth: CGFloat, sizeFactor: CGFloat) {
        switch archetype {
        case .fighter:
            return (SKColor(red: 0.90, green: 0.30, blue: 0.25, alpha: 1.0), .white, 1.5, 0.5)
        case .berserker:
            return (SKColor(red: 0.95, green: 0.45, blue: 0.05, alpha: 1.0), .white, 1.5, 0.5)
        case .swift:
            return (SKColor(red: 0.35, green: 0.70, blue: 0.95, alpha: 1.0), .white, 1.5, 0.45)
        case .bomber:
            return (SKColor(white: 0.15, alpha: 1.0), SKColor(red: 0.90, green: 0.55, blue: 0.15, alpha: 1.0), 1.5, 0.45)
        case .shieldbearer:
            return (SKColor(red: 0.42, green: 0.48, blue: 0.55, alpha: 1.0), SKColor(red: 0.80, green: 0.85, blue: 0.90, alpha: 1.0), 2.5, 0.55)
        case .reaver:
            return (SKColor(red: 0.55, green: 0.05, blue: 0.20, alpha: 1.0), SKColor(red: 0.98, green: 0.85, blue: 0.55, alpha: 1.0), 2.5, 0.5)
        case .juggernaut:
            return (SKColor(red: 0.60, green: 0.25, blue: 0.75, alpha: 1.0), .white, 1.5, 0.7)
        case .boss:
            return (SKColor(red: 0.45, green: 0.10, blue: 0.60, alpha: 1.0), .white, 3, 0.85)
        case .summoner:
            // Teal caster, sized between a juggernaut and a boss.
            return (SKColor(red: 0.15, green: 0.65, blue: 0.60, alpha: 1.0), SKColor(red: 0.75, green: 1.0, blue: 0.95, alpha: 1.0), 2.5, 0.75)
        case .bombardier:
            // Slate-and-amber explosives handler.
            return (SKColor(red: 0.30, green: 0.35, blue: 0.50, alpha: 1.0), SKColor(red: 0.98, green: 0.70, blue: 0.25, alpha: 1.0), 2.5, 0.75)
        }
    }

    @discardableResult
    private func addEnemyNode(for enemy: Enemy) -> ActorNode {
        let style = enemyStyle(enemy.archetype)
        let side = tileSize * style.sizeFactor
        // The diamond is the stand-in body. It carries the 45° rotation itself
        // rather than the actor node, so the weapon in the enemy's hand (and
        // the shield plank, and the stun stars) sit in an upright frame.
        let placeholder = SKShapeNode(rectOf: CGSize(width: side, height: side), cornerRadius: 2)
        placeholder.zRotation = .pi / 4
        placeholder.fillColor = style.fill
        placeholder.strokeColor = style.stroke
        placeholder.lineWidth = style.lineWidth
        let node = ActorNode(bodyID: Art.bodyID(for: enemy.archetype, armed: enemy.fuse != nil),
                             tileSize: tileSize, footprint: style.sizeFactor, placeholder: placeholder)
        node.zPosition = 10
        node.position = point(for: enemy.position)
        // Every enemy shows what it's carrying — the weapon *is* the enemy's
        // identity in the HUD readout, so it should be readable on the board.
        node.hold(heldWeapon(of: enemy), ready: enemy.cooldownRemaining == 0,
                  secondary: enemy.secondaryWeapon,
                  secondaryReady: enemy.secondaryCooldownRemaining == 0)
        node.face(facing(of: enemy))
        boardNode.addChild(node)
        enemyNodes[enemy.id] = node
        return node
    }

    /// What an enemy visibly carries. A bomber carries a dagger in the data —
    /// it's what gives it three tiles of charge — but it never swings the
    /// thing: the rules force its plans to nil and its threat preview shows
    /// the blast instead. Drawing it would promise a jab that can't happen.
    private func heldWeapon(of enemy: Enemy) -> Weapon? {
        enemy.archetype == .bomber ? nil : enemy.weapon
    }

    /// Which way an enemy is turned: at the swing it has drafted, else along
    /// the move it has drafted, else at the player (a shieldbearer's raised
    /// shield already points that way). Nil leaves it as it stands.
    private func facing(of enemy: Enemy) -> Direction? {
        if let direction = enemy.plannedDirection { return direction }
        if let throwTarget = enemy.plannedThrowTarget {
            return Direction.aiming(from: enemy.position, toward: throwTarget, allowDiagonals: true)
        }
        if let target = enemy.plannedTarget, target != enemy.position {
            return Direction.aiming(from: enemy.position, toward: target, allowDiagonals: true)
        }
        if let shieldFacing = enemy.facing { return shieldFacing }
        return Direction.aiming(from: enemy.position, toward: state.playerPosition, allowDiagonals: true)
    }

    /// Whether the equipped weapon can swing this turn. Weapons that have a
    /// `-cooldown` sprite show it while this is false.
    private var playerWeaponIsReady: Bool {
        state.attackCooldownRemaining(of: state.equippedWeapon) == 0
    }

    /// Which way the player is turned: at the drafted swing or throw, else
    /// along the drafted move, else left as they stand.
    private func playerFacing() -> Direction? {
        if let direction = state.plannedAttackDirection { return direction }
        if let throwTarget = state.plannedThrowTarget {
            return Direction.aiming(from: state.playerPosition, toward: throwTarget, allowDiagonals: true)
        }
        if let target = state.plannedTarget, target != state.playerPosition {
            return Direction.aiming(from: state.playerPosition, toward: target, allowDiagonals: true)
        }
        return nil
    }

    /// Re-poses every body and refreshes the weapon in every hand. Cheap and
    /// idempotent — the rig skips the work when nothing changed — so it can
    /// ride along with the tile highlights after any state change.
    private func refreshActorSprites() {
        let hold = resolveHold
        playerNode?.hold(state.equippedWeapon, ready: hold?.playerWeaponReady ?? playerWeaponIsReady)
        // Mid-resolve the facing is driven beat by beat, so an unset one means
        // "don't turn yet" rather than "work it out from the plan".
        playerNode?.face(hold == nil ? playerFacing() : hold?.playerFacing)
        for enemy in state.enemies {
            guard let node = enemyNodes[enemy.id] else { continue }
            node.setBodyID(Art.bodyID(for: enemy.archetype, armed: enemy.fuse != nil))
            // An enemy that arrived mid-resolve has nothing held for it, and
            // shows the live state — the only one it has.
            node.hold(heldWeapon(of: enemy),
                      ready: hold?.enemyWeaponReady[enemy.id] ?? (enemy.cooldownRemaining == 0),
                      secondary: enemy.secondaryWeapon,
                      secondaryReady: hold?.enemySecondaryReady[enemy.id] ?? (enemy.secondaryCooldownRemaining == 0))
            node.face(hold == nil ? facing(of: enemy) : hold?.enemyFacing[enemy.id])
        }
    }

    /// Lets the player's weapon show what the resolve did to it: a spent bow
    /// goes to its cooldown art, and they turn onto the aim they loosed along.
    private func releasePlayerWeaponArt() {
        guard var hold = resolveHold else { return }
        hold.playerWeaponReady = playerWeaponIsReady
        if let aim = hold.playerAim {
            hold.playerFacing = aim
        }
        resolveHold = hold
        refreshActorSprites()
    }

    /// Snapshots what the sprites should keep showing while the resolve
    /// animates. Must run *before* `state.resolveTurn()`: it reads the drafted
    /// plans and the cooldowns that the resolve is about to spend.
    private func beginResolveHold() {
        var hold = ResolveHold(playerWeaponReady: playerWeaponIsReady, playerFacing: nil)
        hold.playerAim = state.plannedAttackDirection
            ?? state.plannedThrowTarget.flatMap {
                Direction.aiming(from: state.playerPosition, toward: $0, allowDiagonals: true)
            }
        // The player steps off first thing, so they turn to walk right away.
        if let target = state.plannedTarget, target != state.playerPosition {
            hold.playerFacing = Direction.aiming(from: state.playerPosition, toward: target, allowDiagonals: true)
        }
        for enemy in state.enemies {
            hold.enemyWeaponReady[enemy.id] = enemy.cooldownRemaining == 0
            hold.enemySecondaryReady[enemy.id] = enemy.secondaryCooldownRemaining == 0
            hold.enemyAim[enemy.id] = enemy.plannedDirection
                ?? enemy.plannedThrowTarget.flatMap {
                    Direction.aiming(from: enemy.position, toward: $0, allowDiagonals: true)
                }
            if let target = enemy.plannedTarget, target != enemy.position {
                hold.enemyMoveFacing[enemy.id] = Direction.aiming(from: enemy.position,
                                                                  toward: target, allowDiagonals: true)
            }
        }
        resolveHold = hold
    }

    /// Armed bombers pulse angrily so the lit fuse is unmistakable.
    private func updateBomberFuses() {
        for enemy in state.enemies where enemy.archetype == .bomber {
            guard let node = enemyNodes[enemy.id] else { continue }
            if enemy.fuse != nil, node.action(forKey: "armed") == nil {
                // Sprite sets have their own armed variant (swapped in by
                // refreshActorSprites); the placeholder gets the red rim.
                node.bodyStrokeColor = SKColor(red: 1.0, green: 0.30, blue: 0.20, alpha: 1.0)
                node.run(SKAction.repeatForever(SKAction.sequence([
                    SKAction.scale(to: 1.25, duration: 0.25),
                    SKAction.scale(to: 1.0, duration: 0.25),
                ])), withKey: "armed")
            }
        }
    }

    /// Fractional board coordinates → scene point (for lob beads between tiles).
    private func boardPoint(x: Double, y: Double) -> CGPoint {
        CGPoint(
            x: (CGFloat(x) - CGFloat(state.columns - 1) / 2) * tileSize,
            y: (CGFloat(y) - CGFloat(state.rows - 1) / 2) * tileSize
        )
    }

    /// Shells in flight: a dark bead partway between thrower and target, further
    /// along the closer it is to landing. Beads persist across turns; a freshly
    /// thrown one glides out of the thrower's hand.
    private func updateProjectileNodes() {
        let liveShellIDs = Set(state.projectiles.map(\.id))
        for (id, node) in lobNodes where !liveShellIDs.contains(id) {
            node.removeFromParent()
            lobNodes[id] = nil
            lobTargets[id] = nil
        }
        for shell in state.projectiles {
            let coordinates = state.lobBeadCoordinates(of: shell)
            let destination = boardPoint(x: coordinates.x, y: coordinates.y)
            if let existing = lobNodes[shell.id] {
                existing.position = destination
            } else {
                let bead = makeShellNode()
                bead.position = point(for: shell.origin)
                boardNode.addChild(bead)
                lobNodes[shell.id] = bead
                lobTargets[shell.id] = point(for: shell.target)

                let distanceInTiles = hypot(destination.x - bead.position.x,
                                            destination.y - bead.position.y) / tileSize
                let launch = SKAction.move(to: destination, duration: 0.06 * TimeInterval(distanceInTiles) + 0.08)
                launch.timingMode = .easeOut
                bead.run(launch)
            }
        }

        // Bolts: a steel sliver on the bolt's actual tile (the red path ahead
        // shows where it flies next). Nodes persist across turns so the resolve
        // phase can glide them; flights normally create them, so the fallback
        // here just places one.
        let liveBoltIDs = Set(state.bolts.map(\.id))
        for (id, node) in boltNodes where !liveBoltIDs.contains(id) {
            node.removeFromParent()
            boltNodes[id] = nil
        }
        for bolt in state.bolts {
            let node: SKNode
            if let existing = boltNodes[bolt.id] {
                node = existing
            } else {
                node = makeBoltNode(Art.ammo(for: bolt), direction: bolt.direction)
                boardNode.addChild(node)
                boltNodes[bolt.id] = node
            }
            node.position = point(for: bolt.position)
        }
    }

    /// One shot in flight, turned to point down its line — the only piece on
    /// the board that rotates. Ammo art is authored pointing right, like every
    /// weapon; without it the steel sliver stands in.
    private func makeBoltNode(_ ammo: Art.ProjectileArt, direction: Direction) -> SKNode {
        let step = direction.unitStep
        let angle = atan2(CGFloat(step.y), CGFloat(step.x))
        let node: SKNode
        if let texture = Art.texture(ammo) {
            let sprite = SKSpriteNode(texture: texture, color: .clear,
                                      size: CGSize(width: tileSize, height: tileSize))
            // Ammo that points where it's going gets turned; anything that
            // tumbles is drawn as it lies.
            sprite.zRotation = ammo.rotatesToFlight ? angle : 0
            node = sprite
        } else {
            let sliver = SKShapeNode(rectOf: CGSize(width: tileSize * 0.45, height: tileSize * 0.12), cornerRadius: 2)
            sliver.fillColor = SKColor(red: 0.75, green: 0.78, blue: 0.82, alpha: 1.0)
            sliver.strokeColor = SKColor(white: 0.3, alpha: 1.0)
            sliver.lineWidth = 1
            sliver.zRotation = angle
            node = sliver
        }
        node.zPosition = 16
        return node
    }

    /// A lobbed grenade or flask mid-arc. It tumbles rather than points, so it
    /// isn't rotated; the dark bead stands in until there's art.
    private func makeShellNode() -> SKNode {
        let node: SKNode
        if let texture = Art.texture(Art.ProjectileArt.shell) {
            node = SKSpriteNode(texture: texture, color: .clear,
                                size: CGSize(width: tileSize, height: tileSize))
        } else {
            let bead = SKShapeNode(circleOfRadius: tileSize * 0.14)
            bead.fillColor = SKColor(red: 0.25, green: 0.25, blue: 0.28, alpha: 1.0)
            bead.strokeColor = .white
            bead.lineWidth = 1.5
            node = bead
        }
        node.zPosition = 16
        return node
    }

    /// Gold rings (with the weapon's initial) marking weapons lying on the
    /// ground; rebuilt from state after every turn.
    private func updateWeaponDropNodes() {
        weaponDropNodes.forEach { $0.removeFromParent() }
        weaponDropNodes.removeAll()
        let gold = SKColor(red: 0.95, green: 0.85, blue: 0.35, alpha: 1.0)
        let bossPurple = SKColor(red: 0.75, green: 0.45, blue: 0.95, alpha: 1.0)
        for drop in state.weaponDrops {
            // Boss trophies gleam purple and slightly larger.
            let tint = drop.isBossDrop ? bossPurple : gold
            let ring = SKShapeNode(circleOfRadius: tileSize * (drop.isBossDrop ? 0.34 : 0.30))
            ring.strokeColor = tint
            ring.lineWidth = drop.isBossDrop ? 3 : 2
            ring.fillColor = tint.withAlphaComponent(0.12)
            ring.position = point(for: drop.position)
            ring.zPosition = 7

            // The same sprite the wielder holds, lying in the ring; until it
            // exists the weapon's initial stands in for it.
            // A weapon on the floor is always shown ready, whatever state it
            // was in when its owner dropped it.
            if let texture = Art.weaponTexture(drop.weapon) {
                let icon = SKSpriteNode(texture: texture, color: .clear,
                                        size: CGSize(width: tileSize * 0.52, height: tileSize * 0.52))
                // Canted, so a drop reads as dropped rather than mounted.
                icon.zRotation = -.pi / 6
                ring.addChild(icon)
            } else {
                let letter = SKLabelNode(text: String(drop.weapon.name.prefix(1)))
                letter.fontName = "HelveticaNeue-Bold"
                letter.fontSize = 14
                letter.fontColor = tint
                letter.verticalAlignmentMode = .center
                ring.addChild(letter)
            }

            boardNode.addChild(ring)
            weaponDropNodes.append(ring)
        }
    }

    /// Jade crate-lids on the mud tiles hiding a cache; rebuilt from state after
    /// every turn. Deliberately the only thing on the board that pulses without
    /// being a threat: the whole mechanic is the player deciding from across the
    /// board whether the slog into the mud is worth it, which they can't do if
    /// the reward doesn't catch the eye against a dim brown tile.
    private func updateCacheNodes() {
        cacheNodes.values.forEach { $0.removeFromParent() }
        cacheNodes.removeAll()
        let jade = SKColor(red: 0.45, green: 0.88, blue: 0.68, alpha: 1.0)
        for cache in state.caches {
            let side = tileSize * 0.36
            let lid = SKShapeNode(rectOf: CGSize(width: side, height: side), cornerRadius: 3)
            lid.strokeColor = jade
            lid.lineWidth = 2
            lid.fillColor = jade.withAlphaComponent(0.15)
            lid.position = point(for: cache.position)
            // Below the weapon drops' rings (7) so a drop stacked nearby still
            // reads first, and below the entities so standing on it covers it.
            lid.zPosition = 6

            let clasp = SKShapeNode(circleOfRadius: max(1.5, tileSize * 0.05))
            clasp.fillColor = jade
            clasp.strokeColor = .clear
            lid.addChild(clasp)

            lid.run(.repeatForever(.sequence([
                .scale(to: 1.12, duration: 0.7),
                .scale(to: 1.0, duration: 0.7),
            ])))

            boardNode.addChild(lid)
            cacheNodes[cache.position] = lid
        }
    }

    /// "!" markers on the tiles where next turn's reinforcements will appear.
    private func updateSpawnMarkers() {
        spawnMarkerNodes.forEach { $0.removeFromParent() }
        spawnMarkerNodes.removeAll()
        guard !state.isGameOver else { return }
        // Pink for incoming enemies, barrel-orange for incoming barrels.
        let markers = state.pendingSpawns.map { ($0, SKColor(red: 0.95, green: 0.45, blue: 0.85, alpha: 1.0)) }
            + state.pendingBarrelSpawns.map { ($0, SKColor(red: 0.90, green: 0.55, blue: 0.15, alpha: 1.0)) }
        for (tile, color) in markers {
            let marker = SKLabelNode(text: "!")
            marker.fontName = "HelveticaNeue-Bold"
            marker.fontSize = 20
            marker.fontColor = color
            marker.verticalAlignmentMode = .center
            marker.position = point(for: tile)
            marker.zPosition = 12
            boardNode.addChild(marker)
            spawnMarkerNodes.append(marker)
        }
    }

    private func setUpObstacles() {
        for obstacle in state.obstacles {
            addObstacleNode(for: obstacle)
        }
    }

    /// A spiky diamond on each spike tile, below the enemies. Its look tracks
    /// the trap's active state (updated each turn by refreshSpikes).
    private func setUpSpikes() {
        spikeNodes.values.forEach { $0.removeFromParent() }
        spikeNodes.removeAll()
        // Three across; the same spacing works for the raised blades and the
        // flush holes so the two states line up.
        let offsets: [CGFloat] = [-tileSize * 0.22, 0, tileSize * 0.22]
        for spike in state.spikes {
            let container = SKNode()
            container.position = point(for: spike.position)
            container.zPosition = 3

            // Active: a row of tall steel blades jutting out of the floor.
            let blades = SKNode()
            blades.name = "active"
            let bladeHeight = tileSize * 0.42
            let bladeWidth = tileSize * 0.17
            for dx in offsets {
                let blade = SKShapeNode(path: spikeTrianglePath(width: bladeWidth, height: bladeHeight))
                blade.fillColor = SKColor(red: 0.82, green: 0.84, blue: 0.88, alpha: 1.0)
                blade.strokeColor = SKColor(red: 0.28, green: 0.30, blue: 0.34, alpha: 1.0)
                blade.lineWidth = 1.5
                blade.position = CGPoint(x: dx, y: -bladeHeight * 0.4)
                blades.addChild(blade)
            }
            container.addChild(blades)

            // Dormant: three little holes flush with the ground the blades
            // retract into.
            let holes = SKNode()
            holes.name = "dormant"
            for dx in offsets {
                let hole = SKShapeNode(circleOfRadius: tileSize * 0.07)
                hole.fillColor = SKColor(white: 0.09, alpha: 1.0)
                hole.strokeColor = SKColor(white: 0.34, alpha: 1.0)
                hole.lineWidth = 1.5
                hole.position = CGPoint(x: dx, y: 0)
                holes.addChild(hole)
            }
            container.addChild(holes)

            boardNode.addChild(container)
            spikeNodes[spike.position] = container
        }
        refreshSpikes()
    }

    /// An upward-pointing triangle (base centered on the origin) for one blade.
    private func spikeTrianglePath(width: CGFloat, height: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -width / 2, y: 0))
        path.addLine(to: CGPoint(x: width / 2, y: 0))
        path.addLine(to: CGPoint(x: 0, y: height))
        path.closeSubpath()
        return path
    }

    /// Raised blades on the turns they'll bite; retracted to floor holes otherwise.
    private func refreshSpikes() {
        for spike in state.spikes {
            guard let container = spikeNodes[spike.position] else { continue }
            container.childNode(withName: "active")?.isHidden = !spike.active
            container.childNode(withName: "dormant")?.isHidden = spike.active
        }
    }

    /// A hue-coded portal ring on both ends of each teleporter pair, so the link
    /// is readable at a glance. Static — teleporters don't toggle.
    private func setUpTeleporters() {
        teleporterNodes.values.forEach { $0.removeFromParent() }
        teleporterNodes.removeAll()
        let hues: [SKColor] = [
            SKColor(red: 0.35, green: 0.80, blue: 0.95, alpha: 1.0),
            SKColor(red: 0.75, green: 0.50, blue: 0.95, alpha: 1.0),
            SKColor(red: 0.45, green: 0.90, blue: 0.60, alpha: 1.0),
        ]
        for teleporter in state.teleporters {
            let hue = hues[teleporter.id % hues.count]
            for tile in [teleporter.a, teleporter.b] {
                let ring = SKShapeNode(circleOfRadius: tileSize * 0.30)
                ring.fillColor = .clear
                ring.strokeColor = hue
                ring.lineWidth = 3
                ring.zPosition = 3
                ring.position = point(for: tile)
                boardNode.addChild(ring)
                teleporterNodes[tile] = ring
            }
        }
    }

    /// A tinted, inset square on each movement-terrain tile, below the entities:
    /// pale blue for ice (slippery, +1 move), muddy brown for mud (−1 move).
    /// Static — terrain doesn't change during a level.
    private func setUpTerrain() {
        terrainNodes.values.forEach { $0.removeFromParent() }
        terrainNodes.removeAll()
        for patch in state.terrain {
            let side = tileSize * 0.9
            let square = SKShapeNode(rectOf: CGSize(width: side, height: side), cornerRadius: tileSize * 0.12)
            switch patch.kind {
            case .ice:
                square.fillColor = SKColor(red: 0.62, green: 0.82, blue: 0.95, alpha: 0.45)
                square.strokeColor = SKColor(red: 0.78, green: 0.92, blue: 1.0, alpha: 0.9)
            case .mud:
                square.fillColor = SKColor(red: 0.42, green: 0.32, blue: 0.20, alpha: 0.55)
                square.strokeColor = SKColor(red: 0.30, green: 0.22, blue: 0.13, alpha: 0.9)
            }
            square.lineWidth = 1.5
            square.zPosition = 1
            square.position = point(for: patch.position)
            boardNode.addChild(square)
            terrainNodes[patch.position] = square
        }
    }

    @discardableResult
    private func addObstacleNode(for obstacle: Obstacle) -> SKNode {
        // A fresh node starts at its authored colour, so any remembered tint
        // for this tile belongs to the wall that used to stand here.
        wallTints[obstacle.position] = nil
        let node: SKNode
        switch obstacle.kind {
        case .wall:
            // Destructible walls read as cracked brown blocks; solid ones stay
            // flat grey.
            let wall = SKSpriteNode(
                color: obstacle.destructible
                    ? SKColor(red: 0.42, green: 0.34, blue: 0.24, alpha: 1.0)
                    : SKColor(white: 0.45, alpha: 1.0),
                size: CGSize(width: tileSize - 2, height: tileSize - 2)
            )
            if obstacle.destructible {
                // A pale seam hints it can be broken. Nest the wall + crack as
                // siblings of a plain container (both centered at its origin)
                // rather than making the crack a child of the sprite: a sprite's
                // child is positioned from the sprite's corner, not its center
                // (fine on SpriteKit, off-center on OpenSpriteKit).
                let container = SKNode()
                // Named so the attack/dig telegraph can find the fill sprite
                // inside the container (see refreshTileHighlights).
                wall.name = "crumbleFill"
                container.addChild(wall)
                let crack = SKSpriteNode(color: SKColor(white: 0.75, alpha: 0.35),
                                         size: CGSize(width: 2, height: tileSize - 8))
                crack.zRotation = .pi / 8
                container.addChild(crack)
                node = container
            } else {
                node = wall
            }
        case .barrel:
            let barrel = SKShapeNode(circleOfRadius: tileSize * 0.30)
            // Colour tells the flavor apart: red = boss-primed, green = fire (no
            // blast, leaves flame), yellow = weak (the Keg's), orange = standard.
            let (fill, stroke): (SKColor, SKColor)
            if obstacle.volatile {
                fill = SKColor(red: 0.85, green: 0.18, blue: 0.15, alpha: 1.0)
                stroke = SKColor(red: 0.45, green: 0.05, blue: 0.05, alpha: 1.0)
            } else {
                switch obstacle.barrelKind {
                case .fire:
                    fill = SKColor(red: 0.30, green: 0.72, blue: 0.32, alpha: 1.0)
                    stroke = SKColor(red: 0.12, green: 0.34, blue: 0.14, alpha: 1.0)
                case .weak:
                    fill = SKColor(red: 0.88, green: 0.82, blue: 0.22, alpha: 1.0)
                    stroke = SKColor(red: 0.45, green: 0.40, blue: 0.06, alpha: 1.0)
                case .standard:
                    fill = SKColor(red: 0.85, green: 0.50, blue: 0.15, alpha: 1.0)
                    stroke = SKColor(red: 0.40, green: 0.22, blue: 0.05, alpha: 1.0)
                }
            }
            barrel.fillColor = fill
            barrel.strokeColor = stroke
            barrel.lineWidth = 2
            node = barrel
        }
        node.position = point(for: obstacle.position)
        node.zPosition = 8
        boardNode.addChild(node)
        obstacleNodes[obstacle.position] = node
        return node
    }

    private func setUpGoButton() {
        let boardSide = min(size.width, size.height) * boardScale
        // Centered over the status bars, whatever the margin width.
        let columnCenter = (size.width + boardSide) / 2 + 16 + 104
        let columnTop = (size.height + boardSide) / 2

        let button = SKShapeNode(rectOf: CGSize(width: 150, height: 56), cornerRadius: 10)
        button.fillColor = SKColor(red: 0.20, green: 0.55, blue: 0.35, alpha: 1.0)
        button.strokeColor = .white
        button.lineWidth = 1.5
        button.zPosition = 20
        button.name = Self.goButtonName
        button.position = CGPoint(x: columnCenter, y: columnTop - 452)

        let label = SKLabelNode(text: "GO")
        label.fontName = "HelveticaNeue-Bold"
        label.fontSize = 22
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.name = Self.goButtonName
        button.addChild(label)

        boardPageNode.addChild(button)
        goButton = button
    }

    /// The right column: a nav bar (BOARD · MILESTONES · HOME) over paged
    /// content. The board page holds health/armor pips, the ultimate bar,
    /// dodge chip, contextual hint, and the weapon and GO buttons; the
    /// milestones page lists the whole arsenal and how to earn it.
    private func setUpHUD() {
        let boardSide = min(size.width, size.height) * boardScale
        let columnLeft = (size.width + boardSide) / 2 + 16
        let columnTop = (size.height + boardSide) / 2

        for container in [boardPageNode, milestonesPageNode] {
            container.removeAllChildren()
            container.removeFromParent()
            container.zPosition = 20
            addChild(container)
        }

        // The nav bar across the top of the column.
        navTabLabels = [:]
        var tabX = columnLeft
        for (title, key) in [("BOARD", "board"), ("MILESTONES", "milestones"), ("SETTINGS", "settings"), ("HOME", "home")] {
            let tab = SKLabelNode(text: title)
            tab.fontName = "HelveticaNeue-Bold"
            tab.fontSize = 14
            tab.horizontalAlignmentMode = .left
            tab.verticalAlignmentMode = .top
            tab.position = CGPoint(x: tabX, y: columnTop + 2)
            tab.zPosition = 20
            tab.name = "navTab:\(key)"
            addChild(tab)
            navTabLabels[key] = tab
            tabX += tab.frame.width + 26
        }

        // — Board page —
        // Captions sit above their rows; updateHUD redraws the contents.
        for (caption, container, rowY) in [
            ("HP", healthBarNode, columnTop - 64),
            ("ARMOR", armorBarNode, columnTop - 116),
            ("ULT", ultimateBarNode, columnTop - 168),
        ] {
            let label = SKLabelNode(text: caption)
            label.fontName = "HelveticaNeue-Bold"
            label.fontSize = 11
            label.fontColor = SKColor(white: 0.55, alpha: 1.0)
            label.horizontalAlignmentMode = .left
            label.verticalAlignmentMode = .bottom
            label.position = CGPoint(x: columnLeft, y: rowY + 12)
            boardPageNode.addChild(label)
            container.removeFromParent()
            container.position = CGPoint(x: columnLeft, y: rowY)
            boardPageNode.addChild(container)
        }

        // Sits just under the HP pips: the bleed/poison currently ticking away.
        afflictionLabel = SKLabelNode(text: "")
        afflictionLabel.fontName = "HelveticaNeue-Bold"
        afflictionLabel.fontSize = 11
        afflictionLabel.fontColor = SKColor(red: 0.85, green: 0.30, blue: 0.45, alpha: 1.0)
        afflictionLabel.horizontalAlignmentMode = .left
        afflictionLabel.verticalAlignmentMode = .center
        afflictionLabel.position = CGPoint(x: columnLeft, y: columnTop - 88)
        boardPageNode.addChild(afflictionLabel)

        // Under the ult bar (which spans rowY ±7 at columnTop − 168) and clear
        // of the dodge chip below it.
        freezeLabel = SKLabelNode(text: "")
        freezeLabel.fontName = "HelveticaNeue-Bold"
        freezeLabel.fontSize = 11
        freezeLabel.horizontalAlignmentMode = .left
        freezeLabel.verticalAlignmentMode = .center
        freezeLabel.position = CGPoint(x: columnLeft, y: columnTop - 192)
        boardPageNode.addChild(freezeLabel)

        dodgeChipLabel = SKLabelNode(text: "DODGE ✓")
        dodgeChipLabel.fontName = "HelveticaNeue-Bold"
        dodgeChipLabel.fontSize = 12
        dodgeChipLabel.fontColor = playerColor
        dodgeChipLabel.horizontalAlignmentMode = .left
        dodgeChipLabel.verticalAlignmentMode = .center
        dodgeChipLabel.position = CGPoint(x: columnLeft, y: columnTop - 212)
        boardPageNode.addChild(dodgeChipLabel)

        itemsLabel = SKLabelNode()
        itemsLabel.fontName = "HelveticaNeue"
        itemsLabel.fontSize = 12
        itemsLabel.fontColor = SKColor(white: 0.8, alpha: 1.0)
        itemsLabel.horizontalAlignmentMode = .left
        itemsLabel.verticalAlignmentMode = .top
        itemsLabel.numberOfLines = 0
        itemsLabel.preferredMaxLayoutWidth = size.width - columnLeft - 16
        itemsLabel.position = CGPoint(x: columnLeft, y: columnTop - 242)
        boardPageNode.addChild(itemsLabel)

        rebuildMilestonesPage()
        setHUDPage(hudPage)

        scoreLabel = SKLabelNode()
        scoreLabel.fontName = "HelveticaNeue-Bold"
        scoreLabel.fontSize = 18
        scoreLabel.fontColor = .white
        scoreLabel.verticalAlignmentMode = .center
        scoreLabel.position = CGPoint(x: size.width / 2, y: size.height - (size.height - boardSide) / 4)
        scoreLabel.zPosition = 20
        addChild(scoreLabel)

        // Just under the score: the pact in play, its boon and curse as separate
        // pieces so the curse can burn red and each can be hovered for its effect.
        pactHUD = SKNode()
        pactHUD.position = CGPoint(x: size.width / 2, y: scoreLabel.position.y - 42)
        pactHUD.zPosition = 20
        addChild(pactHUD)

        buffsLabel = SKLabelNode()
        buffsLabel.fontName = "HelveticaNeue"
        buffsLabel.fontSize = 12
        buffsLabel.fontColor = Self.buffsLabelColor
        buffsLabel.verticalAlignmentMode = .center
        buffsLabel.position = CGPoint(x: size.width / 2, y: size.height - (size.height - boardSide) / 4 - 22)
        buffsLabel.zPosition = 20
        addChild(buffsLabel)

        setUpWeaponButton(center: CGPoint(x: columnLeft + 104, y: columnTop - 362))
        updateHUD()
    }

    /// Every weapon and how it's earned — the MILESTONES page.
    private func rebuildMilestonesPage() {
        milestonesPageNode.removeAllChildren()
        // Everything goes into a container the wheel shifts up/down, so a long
        // arsenal list can be scrolled past the bottom edge (see handleScroll).
        let column = SKNode()
        milestonesPageNode.addChild(column)
        let boardSide = min(size.width, size.height) * boardScale
        let columnLeft = (size.width + boardSide) / 2 + 16
        let columnTop = (size.height + boardSide) / 2
        var y = columnTop - 56

        func addLine(_ text: String, font: String, size fontSize: CGFloat, color: SKColor, drop: CGFloat) {
            let label = SKLabelNode(text: text)
            label.fontName = font
            label.fontSize = fontSize
            label.fontColor = color
            label.horizontalAlignmentMode = .left
            label.verticalAlignmentMode = .top
            label.position = CGPoint(x: columnLeft, y: y)
            column.addChild(label)
            y -= drop
        }

        let gold = SKColor(red: 0.93, green: 0.80, blue: 0.45, alpha: 1.0)
        let earned = SKColor(white: 0.75, alpha: 1.0)
        let locked = SKColor(white: 0.45, alpha: 1.0)
        addLine("THE ARSENAL", font: "HelveticaNeue-Bold", size: 15, color: gold, drop: 28)

        // A slim progress bar for a locked milestone, count at its right end.
        func addProgressBar(progress: Int, total: Int) {
            let width: CGFloat = 172
            let height: CGFloat = 8
            let bar = SKNode()
            bar.position = CGPoint(x: columnLeft, y: y - height / 2)
            let back = SKShapeNode(rectOf: CGSize(width: width, height: height), cornerRadius: 4)
            back.fillColor = SKColor(white: 0.18, alpha: 1.0)
            back.strokeColor = SKColor(white: 0.35, alpha: 1.0)
            back.lineWidth = 1
            back.position = CGPoint(x: width / 2, y: 0)
            bar.addChild(back)
            if progress > 0 {
                let fillWidth = max(height, width * CGFloat(progress) / CGFloat(total)) - 3
                let fill = SKShapeNode(rectOf: CGSize(width: fillWidth, height: height - 3), cornerRadius: 2.5)
                fill.fillColor = gold.withAlphaComponent(0.85)
                fill.strokeColor = .clear
                fill.position = CGPoint(x: fillWidth / 2 + 1.5, y: 0)
                bar.addChild(fill)
            }
            let count = SKLabelNode(text: "\(progress)/\(total)")
            count.fontName = "HelveticaNeue"
            count.fontSize = 10
            count.fontColor = locked
            count.horizontalAlignmentMode = .left
            count.verticalAlignmentMode = .center
            count.position = CGPoint(x: width + 8, y: 0)
            bar.addChild(count)
            column.addChild(bar)
            y -= 20
        }

        let available = Set(currentWeaponPool().map(\.name))
        let lifetime = lifetimeTallies
        // Unlocked weapons rise to the top; alphabetical within each group.
        let sortedArsenal = Weapon.all.sorted { a, b in
            let aOwned = available.contains(a.name), bOwned = available.contains(b.name)
            if aOwned != bOwned { return aOwned }
            return a.name < b.name
        }
        for weapon in sortedArsenal {
            let owned = available.contains(weapon.name)
            let nameColor = owned ? earned : locked
            addLine(owned ? "✓ \(weapon.name)" : "· \(weapon.name)",
                    font: "HelveticaNeue-Bold", size: 13, color: nameColor, drop: 17)
            if Weapon.baseArsenal.contains(where: { $0.name == weapon.name }) {
                addLine("starting arsenal", font: "HelveticaNeue", size: 12, color: nameColor, drop: 21)
            } else if let milestone = Weapon.milestones.first(where: { $0.weapon.name == weapon.name }) {
                if owned {
                    addLine(milestone.requirement + " — done", font: "HelveticaNeue", size: 12, color: nameColor, drop: 21)
                } else {
                    addLine(milestone.requirement, font: "HelveticaNeue", size: 12, color: nameColor, drop: 17)
                    let progress = min(lifetime[milestone.tally, default: 0], milestone.count)
                    addProgressBar(progress: progress, total: milestone.count)
                }
            } else {
                addLine(owned ? "trophy claimed from a gatekeeper" : "claim one off a fallen gatekeeper",
                        font: "HelveticaNeue", size: 12, color: nameColor, drop: 21)
            }
        }

        // Whatever spilled past the bottom edge becomes scrollable: shift the
        // whole column up by the wheel offset, clamped to the overflow.
        let bottomMargin: CGFloat = 16
        milestonesMaxScroll = max(0, bottomMargin - y)
        milestonesScroll = min(milestonesScroll, milestonesMaxScroll)
        column.position = CGPoint(x: 0, y: milestonesScroll)
    }

    /// Switches the right column's visible page and repaints the nav bar.
    private func setHUDPage(_ page: HUDPage) {
        hudPage = page
        boardPageNode.isHidden = page != .board
        milestonesPageNode.isHidden = page != .milestones
        let selected = SKColor(red: 0.55, green: 0.75, blue: 0.95, alpha: 1.0)
        navTabLabels["board"]?.fontColor = page == .board ? selected : SKColor(white: 0.5, alpha: 1.0)
        navTabLabels["milestones"]?.fontColor = page == .milestones ? selected : SKColor(white: 0.5, alpha: 1.0)
        navTabLabels["home"]?.fontColor = SKColor(white: 0.5, alpha: 1.0)
    }

    /// A single button showing the equipped weapon; clicking it (or pressing
    /// Tab/Q) swaps to the holstered weapon.
    private func setUpWeaponButton(center: CGPoint) {
        let buttonSize = Self.weaponButtonSize
        let button = SKShapeNode(rectOf: buttonSize, cornerRadius: 8)
        button.fillColor = SKColor(red: 0.25, green: 0.45, blue: 0.60, alpha: 1.0)
        button.strokeColor = .white
        button.lineWidth = 1.5
        button.zPosition = 20
        button.name = Self.weaponButtonName
        button.position = center

        weaponLabel = SKLabelNode()
        weaponLabel.fontName = "HelveticaNeue-Bold"
        weaponLabel.fontSize = 15
        weaponLabel.fontColor = .white
        weaponLabel.verticalAlignmentMode = .center
        weaponLabel.position = CGPoint(x: 0, y: 11)
        weaponLabel.name = Self.weaponButtonName
        button.addChild(weaponLabel)

        weaponSubLabel = SKLabelNode()
        weaponSubLabel.fontName = "HelveticaNeue"
        weaponSubLabel.fontSize = 11
        weaponSubLabel.fontColor = SKColor(white: 0.85, alpha: 1.0)
        weaponSubLabel.verticalAlignmentMode = .center
        weaponSubLabel.position = CGPoint(x: 0, y: -13)
        weaponSubLabel.name = Self.weaponButtonName
        button.addChild(weaponSubLabel)

        weaponButtonIcon = SKSpriteNode(
            texture: nil, color: .clear,
            size: CGSize(width: Self.weaponIconSize, height: Self.weaponIconSize)
        )
        weaponButtonIcon.position = CGPoint(x: -buttonSize.width / 2 + Self.weaponIconInset, y: 0)
        weaponButtonIcon.name = Self.weaponButtonName
        button.addChild(weaponButtonIcon)

        boardPageNode.addChild(button)
        weaponButton = button
    }

    /// The equipped weapon's sprite on its HUD button — the third place the
    /// one weapon PNG is used (hand, floor, HUD). It tracks the reload the
    /// same way the held weapon does, so the button and the hand agree.
    /// Empty until the art exists.
    private func updateWeaponButtonIcon() {
        weaponButtonIcon?.texture = Art.weaponTexture(state.equippedWeapon, ready: playerWeaponIsReady)
    }

    private var legendNode: SKNode?
    private var expandedLegendSections: Set<LegendSection> = []
    /// Scroll wheel offset for the left dropdowns, so a long open section (the
    /// weapon list) can be read past the bottom edge.
    private var legendScroll: CGFloat = 0
    private var legendMaxScroll: CGFloat = 0
    /// Scroll wheel offset for the milestones page, so the full arsenal list can
    /// be read past the bottom edge.
    private var milestonesScroll: CGFloat = 0
    private var milestonesMaxScroll: CGFloat = 0

    /// The left margin, two columns: weapon/enemy reference dropdowns at the
    /// far edge, how-to-play primer and keybinds beside them. Rebuilt whenever
    /// a dropdown is toggled.
    private func setUpControlsLegend() {
        rebuildLegend()
    }

    private enum LegendSection: String {
        case howToPlay, turnOrder, keys, weapons, enemies, tiles
    }

    private func rebuildLegend() {
        legendNode?.removeFromParent()
        let column = SKNode()
        column.zPosition = 20
        addChild(column)
        legendNode = column

        let boardSide = min(size.width, size.height) * boardScale
        let topEdge = (size.height + boardSide) / 2
        var y = topEdge

        func addLine(
            _ text: String,
            x: CGFloat,
            font: String = "HelveticaNeue",
            size fontSize: CGFloat = 13,
            color: SKColor = SKColor(white: 0.7, alpha: 1.0),
            name: String? = nil,
            drop: CGFloat = 20
        ) {
            let label = SKLabelNode(text: text)
            label.fontName = font
            label.fontSize = fontSize
            label.fontColor = color
            label.horizontalAlignmentMode = .left
            label.verticalAlignmentMode = .top
            label.position = CGPoint(x: x, y: y)
            label.name = name
            column.addChild(label)
            y -= drop
        }

        // A single left column of collapsible dropdowns — clean by default, so
        // new players lean on the tutorial and open a section only when curious.
        let referenceX: CGFloat = 14
        let toggleColor = SKColor(red: 0.55, green: 0.75, blue: 0.95, alpha: 1.0)
        let entryColor = SKColor(white: 0.75, alpha: 1.0)
        let statColor = SKColor(white: 0.55, alpha: 1.0)

        /// A dropdown header; returns whether its section is expanded.
        func header(_ title: String, _ section: LegendSection, drop: CGFloat = 24) -> Bool {
            let open = expandedLegendSections.contains(section)
            addLine("\(open ? "▾" : "▸") \(title)", x: referenceX,
                    font: "HelveticaNeue-Bold", size: 15, color: toggleColor,
                    name: "legendToggle:\(section.rawValue)", drop: drop)
            return open
        }
        /// A plain wrapped text body under a header; blank strings are spacers.
        func addBody(_ bodyLines: [String]) {
            for text in bodyLines {
                addLine(text, x: referenceX + 2, size: 13.5, color: statColor, drop: text.isEmpty ? 10 : 20)
            }
            y -= 6
        }

        addLine("▸ new here? play the tutorial", x: referenceX,
                font: "HelveticaNeue-Bold", size: 14, color: toggleColor,
                name: "tutorialButton", drop: 22)
        addLine("▸ advanced tactics", x: referenceX,
                font: "HelveticaNeue-Bold", size: 14, color: toggleColor,
                name: "advancedTutorialButton", drop: 30)

        if header("HOW TO PLAY", .howToPlay) {
            addBody([
                "Draft a move, then aim an attack",
                "or swap weapon (Tab) — swapping",
                "costs your attack. Then hit GO;",
                "enemies commit to the arrows",
                "you can see.",
                "",
                "Hover an enemy for its health,",
                "weapon, and attack pattern.",
                "",
                "red tiles · incoming attack",
                "! · arrival — hover to see what",
                "gold ring · weapon on floor",
                "purple ring · elite trophy",
                "",
                "Move 2+ tiles without acting to",
                "dodge one hit. Armor refills each",
                "level and regens on calm turns;",
                "HP never does.",
                "",
                "Hit the score milestone and a",
                "gatekeeper spawns — kill it to",
                "level up and take its weapons.",
            ])
        }
        y -= 8
        if header("TURN ORDER", .turnOrder) {
            addBody([
                "Each GO resolves in this order —",
                "plan around it:",
                "",
                "1 · daze & cooldowns tick down",
                "2 · you move",
                "3 · enemies move (their arrows)",
                "4 · airborne bolts & shells fly",
                "5 · your action: attack / grapple",
                "     / omen (knockback & barrel",
                "     shoves happen here)",
                "6 · enemies strike — bombers blow,",
                "     then swings; you're knocked",
                "     back or reeled in now",
                "7 · end of turn: spikes & pools",
                "     bite, bleeds tick",
                "8 · reinforcements telegraph for",
                "     next turn",
                "",
                "So: you always move before your",
                "hit lands, and enemies move before",
                "it too — aim where they'll be.",
            ])
        }
        y -= 8
        if header("KEYS", .keys) {
            addBody([
                "click · draft move",
                "right-click · aim attack",
                "   (reloading ranged? 1 dmg jab)",
                "E · pick up weapon underfoot",
                "tab/Q · swap weapon \(state.swapsAreFree ? "(free)" : "(costs attack)")",
                "F · ultimate when charged",
                "esc · cancel draft",
                "space/return · GO",
                "R×2 · restart",
            ])
        }
        y -= 8
        if header("WEAPONS", .weapons) {
            // Only the collected arsenal shows here; locked weapons and their
            // requirements live on the MILESTONES page.
            let available = Set(currentWeaponPool().map(\.name))
            for weapon in Weapon.all.filter({ available.contains($0.name) }).sorted(by: { $0.name < $1.name }) {
                let (name, stats) = weaponLegendEntry(weapon)
                addLine(name, x: referenceX, font: "HelveticaNeue-Bold", size: 15, color: entryColor, drop: 20)
                addLine(stats, x: referenceX + 12, size: 13.5, color: statColor, drop: 26)
            }
        }
        y -= 8
        if header("ENEMIES", .enemies) {
            // Name gets the same bold white highlight as the weapon entries;
            // its behavior lines sit dimmed beneath it.
            let entries: [(archetype: Archetype, name: String, details: [String])] = [
                (.fighter, "Fighter", ["any weapon, kites"]),
                (.berserker, "Berserker", ["melee, fearless"]),
                (.swift, "Swift", ["+1 move"]),
                (.bomber, "Bomber", ["arms at range \(GameState.bomberArmDistance),",
                                     "blast r\(GameState.bomberBlastRadius), on fuse or death"]),
                (.shieldbearer, "Shieldbearer", ["parries the first head-on",
                                                 "swing; flank it or blast it"]),
                (.reaver, "Reaver", ["rare; 1 dmg per hit", "pierces your armor"]),
                (.juggernaut, "Juggernaut", ["the gate,", "summons waves"]),
                (.summoner, "Summoner", ["the gate; frail caster that",
                                         "floods the board with fodder"]),
                (.bombardier, "Bombardier", ["the gate; summons bomber swarms,",
                                             "rains red barrels, lobs ordnance"]),
                (.boss, "Boss", ["the gate, drafts:",
                                 "volley, cannon nova, summon,",
                                 "or lob red barrels then",
                                 "detonate — all scale w/ depth"]),
            ]
            for (archetype, name, details) in entries.sorted(by: { $0.name < $1.name }) {
                // A little rotated-square swatch in the archetype's colour and
                // relative size — the same art the board draws.
                let style = enemyStyle(archetype)
                let swatchSize = max(9, 9 + (style.sizeFactor - 0.45) * 20)
                let swatch = SKShapeNode(rectOf: CGSize(width: swatchSize, height: swatchSize), cornerRadius: 1)
                swatch.zRotation = .pi / 4
                swatch.fillColor = style.fill
                swatch.strokeColor = style.stroke
                swatch.lineWidth = 1.5
                swatch.position = CGPoint(x: referenceX + 10, y: y - 8)
                column.addChild(swatch)
                addLine(name, x: referenceX + 26, font: "HelveticaNeue-Bold", size: 15, color: entryColor, drop: 20)
                for detail in details {
                    addLine(detail, x: referenceX + 26, size: 13.5, color: statColor, drop: 20)
                }
                y -= 6
            }
        }
        y -= 8
        if header("TILES", .tiles) {
            let swatches: [(SKColor, String)] = [
                (SKColor(red: 0.18, green: 0.36, blue: 0.25, alpha: 1.0), "tiles you can move to"),
                (SKColor(red: 0.80, green: 0.62, blue: 0.22, alpha: 1.0), "your drafted destination"),
                (SKColor(red: 0.68, green: 0.32, blue: 0.12, alpha: 1.0), "your attack lands here"),
                (SKColor(red: 0.58, green: 0.12, blue: 0.10, alpha: 1.0), "enemy attack / incoming"),
                (SKColor(red: 0.42, green: 0.16, blue: 0.46, alpha: 1.0), "arrival materializes here"),
                (SKColor(red: 0.62, green: 0.26, blue: 0.06, alpha: 1.0), "burning pool — hotter is redder"),
                (SKColor(red: 0.18, green: 0.36, blue: 0.48, alpha: 1.0), "throw range"),
                (SKColor(white: 0.95, alpha: 1.0), "ult wave / blocked spawn"),
                (SKColor(red: 0.90, green: 0.28, blue: 0.24, alpha: 1.0), "spike trap — bites while lit, toggles each turn"),
                (SKColor(red: 0.55, green: 0.80, blue: 1.0, alpha: 1.0), "portal — warps you (and enemies) across"),
                (SKColor(red: 0.42, green: 0.34, blue: 0.24, alpha: 1.0), "crumbling wall — a hit or blast breaks it"),
                (SKColor(red: 0.85, green: 0.50, blue: 0.15, alpha: 1.0), "barrel — orange bursts, green burns, yellow weak"),
            ]
            for (color, text) in swatches {
                let swatch = SKSpriteNode(color: color, size: CGSize(width: 13, height: 13))
                swatch.position = CGPoint(x: referenceX + 7, y: y - 7)
                column.addChild(swatch)
                addLine(text, x: referenceX + 20, size: 14, color: statColor, drop: 22)
            }
        }

        // Whatever spilled past the bottom edge becomes scrollable: shift the
        // whole column up by the wheel offset, clamped to the overflow.
        let bottomMargin: CGFloat = 16
        legendMaxScroll = max(0, bottomMargin - y)
        legendScroll = min(legendScroll, legendMaxScroll)
        column.position = CGPoint(x: 0, y: legendScroll)
    }

    /// Shared scroll logic; `event` is the platform-neutral input snapshot,
    /// dispatched by the per-platform responder adapters at the end of the file.
    func handleScroll(_ event: GameInput) {
        // Scrolling down reveals lower entries (content shifts up); natural
        // scrolling flips that so the content tracks the fingers.
        let delta = naturalScrolling ? -event.scrollDeltaY : event.scrollDeltaY
        // Scroll the region under the pointer: the milestones page fills the right
        // column, the legend the left. The board's right edge divides them.
        let boardSide = min(size.width, size.height) * boardScale
        let rightColumnLeft = (size.width + boardSide) / 2
        if hudPage == .milestones && event.location.x >= rightColumnLeft {
            guard milestonesMaxScroll > 0 else { return }
            milestonesScroll = min(milestonesMaxScroll, max(0, milestonesScroll - delta))
            rebuildMilestonesPage()
            return
        }
        guard legendMaxScroll > 0 else { return }
        legendScroll = min(legendMaxScroll, max(0, legendScroll - delta))
        rebuildLegend()
    }

    // MARK: - Tutorial

    /// The live coach behind "new here? play the tutorial": each step advances
    /// off the real input it teaches. Weapon swapping (a trade-off, since it
    /// costs your attack) is covered in the showcase cards afterward rather than
    /// as a gated step.
    private enum TutorialStep: Int {
        case hover, move, attack, go

        var prompt: String {
            switch self {
            case .hover:
                return "TUTORIAL 1/4 · hover an enemy to inspect it — the red tiles are everything its attack will hit"
            case .move:
                return "TUTORIAL 2/4 · left-click a green tile to draft your move — nothing moves until you commit"
            case .attack:
                return "TUTORIAL 3/4 · now right-click an enemy — you get a move AND an attack every turn. Orange is where your strike lands, from where you WILL be standing"
            case .go:
                return "TUTORIAL 4/4 · press SPACE (or click GO) — you and every enemy resolve at once"
            }
        }
    }

    private var tutorialStep: TutorialStep?
    private var tutorialPrompt: SKNode?
    /// Set when the last interactive step finishes, so the next resolve rolls
    /// into the showcase once turn one has fully played out.
    private var tutorialShowcasePending = false
    /// True while the sandboxed showcase runs — board input is frozen.
    private var tutorialShowcasing = false
    /// The run's real state, stashed while the showcase mutates a throwaway copy.
    private var tutorialSnapshot: GameState?
    /// The next showcase beat, run on the player's click so they read at their
    /// own pace. Nil during the boon-pick beat (the picker drives that one).
    private var tutorialAdvance: (() -> Void)?
    /// True on the beginner showcase's closing beat, where a click rolls into the
    /// advanced tutorial and Esc skips it.
    private var offeringAdvanced = false
    /// True while an interactive lesson runs (beginner showcase or advanced): the
    /// board is LIVE, a persistent NEXT/EXIT banner drives it, and it's sandboxed
    /// over the real run.
    private var advancedTutorialActive = false
    private var advancedLessonIndex = 0
    private var advancedOverlay: SKNode?
    /// What the NEXT button does on the current lesson beat (nil = no NEXT button;
    /// something else, like the boon picker, drives the advance).
    private var lessonNext: (() -> Void)?
    /// True through the beginner showcase (swap → formation → gatekeeper → level),
    /// so the boon pick knows to roll into the closing card.
    private var beginnerShowcaseActive = false
    /// When the advanced tutorial was opened from the draft, SKIP/FINISH returns
    /// there rather than dropping the player into a run they never configured.
    private var advancedReturnToBuildPicker = false

    private func startTutorial() {
        // Snapshot the real run, then coach on a plain, pact-free copy so the
        // lessons always match the vanilla rules — a rolled Quickhands (or any
        // pact) shouldn't rewrite what the tutorial teaches. The snapshot is
        // restored when the showcase ends, so the real run (pact and all) is
        // untouched.
        tutorialSnapshot = state
        // makeRunState resets the lifetime-tally baseline; keep the real run's so
        // a mid-run replay's progress accounting survives the sandbox.
        let savedBaseline = tallyBaseline
        state = makeRunState(modifiersOverride: [])
        // Not invincible: hits have to cost something or the tutorial teaches
        // that they don't, and the first real hit of a run comes as a nasty
        // surprise. A killing blow coaches and revives instead — see
        // `tutorialRevive`.
        tallyBaseline = savedBaseline
        resyncBoardToState()
        tutorialStep = .hover
        showTutorialPrompt(TutorialStep.hover.prompt)
    }

    /// Each step lands as a framed banner dead-center on the board — hard to
    /// miss — then glides up out of the way while the player performs it.
    /// Auto-dismissing banners (the 5/4 coda) linger up top, then see
    /// themselves out.
    private func showTutorialPrompt(_ text: String, autoDismiss: Bool = false, then: (() -> Void)? = nil) {
        tutorialPrompt?.removeFromParent()
        let boardSide = min(size.width, size.height) * boardScale
        let container = SKNode()
        container.zPosition = 75

        let label = SKLabelNode(text: text)
        label.fontName = "HelveticaNeue-Bold"
        label.fontSize = 15
        label.fontColor = SKColor(red: 0.93, green: 0.80, blue: 0.45, alpha: 1.0)
        label.verticalAlignmentMode = .center
        label.numberOfLines = 0
        label.preferredMaxLayoutWidth = boardSide - 60

        let plate = SKShapeNode(
            rectOf: CGSize(width: label.frame.width + 36, height: label.frame.height + 22),
            cornerRadius: 9
        )
        plate.fillColor = SKColor(white: 0.06, alpha: 0.92)
        plate.strokeColor = SKColor(red: 0.93, green: 0.80, blue: 0.45, alpha: 0.8)
        plate.lineWidth = 1.5
        container.addChild(plate)
        container.addChild(label)

        container.position = CGPoint(x: size.width / 2, y: size.height / 2)
        container.setScale(0.6)
        container.alpha = 0
        addChild(container)
        tutorialPrompt = container

        let rest = CGPoint(x: size.width / 2, y: (size.height + boardSide) / 2 + 18)
        var sequence: [SKAction] = [
            SKAction.group([
                SKAction.fadeIn(withDuration: 0.15),
                SKAction.scale(to: 1.0, duration: 0.18),
            ]),
            SKAction.wait(forDuration: 1.4),
            SKAction.group([
                SKAction.move(to: rest, duration: 0.35),
                SKAction.scale(to: 0.8, duration: 0.35),
            ]),
        ]
        if autoDismiss {
            sequence += [
                SKAction.wait(forDuration: 3.0),
                SKAction.fadeOut(withDuration: 0.6),
                SKAction.removeFromParent(),
                SKAction.run { [weak self] in
                    if self?.tutorialPrompt === container {
                        self?.tutorialPrompt = nil
                    }
                    then?()
                },
            ]
        }
        container.run(SKAction.sequence(sequence))
    }

    /// True while any coached lesson is running — the four beginner steps, the
    /// showcase beats, or the advanced track.
    private var inTutorial: Bool {
        tutorialStep != nil || tutorialShowcasePending || advancedTutorialActive
    }

    /// The "you would have died there" callout. Red-edged and dead-center on the
    /// board so it can't be mistaken for the gold lesson banner above it, and
    /// its own node so it never displaces the current step's prompt. Sees itself
    /// out after a few seconds; the board is already playable again.
    private func showTutorialRescue(_ killer: String) {
        let boardSide = min(size.width, size.height) * boardScale
        let container = SKNode()
        container.zPosition = 78

        let label = SKLabelNode(
            text: "CAREFUL · \(killer) would have finished you there. In a real run that ends it — read the red tiles before you commit. Patched you up; carry on."
        )
        label.fontName = "HelveticaNeue-Bold"
        label.fontSize = 15
        label.fontColor = SKColor(red: 0.96, green: 0.58, blue: 0.52, alpha: 1.0)
        label.verticalAlignmentMode = .center
        label.numberOfLines = 0
        label.preferredMaxLayoutWidth = boardSide - 120

        let plate = SKShapeNode(
            rectOf: CGSize(width: label.frame.width + 36, height: label.frame.height + 22),
            cornerRadius: 9
        )
        plate.fillColor = SKColor(white: 0.06, alpha: 0.94)
        plate.strokeColor = SKColor(red: 0.95, green: 0.45, blue: 0.40, alpha: 0.9)
        plate.lineWidth = 1.5
        container.addChild(plate)
        container.addChild(label)

        container.position = CGPoint(x: size.width / 2, y: size.height / 2)
        container.alpha = 0
        addChild(container)
        container.run(SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.15),
            SKAction.wait(forDuration: 3.2),
            SKAction.fadeOut(withDuration: 0.5),
            SKAction.removeFromParent(),
        ]))
    }

    /// Steps forward when the taught input actually happened, in order; after
    /// the last interactive step it arms the showcase, which fires once turn one
    /// has finished resolving.
    private func advanceTutorial(after completed: TutorialStep) {
        guard tutorialStep == completed else { return }
        if let next = TutorialStep(rawValue: completed.rawValue + 1) {
            tutorialStep = next
            showTutorialPrompt(next.prompt)
        } else {
            tutorialStep = nil
            tutorialShowcasePending = true
        }
    }

    /// Snapshots the run and force-plays a formation, a gatekeeper, and a real
    /// level-up on a throwaway copy — so the player sees each system without
    /// grinding, and the run is restored untouched afterward.
    private func startTutorialShowcase() {
        // Snapshot was taken back in startTutorial. Run the showcase as live,
        // interactive lessons (same as the advanced track): board playable, a
        // NEXT/EXIT banner drives it, so the player tries each system firsthand.
        tutorialPrompt?.removeFromParent()
        tutorialPrompt = nil
        beginnerShowcaseActive = true
        advancedTutorialActive = true
        advancedReturnToBuildPicker = false   // launched from a live run
        showcaseSwap()
    }

    private func showcaseSwap() {
        // Honest to the run's rules: if the player took the Quickhands pact,
        // swapping really is free — don't teach the costly default over it.
        let cost = state.swapsAreFree
            ? "and you took Quickhands, so it's free."
            : "but it costs your attack that turn (a boon can make it free)."
        buildLessonOverlay(
            text: "SWAP WEAPONS · press Tab (or tap the weapon button) to swap to your holstered weapon — try it. It changes your reach and attack, \(cost)"
        ) { [weak self] in self?.showcaseFormation() }
    }

    private func showcaseFormation() {
        state.tutorialSpawnFormation()
        resyncBoardToState()
        buildLessonOverlay(
            text: "FORMATIONS · enemies sometimes march in as a squad, holding ranks until they close, then breaking to swarm. Take a swing if you like."
        ) { [weak self] in self?.showcaseGatekeeper() }
    }

    private func showcaseGatekeeper() {
        state.tutorialSpawnGatekeeper()
        resyncBoardToState()
        buildLessonOverlay(
            // The four archetypes and their tricks are all in the ENEMIES
            // dropdown; reciting them here made this the longest card by far.
            text: "GATEKEEPERS · every level is locked until its gatekeeper falls, and every third gate is a BOSS. Read its telegraph before you commit — the ENEMIES dropdown lists what each one does."
        ) { [weak self] in self?.showcaseLevelUp() }
    }

    private func showcaseLevelUp() {
        // The boon picker drives this beat, so no NEXT button — picking a boon
        // (see chooseBuff) rolls into the closing card.
        state.tutorialLevelUp()
        resyncBoardToState()
        buildLessonOverlay(
            text: "LEVELING · hit the score bar to level up — the board resets, your armor refills, and you pick a boon. Pick one to continue.",
            next: nil
        )
        showBuffChoice(forLevel: state.level)
    }

    /// The boon pick's hand-off (called from chooseBuff): a closing card. NEXT
    /// rolls into the advanced tutorial; EXIT drops straight into the run.
    private func finishTutorialShowcase() {
        beginnerShowcaseActive = false
        buildLessonOverlay(
            text: "THAT'S THE GIST · one last trick: move 2+ tiles without attacking and you dodge a hit. The rest is in the dropdowns on the left. Want the ADVANCED tactics — barrels, ice, grapple, blink? NEXT to learn them, EXIT to play."
        ) { [weak self] in
            self?.advancedReturnToBuildPicker = false   // chained into a live run
            self?.startAdvancedTutorial()
        }
    }

    // MARK: - Advanced tutorial
    // A separate opt-in track for environmental combat and the utility weapons.
    // Unlike the beginner showcase, these lessons are *played*: the board is live,
    // free swaps are on, and a persistent banner + NEXT/SKIP drives progression.
    // It sandboxes over the live context and restores it when done.

    private struct AdvancedLesson {
        let demo: GameState.TutorialDemo
        let text: String
    }

    private let advancedLessons: [AdvancedLesson] = [
        // Each card names the one thing to try. Flavor catalogues (barrel
        // colours, tile behaviour) live in the TILES dropdown — repeating them
        // here buried the instruction.
        AdvancedLesson(demo: .barrels, text: "KNOCKBACK & BARRELS · you're holding the Ram (knockback 2). Attack the enemy beside you to fling it into the barrel behind it. Slamming a foe into a wall or off the edge bruises it too — and it cuts both ways. (Tab swaps to the Keg: lob it to drop your own barrel.)"),
        AdvancedLesson(demo: .spikes, text: "SPIKES · lit tiles bite whoever ends the turn on them, then toggle. Attack the enemy — the Ram flings it across the live spikes for a bite on the way. Mind your own footing."),
        AdvancedLesson(demo: .teleporters, text: "TELEPORTERS · step onto the portal to warp to its linked twin across the board. Enemies path through them to reach you, and a bolt fired through one flies out the far side."),
        AdvancedLesson(demo: .ice, text: "ICE · a move that ends on ice slides you on down the strip until something stops you, and the gold marker shows where you'll really land. Draft a step onto the ice and slide into the foe."),
        AdvancedLesson(demo: .mud, text: "MUD · crossing a mud tile eats an extra step — yours or an enemy's. Route around it, or use it to slow a foe closing on you."),
        AdvancedLesson(demo: .walls, text: "WALLS · brown walls crumble: smash one with a swing or a blast to open a path. Grey walls are solid."),
        AdvancedLesson(demo: .grapple, text: "GRAPPLE · right-click a direction to fire it: aim RIGHT at the enemy to reel it in, UP at the wall to haul yourself over, or LEFT at the barrel to yank it into your lap for a 2 damage hit."),
        AdvancedLesson(demo: .slipstep, text: "SLIPSTEP · sends you 7 tiles but barely scratches them. Go next to the enemy, then Tab to the Sword (free) and strike the same turn. Next turn, swap back and get out."),
    ]

    private func startAdvancedTutorial() {
        // Standalone launch snapshots the live context; chained off the beginner
        // tutorial it keeps that snapshot. Roll a clean sandbox with free swaps on
        // so the swap combos are actually learnable.
        if tutorialSnapshot == nil { tutorialSnapshot = state }
        let savedBaseline = tallyBaseline
        state = makeRunState(modifiersOverride: [])
        state.devFreeSwap = true
        // Damage is real here too; `tutorialRevive` catches a killing blow.
        tallyBaseline = savedBaseline
        tutorialPrompt?.removeFromParent()
        tutorialPrompt = nil
        offeringAdvanced = false
        beginnerShowcaseActive = false      // advanced has no boon-pick beat
        tutorialShowcasing = false          // the board is LIVE for these lessons
        advancedTutorialActive = true
        showAdvancedLesson(0)
    }

    private func showAdvancedLesson(_ index: Int) {
        guard advancedLessons.indices.contains(index) else { endAdvancedTutorial(); return }
        advancedLessonIndex = index
        state.tutorialSetupDemo(advancedLessons[index].demo)
        resyncBoardToState()
        buildLessonOverlay(text: advancedLessons[index].text, isLast: index == advancedLessons.count - 1) { [weak self] in
            self?.showAdvancedLesson(index + 1)
        }
    }

    private func endAdvancedTutorial() {
        advancedTutorialActive = false
        beginnerShowcaseActive = false
        lessonNext = nil
        advancedOverlay?.removeFromParent()
        advancedOverlay = nil
        // Bailing mid boon-pick (the level-up beat) leaves the picker up; clear it.
        buffChoiceOverlay?.removeFromParent()
        buffChoiceOverlay = nil
        if let snapshot = tutorialSnapshot { state = snapshot }
        tutorialSnapshot = nil
        resyncBoardToState()
        // Opened from the draft: return there so the player picks their own run,
        // rather than being dropped into the sandbox loadout.
        if advancedReturnToBuildPicker {
            advancedReturnToBuildPicker = false
            showBuildPicker()
        }
    }

    /// A persistent coaching banner for an interactive lesson, plus an EXIT
    /// button and — when `next` is given — a NEXT/FINISH button. The board stays
    /// playable beneath it, so the player experiments before advancing.
    private func buildLessonOverlay(text: String, isLast: Bool = false, next: (() -> Void)?) {
        lessonNext = next
        advancedOverlay?.removeFromParent()
        let overlay = SKNode()
        overlay.zPosition = 80
        addChild(overlay)
        advancedOverlay = overlay

        let boardSide = min(size.width, size.height) * boardScale
        let topEdge = (size.height + boardSide) / 2

        let label = SKLabelNode(text: text)
        label.fontName = "HelveticaNeue-Bold"
        label.fontSize = 14
        label.fontColor = SKColor(red: 0.93, green: 0.80, blue: 0.45, alpha: 1.0)
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.numberOfLines = 0
        label.preferredMaxLayoutWidth = boardSide - 60
        // A card tall enough to outgrow the strip above the board would hang its
        // plate off the top of the scene, where the first lines are simply
        // clipped away. Clamp the centre down until the whole plate fits: it
        // reaches further over the board, which stays legible beneath it.
        let plateHeight = label.frame.height + 22
        label.position = CGPoint(
            x: size.width / 2,
            y: min(topEdge - 6, size.height - plateHeight / 2 - 10)
        )

        let plate = SKShapeNode(
            rectOf: CGSize(width: label.frame.width + 36, height: plateHeight),
            cornerRadius: 9
        )
        plate.fillColor = SKColor(white: 0.06, alpha: 0.92)
        plate.strokeColor = SKColor(red: 0.93, green: 0.80, blue: 0.45, alpha: 0.8)
        plate.lineWidth = 1.5
        plate.position = label.position
        overlay.addChild(plate)
        overlay.addChild(label)

        func button(_ title: String, name: String, x: CGFloat, fill: SKColor) {
            let node = SKShapeNode(rectOf: CGSize(width: 124, height: 30), cornerRadius: 6)
            node.fillColor = fill
            node.strokeColor = SKColor(white: 0.9, alpha: 0.9)
            node.lineWidth = 1.5
            node.position = CGPoint(x: x, y: plate.position.y - plate.frame.height / 2 - 24)
            node.name = name
            let title = SKLabelNode(text: title)
            title.fontName = "HelveticaNeue-Bold"
            title.fontSize = 13
            title.fontColor = .white
            title.verticalAlignmentMode = .center
            title.name = name
            node.addChild(title)
            overlay.addChild(node)
        }
        button("EXIT ✕", name: "advTutorial:skip", x: next == nil ? size.width / 2 : size.width / 2 - 72,
               fill: SKColor(white: 0.20, alpha: 0.95))
        if next != nil {
            button(isLast ? "FINISH ▸" : "NEXT ▸", name: "advTutorial:next", x: size.width / 2 + 72,
                   fill: SKColor(red: 0.20, green: 0.42, blue: 0.62, alpha: 0.95))
        }
    }

    /// Rebuilds the board sprites and HUD to match the current `state` — used at
    /// each showcase beat and when the snapshot is restored.
    private func resyncBoardToState() {
        rebuildBoardEntities()
        // The player may have moved during the guided turn; snap the sprite back
        // to wherever `state` now says it stands (rebuildBoardEntities doesn't).
        playerNode.position = point(for: state.playerPosition)
        updatePlanArrow()
        updateHUD()
        updateEnemyPlanArrows()
        updateSpawnMarkers()
        updateWeaponDropNodes()
        updateCacheNodes()
        updateProjectileNodes()
        updateBomberFuses()
        updatePickupHint()
        refreshTileHighlights()
    }

    /// A name line and a compact stat line per weapon for the reference column.
    private func weaponLegendEntry(_ weapon: Weapon) -> (name: String, stats: String) {
        var traits: [String] = []
        if let thrown = weapon.thrown {
            traits.append("lob r\(thrown.range)")
        }
        if weapon.projectileSpeed != nil {
            traits.append("bolt")
        }
        if weapon.impactBlastRadius > 0 {
            traits.append("burst")
        }
        if weapon.pierces {
            traits.append("pierce")
        }
        if weapon.lingering != nil {
            traits.append("trail")
        }
        if let affliction = weapon.affliction {
            traits.append("bleed \(affliction.damagePerTurn)×\(affliction.duration)")
        }
        if weapon.stun > 0 {
            traits.append("stun \(weapon.stun)")
        }
        if weapon.knockback > 0 {
            traits.append("knock \(weapon.knockback)")
        }
        if weapon.cooldown > 0 {
            traits.append("cd\(weapon.cooldown)")
        }
        let name = weapon.name == Weapon.cannon.name ? "\(weapon.name) · boss drop" : weapon.name
        let tail = traits.isEmpty ? "" : " " + traits.joined(separator: " ")
        // A deal-double boon (Sharpened) applies run-wide, so every weapon's
        // listed damage reflects it — matching the equipped-weapon button.
        let multiplier = RunRules(activeModifiers).damageDealtMult
        let shownDamage = Int((Double(weapon.damage) * multiplier).rounded())
        return (name, "\(shownDamage)dmg \(weapon.moveRange)mv\(tail)")
    }

    /// Redraws a pip row: one cell per point, filled up to `filled`.
    private func drawPips(in container: SKNode, filled: Int, total: Int, color: SKColor) {
        container.removeAllChildren()
        guard total > 0 else { return }
        let step: CGFloat = min(21, 208 / CGFloat(total))
        let side = step - 3
        for index in 0..<total {
            let cell = SKShapeNode(rectOf: CGSize(width: side, height: 16), cornerRadius: 3)
            cell.position = CGPoint(x: CGFloat(index) * step + side / 2, y: 0)
            cell.fillColor = index < filled ? color : SKColor(white: 0.18, alpha: 1.0)
            cell.strokeColor = index < filled ? color : SKColor(white: 0.35, alpha: 1.0)
            cell.lineWidth = 1
            container.addChild(cell)
        }
    }

    /// The ultimate as a filling bar; pulses gold once it's ready to call down.
    private func updateUltimateBar() {
        ultimateBarNode.removeAllChildren()
        let width: CGFloat = 208
        let height: CGFloat = 14
        let back = SKShapeNode(rectOf: CGSize(width: width, height: height), cornerRadius: 5)
        back.fillColor = SKColor(white: 0.18, alpha: 1.0)
        back.strokeColor = SKColor(white: 0.35, alpha: 1.0)
        back.lineWidth = 1
        back.position = CGPoint(x: width / 2, y: 0)
        ultimateBarNode.addChild(back)

        // Banked charges replace the fill entirely: there's nothing to charge
        // toward until they're spent, so a creeping bar would be a lie.
        if state.omenCharges > 0 {
            let pips = SKLabelNode(text: String(repeating: "◆", count: state.omenCharges))
            pips.fontName = "HelveticaNeue-Bold"
            pips.fontSize = 13
            pips.fontColor = SKColor(red: 1.0, green: 0.72, blue: 0.35, alpha: 1.0)
            pips.horizontalAlignmentMode = .left
            pips.verticalAlignmentMode = .center
            pips.position = CGPoint(x: 6, y: 0)
            ultimateBarNode.addChild(pips)

            let charged = SKLabelNode(text: "right-click a barrel")
            charged.fontName = "HelveticaNeue-Bold"
            charged.fontSize = 11
            charged.fontColor = SKColor(red: 1.0, green: 0.8, blue: 0.5, alpha: 1.0)
            charged.horizontalAlignmentMode = .right
            charged.verticalAlignmentMode = .bottom
            charged.position = CGPoint(x: width, y: 12)
            ultimateBarNode.addChild(charged)
            return
        }

        let ready = state.ultimateKillCharge >= state.ultimateChargeKills
        let fraction = min(1, CGFloat(state.ultimateKillCharge) / CGFloat(state.ultimateChargeKills))
        if fraction > 0 {
            let fillWidth = max(height, width * fraction) - 4
            let fill = SKShapeNode(rectOf: CGSize(width: fillWidth, height: height - 4), cornerRadius: 3)
            fill.fillColor = ready
                ? SKColor(red: 1.0, green: 0.85, blue: 0.30, alpha: 1.0)
                : SKColor(red: 0.72, green: 0.58, blue: 0.22, alpha: 1.0)
            fill.strokeColor = .clear
            fill.position = CGPoint(x: fillWidth / 2 + 2, y: 0)
            ultimateBarNode.addChild(fill)
            if ready {
                fill.run(SKAction.repeatForever(SKAction.sequence([
                    SKAction.fadeAlpha(to: 0.55, duration: 0.5),
                    SKAction.fadeAlpha(to: 1.0, duration: 0.5),
                ])))
            }
        }

        // The counter shares the caption row, right-aligned over the bar's end.
        let hint = SKLabelNode(text: ready ? "F ✦       READY" : "\(state.ultimateKillCharge)/\(state.ultimateChargeKills)")
        hint.fontName = "HelveticaNeue-Bold"
        hint.fontSize = 11
        hint.fontColor = ready
            ? SKColor(red: 1.0, green: 0.9, blue: 0.45, alpha: 1.0)
            : SKColor(white: 0.65, alpha: 1.0)
        hint.horizontalAlignmentMode = .right
        hint.verticalAlignmentMode = .bottom
        hint.position = CGPoint(x: width, y: 12)
        ultimateBarNode.addChild(hint)
    }

    private func updateHUD() {
        if state.rules.hideHealth {
            // Blindfold pact: no health readout — fight by feel.
            healthBarNode.removeAllChildren()
            let hidden = SKLabelNode(text: "HP ? ? ?")
            hidden.fontName = "HelveticaNeue-Bold"
            hidden.fontSize = 15
            hidden.fontColor = SKColor(red: 0.85, green: 0.25, blue: 0.30, alpha: 1.0)
            hidden.horizontalAlignmentMode = .left
            hidden.verticalAlignmentMode = .center
            healthBarNode.addChild(hidden)
        } else {
            drawPips(
                in: healthBarNode,
                filled: max(0, state.playerHealth),
                total: max(state.maxHealth, state.playerHealth),
                color: SKColor(red: 0.85, green: 0.25, blue: 0.30, alpha: 1.0)
            )
        }
        drawPips(
            in: armorBarNode,
            filled: max(0, state.playerArmor),
            total: max(state.armorCap, state.playerArmor),
            color: armorFlashColor
        )
        updateUltimateBar()
        var playerStatuses: [String] = []
        if let wound = state.playerAffliction {
            playerStatuses.append("BLEEDING \(wound.damagePerTurn) dmg/turn for \(wound.turnsRemaining) turns")
        }
        if state.playerStunTurns > 0 {
            playerStatuses.append("STUNNED · attack disabled")
        }
        // The cold gets its own row under the ult bar rather than joining the
        // affliction line: frostbite's whole payload *is* a stun, so the two
        // would collide on the same line at the one moment both matter. It
        // shows from the first slide and clears once the cold has bled off.
        // The last stack before the cliff shouts, since by then the next slide
        // costs a whole action.
        freezeLabel.isHidden = state.freezeStacks <= 0
        if state.freezeStacks > 0 {
            freezeLabel.text = state.freezeIsCritical
                ? "❄ FREEZING \(state.freezeStacks)/\(GameState.frostbiteAt) — ONE MORE SLIDE AND YOU SEIZE UP"
                : "❄ FREEZING \(state.freezeStacks)/\(GameState.frostbiteAt)"
            // Brighter, not a different hue: it stays unmistakably the cold
            // rather than borrowing the red the affliction row already owns.
            freezeLabel.fontColor = state.freezeIsCritical
                ? SKColor(red: 0.85, green: 0.97, blue: 1.0, alpha: 1.0)
                : SKColor(red: 0.55, green: 0.80, blue: 0.98, alpha: 1.0)
        }
        afflictionLabel.text = playerStatuses.joined(separator: "  ·  ")
        afflictionLabel.isHidden = playerStatuses.isEmpty
        dodgeChipLabel.isHidden = !state.plannedDodgeReady
        let nextLevel = GameState.scoreThreshold(forLevel: state.level + 1)
        let streak = state.killStreak >= 2 ? " · STREAK ×\(state.killStreak)" : ""
        let progress = state.bossPhase ? "\(state.score) · SLAY THE GATEKEEPER" : "\(state.score)/\(nextLevel)"
        // While the best is frozen it neither climbs nor persists, and the whole
        // score line turns blue to make the testing mode unmistakable.
        let best = devFreezeHighScore ? highScore : max(highScore, state.score)
        scoreLabel.text = "LVL \(state.level) · \(state.biome.title.uppercased()) · SCORE \(progress)\(streak) · TURN \(state.turnNumber) · BEST \(best)"
        scoreLabel.fontColor = devFreezeHighScore ? SKColor(red: 0.45, green: 0.65, blue: 0.95, alpha: 1.0) : .white

        // The run's pact: the boon (gold) and curse (red) as separate hoverable
        // pieces, laid out as one centered row.
        rebuildPactHUD(state.modifiers)

        // Held buffs, deduplicated into "name ×2 (3 lv)" style in pickup order;
        // the level count shows the soonest expiry of the stack.
        var buffTexts: [String] = []
        var seenBuffs: [Buff] = []
        for held in state.heldBuffs where !seenBuffs.contains(held.buff) {
            seenBuffs.append(held.buff)
            let stack = state.heldBuffs.filter { $0.buff == held.buff }
            var text = held.buff.name
            if stack.count > 1 {
                text += " ×\(stack.count)"
            }
            if let soonest = stack.compactMap(\.levelsRemaining).min() {
                text += " (\(soonest) lv)"
            }
            // A cache boon is gone in a handful of turns, so its countdown has
            // to be louder than the level-scoped ones sharing this row — the
            // player is already tracking telegraphs, cooldowns and omen charge,
            // and a quiet "(2)" tucked among them lapses unnoticed.
            if let soonest = stack.compactMap(\.turnsRemaining).min() {
                text += soonest == 1 ? " ‼ LAST TURN" : " \(soonest) TURNS"
            }
            buffTexts.append(text)
        }
        buffsLabel.text = buffTexts.joined(separator: " · ")
        let cooldown = state.attackCooldownRemaining(of: state.equippedWeapon)
        let readiness = cooldown > 0 ? " · ready in \(cooldown)" : ""
        weaponLabel.text = "\(state.equippedWeapon.name) · move \(state.moveRange) · dmg \(state.attackDamage)\(readiness)"
        weaponSubLabel.text = "swap ⇄ \(state.holsteredWeapon.name) · \(state.swapsAreFree ? "free" : "costs attack")"
        updateWeaponButtonIcon()

        if state.weaponSwapCostsAttack {
            itemsLabel.text = "swapped to \(state.equippedWeapon.name) — spends your attack (swap back to undo)"
        } else if state.plannedBash {
            let bashDmg = Int((Double(GameState.bashDamage) * state.rules.damageDealtMult).rounded())
            itemsLabel.text = "bash drafted — a \(bashDmg) dmg jab while the \(state.equippedWeapon.name) reloads"
        } else if state.plannedUltimate {
            itemsLabel.text = "omen drafted — \(state.omen.blurb)"
        } else if state.plannedDetonateTarget != nil {
            itemsLabel.text = "charge drafted — that barrel goes off"
        } else if let pickup = state.plannedPickupWeapon {
            itemsLabel.text = "picking up \(pickup.name) — no attack or dodge this turn"
        } else if let underfoot = state.weaponDrop(at: state.playerPosition) {
            itemsLabel.text = "E · pick up \(underfoot.weapon.name) (costs your attack)"
        } else if let thrown = state.equippedWeapon.thrown {
            let flight = thrown.flightTurns > 0 ? " · lands in \(thrown.flightTurns)" : ""
            itemsLabel.text = "thrown · rclick a tile in range (\(thrown.range))\(flight)"
        } else if let lingering = state.equippedWeapon.lingering {
            itemsLabel.text = "leaves hazard: \(lingering.damagePerTurn) dmg for \(lingering.duration) turns"
        } else {
            itemsLabel.text = ""
        }

        // Centre the labels in whatever the icon left them, then shrink long
        // loadouts ("Crossbow · move 1 · dmg 2 · ready in 2") to fit that
        // column rather than spilling across the icon or out of the button.
        // Driven off the texture actually being set, so a weapon whose art
        // hasn't been drawn yet still gets the full width.
        let column = Self.weaponTextColumn(hasIcon: weaponButtonIcon?.texture != nil)
        weaponLabel.position.x = column.centerX
        weaponSubLabel.position.x = column.centerX
        fitLabel(weaponLabel, within: column.width)
        fitLabel(weaponSubLabel, within: column.width)
    }

    /// Scales a label down (never up) so its text fits the given width.
    private func fitLabel(_ label: SKLabelNode, within maxWidth: CGFloat) {
        label.setScale(1.0)
        let width = label.frame.width
        if width > maxWidth && width > 0 {
            label.setScale(maxWidth / width)
        }
    }

    // MARK: - Grid geometry

    /// Board-space center point of a tile.
    private func point(for position: GridPosition) -> CGPoint {
        CGPoint(
            x: (CGFloat(position.x) - CGFloat(state.columns - 1) / 2) * tileSize,
            y: (CGFloat(position.y) - CGFloat(state.rows - 1) / 2) * tileSize
        )
    }

    /// The tile under a scene-space point, if any.
    private func gridPosition(at sceneLocation: CGPoint) -> GridPosition? {
        let local = convert(sceneLocation, to: boardNode)
        let position = GridPosition(
            x: Int(round(local.x / tileSize + CGFloat(state.columns - 1) / 2)),
            y: Int(round(local.y / tileSize + CGFloat(state.rows - 1) / 2))
        )
        return state.contains(position) ? position : nil
    }

    // MARK: - Highlighting

    private func refreshTileHighlights() {
        // Every path that changes the state ends here, so the bodies re-pose
        // and re-arm from the same call — drafting an aim turns the player,
        // and a swap puts the new weapon in their hand immediately.
        refreshActorSprites()

        let planning = !isResolving && !state.isGameOver
        let legalTargets = planning ? state.legalMoveTargets() : []
        var attackTiles = planning ? Set(state.plannedAttackTiles) : []
        if planning {
            attackTiles.formUnion(state.plannedOmenTiles)
        }
        // Thrown weapons show their landing range while planning so right-click
        // targeting is readable.
        let throwRange = planning ? state.throwTargets() : []
        let spawnTiles = planning ? Set(state.pendingSpawns).union(state.pendingBarrelSpawns) : []
        // Damage per hazard tile, live effects taking precedence over the
        // held-from-last-turn snapshot.
        var hazardDamages = heldHazardTiles ?? [:]
        if revealLiveHazards {
            for effect in state.lingeringEffects {
                hazardDamages[effect.position] = effect.damagePerTurn
            }
        }
        // Live spikes telegraph the bite they'll deal at end of turn.
        for spike in state.spikes where spike.active {
            hazardDamages[spike.position] = GameState.spikeDamage
        }
        // Planning a move onto ice or a portal foresees where the player truly
        // ends up: the slide's resting tile (plannedLanding), then any warp from
        // it, lit gold as the real destination — and the tile a drafted attack
        // will swing from.
        var plannedWarpExit: GridPosition?
        if planning, state.plannedTarget != nil {
            let exit = state.plannedDestination
            if exit != state.plannedLanding { plannedWarpExit = exit }
        }

        // Incoming shells and armed bombers always telegraph their zones; while
        // aiming a bolt weapon, the trajectory beyond the first window reads as
        // red too.
        var threatTiles: Set<GridPosition> = planning ? Set(state.projectileThreatTiles) : []
        if planning {
            threatTiles.formUnion(state.plannedAttackLaterTiles)
            threatTiles.formUnion(state.bomberThreatTiles)
        }
        if planning, let hovered = hoveredTile {
            if let enemy = state.enemy(at: hovered) {
                // Show the enemy's drafted attack; fall back to an indicative
                // shape (pattern facing up, or blast around a thrower) when it
                // isn't attacking this turn.
                let drafted = state.threatTiles(of: enemy)
                if !drafted.isEmpty {
                    threatTiles.formUnion(drafted)
                } else if let pattern = enemy.weapon.attackPattern {
                    // Aim the indicative shape at the player, as the enemy would
                    // when it strikes — a fixed "up" clips a top-row enemy's
                    // preview entirely off the board and shows nothing.
                    let facing = Direction.aiming(from: enemy.position, toward: state.playerPosition,
                                                  allowDiagonals: pattern.supportsDiagonals) ?? .up
                    threatTiles.formUnion(pattern.tiles(from: enemy.position, facing: facing).filter(state.contains))
                } else if let thrown = enemy.weapon.thrown {
                    threatTiles.formUnion(state.blastTiles(around: enemy.position, radius: thrown.blastRadius, includeCenter: true))
                }
            } else if let obstacle = state.obstacle(at: hovered), obstacle.kind == .barrel {
                threatTiles.formUnion(state.blastTiles(around: hovered, radius: GameState.barrelBlastRadius + state.rules.barrelBlastBonus))
            }
        }

        // Only repaint what actually changed. Moving the mouse one tile used
        // to rewrite all 225 colours, and every write dirties that layer —
        // which on the web drags the textured layers through the renderer's
        // upload path again and stalls the frame behind the GPU. Two or three
        // tiles really change per hover; the rest are a no-op.
        for (position, tile) in tileNodes {
            let appearance = TileAppearance(
                isLegalTarget: legalTargets.contains(position),
                isPlannedAttack: attackTiles.contains(position),
                isEnemyThreat: threatTiles.contains(position),
                hazardDamage: hazardDamages[position],
                isThrowRange: throwRange.contains(position),
                isSpawnTelegraph: spawnTiles.contains(position),
                isPlannedDestination: position == plannedWarpExit,
                isPlannedTarget: position == state.plannedTarget,
                isHovered: position == hoveredTile,
                biome: state.biome
            )
            guard tileAppearances[position] != appearance else { continue }
            tileAppearances[position] = appearance
            tile.color = tileColor(
                for: position,
                isLegalTarget: appearance.isLegalTarget,
                isPlannedAttack: appearance.isPlannedAttack,
                isEnemyThreat: appearance.isEnemyThreat,
                hazardDamage: appearance.hazardDamage,
                isThrowRange: appearance.isThrowRange,
                isSpawnTelegraph: appearance.isSpawnTelegraph,
                isPlannedDestination: appearance.isPlannedDestination
            )
        }
        // A destructible wall sits on top of its tile, hiding the tile-color
        // telegraph, so tint the wall itself: orange when the planned attack
        // covers it, red when an enemy will smash it open this turn.
        let crumbleBase = SKColor(red: 0.42, green: 0.34, blue: 0.24, alpha: 1.0)
        let attackTint = SKColor(red: 0.85, green: 0.40, blue: 0.15, alpha: 1.0)
        let breachTint = SKColor(red: 0.60, green: 0.28, blue: 0.20, alpha: 1.0)
        // Every crumbling wall that won't survive the enemies' phase: the tile a
        // boxed-in enemy digs out by hand, plus everything its drafted attack
        // sweeps — a swing at a wall breaks the whole pattern's worth, and a
        // swing aimed at the player takes out any crumbling wall in the way.
        // Only tiles from an enemy that is actually attacking count; an idle
        // bomber's threatTiles previews its blast radius, which would otherwise
        // paint walls it has no plan to touch.
        var breachTiles: Set<GridPosition> = []
        if planning {
            for enemy in state.enemies {
                if let dig = enemy.plannedDigTile { breachTiles.insert(dig) }
                guard enemy.plannedDirection != nil || enemy.plannedThrowTarget != nil
                    || enemy.plannedIntent != nil else { continue }
                breachTiles.formUnion(state.threatTiles(of: enemy))
            }
        }
        for (position, node) in obstacleNodes {
            // A crumbling wall is a container (fill + crack seam), so reach in for
            // the named fill sprite; a plain wall is the sprite itself.
            let sprite = (node as? SKSpriteNode) ?? (node.childNode(withName: "crumbleFill") as? SKSpriteNode)
            guard let wall = sprite, state.obstacle(at: position)?.destructible == true else { continue }
            // Same reason as the tiles: repaint only on a change. Barricades
            // fills the board with these, so a blind rewrite is 200 dirtied
            // layers every time the pointer crosses a tile.
            let tint: WallTint = attackTiles.contains(position) ? .attack
                : breachTiles.contains(position) ? .breach : .base
            guard wallTints[position] != tint else { continue }
            wallTints[position] = tint
            switch tint {
            case .attack: wall.color = attackTint
            case .breach: wall.color = breachTint
            case .base: wall.color = crumbleBase
            }
        }
    }

    /// Paints a tile outside the highlight pass — a swing flash, a blocked
    /// spawn. Forgets the cached appearance so the next refresh repaints it
    /// rather than assuming the colour it left there is still on screen.
    private func paintTile(_ position: GridPosition, _ color: SKColor) {
        tileNodes[position]?.color = color
        tileAppearances[position] = nil
    }

    private func tileColor(
        for position: GridPosition,
        isLegalTarget: Bool,
        isPlannedAttack: Bool,
        isEnemyThreat: Bool,
        hazardDamage: Int?,
        isThrowRange: Bool,
        isSpawnTelegraph: Bool,
        isPlannedDestination: Bool
    ) -> SKColor {
        let isDarkTile = (position.x + position.y) % 2 == 0
        if isEnemyThreat {
            return SKColor(red: isDarkTile ? 0.52 : 0.58, green: 0.12, blue: 0.10, alpha: 1.0)
        }
        // The gold destination marks either the drafted tile or, when that tile
        // warps, the portal's exit.
        if position == state.plannedTarget || isPlannedDestination {
            return SKColor(red: 0.80, green: 0.62, blue: 0.22, alpha: 1.0)
        }
        if isPlannedAttack {
            return SKColor(red: isDarkTile ? 0.62 : 0.68, green: 0.32, blue: 0.12, alpha: 1.0)
        }
        if isSpawnTelegraph {
            return SKColor(red: 0.42, green: 0.16, blue: 0.46, alpha: 1.0)
        }
        if let hazardDamage {
            // Hotter pools burn brighter and redder: 1 dmg is ember orange,
            // 4+ approaches open flame.
            let heat = min(CGFloat(hazardDamage), 4) / 4
            return SKColor(
                red: (isDarkTile ? 0.42 : 0.46) + 0.32 * heat,
                green: 0.36 - 0.20 * heat,
                blue: 0.06,
                alpha: 1.0
            )
        }
        // Legal moves draw over the throw-range hint: left-click movement stays
        // readable while a thrown weapon is equipped.
        if isLegalTarget {
            let brightness: CGFloat = position == hoveredTile ? 0.55 : (isDarkTile ? 0.30 : 0.36)
            return SKColor(red: brightness * 0.5, green: brightness, blue: brightness * 0.7, alpha: 1.0)
        }
        if isThrowRange {
            return SKColor(red: 0.18, green: isDarkTile ? 0.32 : 0.36, blue: 0.48, alpha: 1.0)
        }
        // Only the *resting* floor is tinted by biome. Every telegraph colour
        // above returns before this point, so the language the player reads
        // under pressure — green walkable, red incoming, orange yours — is
        // pixel-identical on every floor. The biome shifts the quiet ground
        // it's all drawn on, which is enough to feel a change of place without
        // anything having to be relearned.
        let shade: CGFloat = isDarkTile ? 0.16 : 0.20
        switch state.biome {
        case .plains:
            // Neutral grey — the original board, and the baseline the other
            // two are read against.
            return SKColor(white: shade, alpha: 1.0)
        case .forest:
            return SKColor(red: shade * 0.72, green: shade * 1.12, blue: shade * 0.68, alpha: 1.0)
        case .tundra:
            return SKColor(red: shade * 0.80, green: shade * 1.02, blue: shade * 1.30, alpha: 1.0)
        }
    }

    /// Full mid-flight readout for a bolt: heading, damage, speed, and how much
    /// further it can travel measured from the inspected tile.
    private func boltHoverText(_ bolt: Bolt, at tile: GridPosition) -> String {
        let travelled = max(abs(tile.x - bolt.position.x), abs(tile.y - bolt.position.y))
        let remaining = bolt.remainingRange - travelled
        let range = remaining <= 0 ? "expires here" : "\(remaining) tiles past here"
        // Lead with what fired it — weapon and owner — so the bolt's type is
        // obvious, then tag the traits that tell the flavors apart.
        let blast = bolt.impactBlastRadius > 0 ? " · bursts r\(bolt.impactBlastRadius)" : ""
        let fire = bolt.lingering != nil ? " · leaves fire" : ""
        let bleed = bolt.affliction != nil ? " · bleeds" : ""
        return "\(bolt.sourceName) \(bolt.direction.arrow) · \(bolt.damage) dmg · \(bolt.speed) tiles/turn\(blast)\(fire)\(bleed) · \(range)"
    }

    /// Pulsing prompt above the player when they're standing on a weapon drop,
    /// so the pickup option is discoverable without reading the HUD.
    private func updatePickupHint() {
        pickupHintLabel?.removeFromParent()
        pickupHintLabel = nil
        guard !isResolving, !state.isGameOver,
              let drop = state.weaponDrop(at: state.playerPosition) else { return }

        let text = state.plannedPickup
            ? "picking up \(drop.weapon.name)"
            : "E · pick up \(drop.weapon.name)"
        let label = SKLabelNode(text: text)
        label.fontName = "HelveticaNeue-Bold"
        label.fontSize = 13
        label.fontColor = SKColor(red: 0.95, green: 0.85, blue: 0.35, alpha: 1.0)
        label.verticalAlignmentMode = .bottom
        let anchor = point(for: state.playerPosition)
        label.position = CGPoint(x: anchor.x, y: anchor.y + tileSize * 0.55)
        label.zPosition = 30
        boardNode.addChild(label)
        if !state.plannedPickup {
            label.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.fadeAlpha(to: 0.45, duration: 0.55),
                SKAction.fadeAlpha(to: 1.0, duration: 0.55),
            ])))
        }
        pickupHintLabel = label
    }

    /// Floating one-liner above a hovered tile, tracked as the current hover info.
    private func addHoverLabel(_ text: String, at tile: GridPosition, color: SKColor) {
        let label = SKLabelNode(text: text)
        label.fontName = "HelveticaNeue-Bold"
        label.fontSize = 12
        label.fontColor = color
        label.verticalAlignmentMode = .bottom
        let anchor = point(for: tile)
        label.position = CGPoint(x: anchor.x, y: anchor.y + tileSize * 0.45)
        label.zPosition = 30
        boardNode.addChild(label)
        enemyInfoLabel = label
    }

    /// Shows the hovered enemy's health (or a ground weapon's name, or a
    /// hazard's burn stats) above the tile; the red threat tiles are handled by
    /// refreshTileHighlights.
    private func updateEnemyHoverInfo() {
        enemyInfoLabel?.removeFromParent()
        enemyInfoLabel = nil
        guard !isResolving, let hovered = hoveredTile else { return }

        guard let enemy = state.enemy(at: hovered) else {
            if let drop = state.weaponDrop(at: hovered), hovered != state.playerPosition {
                // (Standing on it already shows the persistent pickup hint.)
                addHoverLabel(
                    "\(drop.weapon.name) · stand here + E to swap",
                    at: hovered,
                    color: SKColor(red: 0.95, green: 0.85, blue: 0.35, alpha: 1.0)
                )
            } else if let barrel = state.obstacle(at: hovered), barrel.kind == .barrel {
                let radius = GameState.barrelBlastRadius + state.rules.barrelBlastBonus
                let text: String
                let color: SKColor
                switch barrel.barrelKind {
                case .fire:
                    text = "green barrel · no blast · leaves fire \(GameState.fireBarrelDamage)/turn · blast r\(radius) · chains"
                    color = SKColor(red: 0.35, green: 0.80, blue: 0.40, alpha: 1.0)
                case .weak:
                    text = "yellow barrel · \(GameState.weakBarrelDamage) dmg · blast r\(radius) · chains"
                    color = SKColor(red: 0.90, green: 0.85, blue: 0.30, alpha: 1.0)
                case .standard:
                    text = "barrel · \(GameState.barrelDamage) dmg · blast r\(radius) · chains"
                    color = SKColor(red: 0.90, green: 0.55, blue: 0.15, alpha: 1.0)
                }
                addHoverLabel(text, at: hovered, color: color)
            } else if let bolt = state.bolt(at: hovered) ?? state.bolt(threatening: hovered) {
                addHoverLabel(
                    boltHoverText(bolt, at: hovered),
                    at: hovered,
                    color: SKColor(red: 0.95, green: 0.45, blue: 0.35, alpha: 1.0)
                )
            } else if let shell = state.lobShell(over: hovered) ?? state.projectileImpact(at: hovered) {
                let heading = Direction.aiming(from: shell.origin, toward: shell.target, allowDiagonals: true)?.arrow ?? ""
                let turns = shell.turnsUntilImpact == 1 ? "1 turn" : "\(shell.turnsUntilImpact) turns"
                addHoverLabel(
                    "shell \(heading) · \(shell.damage) dmg · lands in \(turns)",
                    at: hovered,
                    color: SKColor(red: 0.95, green: 0.45, blue: 0.35, alpha: 1.0)
                )
            } else if let effect = state.lingeringEffect(at: hovered) {
                let turns = effect.turnsRemaining == 1 ? "1 turn" : "\(effect.turnsRemaining) turns"
                addHoverLabel(
                    "hazard · \(effect.damagePerTurn) dmg/turn · \(turns) left",
                    at: hovered,
                    color: SKColor(red: 0.95, green: 0.60, blue: 0.25, alpha: 1.0)
                )
            } else if let spike = state.spikes.first(where: { $0.position == hovered }) {
                let phase = spike.active ? "active · bites at end of turn" : "dormant · arms next turn"
                addHoverLabel(
                    "spikes · \(phase) · \(GameState.spikeDamage) dmg",
                    at: hovered,
                    color: spike.active
                        ? SKColor(red: 0.95, green: 0.35, blue: 0.30, alpha: 1.0)
                        : SKColor(red: 0.70, green: 0.72, blue: 0.75, alpha: 1.0)
                )
            } else if state.teleporters.contains(where: { $0.a == hovered || $0.b == hovered }) {
                addHoverLabel(
                    "portal · step on to warp to its other end",
                    at: hovered,
                    color: SKColor(red: 0.55, green: 0.80, blue: 1.0, alpha: 1.0)
                )
            } else if state.cache(at: hovered) != nil {
                // Checked before the terrain branch below: a cache always sits
                // on mud, so the mud label would otherwise swallow it.
                //
                // Says nothing about what's inside, on purpose — the player is
                // betting a known cost in tempo against an unknown return, and
                // naming the prize here would turn that bet into arithmetic.
                addHoverLabel(
                    "cache · buried in the mud · dig it up to see",
                    at: hovered,
                    color: SKColor(red: 0.45, green: 0.88, blue: 0.68, alpha: 1.0)
                )
            } else if let terrain = state.terrainKind(at: hovered) {
                switch terrain {
                case .ice:
                    addHoverLabel(
                        "ice · +1 move · a move ending here slides you on",
                        at: hovered,
                        color: SKColor(red: 0.70, green: 0.88, blue: 1.0, alpha: 1.0)
                    )
                case .mud:
                    addHoverLabel(
                        "mud · costs an extra move to slog into",
                        at: hovered,
                        color: SKColor(red: 0.72, green: 0.58, blue: 0.40, alpha: 1.0)
                    )
                }
            } else if let arrival = state.pendingArrivals.first(where: { $0.position == hovered }) {
                addHoverLabel(
                    "\(arrival.displayName) arrives next turn · stand here to block (1 dmg)",
                    at: hovered,
                    color: SKColor(red: 0.95, green: 0.45, blue: 0.85, alpha: 1.0)
                )
            } else if state.pendingBarrelSpawns.contains(hovered) {
                addHoverLabel(
                    "barrel lands here next turn · stand here to block it",
                    at: hovered,
                    color: SKColor(red: 0.90, green: 0.55, blue: 0.15, alpha: 1.0)
                )
            }
            return
        }

        // Cooldown weapons always show their status so the attack windows are
        // readable — ranged weapons reload, melee ones recover their swing.
        // Bombers show their fuse instead.
        var status = ""
        if enemy.archetype == .bomber {
            let fuse = enemy.fuse.map { "DETONATES in \($0)" } ?? "unarmed"
            status = " · blast r\(GameState.bomberBlastRadius) · \(GameState.bomberDamage) dmg · \(fuse)"
        } else if enemy.weapon.cooldown > 0 {
            let waiting = enemy.weapon.isMelee ? "ready in" : "reloading"
            status = enemy.cooldownRemaining > 0 ? " · \(waiting) \(enemy.cooldownRemaining)" : " · ready"
        }
        if let wound = enemy.affliction {
            status += " · BLEEDING \(wound.damagePerTurn)/turn ×\(wound.turnsRemaining)"
        }
        if enemy.stunTurns > 0 {
            status += " · STUNNED ×\(enemy.stunTurns)"
        }
        // Readable for the same reason the player's counter is: an enemy near
        // the cliff is one you can herd onto ice instead of hitting.
        if enemy.freezeStacks > 0 {
            status += " · ❄ \(enemy.freezeStacks)/\(GameState.frostbiteAt)"
        }
        if enemy.archetype == .shieldbearer, let facing = enemy.facing {
            status += enemy.shieldReady ? " · shield \(facing.arrow)" : " · shield down"
        }
        if enemy.archetype == .reaver {
            status += " · pierces 1 armor"
        }
        // The boss telegraphs which of its three plays comes next resolve.
        if let intent = enemy.plannedIntent {
            switch intent {
            case .volley: status += " · NEXT: FULL VOLLEY"
            case .nova: status += " · NEXT: CANNON NOVA"
            case .barrage: status += " · NEXT: BARREL BARRAGE"
            case .detonate: status += " · NEXT: DETONATE"
            case .summon: status += " · NEXT: SUMMONING"
            }
        }
        let label = SKLabelNode(text: "\(enemy.displayName) · HP \(enemy.health)\(status)")
        label.fontName = "HelveticaNeue-Bold"
        label.fontSize = 12
        label.fontColor = .white
        label.verticalAlignmentMode = .bottom
        let anchor = point(for: enemy.position)
        label.position = CGPoint(x: anchor.x, y: anchor.y + tileSize * 0.45)
        label.zPosition = 30
        boardNode.addChild(label)
        enemyInfoLabel = label
    }

    // MARK: - Plan arrows

    /// Straight arrow between two tile centers, inset at the start so it doesn't
    /// overlap the piece it points away from.
    private func makeArrowNode(from start: CGPoint, to end: CGPoint, color: SKColor, lineWidth: CGFloat, startInset: CGFloat) -> SKShapeNode {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let shaftStart = CGPoint(
            x: start.x + cos(angle) * startInset,
            y: start.y + sin(angle) * startInset
        )
        let headLength = tileSize * 0.28

        let path = CGMutablePath()
        path.move(to: shaftStart)
        path.addLine(to: end)
        for wing in [angle + .pi * 0.85, angle - .pi * 0.85] as [CGFloat] {
            path.move(to: end)
            path.addLine(to: CGPoint(x: end.x + cos(wing) * headLength, y: end.y + sin(wing) * headLength))
        }

        let arrow = SKShapeNode(path: path)
        arrow.strokeColor = color
        arrow.lineWidth = lineWidth
        arrow.lineCap = .round
        return arrow
    }

    /// Redraws the arrow from the player to the planned tile.
    /// No arrow is shown when the plan is to stay put.
    private func updatePlanArrow() {
        planArrowNode?.removeFromParent()
        planArrowNode = nil
        // Draw to the true resting tile: an ice slide carries the player past
        // the drafted tile, so the arrow follows all the way there.
        guard state.plannedTarget != nil else { return }
        let target = state.plannedLanding
        guard target != state.playerPosition else { return }

        let arrow = makeArrowNode(
            from: point(for: state.playerPosition),
            to: point(for: target),
            color: SKColor(red: 0.95, green: 0.80, blue: 0.30, alpha: 1.0),
            lineWidth: 3,
            startInset: tileSize * 0.38
        )
        arrow.zPosition = 15
        boardNode.addChild(arrow)
        planArrowNode = arrow
    }

    /// Redraws every enemy's telegraphed move so the player can plan around them.
    private func updateEnemyPlanArrows() {
        enemyPlanArrowNodes.forEach { $0.removeFromParent() }
        enemyPlanArrowNodes.removeAll()
        guard !state.isGameOver else { return }

        for enemy in state.enemies {
            guard let target = enemy.plannedTarget, target != enemy.position else { continue }
            let arrow = makeArrowNode(
                from: point(for: enemy.position),
                to: point(for: target),
                color: SKColor(red: 0.95, green: 0.40, blue: 0.35, alpha: 0.85),
                lineWidth: 2,
                startInset: tileSize * 0.30
            )
            arrow.zPosition = 14
            boardNode.addChild(arrow)
            enemyPlanArrowNodes.append(arrow)
        }

        refreshShieldPlanks()

        // Dazed combatants (the player included) wear a little orbit of stars
        // where their threat would be — they plan nothing until it wears off.
        refreshStunMarkers()
    }

    /// Puts — or clears — the dazed-stars marker on the player and every enemy
    /// so it matches the current stun state. The marker rides each body, so it
    /// tracks movement and vanishes with an enemy on death.
    private func refreshStunMarkers() {
        playerNode.childNode(withName: "stunStars")?.removeFromParent()
        if state.playerStunTurns > 0 {
            playerNode.addChild(makeStunStars())
        }
        for (id, node) in enemyNodes {
            node.childNode(withName: "stunStars")?.removeFromParent()
            if let enemy = state.enemies.first(where: { $0.id == id }), enemy.stunTurns > 0 {
                node.addChild(makeStunStars())
            }
        }
    }

    /// A steel plank on each shieldbearer's front, telegraphing the side its
    /// parry covers so a flank can be set up. It's a child of the enemy's
    /// actor node, so it rides along during the move animation instead of
    /// floating off (or vanishing). That node is unrotated — the placeholder
    /// diamond carries its own 45° — so the plank sits at its world angle.
    private func refreshShieldPlanks() {
        for (id, node) in enemyNodes {
            node.childNode(withName: "shieldPlank")?.removeFromParent()
            // Only while the shield is actually up — a parried shield is down a
            // turn, and drawing the plank then would lie.
            guard let enemy = state.enemies.first(where: { $0.id == id }),
                  enemy.archetype == .shieldbearer, enemy.shieldReady,
                  let facing = enemy.facing else { continue }
            let step = facing.unitStep
            let length = hypot(CGFloat(step.x), CGFloat(step.y))
            guard length > 0 else { continue }
            let unit = CGPoint(x: CGFloat(step.x) / length, y: CGFloat(step.y) / length)
            let worldAngle = atan2(unit.y, unit.x)

            let plank = SKShapeNode(rectOf: CGSize(width: tileSize * 0.5, height: max(3, tileSize * 0.1)), cornerRadius: 2)
            plank.fillColor = SKColor(red: 0.82, green: 0.87, blue: 0.93, alpha: 0.95)
            plank.strokeColor = .clear
            plank.name = "shieldPlank"
            plank.zPosition = 5

            plank.zRotation = worldAngle + .pi / 2
            let offset = tileSize * 0.34
            plank.position = CGPoint(x: unit.x * offset, y: unit.y * offset)
            node.addChild(plank)
        }
    }

    /// The classic "seeing stars" marker: three sparks that slowly orbit above
    /// the head and twinkle out of phase. Named "stunStars" so a refresh can
    /// find and remove it.
    private func makeStunStars() -> SKNode {
        let ring = SKNode()
        ring.name = "stunStars"
        ring.position = CGPoint(x: 0, y: tileSize * 0.46)
        ring.zPosition = 30
        let count = 3
        let orbit = tileSize * 0.17
        for index in 0..<count {
            let angle = CGFloat(index) / CGFloat(count) * .pi * 2
            let star = SKLabelNode(text: "✦")
            star.fontName = "HelveticaNeue-Bold"
            star.fontSize = tileSize * 0.26
            star.fontColor = SKColor(red: 1.0, green: 0.90, blue: 0.45, alpha: 1.0)
            star.verticalAlignmentMode = .center
            star.horizontalAlignmentMode = .center
            star.position = CGPoint(x: cos(angle) * orbit, y: sin(angle) * orbit)
            star.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.fadeAlpha(to: 0.30, duration: 0.4),
                SKAction.fadeAlpha(to: 1.0, duration: 0.4),
            ])))
            ring.addChild(star)
        }
        ring.run(SKAction.repeatForever(SKAction.rotate(byAngle: .pi * 2, duration: 1.6)))
        return ring
    }

    // MARK: - Turn flow

    /// Stores the chosen tile and points an arrow at it; nothing moves until GO.
    ///
    /// Clicking the tile you're standing on — or the one you've already drafted
    /// — takes the move back, mirroring how right-clicking the attack origin
    /// clears a drafted swing. Standing still used to be expressible as a
    /// zero-distance move, but `legalMoveTargets` stopped offering the player's
    /// own tile when it became a Dijkstra walk for mud, which left no way at all
    /// to undo a move.
    private func planMove(to target: GridPosition) {
        guard !isResolving else { return }
        if state.plannedTarget != nil,
           target == state.playerPosition || target == state.plannedTarget || target == state.plannedLanding {
            state.clearPlannedMove()
            updatePlanArrow()
            refreshTileHighlights()
            updateHUD()
            return
        }
        guard state.planMove(to: target) else { return }
        advanceTutorial(after: .move)
        updatePlanArrow()
        refreshTileHighlights()
        updateHUD()
    }

    /// Flips the active weapon instantly and for free during planning; the new
    /// weapon's range and pattern apply this turn (any aimed attack clears so
    /// it's re-aimed with the new weapon).
    private func swapWeapons() {
        guard !isResolving, !state.isGameOver else { return }
        state.swapEquipped()
        updatePlanArrow()
        refreshTileHighlights()
        updateHUD()
    }

    /// Plays the resolve phase: the player moves to the planned tile (staying put
    /// if none) and swings the drafted attack, then surviving enemies execute
    /// their telegraphed moves and attack.
    private func resolveTurn() {
        guard !isResolving, !state.isGameOver else { return }
        // Snapshot the pools before the state ticks them, so expired ones stay
        // visible until the hazard phase wraps up.
        heldHazardTiles = Dictionary(
            uniqueKeysWithValues: state.lingeringEffects.map { ($0.position, $0.damagePerTurn) }
        )
        revealLiveHazards = false
        // Same idea for the actors: hold their sprites at the pre-resolve
        // state, then release each on its own beat below.
        beginResolveHold()
        let ultWasReady = state.ultimateKillCharge >= state.ultimateChargeKills
        let resolution = state.resolveTurn()
        pendingUltimateReadyToast = !ultWasReady
            && state.ultimateKillCharge >= state.ultimateChargeKills
        if let picked = resolution.pickedUpWeapon {
            // Claiming an elite trophy unlocks it for every future run.
            if Weapon.eliteTrophies.contains(where: { $0.name == picked.name })
                && !claimedTrophyNames.contains(picked.name) {
                claimedTrophyNames.insert(picked.name)
                showToast("TROPHY CLAIMED: \(picked.name) — now found in the wild", duration: 2.4)
            } else {
                showToast("picked up \(picked.name)", duration: 1.0)
            }
        }
        // The cache reveal isn't announced here — it fires from the player's
        // move animation instead (see animatePlayerMove), so it lands as the
        // piece arrives on the tile rather than a beat before it sets off.
        if !resolution.frostbittenEnemies.isEmpty {
            let count = resolution.frostbittenEnemies.count
            showToast(count == 1 ? "AN ENEMY FREEZES SOLID" : "\(count) ENEMIES FREEZE SOLID", duration: 1.8)
        }
        if resolution.frostbite {
            // Fires the turn the cold maxes out; the lost action lands on the
            // *next* turn, so say so rather than letting the player find out.
            showToast("FROSTBITE — you seize up; no attack next turn", duration: 2.4)
        }
        if resolution.playerActionStunned {
            showToast("STUNNED — your attack fizzled", duration: 1.4)
        }
        isResolving = true
        advanceTutorial(after: .go)
        planArrowNode?.removeFromParent()
        planArrowNode = nil
        enemyPlanArrowNodes.forEach { $0.removeFromParent() }
        enemyPlanArrowNodes.removeAll()
        enemyInfoLabel?.removeFromParent()
        enemyInfoLabel = nil
        pickupHintLabel?.removeFromParent()
        pickupHintLabel = nil
        spawnMarkerNodes.forEach { $0.removeFromParent() }
        spawnMarkerNodes.removeAll()
        goButton.alpha = 0.4
        refreshTileHighlights()

        let resolveAnimation: SKAction
        let destination = point(for: resolution.playerDestination)
        if playerNode.position == destination {
            // Staying put: pulse in place so the turn still visibly resolves.
            resolveAnimation = SKAction.sequence([
                SKAction.scale(to: 1.2, duration: 0.08),
                SKAction.scale(to: 1.0, duration: 0.08),
            ])
        } else {
            // Scale duration with distance so multi-tile moves don't teleport.
            let distanceInTiles = hypot(destination.x - playerNode.position.x,
                                        destination.y - playerNode.position.y) / tileSize
            let move = SKAction.move(to: destination, duration: 0.10 + 0.05 * distanceInTiles)
            move.timingMode = .easeInEaseOut
            resolveAnimation = move
        }

        playerNode.run(resolveAnimation) { [weak self] in
            if let dug = resolution.openedCache {
                self?.revealCache(dug)
            }
            self?.playSpawns(resolution)
        }
    }

    /// The dig, played the instant the player lands on the tile.
    ///
    /// A weapon announces itself — it stays on the floor inside a gold ring.
    /// A boon has no physical tell at all: it's a line appended to a HUD row
    /// the player isn't looking at while they watch the board resolve. So the
    /// reveal has to happen *on* the board, at the tile, at the moment the
    /// piece arrives, and it has to be the loudest non-threatening thing on
    /// screen or the player walks out of the mud unsure anything happened.
    private func revealCache(_ cache: Cache) {
        let jade = SKColor(red: 0.45, green: 0.88, blue: 0.68, alpha: 1.0)
        let origin = point(for: cache.position)

        // Pop the lid rather than letting it linger until the post-turn
        // rebuild: the thing that was buried should visibly come out.
        if let lid = cacheNodes.removeValue(forKey: cache.position) {
            lid.removeAllActions()
            lid.run(.sequence([
                .group([.scale(to: 1.8, duration: 0.22), .fadeOut(withDuration: 0.22)]),
                .removeFromParent(),
            ]))
        }

        // An expanding ring, the same grammar as a portal flash so it reads as
        // "something happened here" without reading as a threat.
        let burst = SKShapeNode(circleOfRadius: tileSize * 0.22)
        burst.strokeColor = jade
        burst.fillColor = .clear
        burst.lineWidth = 3
        burst.position = origin
        burst.zPosition = 13
        boardNode.addChild(burst)
        burst.run(.sequence([
            .group([.scale(to: 2.6, duration: 0.34), .fadeOut(withDuration: 0.34)]),
            .removeFromParent(),
        ]))

        // The name, rising off the tile. This is the part that carries the
        // information; the ring just makes the eye go there first.
        let headline: String
        let tint: SKColor
        switch cache.contents {
        case let .boon(buff):
            // Just the boon's short name here — the full "· what it does" half
            // is already spelled out in the HUD row it just joined.
            headline = buff.name.components(separatedBy: " · ").first ?? buff.name
            tint = jade
        case let .weapon(weapon):
            headline = weapon.name
            tint = SKColor(red: 0.95, green: 0.85, blue: 0.35, alpha: 1.0)
        }
        let label = SKLabelNode(text: headline)
        label.fontName = "HelveticaNeue-Bold"
        label.fontSize = 15
        label.fontColor = tint
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: origin.x, y: origin.y + tileSize * 0.45)
        label.zPosition = 30
        label.setScale(0.6)
        boardNode.addChild(label)
        label.run(.sequence([
            .group([.scale(to: 1.0, duration: 0.16), .moveBy(x: 0, y: tileSize * 0.30, duration: 0.16)]),
            .wait(forDuration: 0.85),
            .group([.fadeOut(withDuration: 0.35), .moveBy(x: 0, y: tileSize * 0.25, duration: 0.35)]),
            .removeFromParent(),
        ]))

        switch cache.contents {
        case let .boon(buff):
            let turns = buff.turnDuration.map { " · \($0) turns" } ?? ""
            showToast("DUG OUT: \(buff.name)\(turns)", duration: 2.2)
            // Tie the board moment to the HUD row the boon landed in, so the
            // player learns where to look for its countdown. Deferred until
            // the resolve repaints the HUD — see `pendingBuffRowFlash`.
            pendingBuffRowFlash = tint
        case let .weapon(weapon):
            // A cache can turn up a weapon the profile hasn't unlocked, which
            // is the best thing it can do — call that out rather than letting
            // it read as an ordinary floor drop.
            let known = currentWeaponPool().contains { $0.name == weapon.name }
            showToast(
                known
                    ? "DUG OUT: \(weapon.name) — pick it up to swap"
                    : "DUG OUT: \(weapon.name) — not yet in your arsenal",
                duration: 2.6
            )
        }
    }

    /// Pulses the held-buffs HUD row, so a boon that appeared without the
    /// player drafting anything has something drawing the eye to where it went.
    private func flashBuffsRow(_ tint: SKColor) {
        // A fixed constant, not whatever the label is currently showing: an
        // overlapping flash would otherwise capture the tint as the resting
        // colour and leave the row stuck on it.
        let resting = Self.buffsLabelColor
        buffsLabel.removeAllActions()
        buffsLabel.run(.sequence([
            .repeat(.sequence([
                .run { [weak self] in self?.buffsLabel.fontColor = tint },
                .wait(forDuration: 0.16),
                .run { [weak self] in self?.buffsLabel.fontColor = resting },
                .wait(forDuration: 0.16),
            ]), count: 3),
            .run { [weak self] in self?.buffsLabel.fontColor = resting },
        ]))
    }

    /// Steps every enemy to its drafted tile, then hands off to the player's attack.
    private func animateEnemyMoves(_ resolution: TurnResolution) {
        // They turn as they set off, not back when the turn was drafted.
        // Mutate a local copy: writing through `resolveHold?` while the same
        // expression reads it is two overlapping accesses to one property,
        // which traps at runtime.
        if var hold = resolveHold {
            for move in resolution.enemyMoves where move.from != move.to {
                hold.enemyFacing[move.enemyID] = hold.enemyMoveFacing[move.enemyID]
            }
            resolveHold = hold
        }
        refreshActorSprites()

        var longestDuration: TimeInterval = 0
        for move in resolution.enemyMoves where move.from != move.to {
            guard let node = enemyNodes[move.enemyID] else { continue }
            let destination = point(for: move.to)
            // Scale duration with distance so multi-tile moves don't teleport.
            let distanceInTiles = hypot(destination.x - node.position.x,
                                        destination.y - node.position.y) / tileSize
            let duration = 0.10 + 0.05 * distanceInTiles
            longestDuration = max(longestDuration, duration)
            let step = SKAction.move(to: destination, duration: duration)
            step.timingMode = .easeInEaseOut
            node.run(step)
        }

        // After the walk settles, pop any warped movers between portal ends.
        let popDuration = animateTeleports(resolution.teleports, afterDelay: longestDuration)
        run(SKAction.wait(forDuration: longestDuration + popDuration)) { [weak self] in
            self?.playProjectileImpacts(resolution)
        }
    }

    /// Pops each warped mover from its portal entry to its exit (a fade-out /
    /// fade-in with a ring flash at both ends), scheduled after the walk. Returns
    /// the extra time this adds so the caller can extend its wait.
    @discardableResult
    private func animateTeleports(_ teleports: [TurnResolution.Teleport], afterDelay delay: TimeInterval) -> TimeInterval {
        guard !teleports.isEmpty else { return 0 }
        for teleport in teleports {
            let node: SKNode? = teleport.enemyID.map { enemyNodes[$0] } ?? playerNode
            guard let node else { continue }
            let exit = point(for: teleport.to)
            node.run(SKAction.sequence([
                SKAction.wait(forDuration: delay),
                SKAction.fadeOut(withDuration: 0.12),
                SKAction.run { node.position = exit },
                SKAction.fadeIn(withDuration: 0.12),
            ]))
            portalFlash(at: point(for: teleport.from), delay: delay)
            portalFlash(at: exit, delay: delay + 0.12)
        }
        return 0.3
    }

    /// A quick expanding ring, to sell a warp in/out at a tile.
    private func portalFlash(at position: CGPoint, delay: TimeInterval) {
        let ring = SKShapeNode(circleOfRadius: tileSize * 0.28)
        ring.strokeColor = SKColor(red: 0.6, green: 0.85, blue: 1.0, alpha: 0.9)
        ring.fillColor = .clear
        ring.lineWidth = 3
        ring.position = position
        ring.zPosition = 12
        ring.alpha = 0
        boardNode.addChild(ring)
        ring.run(SKAction.sequence([
            SKAction.wait(forDuration: delay),
            SKAction.group([
                SKAction.sequence([SKAction.fadeIn(withDuration: 0.08), SKAction.fadeOut(withDuration: 0.18)]),
                SKAction.scale(to: 1.8, duration: 0.26),
            ]),
            SKAction.removeFromParent(),
        ]))
    }

    /// Skids each knocked-back enemy along its shove. Runs concurrently with the
    /// hit/death flash on the same node, so a body flung into a barrel slides in
    /// as it's destroyed.
    private func animateShoves(_ shoves: [TurnResolution.Shove]) {
        for shove in shoves {
            guard let node = enemyNodes[shove.enemyID] else { continue }
            let destination = point(for: shove.to)
            let distanceInTiles = hypot(destination.x - node.position.x,
                                        destination.y - node.position.y) / tileSize
            let skid = SKAction.move(to: destination, duration: 0.08 + 0.04 * distanceInTiles)
            skid.timingMode = .easeOut
            node.run(skid)
        }
    }

    /// Slides shoved/reeled barrels from their old tile to their new one, matching
    /// the shove skid, and re-keys their node so a later explosion (or the board
    /// reconcile) finds it at the right place.
    private func animateBarrelMoves(_ moves: [TurnResolution.BarrelMove]) {
        for move in moves {
            guard let node = obstacleNodes[move.from] else { continue }
            obstacleNodes[move.from] = nil
            obstacleNodes[move.to] = node
            let destination = point(for: move.to)
            let distanceInTiles = hypot(destination.x - node.position.x,
                                        destination.y - node.position.y) / tileSize
            let skid = SKAction.move(to: destination, duration: 0.08 + 0.04 * distanceInTiles)
            skid.timingMode = .easeOut
            node.run(skid)
        }
    }

    /// Bolts glide along the stretch they flew and lob shells arc onward (or
    /// dive into their targets), then anything that landed or struck blows up —
    /// all before anyone attacks.
    private func playProjectileImpacts(_ resolution: TurnResolution) {
        // The player's shot leaves here — a fired bow empties as its arrow
        // goes, and they turn onto their aim to loose it. A melee swing falls
        // straight through the guard below to the attack, so the same release
        // lands on that beat instead.
        releasePlayerWeaponArt()

        guard !resolution.projectileImpacts.isEmpty || !resolution.boltFlights.isEmpty || !lobNodes.isEmpty else {
            playPlayerAttack(resolution)
            return
        }

        var longestFlight: TimeInterval = 0

        // Airborne shells advance along their arc; landed ones dive into the
        // target and vanish just before the blast flash.
        for (id, node) in lobNodes {
            let destination: CGPoint
            let landing: Bool
            if let shell = state.projectiles.first(where: { $0.id == id }) {
                let coordinates = state.lobBeadCoordinates(of: shell)
                destination = boardPoint(x: coordinates.x, y: coordinates.y)
                landing = false
            } else if let target = lobTargets[id] {
                destination = target
                landing = true
            } else {
                continue
            }
            let distanceInTiles = hypot(destination.x - node.position.x,
                                        destination.y - node.position.y) / tileSize
            let duration = 0.06 * TimeInterval(distanceInTiles) + 0.08
            longestFlight = max(longestFlight, duration)
            let glide = SKAction.move(to: destination, duration: duration)
            glide.timingMode = landing ? .easeIn : .easeInEaseOut
            if landing {
                lobNodes[id] = nil
                lobTargets[id] = nil
                node.run(SKAction.sequence([
                    glide,
                    SKAction.fadeOut(withDuration: 0.06),
                    SKAction.removeFromParent(),
                ]))
            } else {
                node.run(glide)
            }
        }
        // A bolt's flight can arrive in several straight segments split at each
        // portal it took, so drive each bolt's sliver through its segments in
        // order, popping it across at every warp.
        let flightsByBolt = Dictionary(grouping: resolution.boltFlights, by: \.boltID)
        for (boltID, segments) in flightsByBolt {
            guard let first = segments.first else { continue }
            let node: SKNode
            if let existing = boltNodes[boltID] {
                node = existing
            } else {
                // Fired this very turn: the shot enters at the shooter's tile.
                // A bolt that struck home is already out of `state.bolts`, so
                // its ammo can't be read back — a plain arrow covers it.
                // Called inside a closure rather than passed as `Art.ammo(for:)`:
                // handing a main-actor method over as a function value strips
                // the isolation the caller has and won't compile.
                let ammo = state.bolts.first { $0.id == boltID }.map { Art.ammo(for: $0) } ?? .arrow
                node = makeBoltNode(ammo, direction: first.direction)
                node.position = point(for: first.from)
                boardNode.addChild(node)
                boltNodes[boltID] = node
            }

            var actions: [SKAction] = []
            var cursor = node.position
            var total: TimeInterval = 0
            for (i, seg) in segments.enumerated() {
                // Every boundary between segments is a warp: blink out at the
                // entry, flash both portal ends, reappear at the exit.
                if i > 0 {
                    let entry = point(for: segments[i - 1].to)
                    let exit = point(for: seg.from)
                    actions.append(SKAction.fadeOut(withDuration: 0.08))
                    actions.append(SKAction.run { [weak self] in
                        node.position = exit
                        self?.portalFlash(at: entry, delay: 0)
                        self?.portalFlash(at: exit, delay: 0)
                    })
                    actions.append(SKAction.fadeIn(withDuration: 0.08))
                    total += 0.16
                    cursor = exit
                }
                let destination = point(for: seg.to)
                let distanceInTiles = hypot(destination.x - cursor.x,
                                            destination.y - cursor.y) / tileSize
                let duration = 0.06 * TimeInterval(distanceInTiles) + 0.08
                let glide = SKAction.move(to: destination, duration: duration)
                glide.timingMode = .easeIn
                actions.append(glide)
                total += duration
                cursor = destination
            }
            longestFlight = max(longestFlight, total)
            if !state.bolts.contains(where: { $0.id == boltID }) {
                // Struck something or expired: finish the flight and vanish.
                boltNodes[boltID] = nil
                actions.append(SKAction.fadeOut(withDuration: 0.08))
                actions.append(SKAction.removeFromParent())
            }
            node.run(SKAction.sequence(actions))
        }

        run(SKAction.wait(forDuration: longestFlight)) { [weak self] in
            guard let self else { return }
            self.animateExplosions(resolution.projectileImpacts)
            self.animateEnemyHits(resolution.projectileHits)
            let pause: TimeInterval = resolution.projectileImpacts.isEmpty ? 0 : 0.3
            self.run(SKAction.wait(forDuration: pause)) { [weak self] in
                guard let self else { return }
                self.refreshTileHighlights()
                self.playPlayerAttack(resolution)
            }
        }
    }

    /// Damage flicker or shrink-and-fade death for each struck enemy.
    private func animateEnemyHits(_ hits: [TurnResolution.EnemyHit]) {
        for hit in hits {
            guard let node = enemyNodes[hit.enemyID] else { continue }
            if hit.blocked {
                // A parry, not a wound: a firm little shield-brace, no damage flash.
                node.run(SKAction.sequence([
                    SKAction.scale(to: 1.18, duration: 0.06),
                    SKAction.scale(to: 1.0, duration: 0.10),
                ]))
                showBlockCallout(at: node.position)
            } else if hit.died {
                enemyNodes[hit.enemyID] = nil
                node.run(SKAction.sequence([
                    SKAction.group([
                        SKAction.fadeOut(withDuration: 0.25),
                        SKAction.scale(to: 0.3, duration: 0.25),
                    ]),
                    SKAction.removeFromParent(),
                ]))
            } else {
                node.run(SKAction.sequence([
                    SKAction.fadeAlpha(to: 0.2, duration: 0.08),
                    SKAction.fadeAlpha(to: 1.0, duration: 0.08),
                ]))
            }
        }
    }

    /// A brief "BLOCKED" that floats up off a parrying shieldbearer.
    private func showBlockCallout(at position: CGPoint) {
        let label = SKLabelNode(text: "BLOCKED")
        label.fontName = "HelveticaNeue-Bold"
        label.fontSize = 13
        label.fontColor = SKColor(red: 0.80, green: 0.85, blue: 0.92, alpha: 1.0)
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: position.x, y: position.y + tileSize * 0.4)
        label.zPosition = 30
        boardNode.addChild(label)
        label.run(SKAction.sequence([
            SKAction.group([
                SKAction.moveBy(x: 0, y: tileSize * 0.6, duration: 0.6),
                SKAction.sequence([
                    SKAction.wait(forDuration: 0.3),
                    SKAction.fadeOut(withDuration: 0.3),
                ]),
            ]),
            SKAction.removeFromParent(),
        ]))
    }

    /// Orange blast flash on each explosion's tiles, and the barrel sprite
    /// swells and vanishes.
    private func animateExplosions(_ explosions: [TurnResolution.Explosion]) {
        for explosion in explosions {
            // Overlay flashes rather than tile repaints: they survive any
            // refreshTileHighlights that lands mid-animation.
            for tile in explosion.tiles {
                guard let tileNode = tileNodes[tile] else { continue }
                let flash = SKSpriteNode(
                    color: SKColor(red: 0.95, green: 0.55, blue: 0.10, alpha: 1.0),
                    size: tileNode.size
                )
                flash.position = tileNode.position
                flash.zPosition = 5
                boardNode.addChild(flash)
                flash.run(SKAction.sequence([
                    SKAction.wait(forDuration: 0.25),
                    SKAction.fadeOut(withDuration: 0.20),
                    SKAction.removeFromParent(),
                ]))
            }
            if let barrel = obstacleNodes.removeValue(forKey: explosion.center) {
                barrel.run(SKAction.sequence([
                    SKAction.group([
                        SKAction.scale(to: 1.8, duration: 0.20),
                        SKAction.fadeOut(withDuration: 0.20),
                    ]),
                    SKAction.removeFromParent(),
                ]))
            }
        }
    }

    /// Flashes the covered tiles (sweep or blast) and plays hit/death/explosion
    /// effects, then hands off to the enemies' attacks.
    private func playPlayerAttack(_ resolution: TurnResolution) {
        // Every bolt and lob has visibly flown by now: fresh trails may show.
        revealLiveHazards = true
        if resolution.omenFired != nil {
            playUltimate(resolution)
            return
        }
        // Bolt shots sweep no tiles, but a bomber dying to one still blasts:
        // its explosion (and the barrels it popped) must play regardless.
        guard !resolution.attackTiles.isEmpty
            || !resolution.playerExplosions.isEmpty || !resolution.enemyHits.isEmpty
            || !resolution.shoves.isEmpty || !resolution.barrelMoves.isEmpty
            || resolution.grappleHook != nil else {
            playEnemyAttacks(resolution)
            return
        }

        for tile in resolution.attackTiles {
            paintTile(tile, SKColor(red: 0.85, green: 0.25, blue: 0.15, alpha: 1.0))
        }
        // Whip the grapple line out to whatever it bit, and reel the player in if
        // it grabbed a wall or barrel (a dragged enemy rides `shoves`, below).
        animateGrapple(resolution)
        // Slide shoved/reeled barrels and flung enemies (both still in their node
        // maps here) so a body or barrel driven into scenery arrives just as it
        // goes off.
        animateBarrelMoves(resolution.barrelMoves)
        animateShoves(resolution.shoves)
        animateEnemyHits(resolution.enemyHits)
        animateExplosions(resolution.playerExplosions)

        run(SKAction.wait(forDuration: 0.3)) { [weak self] in
            guard let self else { return }
            self.refreshTileHighlights()
            self.playEnemyAttacks(resolution)
        }
    }

    /// The grapple: a taut line snaps out from the player to the bitten tile and
    /// fades, and if it caught a wall/barrel the player zips across the gap.
    private func animateGrapple(_ resolution: TurnResolution) {
        guard let hook = resolution.grappleHook else { return }
        drawGrappleLine(from: hook.from, to: hook.to)
        if let zipTo = resolution.playerGrappleTo {
            let destination = point(for: zipTo)
            let distanceInTiles = hypot(destination.x - playerNode.position.x,
                                        destination.y - playerNode.position.y) / tileSize
            let zip = SKAction.move(to: destination, duration: 0.08 + 0.04 * distanceInTiles)
            zip.timingMode = .easeIn
            playerNode.run(zip)
        }
    }

    /// A taut grapple line that snaps out from `from` to `to`, then fades. Shared
    /// by the player's hook and enemies reeling the player in.
    private func drawGrappleLine(from: GridPosition, to: GridPosition) {
        let path = CGMutablePath()
        path.move(to: point(for: from))
        path.addLine(to: point(for: to))
        let line = SKShapeNode(path: path)
        line.strokeColor = SKColor(red: 0.78, green: 0.72, blue: 0.52, alpha: 1.0)
        line.lineWidth = 2.5
        line.zPosition = 9
        boardNode.addChild(line)
        line.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.20),
            SKAction.fadeOut(withDuration: 0.18),
            SKAction.removeFromParent(),
        ]))
    }

    /// The smite: a radio transmission "explains" the incoming strike, then a
    /// shockwave races outward from the player, tiles flaring and victims
    /// falling in order of distance.
    private func playUltimate(_ resolution: TurnResolution) {
        let center = point(for: resolution.playerDestination)
        /// Seconds of shockwave travel per tile of distance.
        let wavePace: TimeInterval = 0.05
        /// A beat for the transmission to type out before the sky falls.
        let leadIn: TimeInterval = 1.1

        showTransmission(Self.omenChatter(for: resolution.omenFired ?? .smite).randomElement()!)

        let ring = SKShapeNode(circleOfRadius: tileSize * 0.4)
        ring.strokeColor = .white
        ring.lineWidth = 4
        ring.fillColor = .clear
        ring.position = center
        ring.zPosition = 25
        ring.alpha = 0
        boardNode.addChild(ring)
        let boardSpan = CGFloat(max(state.columns, state.rows))
        ring.run(SKAction.sequence([
            SKAction.wait(forDuration: leadIn),
            SKAction.fadeIn(withDuration: 0.01),
            SKAction.group([
                SKAction.scale(to: boardSpan * 2.5, duration: wavePace * TimeInterval(boardSpan)),
                SKAction.fadeOut(withDuration: wavePace * TimeInterval(boardSpan)),
            ]),
            SKAction.removeFromParent(),
        ]))

        var longestDelay: TimeInterval = 0
        for tile in resolution.ultimateTiles {
            let tilePoint = point(for: tile)
            let distance = hypot(tilePoint.x - center.x, tilePoint.y - center.y) / tileSize
            let delay = leadIn + wavePace * TimeInterval(distance)
            longestDelay = max(longestDelay, delay)
            run(SKAction.sequence([
                SKAction.wait(forDuration: delay),
                SKAction.run { [weak self] in
                    self?.paintTile(tile, .white)
                },
            ]))
        }
        for hit in resolution.enemyHits {
            guard let node = enemyNodes[hit.enemyID] else { continue }
            let distance = hypot(node.position.x - center.x, node.position.y - center.y) / tileSize
            let delay = leadIn + wavePace * TimeInterval(distance)
            longestDelay = max(longestDelay, delay)
            if hit.died {
                enemyNodes[hit.enemyID] = nil
                node.run(SKAction.sequence([
                    SKAction.wait(forDuration: delay),
                    SKAction.group([
                        SKAction.fadeOut(withDuration: 0.25),
                        SKAction.scale(to: 0.3, duration: 0.25),
                    ]),
                    SKAction.removeFromParent(),
                ]))
            } else {
                node.run(SKAction.sequence([
                    SKAction.wait(forDuration: delay),
                    SKAction.fadeAlpha(to: 0.2, duration: 0.08),
                    SKAction.fadeAlpha(to: 1.0, duration: 0.08),
                ]))
            }
        }

        // Chained blasts (dying bombers, popped barrels) flash once the wave
        // has passed; without this an ult turn played no explosions at all.
        if !resolution.playerExplosions.isEmpty {
            run(SKAction.sequence([
                SKAction.wait(forDuration: longestDelay),
                SKAction.run { [weak self] in
                    self?.animateExplosions(resolution.playerExplosions)
                },
            ]))
        }

        run(SKAction.wait(forDuration: longestDelay + 0.6)) { [weak self] in
            guard let self else { return }
            self.refreshTileHighlights()
            self.playEnemyAttacks(resolution)
        }
    }

    /// Every attacking enemy's swept tiles flash; enemies that connect lunge at
    /// the player, who flashes as the damage lands: red when health was lost,
    /// steel blue when armor soaked it all. Friendly fire and barrel blasts play
    /// out here too.
    private func playEnemyAttacks(_ resolution: TurnResolution) {
        // Everyone who swings turns onto their aim and spends their weapon
        // here; enemies that did nothing keep the art they had.
        if var hold = resolveHold {
            for attack in resolution.enemyAttacks {
                if let aim = hold.enemyAim[attack.enemyID] {
                    hold.enemyFacing[attack.enemyID] = aim
                }
                if let enemy = state.enemies.first(where: { $0.id == attack.enemyID }) {
                    hold.enemyWeaponReady[enemy.id] = enemy.cooldownRemaining == 0
                    hold.enemySecondaryReady[enemy.id] = enemy.secondaryCooldownRemaining == 0
                }
            }
            resolveHold = hold
        }
        refreshActorSprites()

        let playerWasDamaged = resolution.healthLost > 0 || resolution.armorLost > 0
        // Bomber fuses can blow with no attack drafted anywhere: friendly-fire
        // hits and explosions alone still need this phase to play.
        guard !resolution.enemyAttacks.isEmpty || playerWasDamaged
            || !resolution.friendlyFireHits.isEmpty || !resolution.enemyExplosions.isEmpty
            || !resolution.enemyGrappleHooks.isEmpty || !resolution.enemyShoves.isEmpty
            || !resolution.enemyBarrelMoves.isEmpty || !resolution.enemyBarrelSpawns.isEmpty else {
            playHazards(resolution)
            return
        }

        // Enemies reeling something in throw a hook line, just as the player's
        // grapple does — the reel itself is the player's skid to `playerShoveTo`
        // (below), or the comrade/barrel dragged up the line in `enemyShoves`.
        for hook in resolution.enemyGrappleHooks {
            drawGrappleLine(from: hook.from, to: hook.to)
        }

        for attack in resolution.enemyAttacks {
            for tile in attack.tiles {
                paintTile(tile, SKColor(red: 0.55, green: 0.12, blue: 0.10, alpha: 1.0))
            }
        }
        // Comrades and barrels hauled in by an enemy's Vortex or grapple slide
        // as the blast lands — barrels first, so one reeled into the attacker
        // bursts on arrival.
        animateBarrelMoves(resolution.enemyBarrelMoves)
        animateShoves(resolution.enemyShoves)
        // A keg an enemy lobbed pops in where it landed, same flourish as a
        // telegraphed delivery but here in the enemy phase, as the throw lands.
        for tile in resolution.enemyBarrelSpawns {
            guard let barrel = state.obstacle(at: tile) else { continue }
            let node = addObstacleNode(for: barrel)
            node.setScale(0.1)
            node.alpha = 0
            node.run(SKAction.group([
                SKAction.scale(to: 1.0, duration: 0.20),
                SKAction.fadeIn(withDuration: 0.20),
            ]))
        }
        animateEnemyHits(resolution.friendlyFireHits)
        animateExplosions(resolution.enemyExplosions)

        let playerPoint = point(for: resolution.playerDestination)
        for attack in resolution.enemyAttacks where attack.hitsPlayer || attack.dodged {
            guard let node = enemyNodes[attack.enemyID] else { continue }
            let origin = node.position
            let lunge = CGPoint(
                x: origin.x + (playerPoint.x - origin.x) * 0.4,
                y: origin.y + (playerPoint.y - origin.y) * 0.4
            )
            node.run(SKAction.sequence([
                SKAction.move(to: lunge, duration: 0.08),
                SKAction.move(to: origin, duration: 0.10),
            ]))
        }

        // Knockback: the player skids off their tile as the blow lands.
        if let landing = resolution.playerShoveTo {
            let target = point(for: landing)
            let distanceInTiles = hypot(target.x - playerNode.position.x,
                                        target.y - playerNode.position.y) / tileSize
            let skid = SKAction.move(to: target, duration: 0.10 + 0.05 * distanceInTiles)
            skid.timingMode = .easeOut
            playerNode.run(SKAction.sequence([SKAction.wait(forDuration: 0.10), skid]))
        }

        // A dodged hit: the player visibly sidesteps instead of flashing damage.
        if let dodgedAttack = resolution.enemyAttacks.first(where: \.dodged) {
            playDodgeEffect(awayFrom: enemyNodes[dodgedAttack.enemyID]?.position)
        }

        let gotHit = playerWasDamaged
        let flashColor: SKColor = resolution.healthLost > 0 ? .red : armorFlashColor
        run(SKAction.sequence([
            SKAction.wait(forDuration: 0.08),
            SKAction.run { [weak self] in
                guard let self, gotHit else { return }
                self.playerNode.bodyFillColor = flashColor
                self.updateHUD()
            },
            SKAction.wait(forDuration: 0.20),
            SKAction.run { [weak self] in
                guard let self else { return }
                self.playerNode.clearTint()
                self.playHazards(resolution)
            },
        ]))
    }

    /// Lingering effects burn whoever ended the turn in them; struck enemies
    /// flicker (and any bombers that died to the burn blow up) before the
    /// turn wraps up.
    private func playHazards(_ resolution: TurnResolution) {
        guard !resolution.hazardHits.isEmpty || !resolution.hazardExplosions.isEmpty else {
            playLateSpawns(resolution)
            return
        }
        animateEnemyHits(resolution.hazardHits)
        animateExplosions(resolution.hazardExplosions)
        run(SKAction.wait(forDuration: 0.25)) { [weak self] in
            guard let self else { return }
            self.refreshTileHighlights()
            self.playLateSpawns(resolution)
        }
    }

    /// Reinforcements and barrel deliveries pop in on their telegraphed tiles
    /// at the head of the turn — before anyone acts — so a pre-aimed attack
    /// can greet them; blocked spawns flash the tile instead.
    private func playSpawns(_ resolution: TurnResolution) {
        // The gatekeeper's own entrance is summoned by this turn's kills, so it
        // materializes late (after the deaths) rather than here at the head.
        let headSpawns = resolution.spawns.filter { !$0.late }
        guard !headSpawns.isEmpty || !resolution.barrelSpawns.isEmpty else {
            animateEnemyMoves(resolution)
            return
        }
        for tile in resolution.barrelSpawns {
            guard let barrel = state.obstacle(at: tile) else { continue }
            let node = addObstacleNode(for: barrel)
            node.setScale(0.1)
            node.alpha = 0
            node.run(SKAction.group([
                SKAction.scale(to: 1.0, duration: 0.20),
                SKAction.fadeIn(withDuration: 0.20),
            ]))
        }
        for spawn in headSpawns {
            if let id = spawn.enemyID, let enemy = state.enemies.first(where: { $0.id == id }) {
                let node = addEnemyNode(for: enemy)
                node.setScale(0.1)
                node.alpha = 0
                node.run(SKAction.group([
                    SKAction.scale(to: 1.0, duration: 0.20),
                    SKAction.fadeIn(withDuration: 0.20),
                ]))
            } else {
                paintTile(spawn.position, .white)
            }
        }
        run(SKAction.wait(forDuration: 0.25)) { [weak self] in
            self?.animateEnemyMoves(resolution)
        }
    }

    /// The gatekeeper's grand entrance: it materializes only after the kills that
    /// summoned it have finished dying, so cause reads before effect. Hands off
    /// to the turn wrap-up either way.
    private func playLateSpawns(_ resolution: TurnResolution) {
        let lateSpawns = resolution.spawns.filter(\.late)
        guard !lateSpawns.isEmpty else {
            finishResolvePhase(resolution)
            return
        }
        for spawn in lateSpawns {
            guard let id = spawn.enemyID, let enemy = state.enemies.first(where: { $0.id == id }) else { continue }
            let node = addEnemyNode(for: enemy)
            node.setScale(0.1)
            node.alpha = 0
            // A heavier arrival than a rank-and-file pop: it swells past full,
            // then settles.
            node.run(SKAction.sequence([
                SKAction.group([
                    SKAction.scale(to: 1.25, duration: 0.26),
                    SKAction.fadeIn(withDuration: 0.26),
                ]),
                SKAction.scale(to: 1.0, duration: 0.10),
            ]))
        }
        run(SKAction.wait(forDuration: 0.45)) { [weak self] in
            self?.finishResolvePhase(resolution)
        }
    }

    /// A readable dodge: the player hops away from the attacker leaving a fading
    /// after-image at their tile, while a "DODGED!" callout floats up.
    private func playDodgeEffect(awayFrom attackerPoint: CGPoint?) {
        let origin = playerNode.position

        // Hop directly away from the attacker; straight up if unknown.
        var hop = CGVector(dx: 0, dy: tileSize * 0.5)
        if let attackerPoint {
            let dx = origin.x - attackerPoint.x
            let dy = origin.y - attackerPoint.y
            let length = max(hypot(dx, dy), 0.001)
            hop = CGVector(dx: dx / length * tileSize * 0.5, dy: dy / length * tileSize * 0.5)
        }

        let ghost = SKShapeNode(circleOfRadius: tileSize * 0.32)
        ghost.fillColor = playerColor.withAlphaComponent(0.35)
        ghost.strokeColor = .clear
        ghost.position = origin
        ghost.zPosition = 9
        boardNode.addChild(ghost)
        ghost.run(SKAction.sequence([
            SKAction.fadeOut(withDuration: 0.4),
            SKAction.removeFromParent(),
        ]))

        let sidestep = SKAction.move(to: CGPoint(x: origin.x + hop.dx, y: origin.y + hop.dy), duration: 0.10)
        sidestep.timingMode = .easeOut
        let stepBack = SKAction.move(to: origin, duration: 0.14)
        stepBack.timingMode = .easeInEaseOut
        playerNode.run(SKAction.sequence([sidestep, SKAction.wait(forDuration: 0.10), stepBack]))

        let callout = SKLabelNode(text: "DODGED!")
        callout.fontName = "HelveticaNeue-Bold"
        callout.fontSize = 16
        callout.fontColor = playerColor
        callout.verticalAlignmentMode = .bottom
        callout.position = CGPoint(x: origin.x, y: origin.y + tileSize * 0.55)
        callout.zPosition = 30
        boardNode.addChild(callout)
        callout.run(SKAction.sequence([
            SKAction.group([
                SKAction.moveBy(x: 0, y: tileSize * 0.8, duration: 0.7),
                SKAction.sequence([
                    SKAction.wait(forDuration: 0.3),
                    SKAction.fadeOut(withDuration: 0.4),
                ]),
            ]),
            SKAction.removeFromParent(),
        ]))
    }

    /// Tears down and rebuilds the moving pieces after a level-up regenerated
    /// the board (the tiles stay; enemies and obstacles are re-created).
    private func rebuildBoardEntities() {
        enemyNodes.values.forEach { $0.removeFromParent() }
        enemyNodes.removeAll()
        obstacleNodes.values.forEach { $0.removeFromParent() }
        obstacleNodes.removeAll()
        wallTints.removeAll()
        setUpEnemies()
        setUpObstacles()
        setUpTerrain()
        setUpTeleporters()
        setUpSpikes()
    }

    private func finishResolvePhase(_ resolution: TurnResolution) {
        // An elite stepping onto the field earns a transmission.
        let arrivedElite = resolution.spawns.contains { event in
            guard let id = event.enemyID, let enemy = state.enemies.first(where: { $0.id == id }) else { return false }
            return enemy.isElite
        }
        if arrivedElite {
            showTransmission(Self.eliteChatter.randomElement()!)
        }

        syncLifetimeProgress()

        // The charge announcement waits until the kills have visibly happened.
        if pendingUltimateReadyToast {
            pendingUltimateReadyToast = false
            showToast("THE OMEN IS RIPE — press F to bring down the sky", duration: 2.2)
        }

        // The combo callout waits until the kills have visibly happened.
        if resolution.killsThisTurn >= 2 {
            let callout: String
            switch resolution.killsThisTurn {
            case 2: callout = "COMBO x2"
            case 3: callout = "COMBO x3"
            default: callout = "COMBO ×\(resolution.killsThisTurn)"
            }
            showToast(callout, duration: 1.4)
        }
        if let newLevel = resolution.leveledUpTo {
            rebuildBoardEntities()
            // Crossing into a new biome changes what the board can throw at
            // you, so it gets called out. The tint shift alone is too quiet to
            // carry "barrels exist now".
            if Biome.forLevel(newLevel) != Biome.forLevel(newLevel - 1) {
                let arrived = Biome.forLevel(newLevel)
                showToast("ENTERING THE \(arrived.title.uppercased()) — \(arrived.blurb)", duration: 3.0)
            }
            showBuffChoice(forLevel: newLevel)
        }
        // Sweep any sprite whose enemy or obstacle left the state without a
        // death event — insurance against ghosts lingering on the board.
        let alive = Set(state.enemies.map(\.id))
        for (id, node) in enemyNodes where !alive.contains(id) {
            enemyNodes[id] = nil
            node.removeFromParent()
        }
        let solid = Set(state.obstacles.map(\.position))
        for (position, node) in obstacleNodes where !solid.contains(position) {
            obstacleNodes[position] = nil
            node.removeFromParent()
        }
        // Barrels can be shoved or reeled to a new tile mid-turn; place a node for
        // any that moved and now have none at their destination, so they don't
        // vanish (nodes are keyed by position).
        for obstacle in state.obstacles where obstacleNodes[obstacle.position] == nil {
            addObstacleNode(for: obstacle)
        }

        heldHazardTiles = nil
        revealLiveHazards = true
        isResolving = false
        // Planning resumes: the sprites answer to the live state again.
        resolveHold = nil
        refreshActorSprites()
        goButton.alpha = 1.0
        refreshSpikes()
        updateHUD()
        // Now that the row shows the new boon, point at it.
        if let tint = pendingBuffRowFlash {
            pendingBuffRowFlash = nil
            flashBuffsRow(tint)
        }
        updateEnemyPlanArrows()
        updateSpawnMarkers()
        updateWeaponDropNodes()
        updateCacheNodes()
        updateProjectileNodes()
        updateBomberFuses()
        updatePickupHint()
        updateEnemyHoverInfo()
        refreshTileHighlights()
        if state.isGameOver {
            // A lesson can't be lost: the hit landed, but the coach picks you
            // back up and names what got you instead of ending the run.
            if inTutorial {
                let killer = state.tutorialRevive()
                updateHUD()
                showTutorialRescue(killer)
            } else {
                showDeathRecap()
            }
        }
        // Turn one has fully resolved — roll the interactive coach into its
        // sandboxed showcase of the systems a first turn can't reach.
        if tutorialShowcasePending {
            tutorialShowcasePending = false
            startTutorialShowcase()
        }
    }

    // MARK: - Death recap

    private static let deathEpitaphs = [
        "as foretold. (it was not foretold.)",
        "the bones did warn you. vaguely.",
        "the prophecy said 'beware'. it declined to say of what.",
        "written in the stars: 'oops'.",
        "the oracle maintains this is somehow character growth.",
    ]

    /// Full-screen end-of-run summary: what got you, and the numbers the run
    /// leaves behind. Dismissed by the usual single-R restart.
    private func showDeathRecap() {
        let wasBest = state.score > highScore && !devFreezeHighScore
        if wasBest {
            highScore = state.score
        }

        let overlay = SKNode()
        overlay.zPosition = 55

        let dim = SKSpriteNode(color: SKColor(white: 0, alpha: 0.82), size: size)
        dim.position = CGPoint(x: size.width / 2, y: size.height / 2)
        overlay.addChild(dim)

        let centerX = size.width / 2
        var y = size.height / 2 + 190

        func addLine(_ text: String, font: String, size fontSize: CGFloat, color: SKColor, drop: CGFloat) {
            let label = SKLabelNode(text: text)
            label.fontName = font
            label.fontSize = fontSize
            label.fontColor = color
            label.verticalAlignmentMode = .center
            label.position = CGPoint(x: centerX, y: y)
            overlay.addChild(label)
            y -= drop
        }

        let gold = SKColor(red: 0.93, green: 0.80, blue: 0.45, alpha: 1.0)
        addLine("SLAIN", font: "Papyrus", size: 46, color: gold, drop: 44)
        addLine(Self.deathEpitaphs.randomElement()!,
                font: "Baskerville-Italic", size: 16, color: SKColor(white: 0.65, alpha: 1.0), drop: 52)
        addLine("undone by \(state.causeOfDeath ?? "causes unknown")",
                font: "HelveticaNeue-Bold", size: 20, color: SKColor(red: 0.90, green: 0.35, blue: 0.30, alpha: 1.0), drop: 56)

        let statColor = SKColor(white: 0.85, alpha: 1.0)
        let scoreLine = wasBest ? "SCORE \(state.score) — NEW BEST ✦" : "SCORE \(state.score) · best \(highScore)"
        addLine(scoreLine, font: "HelveticaNeue-Bold", size: 22,
                color: wasBest ? gold : statColor, drop: 40)
        addLine("level \(state.level) · \(state.turnNumber) turns survived",
                font: "HelveticaNeue", size: 16, color: statColor, drop: 28)
        addLine("\(state.totalKills) foes felled · \(state.elitesSlain) gatekeeper\(state.elitesSlain == 1 ? "" : "s")",
                font: "HelveticaNeue", size: 16, color: statColor, drop: 28)
        addLine("best turn - ×\(state.bestCombo) kills · longest streak - x\(state.bestStreak)",
                font: "HelveticaNeue", size: 16, color: statColor, drop: 28)
        addLine("\(state.totalDamageTaken) damage endured",
                font: "HelveticaNeue", size: 16, color: statColor, drop: 32)

        // The run's own flavor: the loadout you fell with, and the pact you swore.
        addLine("wielding \(state.equippedWeapon.name) · \(state.holsteredWeapon.name)",
                font: "HelveticaNeue-Bold", size: 15, color: SKColor(red: 0.55, green: 0.75, blue: 0.95, alpha: 1.0), drop: 26)
        let boon = state.modifiers.first(where: \.isBoon)
        let curse = state.modifiers.first(where: { !$0.isBoon })
        if boon != nil || curse != nil {
            let parts = [boon.map { "\($0.title) ⚡" }, curse.map { "\($0.title) ☠" }].compactMap { $0 }
            addLine("pact — \(parts.joined(separator: " · "))",
                    font: "HelveticaNeue", size: 15, color: gold.withAlphaComponent(0.85), drop: 26)
        } else {
            addLine("no pact sworn", font: "HelveticaNeue", size: 15, color: SKColor(white: 0.55, alpha: 1.0), drop: 26)
        }
        // A single earned accolade, if the run had a standout beat.
        if let accolade = deathAccolade() {
            addLine(accolade, font: "Baskerville-Italic", size: 16, color: gold, drop: 40)
        } else {
            y -= 14
        }

        let prompt = SKLabelNode(text: "press R to defy fate again")
        prompt.fontName = "HelveticaNeue-Bold"
        prompt.fontSize = 15
        prompt.fontColor = SKColor(white: 0.7, alpha: 1.0)
        prompt.verticalAlignmentMode = .center
        prompt.position = CGPoint(x: centerX, y: y)
        prompt.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.35, duration: 0.7),
            SKAction.fadeAlpha(to: 1.0, duration: 0.7),
        ])))
        overlay.addChild(prompt)

        addChild(overlay)
    }

    /// One earned epithet for the death card, drawn from the run's standout beat
    /// (nil when nothing stood out — the card just skips the line then).
    private func deathAccolade() -> String? {
        if state.elitesSlain >= 3 { return "a bane of gatekeepers" }
        if state.bestCombo >= 4 { return "a whirlwind — ×\(state.bestCombo) felled in a breath" }
        if state.bestStreak >= 5 { return "relentless — a \(state.bestStreak)-turn killing streak" }
        if state.totalDamageTaken == 0 && state.turnNumber >= 8 { return "untouched to the very last" }
        if state.level >= 6 { return "a delver of the deep floors" }
        if state.totalKills >= 40 { return "a tireless reaper of \(state.totalKills)" }
        return nil
    }

    // MARK: - Level up

    /// Full-screen level-up moment, styled like the death banner: dimmed board,
    /// big title, and a choice of two boons that pauses play until picked.
    private func showBuffChoice(forLevel level: Int) {
        pendingBuffIndex = nil
        let overlay = SKNode()
        overlay.zPosition = 50

        // Dim only the board square, matching the loadout draft, so the HUD and
        // nav column stay legible while the boon is chosen.
        let boardSide = min(size.width, size.height) * boardScale
        let dim = SKSpriteNode(color: SKColor(white: 0, alpha: 0.75),
                               size: CGSize(width: boardSide, height: boardSide))
        dim.position = CGPoint(x: size.width / 2, y: size.height / 2)
        overlay.addChild(dim)

        let title = SKLabelNode(text: "LEVEL \(level)")
        title.fontName = "HelveticaNeue-Bold"
        title.fontSize = 46
        title.fontColor = .white
        title.verticalAlignmentMode = .center
        title.position = CGPoint(x: size.width / 2, y: size.height / 2 + 110)
        overlay.addChild(title)

        let subtitle = SKLabelNode(text: "choose a boon")
        subtitle.fontName = "HelveticaNeue"
        subtitle.fontSize = 18
        subtitle.fontColor = SKColor(white: 0.8, alpha: 1.0)
        subtitle.verticalAlignmentMode = .center
        subtitle.position = CGPoint(x: size.width / 2, y: size.height / 2 + 62)
        subtitle.name = "buffSubtitle"
        overlay.addChild(subtitle)

        let choices = state.pendingBuffChoices
        for (index, buff) in choices.enumerated() {
            let offset: CGFloat = choices.count == 1 ? 0 : (index == 0 ? -170 : 170)
            let buttonSize = CGSize(width: 320, height: 104)
            let button = SKShapeNode(rectOf: buttonSize, cornerRadius: 10)
            button.fillColor = SKColor(red: 0.20, green: 0.40, blue: 0.55, alpha: 1.0)
            button.strokeColor = .white
            button.lineWidth = 1.5
            button.name = "buffChoice:\(index)"
            button.position = CGPoint(x: size.width / 2 + offset, y: size.height / 2 - 20)
            overlay.addChild(button)

            // Buff names read "Title · what it does"; split so the title stays
            // bold and the description wraps beneath instead of overflowing.
            let parts = buff.name.components(separatedBy: " · ")
            let name = SKLabelNode(text: parts[0])
            name.fontName = "HelveticaNeue-Bold"
            name.fontSize = 18
            name.fontColor = .white
            name.verticalAlignmentMode = .center
            name.position = CGPoint(x: 0, y: 32)
            name.name = button.name
            button.addChild(name)

            if parts.count > 1 {
                let desc = SKLabelNode(text: parts[1...].joined(separator: " · "))
                desc.fontName = "HelveticaNeue"
                desc.fontSize = 13
                desc.fontColor = SKColor(white: 0.88, alpha: 1.0)
                desc.verticalAlignmentMode = .center
                desc.horizontalAlignmentMode = .center
                desc.numberOfLines = 0
                desc.preferredMaxLayoutWidth = buttonSize.width - 24
                desc.position = CGPoint(x: 0, y: 4)
                desc.name = button.name
                button.addChild(desc)
            }

            let durationText: String
            if let levels = buff.levelDuration {
                durationText = levels == 1 ? "this level only" : "lasts \(levels) levels"
            } else {
                durationText = buff.isInstantOnly ? "right away" : "whole run"
            }
            let detail = SKLabelNode(text: "\(durationText) · press \(index + 1)")
            detail.fontName = "HelveticaNeue"
            detail.fontSize = 11
            detail.fontColor = SKColor(white: 0.7, alpha: 1.0)
            detail.verticalAlignmentMode = .center
            detail.position = CGPoint(x: 0, y: -34)
            detail.name = button.name
            button.addChild(detail)
        }

        addChild(overlay)
        buffChoiceOverlay = overlay
    }

    /// Routes a click/press on a boon: with two-click confirmation on, the first
    /// pick highlights and waits, and only a repeat pick on the same boon commits.
    private func pickBuff(_ index: Int) {
        guard buffChoiceOverlay != nil, state.pendingBuffChoices.indices.contains(index) else { return }
        if confirmBoonChoice && pendingBuffIndex != index {
            pendingBuffIndex = index
            highlightPendingBuff()
            return
        }
        pendingBuffIndex = nil
        chooseBuff(index)
    }

    /// Lights up the boon awaiting confirmation and nudges the subtitle.
    private func highlightPendingBuff() {
        guard let overlay = buffChoiceOverlay else { return }
        let gold = SKColor(red: 0.98, green: 0.82, blue: 0.35, alpha: 1.0)
        let idle = SKColor(red: 0.20, green: 0.40, blue: 0.55, alpha: 1.0)
        let picked = SKColor(red: 0.28, green: 0.50, blue: 0.62, alpha: 1.0)
        for index in state.pendingBuffChoices.indices {
            let selected = index == pendingBuffIndex
            overlay.enumerateChildNodes(withName: "buffChoice:\(index)") { node, _ in
                guard let shape = node as? SKShapeNode else { return }
                shape.strokeColor = selected ? gold : .white
                shape.lineWidth = selected ? 4 : 1.5
                shape.fillColor = selected ? picked : idle
            }
        }
        (overlay.childNode(withName: "buffSubtitle") as? SKLabelNode)?.text = "click again to confirm"
    }

    /// Applies the picked boon, tears down the overlay, and resumes play.
    private func chooseBuff(_ index: Int) {
        guard buffChoiceOverlay != nil, state.pendingBuffChoices.indices.contains(index) else { return }
        pendingBuffIndex = nil
        let name = state.pendingBuffChoices[index].name
        state.chooseBuff(at: index)
        buffChoiceOverlay?.removeFromParent()
        buffChoiceOverlay = nil
        showToast("gained \(name)", duration: 1.2)
        updateHUD()
        refreshTileHighlights()
        // The showcase's level-up beat paused here for the pick; now roll into
        // the closing card.
        if beginnerShowcaseActive {
            finishTutorialShowcase()
        }
    }

    // MARK: - Game over

    private func showBanner(_ text: String) {
        let label = SKLabelNode(text: text)
        label.fontName = "HelveticaNeue-Bold"
        label.fontSize = 28
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: size.width / 2, y: size.height / 2)
        label.zPosition = 40
        addChild(label)
    }

    /// The oracle's pronouncements, typed out letter by letter: grand gold
    /// Papyrus up to the "|" break, where the mysticism runs out (with a
    /// hesitation beat) and the rest arrives in deflated plain type.
    private func showTransmission(_ text: String) {
        let boardSide = min(size.width, size.height) * boardScale
        let position = CGPoint(x: size.width / 2, y: size.height / 2 + boardSide * 0.28)
        let maxWidth = boardSide - 24

        // Every "|" toggles the voice: grand, deflated, grand again… so one
        // line can lose its nerve, rally, and lose it twice.
        let segments = text.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        let total = segments.reduce(0) { $0 + $1.count }
        var breakPoints: Set<Int> = []
        var cumulative = 0
        for segment in segments.dropLast() {
            cumulative += segment.count
            breakPoints.insert(cumulative)
        }

        #if canImport(AppKit)
        // SKLabelNode renders one font per node, so the deflated voice's flat
        // type never shows through attributedText — it takes the grand run's
        // Papyrus for the whole line. Draw the attributed string with CoreText
        // into a texture instead (which honours per-segment fonts, colours, and
        // wrapping) and swap it onto a sprite each typewriter tick.
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let grandAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont(name: "Papyrus", size: 19) ?? NSFont.systemFont(ofSize: 19),
            .foregroundColor: NSColor(red: 0.93, green: 0.80, blue: 0.45, alpha: 1.0),
            .paragraphStyle: paragraph,
        ]
        let deflatedAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont(name: "HelveticaNeue", size: 14) ?? NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor(white: 0.78, alpha: 1.0),
            .paragraphStyle: paragraph,
        ]
        func attributes(forSegment index: Int) -> [NSAttributedString.Key: Any] {
            index.isMultiple(of: 2) ? grandAttributes : deflatedAttributes
        }
        // The segment owning the character at `position` (or the last one).
        func segmentIndex(at position: Int) -> Int {
            var cumulative = 0
            for (index, segment) in segments.enumerated() {
                cumulative += segment.count
                if position < cumulative {
                    return index
                }
            }
            return max(0, segments.count - 1)
        }
        func rendered(upTo count: Int, cursor: Bool) -> NSAttributedString {
            let result = NSMutableAttributedString()
            var remaining = count
            for (index, segment) in segments.enumerated() {
                guard remaining > 0 else { break }
                let take = min(remaining, segment.count)
                if take > 0 {
                    result.append(NSAttributedString(
                        string: String(segment.prefix(take)),
                        attributes: attributes(forSegment: index)
                    ))
                }
                remaining -= take
            }
            if cursor {
                // The cursor wears the style of whatever comes next, so it
                // visibly deflates (or rallies) right at each break.
                result.append(NSAttributedString(
                    string: " ✦",
                    attributes: attributes(forSegment: segmentIndex(at: count))
                ))
            }
            return result
        }
        // Rasterise an attributed string into a 2× texture (crisp on Retina) and
        // its point size, wrapping within the board's width.
        func texture(for attributed: NSAttributedString) -> (SKTexture, CGSize)? {
            let bounds = attributed.boundingRect(
                with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
            let boxSize = CGSize(width: ceil(bounds.width) + 6, height: ceil(bounds.height) + 6)
            guard boxSize.width > 1, boxSize.height > 1 else { return nil }
            let scale: CGFloat = 2
            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(boxSize.width * scale), pixelsHigh: Int(boxSize.height * scale),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ) else { return nil }
            rep.size = boxSize
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            attributed.draw(with: CGRect(origin: .zero, size: boxSize),
                            options: [.usesLineFragmentOrigin, .usesFontLeading])
            NSGraphicsContext.restoreGraphicsState()
            let image = NSImage(size: boxSize)
            image.addRepresentation(rep)
            return (SKTexture(image: image), boxSize)
        }

        let sprite = SKSpriteNode(color: .clear, size: CGSize(width: 1, height: 1))
        sprite.position = position
        sprite.zPosition = 60
        addChild(sprite)
        func show(_ count: Int, cursor: Bool) {
            guard let (tex, sz) = texture(for: rendered(upTo: count, cursor: cursor)) else { return }
            sprite.texture = tex
            sprite.size = sz
        }
        var actions: [SKAction] = []
        for index in 1...max(1, total) {
            actions.append(SKAction.run { show(index, cursor: true) })
            // The oracle falters at every break before soldiering on.
            actions.append(SKAction.wait(forDuration: breakPoints.contains(index) ? 0.45 : 0.018))
        }
        actions.append(SKAction.run { show(total, cursor: false) })
        actions.append(SKAction.wait(forDuration: 1.8))
        actions.append(SKAction.fadeOut(withDuration: 0.5))
        actions.append(SKAction.removeFromParent())
        sprite.run(SKAction.sequence(actions))
        #else
        // Web: OpenSpriteKit has no attributed text / CoreText, so reveal in a
        // single style, keeping the hesitation beats at each "|".
        let label = SKLabelNode(text: "")
        label.verticalAlignmentMode = .center
        label.numberOfLines = 0
        label.preferredMaxLayoutWidth = maxWidth
        label.position = position
        label.zPosition = 60
        label.fontName = "Papyrus"
        label.fontSize = 19
        label.fontColor = SKColor(red: 0.93, green: 0.80, blue: 0.45, alpha: 1.0)
        addChild(label)
        let plain = segments.joined()
        var actions: [SKAction] = []
        for index in 1...max(1, plain.count) {
            let shown = String(plain.prefix(index))
            actions.append(SKAction.run { label.text = shown + " ✦" })
            actions.append(SKAction.wait(forDuration: breakPoints.contains(index) ? 0.45 : 0.018))
        }
        actions.append(SKAction.run { label.text = plain })
        actions.append(SKAction.wait(forDuration: 1.8))
        actions.append(SKAction.fadeOut(withDuration: 0.5))
        actions.append(SKAction.removeFromParent())
        label.run(SKAction.sequence(actions))
        #endif
    }

    /// Transient status message just below the board (restart confirmation,
    /// mode toggles, and the like). Concurrent toasts stack downward.
    private func showToast(_ text: String, duration: TimeInterval = 0.6) {
        let toast = SKLabelNode(text: text)
        toast.name = "toast"
        toast.fontName = "HelveticaNeue"
        toast.fontSize = 13
        toast.fontColor = SKColor(white: 0.85, alpha: 1.0)
        toast.verticalAlignmentMode = .center
        let boardSide = min(size.width, size.height) * boardScale
        let stacked = CGFloat(children.filter { $0.name == "toast" }.count)
        toast.position = CGPoint(x: size.width / 2, y: (size.height - boardSide) / 2 - 14 - stacked * 20)
        // Above the level-up overlay, so a combo callout survives leveling up
        // off the same kills.
        toast.zPosition = 60
        addChild(toast)
        toast.run(SKAction.sequence([
            SKAction.wait(forDuration: duration),
            SKAction.fadeOut(withDuration: 0.3),
            SKAction.removeFromParent(),
        ]))
    }

    /// Lays the active pact out as "PACT · ⚡ Boon · ☠ Curse" — separate labels so
    /// the curse burns red and each half carries a name for its hover tooltip.
    private func rebuildPactHUD(_ mods: Set<RunModifier>) {
        pactHUD.removeAllChildren()
        pactHUD.isHidden = mods.isEmpty
        guard !mods.isEmpty else {
            pactTooltip?.removeFromParent()
            pactTooltip = nil
            pactTooltipMod = nil
            return
        }
        let gold = SKColor(red: 0.93, green: 0.80, blue: 0.45, alpha: 1.0)
        let curseRed = SKColor(red: 0.95, green: 0.42, blue: 0.38, alpha: 1.0)
        var pieces: [(text: String, color: SKColor, mod: RunModifier?)] = [("PACT ", gold, nil)]
        if let boon = mods.first(where: \.isBoon) {
            pieces.append(("· \(boon.title) ", gold, boon))
        }
        if let curse = mods.first(where: { !$0.isBoon }) {
            pieces.append(("· \(curse.title)", curseRed, curse))
        }
        var labels: [SKLabelNode] = []
        var total: CGFloat = 0
        for piece in pieces {
            let label = SKLabelNode(text: piece.text)
            label.fontName = "HelveticaNeue-Bold"
            label.fontSize = 12
            label.fontColor = piece.color
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .left
            if let mod = piece.mod { label.name = "pactHover:\(mod.rawValue)" }
            labels.append(label)
            total += label.frame.width
        }
        var x = -total / 2
        for label in labels {
            label.position = CGPoint(x: x, y: 0)
            x += label.frame.width
            pactHUD.addChild(label)
        }
        // Remembered so hover can reject the rest of the screen with a rect
        // test instead of a scene-graph search (see updatePactTooltip).
        pactHoverBounds = CGRect(
            x: pactHUD.position.x - total / 2,
            y: pactHUD.position.y - 12,
            width: total,
            height: 24
        )
    }

    /// Shows the hovered pact half's full effect just under the pact row.
    private func updatePactTooltip(at location: CGPoint) {
        // This runs on every pointer move, and `nodes(at:)` walks the whole
        // scene graph — which on the web build costs more than the frame it's
        // stealing from. The pact row occupies one known strip of the HUD, so
        // anywhere else is answered by a rectangle test.
        guard pactHoverBounds.contains(location) else {
            guard pactTooltipMod != nil else { return }
            pactTooltipMod = nil
            pactTooltip?.removeFromParent()
            pactTooltip = nil
            return
        }
        let name = nodes(at: location).compactMap(\.name).first { $0.hasPrefix("pactHover:") }
        let mod = name.flatMap { RunModifier(rawValue: String($0.dropFirst("pactHover:".count))) }
        guard mod != pactTooltipMod else { return }
        pactTooltipMod = mod
        pactTooltip?.removeFromParent()
        pactTooltip = nil
        guard let mod else { return }
        let label = SKLabelNode(text: "\(mod.isBoon ? "BOON" : "CURSE") · \(mod.title) — \(mod.blurb)")
        label.fontName = "HelveticaNeue"
        label.fontSize = 12
        label.fontColor = mod.isBoon
            ? SKColor(red: 0.60, green: 0.85, blue: 0.60, alpha: 1.0)
            : SKColor(red: 0.95, green: 0.45, blue: 0.40, alpha: 1.0)
        label.verticalAlignmentMode = .center
        label.zPosition = 60
        label.position = CGPoint(x: size.width / 2, y: pactHUD.position.y - 16)
        addChild(label)
        pactTooltip = label
    }

    /// Restarting deals a fresh board, then routes back through the draft with a
    /// freshly rolled pact — every new run offers a new bargain.
    private func restartGame() {
        rebuildRun()
        openFreshPactDraft()
    }

    /// Rolls a fresh pact, refills the reroll allowance, and opens the draft.
    private func openFreshPactDraft() {
        draftedPact = rolledPact()
        activeModifiers = draftedPact
        pactRerollsRemaining = Self.maxPactRerolls
        showBuildPicker()
    }

    private func rebuildRun() {
        lastRestartKeyTime = 0
        revealLiveHazards = true
        tutorialStep = nil
        tutorialPrompt = nil
        tutorialShowcasing = false
        tutorialShowcasePending = false
        tutorialSnapshot = nil
        tutorialAdvance = nil
        offeringAdvanced = false
        advancedTutorialActive = false
        advancedOverlay?.removeFromParent()
        advancedOverlay = nil
        advancedReturnToBuildPicker = false
        pactTooltip?.removeFromParent()
        pactTooltip = nil
        pactTooltipMod = nil
        devPanel = nil
        buildPickerOverlay = nil
        // Kill any in-flight resolve callbacks (they run on the scene itself and
        // would otherwise fire into the freshly rebuilt board).
        removeAllActions()
        removeAllChildren()
        boardNode.removeAllChildren()
        tileNodes.removeAll()
        tileAppearances.removeAll()
        enemyNodes.removeAll()
        obstacleNodes.removeAll()
        wallTints.removeAll()
        spikeNodes.removeAll()
        teleporterNodes.removeAll()
        terrainNodes.removeAll()
        enemyPlanArrowNodes.removeAll()
        spawnMarkerNodes.removeAll()
        weaponDropNodes.removeAll()
        cacheNodes.removeAll()
        pendingBuffRowFlash = nil
        lobNodes.removeAll()
        lobTargets.removeAll()
        boltNodes.removeAll()
        planArrowNode = nil
        enemyInfoLabel = nil
        pickupHintLabel = nil
        hoveredTile = nil
        heldHazardTiles = nil
        buffChoiceOverlay = nil
        isResolving = false
        resolveHold = nil
        state = makeRunState()
        setUpScene()
    }

    /// This profile's arsenal: the base weapons, plus milestone unlocks, plus
    /// claimed elite trophies.
    private func currentWeaponPool() -> [Weapon] {
        Weapon.baseArsenal
            + Weapon.milestones.map(\.weapon).filter { unlockedWeaponNames.contains($0.name) }
            + Weapon.eliteTrophies.filter { claimedTrophyNames.contains($0.name) }
    }

    /// Builds a run from the current selections. `modifiersOverride` lets the
    /// tutorial force a plain, pact-free run so it always teaches the vanilla
    /// rules regardless of what the draft rolled.
    private func makeRunState(modifiersOverride: Set<RunModifier>? = nil) -> GameState {
        tallyBaseline = lifetimeTallies
        let pool = currentWeaponPool()
        let modifiers = modifiersOverride ?? activeModifiers
        let powderKeg = modifiers.contains(.powderKeg)
        var run = GameState(
            weapon: devNextEquipped
                ?? pickedLoadoutWeapon(loadoutMeleeName, from: pool.filter(\.isMelee)),
            holsteredWeapon: devNextHolstered
                ?? pickedLoadoutWeapon(loadoutRangedName, from: pool.filter(\.isRanged)),
            playerHealth: devNextMaxHealth,
            maxArmor: devNextMaxArmor,
            walls: powderKeg ? 0 : 10,
            barrels: powderKeg ? 14 : 4,
            weaponPool: currentWeaponPool(),
            modifiers: modifiers
        )
        run.omen = selectedOmen
        return run
    }

    // MARK: - Build picker

    /// The draft before the draft: an overlay over the fresh board where the
    /// starting melee and ranged slots are picked from the unlocked arsenal.
    /// Every restart returns here.
    private var buildPickerOverlay: SKNode?
    /// Persisted slot picks; nil = random from the unlocked pool.
    private var loadoutMeleeName: String? {
        get { Defaults.standard.string(forKey: "loadoutMelee") }
        set {
            if let newValue {
                Defaults.standard.set(newValue, forKey: "loadoutMelee")
            } else {
                Defaults.standard.removeObject(forKey: "loadoutMelee")
            }
        }
    }
    private var loadoutRangedName: String? {
        get { Defaults.standard.string(forKey: "loadoutRanged") }
        set {
            if let newValue {
                Defaults.standard.set(newValue, forKey: "loadoutRanged")
            } else {
                Defaults.standard.removeObject(forKey: "loadoutRanged")
            }
        }
    }

    /// The omen carried into the next run. Persisted like the weapon slots, and
    /// honoured only while it's actually unlocked.
    private var selectedOmen: Omen {
        get {
            guard let raw = Defaults.standard.string(forKey: "loadoutOmen"),
                  let pick = Omen(rawValue: raw), unlockedOmens.contains(pick) else { return .smite }
            return pick
        }
        set { Defaults.standard.set(newValue.rawValue, forKey: "loadoutOmen") }
    }

    /// Omens available to pick. Smite is the starter and is always there; the
    /// rest are meant to come in behind milestones, cheapest to read first
    /// (see `Omen.ordered`). Until those walls exist, everything is unlocked —
    /// the chooser is the part being built here, not the gating.
    private var unlockedOmens: [Omen] {
        let earned = Set(Defaults.standard.stringArray(forKey: "unlockedOmens")?
            .compactMap(Omen.init(rawValue:)) ?? Omen.allCases.map { $0 })
        return Omen.ordered.filter { $0 == .smite || earned.contains($0) }
    }

    /// A persisted pick is honored only while it's actually unlocked.
    private func pickedLoadoutWeapon(_ name: String?, from options: [Weapon]) -> Weapon? {
        guard let name else { return nil }
        return options.first { $0.name == name }
    }

    /// random → each option in order → back to random.
    private func cycledLoadoutName(_ current: String?, options: [Weapon]) -> String? {
        guard let current, let index = options.firstIndex(where: { $0.name == current }) else {
            return options.first?.name
        }
        return index + 1 < options.count ? options[index + 1].name : nil
    }

    private func showBuildPicker() {
        buildPickerOverlay?.removeFromParent()
        let overlay = SKNode()
        overlay.zPosition = 88

        // Dim only the board square, not the whole screen, so the nav tabs —
        // and through them the milestones page and title screen — stay reachable
        // without first starting the run.
        let boardSide = min(size.width, size.height) * boardScale
        let dim = SKSpriteNode(color: SKColor(white: 0, alpha: 0.74),
                               size: CGSize(width: boardSide, height: boardSide))
        dim.position = CGPoint(x: size.width / 2, y: size.height / 2)
        overlay.addChild(dim)

        let centerX = size.width / 2
        let centerY = size.height / 2
        let gold = SKColor(red: 0.93, green: 0.80, blue: 0.45, alpha: 1.0)

        let title = SKLabelNode(text: "the draft before the draft")
        title.fontName = "Papyrus"
        title.fontSize = 28
        title.fontColor = gold
        title.position = CGPoint(x: centerX, y: centerY + 156)
        overlay.addChild(title)

        let hint = SKLabelNode(text: "click a slot or condition to change it")
        hint.fontName = "HelveticaNeue"
        hint.fontSize = 13
        hint.fontColor = SKColor(white: 0.6, alpha: 1.0)
        hint.position = CGPoint(x: centerX, y: centerY + 128)
        overlay.addChild(hint)

        let pool = currentWeaponPool()
        let slots: [(String, String, Weapon?, CGFloat)] = [
            ("melee", "build:melee", pickedLoadoutWeapon(loadoutMeleeName, from: pool.filter(\.isMelee)), centerY + 96),
            ("ranged", "build:ranged", pickedLoadoutWeapon(loadoutRangedName, from: pool.filter(\.isRanged)), centerY + 48),
        ]
        for (slot, action, weapon, rowY) in slots {
            let row = SKLabelNode(text: "\(slot): \(weapon?.name ?? "random") ▸")
            row.fontName = "HelveticaNeue-Bold"
            row.fontSize = 18
            row.fontColor = SKColor(white: 0.9, alpha: 1.0)
            row.verticalAlignmentMode = .center
            row.position = CGPoint(x: centerX, y: rowY)
            row.name = action
            overlay.addChild(row)

            let stats = SKLabelNode(text: weapon.map { weaponLegendEntry($0).stats } ?? "the bones decide")
            stats.fontName = "HelveticaNeue"
            stats.fontSize = 12
            stats.fontColor = SKColor(white: 0.55, alpha: 1.0)
            stats.verticalAlignmentMode = .center
            stats.position = CGPoint(x: centerX, y: rowY - 21)
            overlay.addChild(stats)
        }

        // Omen: the third slot of the loadout. Only offered once there's more
        // than one to choose between — a menu with a single entry is a promise,
        // not a choice, so before that the run just carries Smite.
        let omens = unlockedOmens
        if omens.count > 1 {
            let pick = selectedOmen
            let omenRow = SKLabelNode(text: "omen: \(pick.title) ▸")
            omenRow.fontName = "HelveticaNeue-Bold"
            omenRow.fontSize = 18
            omenRow.fontColor = SKColor(white: 0.9, alpha: 1.0)
            omenRow.verticalAlignmentMode = .center
            omenRow.position = CGPoint(x: centerX, y: centerY)
            omenRow.name = "build:omen"
            overlay.addChild(omenRow)

            let omenStats = SKLabelNode(text: "\(pick.blurb) · \(pick.chargeKills) kills")
            omenStats.fontName = "HelveticaNeue"
            omenStats.fontSize = 12
            omenStats.fontColor = SKColor(white: 0.55, alpha: 1.0)
            omenStats.verticalAlignmentMode = .center
            omenStats.position = CGPoint(x: centerX, y: centerY - 21)
            overlay.addChild(omenStats)
        }

        // Pact: opt into one random boon + one random curse. They offset each
        // other, so there's no score fiddling — just a sharper, riskier run.
        let pactHeader = SKLabelNode(text: "PACT")
        pactHeader.fontName = "HelveticaNeue-Bold"
        pactHeader.fontSize = 12
        pactHeader.fontColor = SKColor(white: 0.55, alpha: 1.0)
        pactHeader.horizontalAlignmentMode = .left
        pactHeader.verticalAlignmentMode = .center
        pactHeader.position = CGPoint(x: centerX - 150, y: centerY - 54)
        overlay.addChild(pactHeader)

        let active = activeModifiers
        let hasPact = !active.isEmpty
        let curseColor = SKColor(red: 0.90, green: 0.42, blue: 0.42, alpha: 1.0)

        let canReroll = pactRerollsRemaining > 0
        let pactText: String
        if hasPact {
            pactText = canReroll ? "reroll (\(pactRerollsRemaining)) ▸" : "no rerolls left"
        } else {
            pactText = "strike a bargain ▸"
        }
        let pactControl = SKLabelNode(text: pactText)
        pactControl.fontName = "HelveticaNeue"
        pactControl.fontSize = 12
        pactControl.fontColor = SKColor(white: (hasPact && !canReroll) ? 0.35 : 0.6, alpha: 1.0)
        pactControl.horizontalAlignmentMode = .right
        pactControl.verticalAlignmentMode = .center
        pactControl.position = CGPoint(x: centerX + 150, y: centerY - 54)
        pactControl.name = hasPact ? (canReroll ? "build:pactReroll" : nil) : "build:pactToggle"
        overlay.addChild(pactControl)

        if hasPact {
            let entries: [(RunModifier?, String, SKColor)] = [
                (active.first(where: \.isBoon), "BOON", gold),
                (active.first(where: { !$0.isBoon }), "CURSE", curseColor),
            ]
            var lineY = centerY - 82
            for (modifier, glyph, color) in entries {
                guard let modifier else { continue }
                let label = SKLabelNode(text: "\(glyph) · \(modifier.title) — \(modifier.blurb)")
                label.fontName = "HelveticaNeue-Bold"
                label.fontSize = 14
                label.fontColor = color
                label.verticalAlignmentMode = .center
                label.position = CGPoint(x: centerX, y: lineY)
                overlay.addChild(label)
                lineY -= 24
            }
            let clear = SKLabelNode(text: "break the pact ▸")
            clear.fontName = "HelveticaNeue"
            clear.fontSize = 12
            clear.fontColor = SKColor(white: 0.5, alpha: 1.0)
            clear.verticalAlignmentMode = .center
            clear.position = CGPoint(x: centerX, y: lineY - 2)
            clear.name = "build:pactToggle"
            overlay.addChild(clear)
        } else {
            let hint = SKLabelNode(text: "take a boon and a curse — a bolder run")
            hint.fontName = "HelveticaNeue"
            hint.fontSize = 13
            hint.fontColor = SKColor(white: 0.55, alpha: 1.0)
            hint.verticalAlignmentMode = .center
            hint.position = CGPoint(x: centerX, y: centerY - 88)
            hint.name = "build:pactToggle"
            overlay.addChild(hint)
        }

        let begin = SKShapeNode(rectOf: CGSize(width: 180, height: 48), cornerRadius: 10)
        begin.fillColor = SKColor(red: 0.20, green: 0.55, blue: 0.35, alpha: 1.0)
        begin.strokeColor = .white
        begin.lineWidth = 1.5
        begin.position = CGPoint(x: centerX, y: centerY - 178)
        begin.name = "build:start"
        let beginLabel = SKLabelNode(text: "BEGIN")
        beginLabel.fontName = "HelveticaNeue-Bold"
        beginLabel.fontSize = 20
        beginLabel.fontColor = .white
        beginLabel.verticalAlignmentMode = .center
        beginLabel.name = "build:start"
        begin.addChild(beginLabel)
        overlay.addChild(begin)

        let spaceHint = SKLabelNode(text: "space also begins")
        spaceHint.fontName = "HelveticaNeue"
        spaceHint.fontSize = 12
        spaceHint.fontColor = SKColor(white: 0.55, alpha: 1.0)
        spaceHint.position = CGPoint(x: centerX, y: centerY - 208)
        overlay.addChild(spaceHint)

        addChild(overlay)
        buildPickerOverlay = overlay
    }

    /// Locks the picks in: a fresh run is dealt with them applied.
    private func startRun() {
        buildPickerOverlay = nil
        rebuildRun()
        // A brand-new player is coached through their first turn automatically;
        // the "new here?" button replays it on demand thereafter.
        if !hasSeenTutorial {
            hasSeenTutorial = true
            startTutorial()
        }
    }

    /// Whether this profile has been shown the interactive tutorial once.
    private var hasSeenTutorial: Bool {
        get { Defaults.standard.bool(forKey: "hasSeenTutorial") }
        set { Defaults.standard.set(newValue, forKey: "hasSeenTutorial") }
    }

    // MARK: - Dev panel

    /// God mode, behind the time-honored backtick. "Next" values apply on the
    /// next restart; the rest is immediate.
    private var devPanel: SKNode?
    private var devNextEquipped: Weapon?
    private var devNextHolstered: Weapon?
    private var devNextMaxHealth = 5
    private var devNextMaxArmor = 3
    /// When on, a run's score never touches the saved best — for testing
    /// without polluting your records.
    private var devFreezeHighScore = false
    /// Next-wave override: how the coming waves spawn, and (in normal mode) the
    /// forced enemy type and weapon. `.standard` hands back to the normal code.
    private enum DevSpawnMode { case standard, normal, formation, elite }
    private var devSpawnMode: DevSpawnMode = .standard
    private var devSpawnArchetype: Archetype?
    /// Which gatekeeper the elite spawn mode drops.
    private var devSpawnEliteArchetype: Archetype = .boss
    private let devEliteArchetypes: [Archetype] = [.boss, .juggernaut, .summoner, .bombardier]
    private var devSpawnWeapon: Weapon?
    /// Which formation the override forces (nil = random).
    private var devSpawnFormationIndex: Int?
    /// The archetypes offered by the spawn-type cycler (nil = roll one).
    private let devSpawnArchetypes: [Archetype?] = [nil, .fighter, .berserker, .swift, .shieldbearer, .bomber, .reaver]

    private func toggleDevPanel() {
        if devPanel != nil {
            devPanel?.removeFromParent()
            devPanel = nil
            return
        }
        showTransmission("oh no! its the real god!| quick! hide!")
        rebuildDevPanel()
    }

    /// Which category of dev tools the panel is currently showing. Persists
    /// while the panel is closed so it reopens on the last-used tab.
    private enum DevTab: CaseIterable {
        case player, spawn, score, run, profile
        var title: String {
            switch self {
            case .player: return "PLAYER"
            case .spawn: return "SPAWN"
            case .score: return "SCORE"
            case .run: return "RUN"
            case .profile: return "PROFILE"
            }
        }
    }
    private var devTab: DevTab = .player

    /// The rows for the active dev tab: (label, action) pairs; an empty action
    /// marks a non-clickable note.
    private func devTabRows() -> [(String, String)] {
        switch devTab {
        case .run:
            return [
                ("next equipped: \(devNextEquipped?.name ?? "random") ▸", "dev:equipped"),
                ("next holstered: \(devNextHolstered?.name ?? "random") ▸", "dev:holstered"),
                ("next max HP: \(devNextMaxHealth) ▸", "dev:hp"),
                ("next armor cap: \(devNextMaxArmor) ▸", "dev:armor"),
                ("— applies on R restart —", ""),
                ("next pact boon: \(devForcedPactBoon?.title ?? "random") ▸", "dev:pactBoon"),
                ("next pact curse: \(devForcedPactCurse?.title ?? "random") ▸", "dev:pactCurse"),
                ("next level boon 1: \(state.devForcedBuff?.name ?? "random") ▸", "dev:levelBoon"),
                ("next level boon 2: \(state.devForcedBuff2?.name ?? "random") ▸", "dev:levelBoon2"),
            ]
        case .player:
            return [
                ("heal fully", "dev:heal"),
                ("fill ultimate", "dev:ultFill"),
                ("zero ultimate", "dev:ultZero"),
                ("invincible: \(state.devInvincible ? "ON" : "off")", "dev:invincible"),
                ("stun immune: \(state.devStunImmune ? "ON" : "off")", "dev:stunImmune"),
                ("knockback immune: \(state.devKnockbackImmune ? "ON" : "off")", "dev:kbImmune"),
                ("infinite speed: \(state.devInfiniteSpeed ? "ON" : "off")", "dev:infiniteSpeed"),
                ("infinite range: \(state.devInfiniteRange ? "ON" : "off")", "dev:infiniteRange"),
                ("no cooldown: \(state.devNoCooldown ? "ON" : "off")", "dev:noCooldown"),
                ("free swap: \(state.devFreeSwap ? "ON" : "off")", "dev:freeSwap"),
                ("ignore shields: \(state.devIgnoreShields ? "ON" : "off")", "dev:ignoreShields"),
                ("attack damage: \(devDamageModeLabel) ▸", "dev:damageMode"),
            ]
        case .score:
            return [
                ("+100 score", "dev:score"),
                ("freeze high score: \(devFreezeHighScore ? "ON" : "off")", "dev:freezeScore"),
                ("freeze score gain: \(state.devFreezeScore ? "ON" : "off")", "dev:freezeScoreGain"),
            ]
        case .spawn:
            var rows: [(String, String)] = [
                ("elites: \(state.devNoElites ? "OFF" : "on")", "dev:noElites"),
                ("next wave: \(devSpawnModeLabel) ▸", "dev:spawnMode"),
            ]
            if devSpawnMode == .normal {
                rows.append(("spawn type: \(devArchetypeLabel(devSpawnArchetype)) ▸", "dev:spawnType"))
                rows.append(("spawn weapon: \(devSpawnWeapon?.name ?? "random") ▸", "dev:spawnWeapon"))
            } else if devSpawnMode == .formation {
                let name = devSpawnFormationIndex.map { Formation.all[$0].name } ?? "random"
                rows.append(("formation: \(name) ▸", "dev:spawnFormation"))
            } else if devSpawnMode == .elite {
                rows.append(("elite: \(devArchetypeLabel(devSpawnEliteArchetype)) ▸", "dev:eliteType"))
            }
            return rows
        case .profile:
            return [
                ("unlock entire arsenal", "dev:unlockAll"),
                ("reset profile (unlocks, tallies, best)", "dev:resetProfile"),
            ]
        }
    }

    private func rebuildDevPanel() {
        devPanel?.removeFromParent()
        let overlay = SKNode()
        // Above the build-picker overlay (88) so opening the dev panel over the
        // "draft before the draft" isn't hidden behind that overlay's board dim.
        overlay.zPosition = 95

        let bodyRows = devTabRows()
        let rowHeight: CGFloat = 24
        // A title row, the tab bar, then the active tab's rows.
        let lineCount = 2 + bodyRows.count
        let panelSize = CGSize(width: 440, height: CGFloat(lineCount) * rowHeight + 30)
        // Keep the panel clear of the "real god" transmission, which types out
        // just above centre (see showTransmission). Pin the panel's top edge
        // below that line, then clamp so a tall panel still sits on-screen.
        let boardSide = min(size.width, size.height) * boardScale
        let transmissionBottom = size.height / 2 + boardSide * 0.28 - 48
        let panelCenterY = max(panelSize.height / 2 + 20, transmissionBottom - panelSize.height / 2)
        let centerX = size.width / 2
        let plate = SKShapeNode(rectOf: panelSize, cornerRadius: 10)
        plate.fillColor = SKColor(white: 0.05, alpha: 0.95)
        plate.strokeColor = SKColor(red: 0.55, green: 0.75, blue: 0.95, alpha: 0.9)
        plate.lineWidth = 1.5
        plate.position = CGPoint(x: centerX, y: panelCenterY)
        // Named so a click landing on the panel (but not a row) is caught as
        // "inside" and doesn't dismiss it — only clicks outside close the panel.
        plate.name = "dev:plate"
        overlay.addChild(plate)

        var y = panelCenterY + panelSize.height / 2 - 24

        // Title.
        let title = SKLabelNode(text: "DEV MODE — ` or esc closes")
        title.fontName = "HelveticaNeue-Bold"
        title.fontSize = 12
        title.fontColor = SKColor(white: 0.5, alpha: 1.0)
        title.verticalAlignmentMode = .center
        title.horizontalAlignmentMode = .center
        title.position = CGPoint(x: centerX, y: y)
        overlay.addChild(title)
        y -= rowHeight

        // Tab bar: a row of category tabs, the active one lit like the HUD nav.
        let selected = SKColor(red: 0.55, green: 0.75, blue: 0.95, alpha: 1.0)
        let dim = SKColor(white: 0.5, alpha: 1.0)
        let gap: CGFloat = 16
        var tabLabels: [SKLabelNode] = []
        var totalWidth: CGFloat = 0
        for tab in DevTab.allCases {
            let label = SKLabelNode(text: tab.title)
            label.fontName = "HelveticaNeue-Bold"
            label.fontSize = 13
            label.fontColor = tab == devTab ? selected : dim
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .left
            label.name = "dev:tab:\(tab.title)"
            tabLabels.append(label)
            totalWidth += label.frame.width
        }
        totalWidth += gap * CGFloat(max(0, tabLabels.count - 1))
        var tabX = centerX - totalWidth / 2
        for label in tabLabels {
            label.position = CGPoint(x: tabX, y: y)
            overlay.addChild(label)
            tabX += label.frame.width + gap
        }
        y -= rowHeight

        // Active tab's rows.
        for (text, action) in bodyRows {
            let label = SKLabelNode(text: text)
            label.fontName = action.isEmpty ? "HelveticaNeue-Bold" : "HelveticaNeue"
            label.fontSize = 14
            label.fontColor = action.isEmpty
                ? SKColor(white: 0.5, alpha: 1.0)
                : SKColor(white: 0.88, alpha: 1.0)
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            label.position = CGPoint(x: centerX, y: y)
            if !action.isEmpty {
                label.name = action
            }
            overlay.addChild(label)
            y -= rowHeight
        }

        addChild(overlay)
        devPanel = overlay
    }

    // MARK: - Settings

    private func showSettings() {
        rebindingAction = nil
        rebuildSettings()
    }

    /// Scales every timed action: near-instant when animations are skipped.
    private func applyAnimationSpeed() {
        speed = skipAnimations ? 10 : 1
    }

    /// Shows or hides the SKView's FPS and node-count readouts per the pref.
    private func applyDebugOverlays() {
        // OpenSpriteKit's SKView members are @MainActor; this dev-only overlay
        // isn't worth threading isolation through the shared scene, so it's a
        // no-op on web (browser DevTools cover FPS anyway).
        #if canImport(AppKit)
        guard let skView = view else { return }
        skView.showsFPS = showFPS
        skView.showsNodeCount = showFPS
        #endif
    }

    /// Starts the run, or on the first press (with confirmation on) asks again.
    private func attemptStartRun(at time: TimeInterval) {
        if !confirmStartRun || time - lastStartConfirmTime < Self.restartDoubleTapWindow {
            startRun()
        } else {
            lastStartConfirmTime = time
            showToast("press again to begin the run")
        }
    }

    private func closeSettings() {
        settingsOverlay?.removeFromParent()
        settingsOverlay = nil
        rebindingAction = nil
    }

    /// The settings rows: (label, action) — an empty action marks a plain note.
    private func settingsRows() -> [(String, String)] {
        var rows: [(String, String)] = [
            ("— preferences —", ""),
            ("natural scrolling: \(naturalScrolling ? "ON" : "off")", "set:naturalScroll"),
            ("skip animations: \(skipAnimations ? "ON" : "off")", "set:skipAnim"),
            ("confirm restarts: \(confirmRestart ? "ON" : "off")", "set:confirmRestart"),
            ("confirm starting a run: \(confirmStartRun ? "ON" : "off")", "set:confirmStart"),
            ("click twice to pick a boon: \(confirmBoonChoice ? "ON" : "off")", "set:confirmBoon"),
            ("show FPS counter: \(showFPS ? "ON" : "off")", "set:showFPS"),
            ("— keybinds —", ""),
        ]
        for action in KeyAction.allCases {
            let key = rebindingAction == action ? "press a key…" : keyName(boundCode(for: action))
            rows.append(("\(action.title): \(key)", "set:bind:\(action.rawValue)"))
        }
        rows.append(("reset keybinds to defaults", "set:resetBinds"))
        rows.append(("— note —", ""))
        rows.append(("Return always resolves · Esc always cancels", ""))
        rows.append(("done ▸", "set:close"))
        return rows
    }

    private func rebuildSettings() {
        settingsOverlay?.removeFromParent()
        let overlay = SKNode()
        overlay.zPosition = 95

        let bodyRows = settingsRows()
        let rowHeight: CGFloat = 24
        let lineCount = 1 + bodyRows.count // title + rows.
        let panelSize = CGSize(width: 440, height: CGFloat(lineCount) * rowHeight + 30)
        let centerX = size.width / 2
        let panelCenterY = size.height / 2
        let plate = SKShapeNode(rectOf: panelSize, cornerRadius: 10)
        plate.fillColor = SKColor(white: 0.05, alpha: 0.97)
        plate.strokeColor = SKColor(red: 0.55, green: 0.75, blue: 0.95, alpha: 0.9)
        plate.lineWidth = 1.5
        plate.position = CGPoint(x: centerX, y: panelCenterY)
        plate.name = "set:plate"
        overlay.addChild(plate)

        var y = panelCenterY + panelSize.height / 2 - 24

        let title = SKLabelNode(text: "SETTINGS — esc closes")
        title.fontName = "HelveticaNeue-Bold"
        title.fontSize = 12
        title.fontColor = SKColor(white: 0.5, alpha: 1.0)
        title.verticalAlignmentMode = .center
        title.horizontalAlignmentMode = .center
        title.position = CGPoint(x: centerX, y: y)
        overlay.addChild(title)
        y -= rowHeight

        for (text, action) in bodyRows {
            let label = SKLabelNode(text: text)
            label.fontName = action.isEmpty ? "HelveticaNeue-Bold" : "HelveticaNeue"
            label.fontSize = 14
            label.fontColor = action.isEmpty
                ? SKColor(white: 0.5, alpha: 1.0)
                : SKColor(white: 0.88, alpha: 1.0)
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            label.position = CGPoint(x: centerX, y: y)
            if !action.isEmpty {
                label.name = action
            }
            overlay.addChild(label)
            y -= rowHeight
        }

        addChild(overlay)
        settingsOverlay = overlay
    }

    private func handleSettingsAction(_ action: String) {
        switch action {
        case "set:naturalScroll":
            naturalScrolling.toggle()
            rebuildSettings()
        case "set:skipAnim":
            skipAnimations.toggle()
            applyAnimationSpeed()
            rebuildSettings()
        case "set:confirmRestart":
            confirmRestart.toggle()
            rebuildSettings()
        case "set:confirmStart":
            confirmStartRun.toggle()
            rebuildSettings()
        case "set:confirmBoon":
            confirmBoonChoice.toggle()
            rebuildSettings()
        case "set:showFPS":
            showFPS.toggle()
            applyDebugOverlays()
            rebuildSettings()
        case "set:resetBinds":
            keyBindings = [:]
            rebindingAction = nil
            rebuildSettings()
        case "set:close":
            closeSettings()
        default:
            if action.hasPrefix("set:bind:"),
               let bind = KeyAction(rawValue: String(action.dropFirst("set:bind:".count))) {
                // Toggle capture: click the row again to cancel listening.
                rebindingAction = (rebindingAction == bind) ? nil : bind
                rebuildSettings()
            }
        }
    }

    /// Cycles a next-run weapon slot through random and the whole arsenal,
    /// including the dev-only toys that never appear in normal pools.
    private func cycleDevWeapon(_ current: Weapon?) -> Weapon? {
        let pool = Weapon.devArsenal.sorted { $0.name < $1.name }
        guard let current else { return pool.first }
        guard let index = pool.firstIndex(where: { $0.name == current.name }),
              index + 1 < pool.count else { return nil }
        return pool[index + 1]
    }

    private var devSpawnModeLabel: String {
        switch devSpawnMode {
        case .standard: return "standard (normal code)"
        case .normal: return "normal"
        case .formation: return "formation"
        case .elite: return "elite gate"
        }
    }

    private var devDamageModeLabel: String {
        switch state.devDamageMode {
        case .normal: return "normal"
        case .instakill: return "insta-kill"
        case .zero: return "zero"
        }
    }

    private func devArchetypeLabel(_ archetype: Archetype?) -> String {
        switch archetype {
        case .none: return "random"
        case .fighter: return "fighter"
        case .berserker: return "berserker"
        case .swift: return "swift"
        case .shieldbearer: return "shieldbearer"
        case .bomber: return "bomber"
        case .reaver: return "reaver"
        case .juggernaut: return "juggernaut"
        case .boss: return "boss"
        case .summoner: return "summoner"
        case .bombardier: return "bombardier"
        }
    }

    /// Pushes the current dev spawn selections into the game state so the next
    /// wave honors them (standard mode clears the override).
    private func syncDevSpawnOverride() {
        switch devSpawnMode {
        case .standard: state.devSpawnOverride = nil
        case .normal: state.devSpawnOverride = .single(archetype: devSpawnArchetype, weapon: devSpawnWeapon)
        case .formation: state.devSpawnOverride = .formation(index: devSpawnFormationIndex)
        case .elite: state.devSpawnOverride = .elite(archetype: devSpawnEliteArchetype)
        }
    }

    private func handleDevAction(_ action: String) {
        switch action {
        case let tabAction where tabAction.hasPrefix("dev:tab:"):
            let title = String(tabAction.dropFirst("dev:tab:".count))
            devTab = DevTab.allCases.first { $0.title == title } ?? devTab
        case "dev:equipped": devNextEquipped = cycleDevWeapon(devNextEquipped)
        case "dev:holstered": devNextHolstered = cycleDevWeapon(devNextHolstered)
        case "dev:hp": devNextMaxHealth = devNextMaxHealth >= 20 ? 1 : devNextMaxHealth + 1
        case "dev:armor": devNextMaxArmor = devNextMaxArmor >= 8 ? 0 : devNextMaxArmor + 1
        case "dev:ultFill": state.devSetUltimateCharge(state.ultimateChargeKills)
        case "dev:ultZero": state.devSetUltimateCharge(0)
        case "dev:heal": state.devHealFully()
        case "dev:score": state.devAddScore(100)
        case "dev:invincible": state.devInvincible.toggle()
        case "dev:stunImmune":
            state.devStunImmune.toggle()
            if state.devStunImmune { state.devClearPlayerStun() }
            refreshStunMarkers()
        case "dev:kbImmune": state.devKnockbackImmune.toggle()
        case "dev:infiniteSpeed":
            state.devInfiniteSpeed.toggle()
            refreshTileHighlights()
        case "dev:infiniteRange":
            state.devInfiniteRange.toggle()
            refreshTileHighlights()
        case "dev:noCooldown":
            state.devNoCooldown.toggle()
            refreshTileHighlights()
        case "dev:freeSwap": state.devFreeSwap.toggle()
        case "dev:ignoreShields": state.devIgnoreShields.toggle()
        case "dev:pactBoon":
            // Cycle the forced pact boon: random → each boon → random.
            let boons = devPactBoons
            if let current = devForcedPactBoon, let i = boons.firstIndex(of: current) {
                devForcedPactBoon = i + 1 < boons.count ? boons[i + 1] : nil
            } else {
                devForcedPactBoon = boons.first
            }
        case "dev:pactCurse":
            // Cycle the forced pact curse: random → each curse → random.
            let curses = devPactCurses
            if let current = devForcedPactCurse, let i = curses.firstIndex(of: current) {
                devForcedPactCurse = i + 1 < curses.count ? curses[i + 1] : nil
            } else {
                devForcedPactCurse = curses.first
            }
        case "dev:levelBoon":
            // Cycle the first forced level-up option: random → each buff → random.
            let all = devLevelBoons
            if let current = state.devForcedBuff, let i = all.firstIndex(of: current) {
                state.devForcedBuff = i + 1 < all.count ? all[i + 1] : nil
            } else {
                state.devForcedBuff = all.first
            }
        case "dev:levelBoon2":
            // Cycle the second forced level-up option: random → each buff → random.
            let all = devLevelBoons
            if let current = state.devForcedBuff2, let i = all.firstIndex(of: current) {
                state.devForcedBuff2 = i + 1 < all.count ? all[i + 1] : nil
            } else {
                state.devForcedBuff2 = all.first
            }
        case "dev:damageMode":
            switch state.devDamageMode {
            case .normal: state.devDamageMode = .instakill
            case .instakill: state.devDamageMode = .zero
            case .zero: state.devDamageMode = .normal
            }
        case "dev:freezeScore": devFreezeHighScore.toggle()
        case "dev:freezeScoreGain": state.devFreezeScore.toggle()
        case "dev:noElites": state.devNoElites.toggle()
        case "dev:spawnMode":
            switch devSpawnMode {
            case .standard: devSpawnMode = .normal
            case .normal: devSpawnMode = .formation
            case .formation: devSpawnMode = .elite
            case .elite: devSpawnMode = .standard
            }
            syncDevSpawnOverride()
        case "dev:eliteType":
            let idx = devEliteArchetypes.firstIndex(of: devSpawnEliteArchetype) ?? 0
            devSpawnEliteArchetype = devEliteArchetypes[(idx + 1) % devEliteArchetypes.count]
            syncDevSpawnOverride()
        case "dev:spawnType":
            let idx = devSpawnArchetypes.firstIndex(where: { $0 == devSpawnArchetype }) ?? 0
            devSpawnArchetype = devSpawnArchetypes[(idx + 1) % devSpawnArchetypes.count]
            syncDevSpawnOverride()
        case "dev:spawnWeapon":
            // Cycle random → each real weapon (dev-only toys excluded from enemies).
            let spawnPool = Weapon.all.sorted { $0.name < $1.name }
            if let current = devSpawnWeapon,
               let i = spawnPool.firstIndex(where: { $0.name == current.name }), i + 1 < spawnPool.count {
                devSpawnWeapon = spawnPool[i + 1]
            } else if devSpawnWeapon == nil {
                devSpawnWeapon = spawnPool.first
            } else {
                devSpawnWeapon = nil
            }
            syncDevSpawnOverride()
        case "dev:spawnFormation":
            // Cycle random → each named formation → random.
            switch devSpawnFormationIndex {
            case nil: devSpawnFormationIndex = Formation.all.isEmpty ? nil : 0
            case let i? where i + 1 < Formation.all.count: devSpawnFormationIndex = i + 1
            default: devSpawnFormationIndex = nil
            }
            syncDevSpawnOverride()
        case "dev:unlockAll":
            unlockedWeaponNames = Set(Weapon.milestones.map(\.weapon.name))
            claimedTrophyNames = Set(Weapon.eliteTrophies.map(\.name))
            rebuildLegend()
            rebuildMilestonesPage()
        case "dev:resetProfile":
            for key in ["claimedTrophies", "unlockedWeapons", "lifetimeTallies", "highScore", "hasSeenTutorial"] {
                Defaults.standard.removeObject(forKey: key)
            }
            tallyBaseline = [:]
            rebuildLegend()
            rebuildMilestonesPage()
        default:
            break
        }
        rebuildDevPanel()
        updateHUD()
    }

    /// Folds this run's credited kills into the lifetime record and announces
    /// any milestone that just cleared (its weapon joins the next run's pool).
    private func syncLifetimeProgress() {
        var lifetime = tallyBaseline
        for (key, count) in state.progressTallies {
            lifetime[key, default: 0] += count
        }
        lifetimeTallies = lifetime
        for milestone in Weapon.milestones
        where !unlockedWeaponNames.contains(milestone.weapon.name)
            && lifetime[milestone.tally, default: 0] >= milestone.count {
            unlockedWeaponNames.insert(milestone.weapon.name)
            showToast("UNLOCKED: \(milestone.weapon.name) — found in the wild from your next run", duration: 2.6)
            rebuildLegend()
        }
        if !milestonesPageNode.isHidden {
            rebuildMilestonesPage()
        }
    }

    // MARK: - Title screen

    /// The front door: shown on launch over a fresh board, dismissed by any
    /// key or click.
    private func showTitleScreen() {
        let overlay = SKNode()
        overlay.zPosition = 90

        let dim = SKSpriteNode(color: SKColor(white: 0.04, alpha: 0.96), size: size)
        dim.position = CGPoint(x: size.width / 2, y: size.height / 2)
        overlay.addChild(dim)

        let centerX = size.width / 2
        let gold = SKColor(red: 0.93, green: 0.80, blue: 0.45, alpha: 1.0)

        let title = SKLabelNode(text: "FORETOLD")
        title.fontName = "Papyrus"
        title.fontSize = 82
        title.fontColor = gold
        title.position = CGPoint(x: centerX, y: size.height / 2 + 120)
        overlay.addChild(title)

        let subtitle = SKLabelNode(text: "every turn is drafted. every death, foretold.")
        subtitle.fontName = "Baskerville-Italic"
        subtitle.fontSize = 19
        subtitle.fontColor = SKColor(white: 0.7, alpha: 1.0)
        subtitle.position = CGPoint(x: centerX, y: size.height / 2 + 62)
        overlay.addChild(subtitle)

        let best = SKLabelNode(text: highScore > 0 ? "best score \(highScore)" : "no runs yet — the bones are optimistic")
        best.fontName = "HelveticaNeue"
        best.fontSize = 15
        best.fontColor = SKColor(white: 0.75, alpha: 1.0)
        best.position = CGPoint(x: centerX, y: size.height / 2 - 10)
        overlay.addChild(best)

        let claimed = claimedTrophyNames.sorted().joined(separator: ", ")
        let trophies = SKLabelNode(text: claimed.isEmpty
            ? "elite trophies claimed: none — take one off a gatekeeper's corpse"
            : "elite trophies claimed: \(claimed) — now found in the wild")
        trophies.fontName = "HelveticaNeue"
        trophies.fontSize = 13
        trophies.fontColor = gold.withAlphaComponent(0.85)
        trophies.position = CGPoint(x: centerX, y: size.height / 2 - 38)
        overlay.addChild(trophies)

        let prompt = SKLabelNode(text: "click — or any key — to begin")
        prompt.fontName = "HelveticaNeue-Bold"
        prompt.fontSize = 16
        prompt.fontColor = SKColor(white: 0.8, alpha: 1.0)
        prompt.position = CGPoint(x: centerX, y: size.height / 2 - 110)
        prompt.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.3, duration: 0.8),
            SKAction.fadeAlpha(to: 1.0, duration: 0.8),
        ])))
        overlay.addChild(prompt)

        addChild(overlay)
        titleOverlay = overlay
    }

    private func dismissTitleScreen() {
        guard let overlay = titleOverlay else { return }
        titleOverlay = nil
        overlay.run(SKAction.sequence([
            SKAction.fadeOut(withDuration: 0.35),
            SKAction.removeFromParent(),
        ]))
        // An untouched run behind the title means we're heading into a fresh
        // one: roll a new pact and route through the loadout draft first.
        if state.turnNumber == 0 && buildPickerOverlay == nil {
            openFreshPactDraft()
        }
    }

    // MARK: - Input

    func handleMouseMoved(_ event: GameInput) {
        // Pact hover lives outside the board grid, so update it before the
        // tile-hover early-out below.
        updatePactTooltip(at: event.location)
        let newHover = gridPosition(at: event.location)
        guard newHover != hoveredTile else { return }
        hoveredTile = newHover
        if tutorialStep == .hover, let hovered = newHover, state.enemy(at: hovered) != nil {
            advanceTutorial(after: .hover)
        }
        // Mid-resolve, a hover repaint would wipe the attack/blast tile
        // flashes; finishResolvePhase refreshes with the new hover anyway.
        guard !isResolving else { return }
        updateEnemyHoverInfo()
        refreshTileHighlights()
    }

    func handleMouseDown(_ event: GameInput) {
        if titleOverlay != nil {
            dismissTitleScreen()
            return
        }
        let location = event.location
        let clickedNames = nodes(at: location).compactMap(\.name)
        // The advanced tutorial keeps the board playable: only its own NEXT/SKIP
        // buttons are intercepted; every other click falls through to normal play.
        if advancedTutorialActive {
            if clickedNames.contains("advTutorial:skip") { endAdvancedTutorial(); return }
            if clickedNames.contains("advTutorial:next"), let advance = lessonNext { advance(); return }
        }
        if devPanel != nil {
            // The dev panel is modal: a row acts, empty panel space is inert,
            // and only a click outside the panel (or ` / esc) dismisses it.
            if let action = clickedNames.first(where: { $0.hasPrefix("dev:") && $0 != "dev:plate" }) {
                handleDevAction(action)
            } else if !clickedNames.contains("dev:plate") {
                toggleDevPanel()
            }
            return
        }
        if settingsOverlay != nil {
            // Modal like the dev panel: rows act, the plate swallows stray clicks,
            // and a click outside (or Esc / DONE) closes it.
            if let action = clickedNames.first(where: { $0.hasPrefix("set:") && $0 != "set:plate" }) {
                handleSettingsAction(action)
            } else if !clickedNames.contains("set:plate") {
                closeSettings()
            }
            return
        }
        if buildPickerOverlay != nil {
            // The loadout draft dims only the board: slots cycle and BEGIN deals
            // the run, but the nav tabs stay live so the milestones page and the
            // title screen are reachable without starting.
            let pool = currentWeaponPool()
            if clickedNames.contains("build:melee") {
                loadoutMeleeName = cycledLoadoutName(loadoutMeleeName, options: pool.filter(\.isMelee))
                showBuildPicker()
            } else if clickedNames.contains("build:ranged") {
                loadoutRangedName = cycledLoadoutName(loadoutRangedName, options: pool.filter(\.isRanged))
                showBuildPicker()
            } else if clickedNames.contains("build:omen") {
                let omens = unlockedOmens
                let next = omens.firstIndex(of: selectedOmen).map { omens[($0 + 1) % omens.count] }
                selectedOmen = next ?? .smite
                showBuildPicker()
            } else if clickedNames.contains("build:pactToggle") {
                // No pact → take the drafted bargain (rolling one the first time);
                // active pact → break it. Toggling reuses the same pact so it can't
                // be spun for a new one without spending a reroll.
                if activeModifiers.isEmpty {
                    if draftedPact.isEmpty { draftedPact = rolledPact() }
                    activeModifiers = draftedPact
                } else {
                    activeModifiers = []
                }
                showBuildPicker()
            } else if clickedNames.contains("build:pactReroll") {
                guard pactRerollsRemaining > 0 else { return }
                pactRerollsRemaining -= 1
                draftedPact = rolledPact()
                activeModifiers = draftedPact
                showBuildPicker()
            } else if clickedNames.contains("build:start") {
                attemptStartRun(at: event.timestamp)
            } else if clickedNames.contains("tutorialButton") {
                // The tutorial button works straight from the draft: it just
                // begins the run (whatever's picked, or random) and coaches.
                startRun()
                if tutorialStep == nil && !advancedTutorialActive { startTutorial() }
            } else if clickedNames.contains("advancedTutorialButton") {
                // Sandbox over the draft (don't commit a run); SKIP/FINISH returns
                // here so the player still gets to pick their loadout and pact.
                advancedReturnToBuildPicker = true
                buildPickerOverlay?.removeFromParent()
                buildPickerOverlay = nil
                startAdvancedTutorial()
            } else if let tab = clickedNames.first(where: { $0.hasPrefix("navTab:") }) {
                switch tab {
                case "navTab:board": setHUDPage(.board)
                case "navTab:milestones":
                    rebuildMilestonesPage()
                    setHUDPage(.milestones)
                case "navTab:settings": showSettings()
                default: showTitleScreen()
                }
            } else {
                // The far-left reference dropdowns stay live under the draft too.
                toggleLegendSection(named: clickedNames)
            }
            return
        }
        if buffChoiceOverlay != nil {
            // The boon chooser dims the board, but the far-left reference
            // dropdowns stay live so you can read up before committing.
            if let choice = clickedNames.first(where: { $0.hasPrefix("buffChoice:") }),
               let index = Int(choice.dropFirst("buffChoice:".count)) {
                pickBuff(index)
            } else {
                toggleLegendSection(named: clickedNames)
            }
            return
        }
        if clickedNames.contains(Self.goButtonName) {
            resolveTurn()
            return
        }
        if clickedNames.contains(Self.weaponButtonName) {
            swapWeapons()
            return
        }
        if clickedNames.contains("tutorialButton") {
            startTutorial()
            return
        }
        if clickedNames.contains("advancedTutorialButton") {
            advancedReturnToBuildPicker = false
            startAdvancedTutorial()
            return
        }
        if let tab = clickedNames.first(where: { $0.hasPrefix("navTab:") }) {
            switch tab {
            case "navTab:board": setHUDPage(.board)
            case "navTab:milestones":
                rebuildMilestonesPage()
                setHUDPage(.milestones)
            default: showTitleScreen()
            }
            return
        }
        if toggleLegendSection(named: clickedNames) {
            return
        }
        guard let target = gridPosition(at: location) else { return }
        planMove(to: target)
    }

    /// Flips the tapped reference dropdown open/closed and rebuilds the legend.
    /// Returns whether a toggle was hit, so callers can early-out.
    @discardableResult
    private func toggleLegendSection(named clickedNames: [String]) -> Bool {
        guard let toggle = clickedNames.first(where: { $0.hasPrefix("legendToggle:") }),
              let section = LegendSection(rawValue: String(toggle.dropFirst("legendToggle:".count))) else {
            return false
        }
        // Accordion: opening a section collapses the others; clicking the open
        // one closes it. At most one dropdown is expanded at a time.
        if expandedLegendSections.contains(section) {
            expandedLegendSections.removeAll()
        } else {
            expandedLegendSections = [section]
        }
        legendScroll = 0   // start a freshly-opened section at its top
        rebuildLegend()
        return true
    }

    /// Right-click drafts the equipped weapon's attack: directional weapons face
    /// the clicked tile, thrown weapons land on it. Right-clicking the planned
    /// destination cancels whatever's drafted — directional swing or throw alike.
    func handleRightMouseDown(_ event: GameInput) {
        guard titleOverlay == nil, buildPickerOverlay == nil, devPanel == nil else { return }
        guard !tutorialShowcasing else { return }
        guard !isResolving, !state.isGameOver, buffChoiceOverlay == nil else { return }
        guard let tile = gridPosition(at: event.location) else { return }
        // With Detonation charges in hand, right-clicking a barrel spends one on
        // it instead of swinging at it — clicking the aimed barrel again takes
        // it back, the same toggle the attack draft uses.
        if state.omenCharges > 0, state.obstacle(at: tile)?.kind == .barrel {
            if state.plannedDetonateTarget == tile {
                state.clearPlannedDetonation()
            } else {
                state.planDetonation(at: tile)
            }
            refreshTileHighlights()
            updateHUD()
            return
        }
        let hasDraft = state.plannedAttackDirection != nil || state.plannedThrowTarget != nil
            || state.plannedDetonateTarget != nil
        if tile == state.attackOrigin && hasDraft {
            state.clearPlannedAttack()
            state.clearPlannedDetonation()
        } else {
            state.planAttack(toward: tile)
            if state.plannedAttackDirection != nil || state.plannedThrowTarget != nil {
                advanceTutorial(after: .attack)
            }
        }
        refreshTileHighlights()
        updateHUD()
    }

    func handleKeyDown(_ event: GameInput) {
        if titleOverlay != nil {
            dismissTitleScreen()
            return
        }
        // An interactive lesson leaves keys live for play (Tab to swap, etc.);
        // Esc bails out of it early.
        if advancedTutorialActive && event.keyCode == 0x35 {
            endAdvancedTutorial()
            return
        }
        if event.keyCode == 0x32 { // ` — the time-honored dev console key.
            toggleDevPanel()
            return
        }
        if devPanel != nil {
            if event.keyCode == 0x35 { // Esc also closes it.
                toggleDevPanel()
            }
            return
        }
        if settingsOverlay != nil {
            if let action = rebindingAction {
                // Capturing a new key for a binding: Esc aborts, anything else binds.
                if event.keyCode != 0x35 {
                    var binds = keyBindings
                    binds[action.rawValue] = Int(event.keyCode)
                    keyBindings = binds
                }
                rebindingAction = nil
                rebuildSettings()
                return
            }
            if event.keyCode == 0x35 { closeSettings() }
            return
        }
        if buildPickerOverlay != nil {
            // Space or Return deals the run with the drafted loadout.
            if event.keyCode == 0x31 || event.keyCode == 0x24 {
                attemptStartRun(at: event.timestamp)
            }
            return
        }
        if buffChoiceOverlay != nil {
            // The boon chooser is modal: 1/2 pick, everything else waits.
            switch event.keyCode {
            case 0x12: pickBuff(0)
            case 0x13: pickBuff(1)
            default: break
            }
            return
        }
        let code = event.keyCode
        // Return always resolves and Esc always cancels — structural keys kept
        // fixed so the turn and menus stay reachable no matter how binds change.
        if code == 0x24 { // Return.
            resolveTurn()
            return
        }
        if code == 0x35 { // Escape: cancel the drafted attack, throw, pickup, or ultimate.
            guard !isResolving else { return }
            state.clearPlannedAttack()
            state.clearPlannedPickup()
            state.clearPlannedUltimate()
            updatePickupHint()
            refreshTileHighlights()
            updateHUD()
            return
        }
        // The rest honor the player's keybinds (defaults: Space, Tab, E, F, R).
        if code == boundCode(for: .resolve) {
            resolveTurn()
        } else if code == boundCode(for: .swap) {
            swapWeapons()
        } else if code == boundCode(for: .pickup) {
            guard !isResolving, !state.isGameOver else { return }
            if state.plannedPickup {
                state.clearPlannedPickup()
            } else {
                state.planPickup()
            }
            updatePickupHint()
            refreshTileHighlights()
            updateHUD()
        } else if code == boundCode(for: .ultimate) {
            guard !isResolving, !state.isGameOver else { return }
            if state.plannedUltimate {
                state.clearPlannedUltimate()
            } else if !state.planUltimate() {
                let needed = state.ultimateChargeKills - state.ultimateKillCharge
                showToast("the omen needs \(needed) more soul\(needed == 1 ? "" : "s")")
            }
            updatePickupHint()
            refreshTileHighlights()
            updateHUD()
        } else if code == boundCode(for: .restart) {
            // Instant once the run is over (or when confirmation is off); otherwise
            // double-tap mid-run to avoid a stray restart.
            if state.isGameOver || !confirmRestart
                || event.timestamp - lastRestartKeyTime < Self.restartDoubleTapWindow {
                restartGame()
            } else {
                lastRestartKeyTime = event.timestamp
                showToast("press R again to restart")
            }
        }
    }

    // MARK: - Platform input adapters

    // The macOS responder overrides translate an NSEvent into the neutral
    // GameInput the shared handlers above consume. The web target will add a
    // DOM adapter that builds GameInput from browser pointer/keyboard/wheel
    // events instead — the handlers themselves never change.
    #if canImport(AppKit)
    override func scrollWheel(with event: NSEvent) {
        handleScroll(GameInput(scrollDeltaY: event.scrollingDeltaY))
    }

    override func mouseMoved(with event: NSEvent) {
        handleMouseMoved(GameInput(location: event.location(in: self)))
    }

    override func mouseDown(with event: NSEvent) {
        handleMouseDown(GameInput(location: event.location(in: self),
                                  timestamp: event.timestamp))
    }

    override func rightMouseDown(with event: NSEvent) {
        handleRightMouseDown(GameInput(location: event.location(in: self)))
    }

    override func keyDown(with event: NSEvent) {
        handleKeyDown(GameInput(keyCode: event.keyCode, timestamp: event.timestamp))
    }
    #endif
}
