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
    private var statsLabel: SKLabelNode!
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
    /// Best score across runs, persisted in UserDefaults.
    private var highScore: Int {
        get { UserDefaults.standard.integer(forKey: "highScore") }
        set { UserDefaults.standard.set(newValue, forKey: "highScore") }
    }
    private let playerColor = SKColor(red: 0.35, green: 0.85, blue: 0.95, alpha: 1.0)
    private let armorFlashColor = SKColor(red: 0.65, green: 0.75, blue: 0.95, alpha: 1.0)
    private static let goButtonName = "goButton"
    private static let weaponButtonName = "weaponButton"
    /// Radio traffic that "explains" the ultimate. A fox 4 is not a real
    /// designation, which is exactly why it can be a massive nuke.
    private static let ultimateChatter = [
        "alpha charlie 3, we have a rogue fox 4 headed your direction, over",
        "fire mission approved — danger close, get small, out",
        "bird away. i say again, bird away.",
        "command copies. forecast: sunshine, brief and total, over",
        "Incoming payload detected: High Command reminds you that looking directly at the blast violates your non-disclosure agreement.",
        "negative on abort. fox 4 does not abort.. out.",
        "requesting fox 4... approved?? who approved that. all stations get down.",
        "this is fox actual. delivery inbound. signature not required. out.",
        "danger close waiver granted. by whom? unclear. splash imminent. out.",
    ]
    private static let weaponButtonSize = CGSize(width: 200, height: 44)

    // MARK: - Setup

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(white: 0.10, alpha: 1.0)
        setUpScene()

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
        setUpGoButton()
        setUpHUD()
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
        let side = tileSize * 0.5
        let node = SKShapeNode(rectOf: CGSize(width: side, height: side), cornerRadius: 2)
        node.zRotation = .pi / 4
        node.fillColor = SKColor(red: 0.90, green: 0.30, blue: 0.25, alpha: 1.0)
        node.strokeColor = .white
        node.lineWidth = 1.5
        node.zPosition = 10
        node.position = point(for: enemy.position)
        boardNode.addChild(node)
        enemyNodes[enemy.id] = node
        return node
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
        for drop in state.weaponDrops {
            let ring = SKShapeNode(circleOfRadius: tileSize * 0.30)
            ring.strokeColor = gold
            ring.lineWidth = 2
            ring.fillColor = gold.withAlphaComponent(0.12)
            ring.position = point(for: drop.position)
            ring.zPosition = 7

            let letter = SKLabelNode(text: String(drop.weapon.name.prefix(1)))
            letter.fontName = "HelveticaNeue-Bold"
            letter.fontSize = 14
            letter.fontColor = gold
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
        let button = SKShapeNode(rectOf: CGSize(width: 110, height: 40), cornerRadius: 8)
        button.fillColor = SKColor(red: 0.20, green: 0.55, blue: 0.35, alpha: 1.0)
        button.strokeColor = .white
        button.lineWidth = 1.5
        button.zPosition = 20
        button.name = Self.goButtonName

        // Centered in the margin between the board's bottom edge and the screen.
        let boardSide = min(size.width, size.height) * boardScale
        button.position = CGPoint(x: size.width / 2, y: (size.height - boardSide) / 4)

        let label = SKLabelNode(text: "GO")
        label.fontName = "HelveticaNeue-Bold"
        label.fontSize = 18
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.name = Self.goButtonName
        button.addChild(label)

        addChild(button)
        goButton = button
    }

    private func setUpHUD() {
        let boardSide = min(size.width, size.height) * boardScale
        let hudY = (size.height - boardSide) / 4

        statsLabel = SKLabelNode()
        statsLabel.fontName = "HelveticaNeue-Bold"
        statsLabel.fontSize = 16
        statsLabel.fontColor = .white
        statsLabel.horizontalAlignmentMode = .left
        statsLabel.verticalAlignmentMode = .center
        statsLabel.position = CGPoint(x: (size.width - boardSide) / 2, y: hudY + 12)
        statsLabel.zPosition = 20
        addChild(statsLabel)

        itemsLabel = SKLabelNode()
        itemsLabel.fontName = "HelveticaNeue"
        itemsLabel.fontSize = 12
        itemsLabel.fontColor = SKColor(white: 0.8, alpha: 1.0)
        itemsLabel.horizontalAlignmentMode = .left
        itemsLabel.verticalAlignmentMode = .center
        itemsLabel.position = CGPoint(x: (size.width - boardSide) / 2, y: hudY - 10)
        itemsLabel.zPosition = 20
        addChild(itemsLabel)

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

        setUpWeaponButton(rightEdge: (size.width + boardSide) / 2, y: hudY)
        updateHUD()
    }

    /// A single button showing the equipped weapon; clicking it (or pressing
    /// Tab/Q) swaps to the holstered weapon.
    private func setUpWeaponButton(rightEdge: CGFloat, y: CGFloat) {
        let buttonSize = Self.weaponButtonSize
        let button = SKShapeNode(rectOf: buttonSize, cornerRadius: 6)
        button.fillColor = SKColor(red: 0.25, green: 0.45, blue: 0.60, alpha: 1.0)
        button.strokeColor = .white
        button.lineWidth = 1.5
        button.zPosition = 20
        button.name = Self.weaponButtonName
        button.position = CGPoint(x: rightEdge - buttonSize.width / 2, y: y)

        weaponLabel = SKLabelNode()
        weaponLabel.fontName = "HelveticaNeue-Bold"
        weaponLabel.fontSize = 14
        weaponLabel.fontColor = .white
        weaponLabel.verticalAlignmentMode = .center
        weaponLabel.position = CGPoint(x: 0, y: 9)
        weaponLabel.name = Self.weaponButtonName
        button.addChild(weaponLabel)

        weaponSubLabel = SKLabelNode()
        weaponSubLabel.fontName = "HelveticaNeue"
        weaponSubLabel.fontSize = 11
        weaponSubLabel.fontColor = SKColor(white: 0.85, alpha: 1.0)
        weaponSubLabel.verticalAlignmentMode = .center
        weaponSubLabel.position = CGPoint(x: 0, y: -11)
        weaponSubLabel.name = Self.weaponButtonName
        button.addChild(weaponSubLabel)

        addChild(button)
        weaponButton = button
    }

    /// How-to-play primer and keybind reference filling the left column.
    private func setUpControlsLegend() {
        let lines = [
            "HOW TO PLAY",
            "Draft a move, aim an attack,",
            "then hit GO — enemies commit",
            "to the arrows you can see.",
            "",
            "red tiles · incoming attack",
            "! · spawn arriving next turn",
            "gold ring · weapon on floor",
            "stand on it + E to swap",
            "(spends your attack)",
            "",
            "Move 2+ tiles without",
            "attacking to dodge one hit.",
            "Armor regens on calm turns;",
            "HP never does.",
            "",
            "KEYS",
            "click · draft move",
            "right-click · aim attack",
            "E · pick up weapon",
            "F · ultimate",
            "esc · cancel draft",
            "space/return · GO",
            "tab/Q · swap weapon (turn)",
            "R×2 · restart",
            "B · boom mode",
        ]
        let boardSide = min(size.width, size.height) * boardScale
        let topEdge = (size.height + boardSide) / 2
        for (index, text) in lines.enumerated() {
            let label = SKLabelNode(text: text)
            let isHeader = text == "HOW TO PLAY" || text == "KEYS"
            label.fontName = isHeader ? "HelveticaNeue-Bold" : "HelveticaNeue"
            label.fontSize = 13
            label.fontColor = SKColor(white: 0.7, alpha: 1.0)
            label.horizontalAlignmentMode = .left
            label.verticalAlignmentMode = .top
            label.position = CGPoint(x: 16, y: topEdge - CGFloat(index) * 21)
            label.zPosition = 20
            addChild(label)
        }
    }

    private func updateHUD() {
        let dodge = state.plannedDodgeReady ? "   DODGE ✓" : ""
        let ult = state.ultimateKillCharge >= GameState.ultimateChargeKills
            ? "   ULT ✦"
            : "   ULT \(state.ultimateKillCharge)/\(GameState.ultimateChargeKills)"
        statsLabel.text = "HP \(state.playerHealth)   ARMOR \(state.playerArmor)/\(state.armorCap)\(dodge)\(ult)"
        let nextLevel = GameState.scoreThreshold(forLevel: state.level + 1)
        let streak = state.killStreak >= 2 ? " · STREAK ×\(state.killStreak)" : ""
        scoreLabel.text = "LVL \(state.level) · SCORE \(state.score)/\(nextLevel)\(streak) · TURN \(state.turnNumber) · BEST \(max(highScore, state.score))"

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
        weaponSubLabel.text = "swap ⇄ \(state.holsteredWeapon.name) · costs turn"

        if state.plannedUltimate {
            itemsLabel.text = "ULTIMATE drafted — smites every enemy on the board"
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
        for effect in state.lingeringEffects {
            hazardDamages[effect.position] = effect.damagePerTurn
        }

        // Incoming shells always telegraph their impact zones; while aiming a
        // bolt weapon, the trajectory beyond the first window reads as red too.
        var threatTiles: Set<GridPosition> = planning ? Set(state.projectileThreatTiles) : []
        if planning {
            threatTiles.formUnion(state.plannedAttackLaterTiles)
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
            } else if state.pendingSpawns.contains(hovered) {
                addHoverLabel(
                    "enemy spawns here next turn · stand here to block (1 dmg)",
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
        var status = ""
        if enemy.weapon.cooldown > 0 {
            let waiting = enemy.weapon.isMelee ? "ready in" : "reloading"
            status = enemy.cooldownRemaining > 0 ? " · \(waiting) \(enemy.cooldownRemaining)" : " · ready"
        }
        let label = SKLabelNode(text: "\(enemy.weapon.name) · HP \(enemy.health)\(status)")
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
        updatePlanArrow()
        refreshTileHighlights()
        updateHUD()
    }

    /// Swapping weapons costs the whole turn: the swap commits, any drafted move
    /// and attack are discarded, and the turn resolves immediately.
    private func swapWeapons() {
        guard !isResolving, !state.isGameOver else { return }
        state.swapWeapons()
        updateHUD()
        resolveTurn()
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
        let resolution = state.resolveTurn()
        if let picked = resolution.pickedUpWeapon {
            showToast("picked up \(picked.name)", duration: 1.0)
        }
        isResolving = true
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
            self?.animateEnemyMoves(resolution)
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
            for tile in explosion.tiles {
                tileNodes[tile]?.color = SKColor(red: 0.95, green: 0.55, blue: 0.10, alpha: 1.0)
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
        if !resolution.ultimateTiles.isEmpty {
            playUltimate(resolution)
            return
        }
        guard !resolution.attackTiles.isEmpty else {
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

        run(SKAction.wait(forDuration: longestDelay + 0.4)) { [weak self] in
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
        guard !resolution.enemyAttacks.isEmpty || playerWasDamaged else {
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
    /// flicker before the reinforcements arrive.
    private func playHazards(_ resolution: TurnResolution) {
        guard !resolution.hazardHits.isEmpty else {
            playSpawns(resolution)
            return
        }
        animateEnemyHits(resolution.hazardHits)
        run(SKAction.wait(forDuration: 0.25)) { [weak self] in
            self?.playSpawns(resolution)
        }
    }

    /// Reinforcements and barrel deliveries pop in on their telegraphed tiles;
    /// blocked spawns flash the tile instead.
    private func playSpawns(_ resolution: TurnResolution) {
        guard !resolution.spawns.isEmpty || !resolution.barrelSpawns.isEmpty else {
            finishResolvePhase(resolution)
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
        setUpEnemies()
        setUpObstacles()
    }

    private func finishResolvePhase(_ resolution: TurnResolution) {
        // The combo callout waits until the kills have visibly happened.
        if resolution.killsThisTurn >= 2 {
            let callout: String
            switch resolution.killsThisTurn {
            case 2: callout = "DOUBLE KILL"
            case 3: callout = "TRIPLE KILL"
            default: callout = "RAMPAGE ×\(resolution.killsThisTurn)"
            }
            showToast(callout, duration: 1.4)
        }
        if let newLevel = resolution.leveledUpTo {
            rebuildBoardEntities()
            showBuffChoice(forLevel: newLevel)
        }
        heldHazardTiles = nil
        isResolving = false
        goButton.alpha = 1.0
        updateHUD()
        updateEnemyPlanArrows()
        updateSpawnMarkers()
        updateWeaponDropNodes()
        updateProjectileNodes()
        updatePickupHint()
        updateEnemyHoverInfo()
        refreshTileHighlights()
        if state.isGameOver {
            if state.score > highScore {
                highScore = state.score
                showBanner("DEFEATED — NEW BEST \(state.score)! — press R to restart")
            } else {
                showBanner("DEFEATED — score \(state.score) · best \(highScore) — press R to restart")
            }
        }
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

    /// Incoming radio traffic: monospaced comms-green text over the board,
    /// revealed character by character like a teletype, then held and faded.
    private func showTransmission(_ text: String) {
        let boardSide = min(size.width, size.height) * boardScale
        let label = SKLabelNode(text: "")
        label.fontName = "Menlo-Bold"
        label.fontSize = 15
        label.fontColor = SKColor(red: 0.55, green: 0.95, blue: 0.55, alpha: 1.0)
        label.verticalAlignmentMode = .center
        // Long transmissions wrap instead of overhanging the board.
        label.numberOfLines = 0
        label.preferredMaxLayoutWidth = boardSide - 24
        label.position = CGPoint(x: size.width / 2, y: size.height / 2 + boardSide * 0.28)
        label.zPosition = 60
        addChild(label)

        let characters = Array(text.uppercased())
        var actions: [SKAction] = []
        for index in characters.indices {
            actions.append(SKAction.run { label.text = String(characters[0...index]) + "_" })
            actions.append(SKAction.wait(forDuration: 0.016))
        }
        actions.append(SKAction.run { label.text = String(characters) })
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
        state = allBarrelsMode ? GameState(walls: 0, barrels: 14) : GameState()
        setUpScene()
    }

    // MARK: - Input

    override func mouseMoved(with event: NSEvent) {
        let newHover = gridPosition(at: event.location(in: self))
        guard newHover != hoveredTile else { return }
        hoveredTile = newHover
        updateEnemyHoverInfo()
        refreshTileHighlights()
    }

    override func mouseDown(with event: NSEvent) {
        let location = event.location(in: self)
        let clickedNames = nodes(at: location).compactMap(\.name)
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
        guard let target = gridPosition(at: location) else { return }
        planMove(to: target)
    }

    /// Right-click drafts the equipped weapon's attack: directional weapons face
    /// the clicked tile, thrown weapons land on it. Right-clicking the planned
    /// destination itself cancels the draft.
    override func rightMouseDown(with event: NSEvent) {
        guard !isResolving, !state.isGameOver, buffChoiceOverlay == nil else { return }
        guard let tile = gridPosition(at: event.location(in: self)) else { return }
        if tile == state.attackOrigin && state.equippedWeapon.thrown == nil {
            state.clearPlannedAttack()
        } else {
            state.planAttack(toward: tile)
        }
        refreshTileHighlights()
        updateHUD()
    }

    override func keyDown(with event: NSEvent) {
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
                showToast("ultimate needs \(needed) more kill\(needed == 1 ? "" : "s")")
            }
            updatePickupHint()
            refreshTileHighlights()
            updateHUD()
        case 0x35: // Escape: cancel the drafted attack, throw, pickup, or ultimate.
            guard !isResolving else { return }
            state.clearPlannedAttack()
            state.clearPlannedPickup()
            state.clearPlannedUltimate()
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
