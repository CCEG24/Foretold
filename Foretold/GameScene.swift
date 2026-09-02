//
//  GameScene.swift
//  Foretold
//

import SpriteKit

/// Renders the board and turns mouse/keyboard input into turn decisions.
/// All game rules live in GameState; this class only draws and animates.
class GameScene: SKScene {

    private var state = GameState()

    private let boardNode = SKNode()
    private var tileNodes: [GridPosition: SKSpriteNode] = [:]
    private var playerNode: SKShapeNode!
    private var enemyNodes: [Int: SKShapeNode] = [:]
    private var obstacleNodes: [GridPosition: SKNode] = [:]
    private var planArrowNode: SKShapeNode?
    private var enemyPlanArrowNodes: [SKShapeNode] = []
    private var enemyInfoLabel: SKLabelNode?
    private var goButton: SKShapeNode!
    /// Bottom-left status: health/armor pip rows and the ultimate charge bar.
    private let healthBarNode = SKNode()
    private let armorBarNode = SKNode()
    private let ultimateBarNode = SKNode()
    private var dodgeChipLabel: SKLabelNode!
    private var itemsLabel: SKLabelNode!
    private var scoreLabel: SKLabelNode!
    private var buffsLabel: SKLabelNode!
    private var spawnMarkerNodes: [SKNode] = []
    private var weaponDropNodes: [SKNode] = []
    /// Lob shell beads, keyed by projectile id — persistent so the resolve
    /// phase can glide them along their arc.
    private var lobNodes: [Int: SKShapeNode] = [:]
    /// Where each airborne lob will land, for the landing dive animation.
    private var lobTargets: [Int: CGPoint] = [:]
    /// Bolt slivers, keyed by bolt id — persistent so the resolve phase can
    /// glide them along their flight.
    private var boltNodes: [Int: SKShapeNode] = [:]
    private var weaponButton: SKShapeNode!
    private var weaponLabel: SKLabelNode!
    private var weaponSubLabel: SKLabelNode!
    private var tileSize: CGFloat = 0

    private var hoveredTile: GridPosition?
    /// Hazard tiles (and their damage) as they looked before the current
    /// resolve; kept tinted through the animation phases so expired pools only
    /// visually dissipate at the end of the turn.
    private var heldHazardTiles: [GridPosition: Int]?
    /// True while the resolve phase animates; input is ignored until planning resumes.
    private var isResolving = false

