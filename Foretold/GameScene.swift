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
    private var spawnMarkerNodes: [SKNode] = []
    private var weaponButton: SKShapeNode!
    private var weaponLabel: SKLabelNode!
    private var weaponSubLabel: SKLabelNode!
    private var tileSize: CGFloat = 0

    private var hoveredTile: GridPosition?
    /// Hazard tiles as they looked before the current resolve; kept tinted
    /// through the animation phases so expired pools only visually dissipate at
    /// the end of the turn.
    private var heldHazardTiles: Set<GridPosition>?
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
    private let playerColor = SKColor(red: 0.35, green: 0.85, blue: 0.95, alpha: 1.0)
    private let armorFlashColor = SKColor(red: 0.65, green: 0.75, blue: 0.95, alpha: 1.0)
    private static let goButtonName = "goButton"
    private static let weaponButtonName = "weaponButton"
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

    /// "!" markers on the tiles where next turn's reinforcements will appear.
    private func updateSpawnMarkers() {
        spawnMarkerNodes.forEach { $0.removeFromParent() }
        spawnMarkerNodes.removeAll()
        guard !state.isGameOver else { return }
        for tile in state.pendingSpawns {
            let marker = SKLabelNode(text: "!")
            marker.fontName = "HelveticaNeue-Bold"
            marker.fontSize = 20
            marker.fontColor = SKColor(red: 0.95, green: 0.45, blue: 0.85, alpha: 1.0)
            marker.verticalAlignmentMode = .center
            marker.position = point(for: tile)
            marker.zPosition = 12
            boardNode.addChild(marker)
            spawnMarkerNodes.append(marker)
        }
    }

    private func setUpObstacles() {
        for obstacle in state.obstacles {
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
        }
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

    /// Keybind reference stacked down the left margin beside the board.
    private func setUpControlsLegend() {
        let lines = [
            "KEYS",
            "click · move",
            "rclick · aim",
            "esc · cancel",
            "space · go",
            "tab · swap",
            "r×2 · restart",
            "b · boom mode",
        ]
        let boardSide = min(size.width, size.height) * boardScale
        let topEdge = (size.height + boardSide) / 2
        for (index, text) in lines.enumerated() {
            let label = SKLabelNode(text: text)
            label.fontName = index == 0 ? "HelveticaNeue-Bold" : "HelveticaNeue"
            label.fontSize = 10
            label.fontColor = SKColor(white: 0.65, alpha: 1.0)
            label.horizontalAlignmentMode = .left
            label.verticalAlignmentMode = .top
            label.position = CGPoint(x: 6, y: topEdge - CGFloat(index) * 16)
            label.zPosition = 20
            addChild(label)
        }
    }

    private func updateHUD() {
        let dodge = state.plannedDodgeReady ? "   DODGE ✓" : ""
        statsLabel.text = "HP \(state.playerHealth)   ARMOR \(state.playerArmor)/\(state.maxArmor)\(dodge)"
        scoreLabel.text = "SCORE \(state.score) · TURN \(state.turnNumber)"
        let cooldown = state.attackCooldownRemaining(of: state.equippedWeapon)
        let readiness = cooldown > 0 ? " · ready in \(cooldown)" : ""
        weaponLabel.text = "\(state.equippedWeapon.name) · move \(state.moveRange) · dmg \(state.equippedWeapon.damage)\(readiness)"
        weaponSubLabel.text = "swap ⇄ \(state.holsteredWeapon.name) · costs turn"

        if let thrown = state.equippedWeapon.thrown {
            itemsLabel.text = "thrown · rclick a tile in range (\(thrown.range))"
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
        let attackTiles = planning ? Set(state.plannedAttackTiles) : []
        // Thrown weapons show their landing range while planning so right-click
        // targeting is readable.
        let throwRange = planning ? state.throwTargets() : []
        let spawnTiles = planning ? Set(state.pendingSpawns) : []
        var hazardTiles = Set(state.lingeringEffects.map(\.position))
        if let held = heldHazardTiles {
            hazardTiles.formUnion(held)
        }

        var threatTiles: Set<GridPosition> = []
        if planning, let hovered = hoveredTile {
            if let enemy = state.enemy(at: hovered) {
                // Show the enemy's drafted attack; fall back to an indicative
                // shape (pattern facing up, or blast around a thrower) when it
                // isn't attacking this turn.
                let drafted = state.threatTiles(of: enemy)
                if !drafted.isEmpty {
                    threatTiles = Set(drafted)
                } else if let pattern = enemy.weapon.attackPattern {
                    threatTiles = Set(pattern.tiles(from: enemy.position, facing: .up).filter(state.contains))
                } else if let thrown = enemy.weapon.thrown {
                    threatTiles = Set(state.blastTiles(around: enemy.position, radius: thrown.blastRadius, includeCenter: true))
                }
            } else if let obstacle = state.obstacle(at: hovered), obstacle.kind == .barrel {
                threatTiles = Set(state.blastTiles(around: hovered, radius: GameState.barrelBlastRadius))
            }
        }

        for (position, tile) in tileNodes {
            tile.color = tileColor(
                for: position,
                isLegalTarget: legalTargets.contains(position),
                isPlannedAttack: attackTiles.contains(position),
                isEnemyThreat: threatTiles.contains(position),
                isHazard: hazardTiles.contains(position),
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
        isHazard: Bool,
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
        if isHazard {
            return SKColor(red: isDarkTile ? 0.55 : 0.60, green: 0.30, blue: 0.06, alpha: 1.0)
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

    /// Shows the hovered enemy's health above it; the red threat tiles are
    /// handled by refreshTileHighlights.
    private func updateEnemyHoverInfo() {
        enemyInfoLabel?.removeFromParent()
        enemyInfoLabel = nil
        guard !isResolving, let hovered = hoveredTile, let enemy = state.enemy(at: hovered) else { return }

        // Cooldown weapons always show their status so reload windows are readable.
        var status = ""
        if enemy.weapon.cooldown > 0 {
            status = enemy.cooldownRemaining > 0 ? " · reloading \(enemy.cooldownRemaining)" : " · ready"
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
        heldHazardTiles = Set(state.lingeringEffects.map(\.position))
        let resolution = state.resolveTurn()
        isResolving = true
        planArrowNode?.removeFromParent()
        planArrowNode = nil
        enemyPlanArrowNodes.forEach { $0.removeFromParent() }
        enemyPlanArrowNodes.removeAll()
        enemyInfoLabel?.removeFromParent()
        enemyInfoLabel = nil
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
            self?.playPlayerAttack(resolution)
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

    /// Reinforcements pop in on their telegraphed tiles; blocked spawns flash
    /// the tile instead.
    private func playSpawns(_ resolution: TurnResolution) {
        guard !resolution.spawns.isEmpty else {
            finishResolvePhase()
            return
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
            self?.finishResolvePhase()
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

    private func finishResolvePhase() {
        heldHazardTiles = nil
        isResolving = false
        goButton.alpha = 1.0
        updateHUD()
        updateEnemyPlanArrows()
        updateSpawnMarkers()
        updateEnemyHoverInfo()
        refreshTileHighlights()
        if state.isGameOver {
            showBanner("DEFEATED — score \(state.score) — press R to restart")
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

    /// Transient status message just below the board (restart confirmation,
    /// mode toggles, and the like).
    private func showToast(_ text: String, duration: TimeInterval = 0.6) {
        let toast = SKLabelNode(text: text)
        toast.fontName = "HelveticaNeue"
        toast.fontSize = 13
        toast.fontColor = SKColor(white: 0.85, alpha: 1.0)
        toast.verticalAlignmentMode = .center
        let boardSide = min(size.width, size.height) * boardScale
        toast.position = CGPoint(x: size.width / 2, y: (size.height - boardSide) / 2 - 14)
        toast.zPosition = 30
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
        planArrowNode = nil
        enemyInfoLabel = nil
        hoveredTile = nil
        heldHazardTiles = nil
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
        guard !isResolving, !state.isGameOver else { return }
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
        switch event.keyCode {
        case 0x31, 0x24: // Space or Return: resolve the planned turn.
            resolveTurn()
        case 0x30, 0x0C: // Tab or Q: swap to the holstered weapon.
            swapWeapons()
        case 0x35: // Escape: cancel the drafted attack or throw.
            guard !isResolving else { return }
            state.clearPlannedAttack()
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