    /// Fraction of the smaller scene dimension the board occupies; the margin
    /// below the board leaves room for the GO button and HUD.
    private let boardScale: CGFloat = 0.8
    /// Max gap between R presses for a mid-run restart.
    private static let restartDoubleTapWindow: TimeInterval = 0.45
    private var lastRestartKeyTime: TimeInterval = 0
    /// Chaos toggle: the next restart replaces every wall with an explosive barrel.
    private var allBarrelsMode = false
    /// The level-up boon chooser; input is captive while it's up.
    private var buffChoiceOverlay: SKNode?
    /// Floating "E · pick up" prompt above the weapon the player is standing on.
    private var pickupHintLabel: SKLabelNode?
    /// Set when this resolve's kills finished charging the ultimate; announced
    /// once the animations wrap up.
    private var pendingUltimateReadyToast = false
    /// While false (early resolve phases), freshly painted pools stay hidden:
    /// the arrow that paints a trail must visibly cross the tiles first.
    private var revealLiveHazards = true
    /// Best score across runs, persisted in UserDefaults.
    private var highScore: Int {
        get { UserDefaults.standard.integer(forKey: "highScore") }
        set { UserDefaults.standard.set(newValue, forKey: "highScore") }
    }
    /// Elite trophies claimed across runs (by weapon name); once claimed they
    /// join every future run's weapon pool.
    private var claimedTrophyNames: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "claimedTrophies") ?? []) }
        set { UserDefaults.standard.set(Array(newValue).sorted(), forKey: "claimedTrophies") }
    }
    /// Milestone weapons earned across runs (by weapon name).
    private var unlockedWeaponNames: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "unlockedWeapons") ?? []) }
        set { UserDefaults.standard.set(Array(newValue).sorted(), forKey: "unlockedWeapons") }
    }
    /// Lifetime credited-kill tallies that gate the milestones.
    private var lifetimeTallies: [String: Int] {
        get { (UserDefaults.standard.dictionary(forKey: "lifetimeTallies") as? [String: Int]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "lifetimeTallies") }
    }
    /// Lifetime tallies as they stood when this run began; the run's own
    /// tallies are folded on top after every turn.
    private var tallyBaseline: [String: Int] = [:]
    /// The launch title screen; input is captive while it's up.
    private var titleOverlay: SKNode?
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
    /// Prophecies for the level's gatekeeper stomping in, same oracle.
    private static let eliteChatter = [
        "dark portents gather! something huge this way...| comes? cometh? it's coming.",
        "i foresaw this!| definitely | slay the big one and the road shall, |um, open. mystically.",
        "hark! the gate walks in flesh most foul!| yes, the massive one. kill that.",
    ]
    private static let weaponButtonSize = CGSize(width: 208, height: 56)

    // MARK: - Setup

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(white: 0.10, alpha: 1.0)
        state = makeRunState()
        setUpScene()
        showTitleScreen()

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
    }

    /// Builds every node from the current state; also used to restart after game over.
    private func setUpScene() {
        setUpBoard()
        setUpPlayer()
        setUpEnemies()
        setUpObstacles()
        setUpHUD()
        setUpGoButton()
        setUpControlsLegend()
        updateEnemyPlanArrows()
        updateSpawnMarkers()
        updateWeaponDropNodes()
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
        playerNode = SKShapeNode(circleOfRadius: tileSize * 0.32)
        playerNode.fillColor = playerColor
        playerNode.strokeColor = .white
        playerNode.lineWidth = 2
        playerNode.zPosition = 10
        playerNode.position = point(for: state.playerPosition)
        boardNode.addChild(playerNode)
    }

    private func setUpEnemies() {
        for enemy in state.enemies {
            addEnemyNode(for: enemy)
        }
    }

    @discardableResult
    private func addEnemyNode(for enemy: Enemy) -> SKShapeNode {
        // Placeholder art: archetypes differ by size and color until sprites exist.
        let side: CGFloat
        let fill: SKColor
        var stroke = SKColor.white
        var lineWidth: CGFloat = 1.5
        switch enemy.archetype {
        case .fighter:
            side = tileSize * 0.5
            fill = SKColor(red: 0.90, green: 0.30, blue: 0.25, alpha: 1.0)
        case .berserker:
            side = tileSize * 0.5
            fill = SKColor(red: 0.95, green: 0.45, blue: 0.05, alpha: 1.0)
        case .swift:
            side = tileSize * 0.45
            fill = SKColor(red: 0.35, green: 0.70, blue: 0.95, alpha: 1.0)
        case .bomber:
            side = tileSize * 0.45
            fill = SKColor(white: 0.15, alpha: 1.0)
            stroke = SKColor(red: 0.90, green: 0.55, blue: 0.15, alpha: 1.0)
        case .juggernaut:
            side = tileSize * 0.7
            fill = SKColor(red: 0.60, green: 0.25, blue: 0.75, alpha: 1.0)
        case .boss:
            side = tileSize * 0.85
            fill = SKColor(red: 0.45, green: 0.10, blue: 0.60, alpha: 1.0)
            lineWidth = 3
        }
        let node = SKShapeNode(rectOf: CGSize(width: side, height: side), cornerRadius: 2)
        node.zRotation = .pi / 4
        node.fillColor = fill
        node.strokeColor = stroke
        node.lineWidth = lineWidth
        node.zPosition = 10
        node.position = point(for: enemy.position)
        boardNode.addChild(node)
        enemyNodes[enemy.id] = node
        return node
    }

    /// Armed bombers pulse angrily so the lit fuse is unmistakable.
    private func updateBomberFuses() {
        for enemy in state.enemies where enemy.archetype == .bomber {
            guard let node = enemyNodes[enemy.id] else { continue }
            if enemy.fuse != nil, node.action(forKey: "armed") == nil {
                node.strokeColor = SKColor(red: 1.0, green: 0.30, blue: 0.20, alpha: 1.0)
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
                let bead = SKShapeNode(circleOfRadius: tileSize * 0.14)
                bead.fillColor = SKColor(red: 0.25, green: 0.25, blue: 0.28, alpha: 1.0)
                bead.strokeColor = .white
                bead.lineWidth = 1.5
                bead.position = point(for: shell.origin)
                bead.zPosition = 16
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
            let node: SKShapeNode
            if let existing = boltNodes[bolt.id] {
                node = existing
            } else {
                node = makeBoltSliver(direction: bolt.direction)
                boardNode.addChild(node)
                boltNodes[bolt.id] = node
            }
            node.position = point(for: bolt.position)
        }
    }

    private func makeBoltSliver(direction: Direction) -> SKShapeNode {
        let sliver = SKShapeNode(rectOf: CGSize(width: tileSize * 0.45, height: tileSize * 0.12), cornerRadius: 2)
        sliver.fillColor = SKColor(red: 0.75, green: 0.78, blue: 0.82, alpha: 1.0)
        sliver.strokeColor = SKColor(white: 0.3, alpha: 1.0)
        sliver.lineWidth = 1
        let step = direction.unitStep
        sliver.zRotation = atan2(CGFloat(step.y), CGFloat(step.x))
        sliver.zPosition = 16
        return sliver
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

            let letter = SKLabelNode(text: String(drop.weapon.name.prefix(1)))
            letter.fontName = "HelveticaNeue-Bold"
            letter.fontSize = 14
            letter.fontColor = tint
            letter.verticalAlignmentMode = .center
            ring.addChild(letter)

            boardNode.addChild(ring)
            weaponDropNodes.append(ring)
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

    @discardableResult
    private func addObstacleNode(for obstacle: Obstacle) -> SKNode {
        let node: SKNode
        switch obstacle.kind {
        case .wall:
            node = SKSpriteNode(
                color: SKColor(white: 0.45, alpha: 1.0),
                size: CGSize(width: tileSize - 2, height: tileSize - 2)
            )
        case .barrel:
            let barrel = SKShapeNode(circleOfRadius: tileSize * 0.30)
            barrel.fillColor = SKColor(red: 0.85, green: 0.50, blue: 0.15, alpha: 1.0)
            barrel.strokeColor = SKColor(red: 0.40, green: 0.22, blue: 0.05, alpha: 1.0)
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
        for (title, key) in [("BOARD", "board"), ("MILESTONES", "milestones"), ("HOME", "home")] {
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

        buffsLabel = SKLabelNode()
        buffsLabel.fontName = "HelveticaNeue"
        buffsLabel.fontSize = 12
        buffsLabel.fontColor = SKColor(red: 0.65, green: 0.85, blue: 0.65, alpha: 1.0)
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
            milestonesPageNode.addChild(label)
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
            milestonesPageNode.addChild(bar)
            y -= 20
        }

        let available = Set(currentWeaponPool().map(\.name))
        let lifetime = lifetimeTallies
        for weapon in Weapon.all {
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

        boardPageNode.addChild(button)
        weaponButton = button
    }

    private var legendNode: SKNode?
    private var expandedLegendSections: Set<LegendSection> = [.weapons, .enemies]

    /// The left margin, two columns: weapon/enemy reference dropdowns at the
    /// far edge, how-to-play primer and keybinds beside them. Rebuilt whenever
    /// a dropdown is toggled.
    private func setUpControlsLegend() {
        rebuildLegend()
    }

    private enum LegendSection {
        case weapons, enemies
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

        // Reference column at the far-left edge.
        let referenceX: CGFloat = 14
        let toggleColor = SKColor(red: 0.55, green: 0.75, blue: 0.95, alpha: 1.0)
        let entryColor = SKColor(white: 0.75, alpha: 1.0)
        let statColor = SKColor(white: 0.55, alpha: 1.0)

        let weaponsOpen = expandedLegendSections.contains(.weapons)
        addLine("\(weaponsOpen ? "▾" : "▸") WEAPONS", x: referenceX,
                font: "HelveticaNeue-Bold", size: 15, color: toggleColor,
                name: "legendToggle:weapons", drop: 26)
        if weaponsOpen {
            // Only the collected arsenal shows here; locked weapons and their
            // requirements live on the MILESTONES page.
            let available = Set(currentWeaponPool().map(\.name))
            for weapon in Weapon.all where available.contains(weapon.name) {
                let (name, stats) = weaponLegendEntry(weapon)
                addLine(name, x: referenceX, font: "HelveticaNeue-Bold", size: 13, color: entryColor, drop: 17)
                addLine(stats, x: referenceX + 10, size: 12, color: statColor, drop: 21)
            }
        }
        y -= 8
        let enemiesOpen = expandedLegendSections.contains(.enemies)
        addLine("\(enemiesOpen ? "▾" : "▸") ENEMIES", x: referenceX,
                font: "HelveticaNeue-Bold", size: 15, color: toggleColor,
                name: "legendToggle:enemies", drop: 26)
        if enemiesOpen {
            let entries = [
                "Fighter · any weapon, kites",
                "Berserker · melee, fearless",
                "Swift · +1 move",
                "Bomber · arms at range \(GameState.bomberArmDistance),",
                "   blast r\(GameState.bomberBlastRadius), on fuse or death",
                "Juggernaut · the gate,",
                "   summons waves",
                "Boss · the gate, drafts:",
                "   volley both weapons,",
                "   cannon nova r\(GameState.bossNovaRadius), or summon",
            ]
            for entry in entries {
                addLine(entry, x: referenceX, size: 12.5, color: statColor, drop: 18)
            }
        }

        // Instructions column beside the reference, with room to breathe.
        y = topEdge
        let instructionsX: CGFloat = 262
        let lines = [
            ("HOW TO PLAY", true),
            ("Draft a move, aim an attack,", false),
            ("then hit GO — enemies commit", false),
            ("to the arrows you can see.", false),
            ("", false),
            ("red tiles · incoming attack", false),
            ("! · arrival — hover to see what", false),
            ("gold ring · weapon on floor", false),
            ("purple ring · elite trophy", false),
            ("", false),
            ("Move 2+ tiles without acting", false),
            ("to dodge one hit. Armor regens", false),
            ("on calm turns; HP never does.", false),
            ("", false),
            ("Hit the score milestone and a", false),
            ("gatekeeper spawns — kill it to", false),
            ("level up and take its weapons.", false),
            ("", false),
            ("KEYS", true),
            ("click · draft move", false),
            ("right-click · aim attack", false),
            ("   (reloading ranged? 1 dmg jab)", false),
            ("E · pick up weapon underfoot", false),
            ("tab/Q · swap weapon", false),
            ("F · ultimate when charged", false),
            ("esc · cancel draft", false),
            ("space/return · GO", false),
            ("R×2 · restart · B · boom mode", false),
        ]
        for (text, isHeader) in lines {
            addLine(text, x: instructionsX, font: isHeader ? "HelveticaNeue-Bold" : "HelveticaNeue")
        }
        y -= 6
        addLine("▸ i'm too lazy to read", x: instructionsX, font: "HelveticaNeue-Bold", size: 14,
                color: SKColor(red: 0.55, green: 0.75, blue: 0.95, alpha: 1.0),
                name: "tutorialButton", drop: 20)
    }

    // MARK: - Tutorial

    /// The four-step live coach behind "i'm too lazy to read": each step
    /// advances off the real input it teaches. Everything past the basics is
    /// left to the reading.
    private enum TutorialStep: Int {
        case hover, move, attack, go, read

        var prompt: String {
            switch self {
            case .hover:
                return "TUTORIAL 1/4 · hover an enemy to inspect it — the red tiles are everything its attack will hit"
            case .move:
                return "TUTORIAL 2/4 · left-click a green tile to draft your move — nothing moves until you commit"
            case .attack:
                return "TUTORIAL 3/4 · right-click to aim — the orange tiles are your strike, from where you WILL be standing"
            case .go:
                return "TUTORIAL 4/4 · press SPACE (or click GO) — the whole turn resolves at once"
            case .read:
                return "TUTORIAL 5/4 · go read the rest, it's on the left — if you don't, good luck out there"
            }
        }
    }

    private var tutorialStep: TutorialStep?
    private var tutorialPrompt: SKNode?

    private func startTutorial() {
        tutorialStep = .hover
        showTutorialPrompt(TutorialStep.hover.prompt)
    }

    /// Each step lands as a framed banner dead-center on the board — hard to
    /// miss — then glides up out of the way while the player performs it.
    /// Auto-dismissing banners (the 5/4 coda) linger up top, then see
    /// themselves out.
    private func showTutorialPrompt(_ text: String, autoDismiss: Bool = false) {
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
                },
            ]
        }
        container.run(SKAction.sequence(sequence))
    }

    /// Steps forward when the taught input actually happened, in order.
    private func advanceTutorial(after completed: TutorialStep) {
        guard tutorialStep == completed else { return }
        guard let next = TutorialStep(rawValue: completed.rawValue + 1) else {
            tutorialStep = nil
            return
        }
        if next == .read {
            // The coda: nothing left to detect — it lingers, then sees
            // itself out.
            tutorialStep = nil
            showTutorialPrompt(next.prompt, autoDismiss: true)
        } else {
            tutorialStep = next
            showTutorialPrompt(next.prompt)
        }
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
        if weapon.cooldown > 0 {
            traits.append("cd\(weapon.cooldown)")
        }
        let name = weapon.name == Weapon.cannon.name ? "\(weapon.name) · boss drop" : weapon.name
        let tail = traits.isEmpty ? "" : " " + traits.joined(separator: " ")
        return (name, "\(weapon.damage)dmg \(weapon.moveRange)mv\(tail)")
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

        let ready = state.ultimateKillCharge >= GameState.ultimateChargeKills
        let fraction = min(1, CGFloat(state.ultimateKillCharge) / CGFloat(GameState.ultimateChargeKills))
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
        let hint = SKLabelNode(text: ready ? "F ✦       READY" : "\(state.ultimateKillCharge)/\(GameState.ultimateChargeKills)")
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
        drawPips(
            in: healthBarNode,
            filled: max(0, state.playerHealth),
            total: max(state.maxHealth, state.playerHealth),
            color: SKColor(red: 0.85, green: 0.25, blue: 0.30, alpha: 1.0)
        )
        drawPips(
            in: armorBarNode,
            filled: max(0, state.playerArmor),
            total: max(state.armorCap, state.playerArmor),
            color: armorFlashColor
        )
        updateUltimateBar()
        dodgeChipLabel.isHidden = !state.plannedDodgeReady
        let nextLevel = GameState.scoreThreshold(forLevel: state.level + 1)
        let streak = state.killStreak >= 2 ? " · STREAK ×\(state.killStreak)" : ""
        let progress = state.bossPhase ? "\(state.score) · SLAY THE GATEKEEPER" : "\(state.score)/\(nextLevel)"
        scoreLabel.text = "LVL \(state.level) · SCORE \(progress)\(streak) · TURN \(state.turnNumber) · BEST \(max(highScore, state.score))"

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
            buffTexts.append(text)
        }
        buffsLabel.text = buffTexts.joined(separator: " · ")
        let cooldown = state.attackCooldownRemaining(of: state.equippedWeapon)
        let readiness = cooldown > 0 ? " · ready in \(cooldown)" : ""
        weaponLabel.text = "\(state.equippedWeapon.name) · move \(state.moveRange) · dmg \(state.attackDamage)\(readiness)"
        weaponSubLabel.text = "swap ⇄ \(state.holsteredWeapon.name) · costs attack"

        if state.plannedBash {
            itemsLabel.text = "bash drafted — a 1 dmg jab while the \(state.equippedWeapon.name) reloads"
        } else if state.plannedUltimate {
            itemsLabel.text = "omen drafted — the sky falls on every enemy"
        } else if state.plannedSwap {
            itemsLabel.text = "swapping to \(state.holsteredWeapon.name) — no attack or dodge this turn"
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

        // Long loadouts ("Crossbow · move 1 · dmg 2 · ready in 2") shrink to fit
        // instead of spilling out of the button.
        fitLabel(weaponLabel, within: Self.weaponButtonSize.width - 16)
        fitLabel(weaponSubLabel, within: Self.weaponButtonSize.width - 16)
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
        let planning = !isResolving && !state.isGameOver
        let legalTargets = planning ? state.legalMoveTargets() : []
        var attackTiles = planning ? Set(state.plannedAttackTiles) : []
        if planning && state.plannedUltimate {
            attackTiles.formUnion(state.enemies.map(\.position))
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
                    threatTiles.formUnion(pattern.tiles(from: enemy.position, facing: .up).filter(state.contains))
                } else if let thrown = enemy.weapon.thrown {
                    threatTiles.formUnion(state.blastTiles(around: enemy.position, radius: thrown.blastRadius, includeCenter: true))
                }
            } else if let obstacle = state.obstacle(at: hovered), obstacle.kind == .barrel {
                threatTiles.formUnion(state.blastTiles(around: hovered, radius: GameState.barrelBlastRadius))
            }
        }

        for (position, tile) in tileNodes {
            tile.color = tileColor(
                for: position,
                isLegalTarget: legalTargets.contains(position),
                isPlannedAttack: attackTiles.contains(position),
                isEnemyThreat: threatTiles.contains(position),
                hazardDamage: hazardDamages[position],
                isThrowRange: throwRange.contains(position),
                isSpawnTelegraph: spawnTiles.contains(position)
            )
        }
    }

    private func tileColor(
        for position: GridPosition,
        isLegalTarget: Bool,
        isPlannedAttack: Bool,
        isEnemyThreat: Bool,
        hazardDamage: Int?,
        isThrowRange: Bool,
        isSpawnTelegraph: Bool
    ) -> SKColor {
        let isDarkTile = (position.x + position.y) % 2 == 0
        if isEnemyThreat {
            return SKColor(red: isDarkTile ? 0.52 : 0.58, green: 0.12, blue: 0.10, alpha: 1.0)
        }
        if position == state.plannedTarget {
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
        return SKColor(white: isDarkTile ? 0.16 : 0.20, alpha: 1.0)
    }

    /// Full mid-flight readout for a bolt: heading, damage, speed, and how much
    /// further it can travel measured from the inspected tile.
    private func boltHoverText(_ bolt: Bolt, at tile: GridPosition) -> String {
        let travelled = max(abs(tile.x - bolt.position.x), abs(tile.y - bolt.position.y))
        let remaining = bolt.remainingRange - travelled
        let range = remaining <= 0 ? "expires here" : "\(remaining) tiles past here"
        let blast = bolt.impactBlastRadius > 0 ? " · bursts r\(bolt.impactBlastRadius)" : ""
        return "bolt \(bolt.direction.arrow) · \(bolt.damage) dmg · \(bolt.speed) tiles/turn\(blast) · \(range)"
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
            } else if state.obstacle(at: hovered)?.kind == .barrel {
                addHoverLabel(
                    "barrel · \(GameState.barrelDamage) dmg · blast r\(GameState.barrelBlastRadius) · chains",
                    at: hovered,
                    color: SKColor(red: 0.90, green: 0.55, blue: 0.15, alpha: 1.0)
                )
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
            status = enemy.fuse.map { " · DETONATES in \($0)" } ?? " · unarmed"
        } else if enemy.weapon.cooldown > 0 {
            let waiting = enemy.weapon.isMelee ? "ready in" : "reloading"
            status = enemy.cooldownRemaining > 0 ? " · \(waiting) \(enemy.cooldownRemaining)" : " · ready"
        }
        // The boss telegraphs which of its three plays comes next resolve.
        if let intent = enemy.plannedIntent {
            switch intent {
            case .volley: status += " · NEXT: FULL VOLLEY"
            case .nova: status += " · NEXT: CANNON NOVA"
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
        guard let target = state.plannedTarget, target != state.playerPosition else { return }

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
    }

    // MARK: - Turn flow

    /// Stores the chosen tile and points an arrow at it; nothing moves until GO.
    private func planMove(to target: GridPosition) {
        guard !isResolving, state.planMove(to: target) else { return }
        advanceTutorial(after: .move)
        updatePlanArrow()
        refreshTileHighlights()
        updateHUD()
    }

    /// Toggles a drafted weapon swap: like a pickup it spends the turn's attack
    /// and dodge, but the drafted move still happens and the exchange lands on
    /// resolve.
    private func swapWeapons() {
        guard !isResolving, !state.isGameOver else { return }
        if state.plannedSwap {
            state.clearPlannedSwap()
        } else {
            state.planSwap()
        }
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
        let ultWasReady = state.ultimateKillCharge >= GameState.ultimateChargeKills
        let resolution = state.resolveTurn()
        pendingUltimateReadyToast = !ultWasReady
            && state.ultimateKillCharge >= GameState.ultimateChargeKills
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
            self?.playSpawns(resolution)
        }
    }

    /// Steps every enemy to its drafted tile, then hands off to the player's attack.
    private func animateEnemyMoves(_ resolution: TurnResolution) {
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

        run(SKAction.wait(forDuration: longestDuration)) { [weak self] in
            self?.playProjectileImpacts(resolution)
        }
    }

    /// Bolts glide along the stretch they flew and lob shells arc onward (or
    /// dive into their targets), then anything that landed or struck blows up —
    /// all before anyone attacks.
    private func playProjectileImpacts(_ resolution: TurnResolution) {
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
        for flight in resolution.boltFlights {
            let node: SKShapeNode
            if let existing = boltNodes[flight.boltID] {
                node = existing
            } else {
                // Fired this very turn: the sliver enters at the shooter's tile.
                node = makeBoltSliver(direction: flight.direction)
                node.position = point(for: flight.from)
                boardNode.addChild(node)
                boltNodes[flight.boltID] = node
            }

            let destination = point(for: flight.to)
            let distanceInTiles = hypot(destination.x - node.position.x,
                                        destination.y - node.position.y) / tileSize
            let duration = 0.06 * TimeInterval(distanceInTiles) + 0.08
            longestFlight = max(longestFlight, duration)
            let glide = SKAction.move(to: destination, duration: duration)
            glide.timingMode = .easeIn
            if state.bolts.contains(where: { $0.id == flight.boltID }) {
                node.run(glide)
            } else {
                // Struck something or expired: finish the flight and vanish.
                boltNodes[flight.boltID] = nil
                node.run(SKAction.sequence([
                    glide,
                    SKAction.fadeOut(withDuration: 0.08),
                    SKAction.removeFromParent(),
                ]))
            }
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
            if hit.died {
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
        if !resolution.ultimateTiles.isEmpty {
            playUltimate(resolution)
            return
        }
        // Bolt shots sweep no tiles, but a bomber dying to one still blasts:
        // its explosion (and the barrels it popped) must play regardless.
        guard !resolution.attackTiles.isEmpty
            || !resolution.playerExplosions.isEmpty || !resolution.enemyHits.isEmpty else {
            playEnemyAttacks(resolution)
            return
        }

        for tile in resolution.attackTiles {
            tileNodes[tile]?.color = SKColor(red: 0.85, green: 0.25, blue: 0.15, alpha: 1.0)
        }
        animateEnemyHits(resolution.enemyHits)
        animateExplosions(resolution.playerExplosions)

        run(SKAction.wait(forDuration: 0.3)) { [weak self] in
            guard let self else { return }
            self.refreshTileHighlights()
            self.playEnemyAttacks(resolution)
        }
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

        showTransmission(Self.ultimateChatter.randomElement()!)

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
                    self?.tileNodes[tile]?.color = .white
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
        let playerWasDamaged = resolution.healthLost > 0 || resolution.armorLost > 0
        // Bomber fuses can blow with no attack drafted anywhere: friendly-fire
        // hits and explosions alone still need this phase to play.
        guard !resolution.enemyAttacks.isEmpty || playerWasDamaged
            || !resolution.friendlyFireHits.isEmpty || !resolution.enemyExplosions.isEmpty else {
            playHazards(resolution)
            return
        }

        for attack in resolution.enemyAttacks {
            for tile in attack.tiles {
                tileNodes[tile]?.color = SKColor(red: 0.55, green: 0.12, blue: 0.10, alpha: 1.0)
            }
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
                self.playerNode.fillColor = flashColor
                self.updateHUD()
            },
            SKAction.wait(forDuration: 0.20),
            SKAction.run { [weak self] in
                guard let self else { return }
                self.playerNode.fillColor = self.playerColor
                self.playHazards(resolution)
            },
        ]))
    }

    /// Lingering effects burn whoever ended the turn in them; struck enemies
    /// flicker (and any bombers that died to the burn blow up) before the
    /// turn wraps up.
    private func playHazards(_ resolution: TurnResolution) {
        guard !resolution.hazardHits.isEmpty || !resolution.hazardExplosions.isEmpty else {
            finishResolvePhase(resolution)
            return
        }
        animateEnemyHits(resolution.hazardHits)
        animateExplosions(resolution.hazardExplosions)
        run(SKAction.wait(forDuration: 0.25)) { [weak self] in
            guard let self else { return }
            self.refreshTileHighlights()
            self.finishResolvePhase(resolution)
        }
    }

    /// Reinforcements and barrel deliveries pop in on their telegraphed tiles
    /// at the head of the turn — before anyone acts — so a pre-aimed attack
    /// can greet them; blocked spawns flash the tile instead.
    private func playSpawns(_ resolution: TurnResolution) {
        guard !resolution.spawns.isEmpty || !resolution.barrelSpawns.isEmpty else {
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
        for spawn in resolution.spawns {
            if let id = spawn.enemyID, let enemy = state.enemies.first(where: { $0.id == id }) {
                let node = addEnemyNode(for: enemy)
                node.setScale(0.1)
                node.alpha = 0
                node.run(SKAction.group([
                    SKAction.scale(to: 1.0, duration: 0.20),
                    SKAction.fadeIn(withDuration: 0.20),
                ]))
            } else {
                tileNodes[spawn.position]?.color = .white
            }
        }
        run(SKAction.wait(forDuration: 0.25)) { [weak self] in
            self?.animateEnemyMoves(resolution)
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
        setUpEnemies()
        setUpObstacles()
    }

    private func finishResolvePhase(_ resolution: TurnResolution) {
        // An elite stepping onto the field earns a transmission.
        let arrivedElite = resolution.spawns.contains { event in
            guard let id = event.enemyID, let enemy = state.enemies.first(where: { $0.id == id }) else { return false }
            return enemy.archetype == .juggernaut || enemy.archetype == .boss
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

        heldHazardTiles = nil
        revealLiveHazards = true
        isResolving = false
        goButton.alpha = 1.0
        updateHUD()
        updateEnemyPlanArrows()
        updateSpawnMarkers()
        updateWeaponDropNodes()
        updateProjectileNodes()
        updateBomberFuses()
        updatePickupHint()
        updateEnemyHoverInfo()
        refreshTileHighlights()
        if state.isGameOver {
            showDeathRecap()
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
        let wasBest = state.score > highScore
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
                font: "HelveticaNeue", size: 16, color: statColor, drop: 48)

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

    // MARK: - Level up

    /// Full-screen level-up moment, styled like the death banner: dimmed board,
    /// big title, and a choice of two boons that pauses play until picked.
    private func showBuffChoice(forLevel level: Int) {
        let overlay = SKNode()
        overlay.zPosition = 50

        let dim = SKSpriteNode(color: SKColor(white: 0, alpha: 0.75), size: size)
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
        overlay.addChild(subtitle)

        let choices = state.pendingBuffChoices
        for (index, buff) in choices.enumerated() {
            let offset: CGFloat = choices.count == 1 ? 0 : (index == 0 ? -160 : 160)
            let button = SKShapeNode(rectOf: CGSize(width: 280, height: 76), cornerRadius: 10)
            button.fillColor = SKColor(red: 0.20, green: 0.40, blue: 0.55, alpha: 1.0)
            button.strokeColor = .white
            button.lineWidth = 1.5
            button.name = "buffChoice:\(index)"
            button.position = CGPoint(x: size.width / 2 + offset, y: size.height / 2 - 20)
            overlay.addChild(button)

            let name = SKLabelNode(text: buff.name)
            name.fontName = "HelveticaNeue-Bold"
            name.fontSize = 18
            name.fontColor = .white
            name.verticalAlignmentMode = .center
            name.position = CGPoint(x: 0, y: 12)
            name.name = button.name
            button.addChild(name)

            let durationText: String
            if let levels = buff.levelDuration {
                durationText = levels == 1 ? "this level only" : "lasts \(levels) levels"
            } else {
                durationText = buff.isInstantOnly ? "right away" : "whole run"
            }
            let detail = SKLabelNode(text: "\(durationText) · press \(index + 1)")
            detail.fontName = "HelveticaNeue"
            detail.fontSize = 12
            detail.fontColor = SKColor(white: 0.8, alpha: 1.0)
            detail.verticalAlignmentMode = .center
            detail.position = CGPoint(x: 0, y: -14)
            detail.name = button.name
            button.addChild(detail)
        }

        addChild(overlay)
        buffChoiceOverlay = overlay
    }

    /// Applies the picked boon, tears down the overlay, and resumes play.
    private func chooseBuff(_ index: Int) {
        guard buffChoiceOverlay != nil, state.pendingBuffChoices.indices.contains(index) else { return }
        let name = state.pendingBuffChoices[index].name
        state.chooseBuff(at: index)
        buffChoiceOverlay?.removeFromParent()
        buffChoiceOverlay = nil
        showToast("gained \(name)", duration: 1.2)
        updateHUD()
        refreshTileHighlights()
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
        let label = SKLabelNode(text: "")
        label.verticalAlignmentMode = .center
        // Long pronouncements wrap instead of overhanging the board.
        label.numberOfLines = 0
        label.preferredMaxLayoutWidth = boardSide - 24
        label.position = CGPoint(x: size.width / 2, y: size.height / 2 + boardSide * 0.28)
        label.zPosition = 60
        addChild(label)

        // Every "|" toggles the voice: grand, deflated, grand again… so one
        // line can lose its nerve, rally, and lose it twice.
        let segments = text.split(separator: "|", omittingEmptySubsequences: false).map(String.init)

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

        let total = segments.reduce(0) { $0 + $1.count }
        var breakPoints: Set<Int> = []
        var cumulative = 0
        for segment in segments.dropLast() {
            cumulative += segment.count
            breakPoints.insert(cumulative)
        }

        var actions: [SKAction] = []
        for index in 1...max(1, total) {
            actions.append(SKAction.run { label.attributedText = rendered(upTo: index, cursor: true) })
            // The oracle falters at every break before soldiering on.
            actions.append(SKAction.wait(forDuration: breakPoints.contains(index) ? 0.45 : 0.018))
        }
        actions.append(SKAction.run { label.attributedText = rendered(upTo: total, cursor: false) })
        actions.append(SKAction.wait(forDuration: 1.8))
        actions.append(SKAction.fadeOut(withDuration: 0.5))
        actions.append(SKAction.removeFromParent())
        label.run(SKAction.sequence(actions))
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

    private func restartGame() {
        lastRestartKeyTime = 0
        revealLiveHazards = true
        tutorialStep = nil
        tutorialPrompt = nil
        devPanel = nil
        // Kill any in-flight resolve callbacks (they run on the scene itself and
        // would otherwise fire into the freshly rebuilt board).
        removeAllActions()
        removeAllChildren()
        boardNode.removeAllChildren()
        tileNodes.removeAll()
        enemyNodes.removeAll()
        obstacleNodes.removeAll()
        enemyPlanArrowNodes.removeAll()
        spawnMarkerNodes.removeAll()
        weaponDropNodes.removeAll()
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

    private func makeRunState() -> GameState {
        tallyBaseline = lifetimeTallies
        return GameState(
            weapon: devNextEquipped,
            holsteredWeapon: devNextHolstered,
            playerHealth: devNextMaxHealth,
            maxArmor: devNextMaxArmor,
            walls: allBarrelsMode ? 0 : 10,
            barrels: allBarrelsMode ? 14 : 4,
            weaponPool: currentWeaponPool()
        )
    }

    // MARK: - Dev panel

    /// God mode, behind the time-honored backtick. "Next" values apply on the
    /// next restart; the rest is immediate.
    private var devPanel: SKNode?
    private var devNextEquipped: Weapon?
    private var devNextHolstered: Weapon?
    private var devNextMaxHealth = 5
    private var devNextMaxArmor = 3

    private func toggleDevPanel() {
        if devPanel != nil {
            devPanel?.removeFromParent()
            devPanel = nil
            return
        }
        showToast("oh no! its the real god! quick! hide!", duration: 1.4)
        rebuildDevPanel()
    }

    private func rebuildDevPanel() {
        devPanel?.removeFromParent()
        let overlay = SKNode()
        overlay.zPosition = 85

        let rows: [(String, String)] = [
            ("DEV MODE — click a row · ` or esc closes", ""),
            ("next equipped: \(devNextEquipped?.name ?? "random") ▸", "dev:equipped"),
            ("next holstered: \(devNextHolstered?.name ?? "random") ▸", "dev:holstered"),
            ("next max HP: \(devNextMaxHealth) ▸", "dev:hp"),
            ("next armor cap: \(devNextMaxArmor) ▸", "dev:armor"),
            ("— the four above apply on R restart —", ""),
            ("fill ultimate", "dev:ultFill"),
            ("zero ultimate", "dev:ultZero"),
            ("heal fully", "dev:heal"),
            ("+100 score", "dev:score"),
            ("invincible: \(state.devInvincible ? "ON" : "off")", "dev:invincible"),
            ("unlock entire arsenal", "dev:unlockAll"),
            ("reset profile (unlocks, tallies, best)", "dev:resetProfile"),
        ]

        let rowHeight: CGFloat = 26
        let panelSize = CGSize(width: 430, height: CGFloat(rows.count) * rowHeight + 28)
        let plate = SKShapeNode(rectOf: panelSize, cornerRadius: 10)
        plate.fillColor = SKColor(white: 0.05, alpha: 0.95)
        plate.strokeColor = SKColor(red: 0.55, green: 0.75, blue: 0.95, alpha: 0.9)
        plate.lineWidth = 1.5
        plate.position = CGPoint(x: size.width / 2, y: size.height / 2)
        overlay.addChild(plate)

        var y = size.height / 2 + panelSize.height / 2 - 26
        for (text, action) in rows {
            let label = SKLabelNode(text: text)
            label.fontName = action.isEmpty ? "HelveticaNeue-Bold" : "HelveticaNeue"
            label.fontSize = 14
            label.fontColor = action.isEmpty
                ? SKColor(white: 0.55, alpha: 1.0)
                : SKColor(white: 0.85, alpha: 1.0)
            label.verticalAlignmentMode = .center
            label.position = CGPoint(x: size.width / 2, y: y)
            if !action.isEmpty {
                label.name = action
            }
            overlay.addChild(label)
            y -= rowHeight
        }

        addChild(overlay)
        devPanel = overlay
    }

    /// Cycles a next-run weapon slot through random and the whole arsenal.
    private func cycleDevWeapon(_ current: Weapon?) -> Weapon? {
        guard let current else { return Weapon.all.first }
        guard let index = Weapon.all.firstIndex(where: { $0.name == current.name }),
              index + 1 < Weapon.all.count else { return nil }
        return Weapon.all[index + 1]
    }

    private func handleDevAction(_ action: String) {
        switch action {
        case "dev:equipped": devNextEquipped = cycleDevWeapon(devNextEquipped)
        case "dev:holstered": devNextHolstered = cycleDevWeapon(devNextHolstered)
        case "dev:hp": devNextMaxHealth = devNextMaxHealth >= 20 ? 1 : devNextMaxHealth + 1
        case "dev:armor": devNextMaxArmor = devNextMaxArmor >= 8 ? 0 : devNextMaxArmor + 1
        case "dev:ultFill": state.devSetUltimateCharge(GameState.ultimateChargeKills)
        case "dev:ultZero": state.devSetUltimateCharge(0)
        case "dev:heal": state.devHealFully()
        case "dev:score": state.devAddScore(100)
        case "dev:invincible": state.devInvincible.toggle()
        case "dev:unlockAll":
            unlockedWeaponNames = Set(Weapon.milestones.map(\.weapon.name))
            claimedTrophyNames = Set(Weapon.eliteTrophies.map(\.name))
            rebuildLegend()
            rebuildMilestonesPage()
        case "dev:resetProfile":
            for key in ["claimedTrophies", "unlockedWeapons", "lifetimeTallies", "highScore"] {
                UserDefaults.standard.removeObject(forKey: key)
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
    }

    // MARK: - Input

    override func mouseMoved(with event: NSEvent) {
        let newHover = gridPosition(at: event.location(in: self))
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

    override func mouseDown(with event: NSEvent) {
        if titleOverlay != nil {
            dismissTitleScreen()
            return
        }
        let location = event.location(in: self)
        let clickedNames = nodes(at: location).compactMap(\.name)
        if devPanel != nil {
            // The dev panel is modal: rows act, anything else closes it.
            if let action = clickedNames.first(where: { $0.hasPrefix("dev:") }) {
                handleDevAction(action)
            } else {
                toggleDevPanel()
            }
            return
        }
        if buffChoiceOverlay != nil {
            // The boon chooser is modal: only its buttons respond.
            if let choice = clickedNames.first(where: { $0.hasPrefix("buffChoice:") }),
               let index = Int(choice.dropFirst("buffChoice:".count)) {
                chooseBuff(index)
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
        if let toggle = clickedNames.first(where: { $0.hasPrefix("legendToggle:") }) {
            let section: LegendSection = toggle.hasSuffix("weapons") ? .weapons : .enemies
            if expandedLegendSections.contains(section) {
                expandedLegendSections.remove(section)
            } else {
                expandedLegendSections.insert(section)
            }
            rebuildLegend()
            return
        }
        guard let target = gridPosition(at: location) else { return }
        planMove(to: target)
    }

    /// Right-click drafts the equipped weapon's attack: directional weapons face
    /// the clicked tile, thrown weapons land on it. Right-clicking the planned
    /// destination itself cancels the draft.
    override func rightMouseDown(with event: NSEvent) {
        guard titleOverlay == nil else { return }
        guard !isResolving, !state.isGameOver, buffChoiceOverlay == nil else { return }
        guard let tile = gridPosition(at: event.location(in: self)) else { return }
        if tile == state.attackOrigin && state.equippedWeapon.thrown == nil {
            state.clearPlannedAttack()
        } else {
            state.planAttack(toward: tile)
            if state.plannedAttackDirection != nil || state.plannedThrowTarget != nil {
                advanceTutorial(after: .attack)
            }
        }
        refreshTileHighlights()
        updateHUD()
    }

    override func keyDown(with event: NSEvent) {
        if titleOverlay != nil {
            dismissTitleScreen()
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
        if buffChoiceOverlay != nil {
            // The boon chooser is modal: 1/2 pick, everything else waits.
            switch event.keyCode {
            case 0x12: chooseBuff(0)
            case 0x13: chooseBuff(1)
            default: break
            }
            return
        }
        switch event.keyCode {
        case 0x31, 0x24: // Space or Return: resolve the planned turn.
            resolveTurn()
        case 0x30, 0x0C: // Tab or Q: swap to the holstered weapon.
            swapWeapons()
        case 0x0E: // E: toggle picking up the weapon underfoot (costs the attack).
            guard !isResolving, !state.isGameOver else { return }
            if state.plannedPickup {
                state.clearPlannedPickup()
            } else {
                state.planPickup()
            }
            updatePickupHint()
            refreshTileHighlights()
            updateHUD()
        case 0x03: // F: draft the ultimate — smites every enemy (long cooldown).
            guard !isResolving, !state.isGameOver else { return }
            if state.plannedUltimate {
                state.clearPlannedUltimate()
            } else if !state.planUltimate() {
                let needed = GameState.ultimateChargeKills - state.ultimateKillCharge
                showToast("the omen needs \(needed) more soul\(needed == 1 ? "" : "s")")
            }
            updatePickupHint()
            refreshTileHighlights()
            updateHUD()
        case 0x35: // Escape: cancel the drafted attack, throw, pickup, swap, or ultimate.
            guard !isResolving else { return }
            state.clearPlannedAttack()
            state.clearPlannedPickup()
            state.clearPlannedUltimate()
            state.clearPlannedSwap()
            updatePickupHint()
            refreshTileHighlights()
            updateHUD()
        case 0x0F: // R: restart — instant once the run is over, double-tap mid-run.
            if state.isGameOver
                || event.timestamp - lastRestartKeyTime < Self.restartDoubleTapWindow {
                restartGame()
            } else {
                lastRestartKeyTime = event.timestamp
                showToast("press R again to restart")
            }
        case 0x0B: // B: next restart swaps every wall for an explosive barrel.
            allBarrelsMode.toggle()
            showToast(allBarrelsMode ? "BOOM MODE — walls become barrels on restart" : "boom mode off", duration: 1.0)
        default:
            break
        }
    }
}
