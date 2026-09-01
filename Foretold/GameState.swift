//
//  GameState.swift
//  Foretold
//

import Foundation

/// A tile coordinate on the board. Origin (0, 0) is the bottom-left tile.
struct GridPosition: Hashable {
    var x: Int
    var y: Int
}

extension GridPosition {
    /// Manhattan distance: tiles apart moving only orthogonally.
    func distance(to other: GridPosition) -> Int {
        abs(x - other.x) + abs(y - other.y)
    }
}

/// The eight directions an attack can face. Orthogonal patterns are authored
/// facing right (+x); diagonal patterns are authored facing up-right (+x, +y).
/// Both are rotated in quarter turns to the other three facings of their kind.
enum Direction: CaseIterable {
    case right, up, left, down
    case upRight, upLeft, downLeft, downRight

    var isDiagonal: Bool {
        switch self {
        case .right, .up, .left, .down: return false
        case .upRight, .upLeft, .downLeft, .downRight: return true
        }
    }

    /// Quarter turns from this direction's canonical facing (right for
    /// orthogonal, up-right for diagonal).
    private var quarterTurns: Int {
        switch self {
        case .right, .upRight: return 0
        case .up, .upLeft: return 1
        case .left, .downLeft: return 2
        case .down, .downRight: return 3
        }
    }

    /// Rotates a canonically-authored offset into this direction.
    func rotated(_ offset: GridPosition) -> GridPosition {
        var result = offset
        for _ in 0..<quarterTurns {
            result = GridPosition(x: -result.y, y: result.x)
        }
        return result
    }

    /// The direction that best matches aiming from origin toward tile; diagonal
    /// facings are only chosen when allowed and the aim is closer to 45° than to
    /// an axis. Nil when origin and tile coincide.
    static func aiming(from origin: GridPosition, toward tile: GridPosition, allowDiagonals: Bool) -> Direction? {
        let dx = tile.x - origin.x
        let dy = tile.y - origin.y
        guard dx != 0 || dy != 0 else { return nil }
        if allowDiagonals && min(abs(dx), abs(dy)) * 2 > max(abs(dx), abs(dy)) {
            switch (dx > 0, dy > 0) {
            case (true, true): return .upRight
            case (false, true): return .upLeft
            case (false, false): return .downLeft
            case (true, false): return .downRight
            }
        }
        if abs(dx) >= abs(dy) {
            return dx > 0 ? .right : .left
        }
        return dy > 0 ? .up : .down
    }
}

/// The tiles an attack covers. `offsets` is authored relative to an attacker
/// facing right (+x): (x: 1, y: 0) is the tile directly ahead, (x: 1, y: 1)
/// ahead and to the left, (x: 2, y: 0) two tiles ahead. `diagonalOffsets`, when
/// provided, is the shape used for diagonal aims, authored facing up-right;
/// weapons without it can only aim orthogonally. Offsets should be listed
/// nearest-first so non-piercing attacks stop at the right target.
struct AttackPattern: Equatable {
    let offsets: [GridPosition]
    let diagonalOffsets: [GridPosition]?

    init(offsets: [GridPosition], diagonalOffsets: [GridPosition]? = nil) {
        self.offsets = offsets
        self.diagonalOffsets = diagonalOffsets
    }

    var supportsDiagonals: Bool { diagonalOffsets != nil }

    /// Absolute board tiles covered when attacking from origin facing direction
    /// (not yet clipped to the board), in authored order. Empty for a diagonal
    /// facing when the pattern has no diagonal shape.
    func tiles(from origin: GridPosition, facing direction: Direction) -> [GridPosition] {
        let base = direction.isDiagonal ? (diagonalOffsets ?? []) : offsets
        return base.map { offset in
            let rotated = direction.rotated(offset)
            return GridPosition(x: origin.x + rotated.x, y: origin.y + rotated.y)
        }
    }
}

// MARK: - Attack patterns
// Author each weapon's shape here, facing right (and up-right for the optional
// diagonal shape).
extension AttackPattern {
    /// A straight thrust of `length` tiles directly ahead, with the matching
    /// diagonal thrust built in. Off-board tiles are clipped at attack time, so
    /// pass the board's span (columns - 1) to reach the far edge from anywhere.
    static func line(length: Int) -> AttackPattern {
        AttackPattern(
            offsets: (1...length).map { GridPosition(x: $0, y: 0) },
            diagonalOffsets: (1...length).map { GridPosition(x: $0, y: $0) }
        )
    }

    static let dagger = AttackPattern.line(length: 1)
    static let sword = AttackPattern(offsets: [
        GridPosition(x: 2, y: -1),
        GridPosition(x: 2, y: 0),
        GridPosition(x: 1, y: 0),
        GridPosition(x: 2, y: 1),
    ],
    diagonalOffsets: [
        GridPosition(x: 1, y: 1),
        GridPosition(x: 2, y: 2),
        GridPosition(x: 2, y: 1),
        GridPosition(x: 1, y: 2)
    ])
    static let hammer = AttackPattern(offsets: [
        GridPosition(x: -1, y: -1), GridPosition(x: 0, y: -1), GridPosition(x: 1, y: -1),
        GridPosition(x: -1, y: 0), GridPosition(x: 1, y: 0),
        GridPosition(x: -1, y: 1), GridPosition(x: 0, y: 1), GridPosition(x: 1, y: 1),
    ])
    static let pike = AttackPattern.line(length: 3)
    static let bow = AttackPattern.line(length: 10)
    static let crossbow = AttackPattern.line(length: 14)
}

/// Gear anyone can carry. A weapon attacks either directionally (via
/// `attackPattern`) or by being lobbed at a tile (via `thrown`) — exactly one of
/// the two. Heavier weapons restrict how far the wielder can move but hit
/// harder, so weapon choice is a mobility/damage trade-off.
struct Weapon: Equatable {
    /// A lobbed attack: pick any tile within `range`, and the blast covers a
    /// diamond of `blastRadius` around it. Throws arc over walls and bodies, and
    /// the blast hits everyone caught in it — the thrower included.
    struct Thrown: Equatable {
        /// Max Manhattan distance the weapon can be thrown.
        let range: Int
        /// Manhattan radius of the blast diamond around the impact tile.
        let blastRadius: Int
    }

    /// A hazard the attack leaves burning on every tile it swept — the tiles
    /// highlighted while aiming. Anything ending a turn on one takes damage.
    struct Lingering: Equatable {
        let damagePerTurn: Int
        let duration: Int
    }

    let name: String
    /// Tiles of orthogonal movement this weapon allows per turn.
    let moveRange: Int
    let damage: Int
    /// Whether the attack sweeps past the first enemy it hits (matters for
    /// ordered patterns like lines).
    let pierces: Bool
    /// Turns the wielder must wait after attacking before attacking again;
    /// 0 attacks every turn, 1 every other turn.
    let cooldown: Int
    /// Health an enemy carrying this weapon spawns with — melee bruisers take
    /// more hits than ranged skirmishers.
    let enemyHealth: Int
    /// Directional swing shape; nil for thrown weapons.
    let attackPattern: AttackPattern?
    /// Set for lobbed weapons (grenades, potions); nil for directional ones.
    let thrown: Thrown?
    let lingering: Lingering?

    init(
        name: String,
        moveRange: Int,
        damage: Int,
        pierces: Bool = true,
        cooldown: Int = 0,
        enemyHealth: Int = 3,
        attackPattern: AttackPattern? = nil,
        thrown: Thrown? = nil,
        lingering: Lingering? = nil
    ) {
        precondition((attackPattern != nil) != (thrown != nil), "A weapon attacks with either a pattern or a throw, not both")
        self.name = name
        self.moveRange = moveRange
        self.damage = damage
        self.pierces = pierces
        self.cooldown = cooldown
        self.enemyHealth = enemyHealth
        self.attackPattern = attackPattern
        self.thrown = thrown
        self.lingering = lingering
    }
}

extension Weapon {
    static let dagger = Weapon(name: "Dagger", moveRange: 3, damage: 1, enemyHealth: 4, attackPattern: .dagger)
    static let sword = Weapon(name: "Sword", moveRange: 2, damage: 2, enemyHealth: 4, attackPattern: .sword)
    static let hammer = Weapon(name: "Hammer", moveRange: 1, damage: 4, cooldown: 1, enemyHealth: 5, attackPattern: .hammer)
    static let pike = Weapon(name: "Pike", moveRange: 2, damage: 2, enemyHealth: 3, attackPattern: .pike)
    static let bow = Weapon(name: "Bow", moveRange: 2, damage: 2, pierces: false, cooldown: 1, enemyHealth: 2, attackPattern: .bow)
    static let tippedBow = Weapon(name: "Tipped Bow", moveRange: 2, damage: 1, pierces: false, cooldown: 2, enemyHealth: 2, attackPattern: .bow, lingering: Lingering(damagePerTurn: 1, duration: 2))
    static let crossbow = Weapon(name: "Crossbow", moveRange: 1, damage: 3, pierces: true , cooldown: 2, enemyHealth: 2, attackPattern: .crossbow)
    static let grenade = Weapon(
        name: "Grenade",
        moveRange: 2,
        damage: 3,
        cooldown: 1,
        enemyHealth: 2,
        thrown: Thrown(range: 8, blastRadius: 1),
        lingering: Lingering(damagePerTurn: 1, duration: 1),
    )
    static let poisonPotion = Weapon(
        name: "Poison Potion",
        moveRange: 2,
        damage: 1,
        cooldown: 1,
        enemyHealth: 2,
        thrown: Thrown(range: 4, blastRadius: 2),
        lingering: Lingering(damagePerTurn: 3, duration: 3)
    )
    /// The pool random loadouts and enemy weapons draw from.
    static let all: [Weapon] = [.dagger, .sword, .hammer, .pike, .bow, .crossbow, .grenade, .poisonPotion, .tippedBow]
}

/// A hazard burning on one tile for a few turns; anything standing there when
/// the turn resolves takes damage.
struct LingeringEffect {
    let position: GridPosition
    let damagePerTurn: Int
    var turnsRemaining: Int
    /// Freshly placed this turn; the first end-of-turn tick skips it so the
    /// hazard lasts its full duration after the attack that created it.
    var justPlaced = true
}

/// A foe on the board. Enemies draft a move toward the player and, when their
/// weapon can reach the player's tile from the drafted position (and isn't on
/// cooldown), an aimed swing or a lobbed throw — all telegraphed during the
/// planning phase.
struct Enemy {
    let id: Int
    var position: GridPosition
    var health: Int
    /// Where this enemy intends to move next resolve; visible to the player while planning.
    var plannedTarget: GridPosition?
    /// The facing of the swing this enemy intends after moving (directional weapons).
    var plannedDirection: Direction?
    /// The tile this enemy intends to lob its weapon at (thrown weapons).
    var plannedThrowTarget: GridPosition?
    /// Turns left before this enemy's weapon is ready again.
    var cooldownRemaining = 0
    let weapon: Weapon
    /// Damage dealt per hit; defaults to the weapon's damage.
    let damage: Int

    init(id: Int, position: GridPosition, health: Int? = nil, weapon: Weapon? = nil, damage: Int? = nil) {
        self.id = id
        self.position = position
        let carried = weapon ?? Weapon.all.randomElement()!
        self.weapon = carried
        self.health = health ?? carried.enemyHealth
        self.damage = damage ?? carried.damage
    }
}

/// Scenery on the board. Walls block movement and stop attacks dead; barrels
/// block movement and explode when any attack sweeps them, damaging everything
/// beside them (player, enemies, and other barrels — chain reactions included).
struct Obstacle {
    enum Kind {
        case wall, barrel
    }

    let id: Int
    let kind: Kind
    let position: GridPosition
}

/// Everything that happened during one resolve phase, so the scene can animate it.
struct TurnResolution {
    struct EnemyMove {
        let enemyID: Int
        let from: GridPosition
        let to: GridPosition
    }

    struct EnemyHit {
        let enemyID: Int
        let healthAfter: Int
        let died: Bool
    }

    struct EnemyAttack {
        let enemyID: Int
        let tiles: [GridPosition]
        let hitsPlayer: Bool
        /// True when the attack had the player but their dodge (a long move with
        /// no attack drafted) made it miss.
        let dodged: Bool
    }

    /// A barrel going off: its tile and the surrounding tiles the blast damaged.
    struct Explosion {
        let center: GridPosition
        let tiles: [GridPosition]
    }

    /// A telegraphed reinforcement arriving (or being blocked).
    struct SpawnEvent {
        let position: GridPosition
        /// The new enemy's id, or nil when the spawn was blocked by whoever was
        /// standing on the tile (who took 1 damage for it) or by scenery.
        let enemyID: Int?
    }

    let playerDestination: GridPosition
    /// Tiles the player's attack covered — a directional sweep or a throw's
    /// blast; empty when no attack was drafted.
    let attackTiles: [GridPosition]
    /// Enemies damaged during the player's phase (weapon and explosions).
    let enemyHits: [EnemyHit]
    let playerExplosions: [Explosion]
    let enemyMoves: [EnemyMove]
    let enemyAttacks: [EnemyAttack]
    /// Enemies damaged during the enemies' own phase: friendly fire and explosions.
    let friendlyFireHits: [EnemyHit]
    let enemyExplosions: [Explosion]
    /// Enemies burned by lingering effects at the end of the turn (plus anyone
    /// damaged blocking a spawn).
    let hazardHits: [EnemyHit]
    /// Reinforcements that arrived (or were blocked) this turn.
    let spawns: [SpawnEvent]
    let healthLost: Int
    let armorLost: Int
    let playerHealth: Int
    let playerArmor: Int
}

/// Pure game rules, independent of SpriteKit so turn logic stays unit-testable.
///
/// A turn has two phases: planning, where the player drafts a move plus an
/// attack (a directional swing or a tile-targeted throw, depending on the
/// equipped weapon) while seeing every enemy's drafted move and aim, and
/// resolving, in order: the player moves, enemies move, the player's attack
/// goes off, surviving enemies swing (hitting anything in the way, friend or
/// foe), and lingering hazards burn whoever ended the turn standing in them.
struct GameState {
    /// Damage a barrel blast deals to everything on its surrounding tiles.
    static let barrelDamage = 3
    /// How far (Manhattan) a barrel blast reaches.
    static let barrelBlastRadius = 2
    /// Moving at least this many tiles in a turn without attacking earns a
    /// dodge: the first enemy hit that turn misses.
    static let dodgeDistance = 2
    /// A new wave of reinforcements is telegraphed every this many turns.
    static let spawnInterval = 3
    /// Waves grow by one enemy every this many turns survived.
    static let spawnGrowthInterval = 15
    /// Points for a kill, however it dies.
    static let killScore = 10
    /// Points for surviving a turn.
    static let survivalScore = 1

    let columns: Int
    let rows: Int
    /// Armor absorbs damage before health and regenerates 1 on every second
    /// consecutive turn without taking damage (Soul Knight style); health never
    /// regenerates.
    let maxArmor: Int
    private(set) var equippedWeapon: Weapon
    /// The backup weapon. Only two can be carried (Soul Knight style); swapping
    /// exchanges it with the equipped one and costs the whole turn.
    private(set) var holsteredWeapon: Weapon
    private(set) var playerPosition: GridPosition
    /// The destination chosen during planning; nil until a move is planned.
    private(set) var plannedTarget: GridPosition?
    /// The drafted swing's facing (directional weapons); nil when none is
    /// drafted. Originates from the drafted destination.
    private(set) var plannedAttackDirection: Direction?
    /// The drafted throw's impact tile (thrown weapons); nil when none is drafted.
    private(set) var plannedThrowTarget: GridPosition?
    private(set) var enemies: [Enemy]
    private(set) var obstacles: [Obstacle]
    private(set) var lingeringEffects: [LingeringEffect] = []
    private(set) var playerHealth: Int
    private(set) var playerArmor: Int
    private var undamagedTurns = 0
    /// Turns left before each carried weapon may attack again, keyed by name.
    private var weaponCooldowns: [String: Int] = [:]
    private(set) var turnNumber = 0
    private(set) var score = 0
    /// Tiles where next turn's reinforcements will appear; telegraphed during
    /// planning. Anyone standing on one blocks that spawn but takes 1 damage.
    private(set) var pendingSpawns: [GridPosition] = []
    private var nextEnemyID = 0

    /// How many tiles the player may move per turn, set by the equipped weapon.
    var moveRange: Int { equippedWeapon.moveRange }
    var isGameOver: Bool { playerHealth <= 0 }

    /// Where a drafted attack or throw would originate right now.
    var attackOrigin: GridPosition { plannedTarget ?? playerPosition }

    /// Turns before the given carried weapon can attack again; 0 means ready.
    func attackCooldownRemaining(of weapon: Weapon) -> Int {
        weaponCooldowns[weapon.name] ?? 0
    }

    var canAttack: Bool { attackCooldownRemaining(of: equippedWeapon) == 0 }

    /// True when the current draft earns the dodge: no attack or throw drafted,
    /// and a move of at least dodgeDistance tiles.
    var plannedDodgeReady: Bool {
        guard plannedAttackDirection == nil, plannedThrowTarget == nil, let target = plannedTarget else { return false }
        return playerPosition.distance(to: target) >= Self.dodgeDistance
    }

    /// The on-board tiles the drafted attack would cover — the directional sweep
    /// or the throw's blast; empty when nothing is drafted.
    var plannedAttackTiles: [GridPosition] {
        if let target = plannedThrowTarget, let thrown = equippedWeapon.thrown {
            return blastTiles(around: target, radius: thrown.blastRadius, includeCenter: true)
        }
        guard let direction = plannedAttackDirection, let pattern = equippedWeapon.attackPattern else { return [] }
        return sweep(
            pattern,
            from: attackOrigin,
            facing: direction,
            pierces: equippedWeapon.pierces,
            blockers: Set(enemies.map(\.position))
        )
    }

    init(
        columns: Int = 15,
        rows: Int = 15,
        weapon: Weapon? = nil,
        holsteredWeapon: Weapon? = nil,
        playerHealth: Int = 5,
        maxArmor: Int = 3,
        playerStart: GridPosition? = nil,
        walls: Int = 10,
        barrels: Int = 4,
        enemies: [Enemy]? = nil,
        obstacles: [Obstacle]? = nil
    ) {
        precondition(columns > 0 && rows > 0, "Board must have at least one tile")
        self.columns = columns
        self.rows = rows
        // Unspecified loadout slots are drawn randomly, never duplicating the
        // other slot.
        var pool = Weapon.all.filter { $0 != weapon && $0 != holsteredWeapon }.shuffled()
        self.equippedWeapon = weapon ?? pool.removeFirst()
        self.holsteredWeapon = holsteredWeapon ?? pool.removeFirst()
        self.playerHealth = playerHealth
        self.maxArmor = maxArmor
        self.playerArmor = maxArmor
        let start = playerStart ?? GridPosition(x: columns / 2, y: rows / 2)
        self.playerPosition = start
        self.enemies = enemies ?? [
            Enemy(id: 0, position: GridPosition(x: 0, y: 0)),
            Enemy(id: 1, position: GridPosition(x: columns - 1, y: 0)),
            Enemy(id: 2, position: GridPosition(x: 0, y: rows - 1)),
            Enemy(id: 3, position: GridPosition(x: columns - 1, y: rows - 1)),
        ]
        self.obstacles = obstacles ?? Self.scatterObstacles(
            columns: columns,
            rows: rows,
            walls: walls,
            barrels: barrels,
            keepClear: Set(self.enemies.map(\.position)),
            playerStart: start
        )
        self.nextEnemyID = (self.enemies.map(\.id).max() ?? -1) + 1
        draftEnemyPlans()
    }

    /// Random walls and barrels on open tiles, kept off spawn points and their
    /// neighbors (so no one starts walled into a corner) and out of the player's
    /// immediate surroundings.
    private static func scatterObstacles(
        columns: Int,
        rows: Int,
        walls: Int,
        barrels: Int,
        keepClear: Set<GridPosition>,
        playerStart: GridPosition
    ) -> [Obstacle] {
        var placed: [Obstacle] = []
        var blocked = keepClear
        var nextID = 0
        let kinds = Array(repeating: Obstacle.Kind.wall, count: walls)
            + Array(repeating: Obstacle.Kind.barrel, count: barrels)
        for kind in kinds {
            for _ in 0..<50 {
                let candidate = GridPosition(x: Int.random(in: 0..<columns), y: Int.random(in: 0..<rows))
                guard !blocked.contains(candidate),
                      candidate.distance(to: playerStart) > 2,
                      !keepClear.contains(where: { $0.distance(to: candidate) <= 1 })
                else { continue }
                placed.append(Obstacle(id: nextID, kind: kind, position: candidate))
                blocked.insert(candidate)
                nextID += 1
                break
            }
        }
        return placed
    }

    func contains(_ position: GridPosition) -> Bool {
        position.x >= 0 && position.x < columns && position.y >= 0 && position.y < rows
    }

    func enemy(at position: GridPosition) -> Enemy? {
        enemies.first { $0.position == position }
    }

    func obstacle(at position: GridPosition) -> Obstacle? {
        obstacles.first { $0.position == position }
    }

    /// On-board tiles within `radius` Manhattan steps of center — a diamond,
    /// matching the shape of movement and throw ranges. Used for barrel blasts,
    /// throw blasts, lingering effects, and their hover previews.
    func blastTiles(around center: GridPosition, radius: Int = 1, includeCenter: Bool = false) -> [GridPosition] {
        var tiles: [GridPosition] = []
        for dx in -radius...radius {
            let remaining = radius - abs(dx)
            for dy in -remaining...remaining where includeCenter || !(dx == 0 && dy == 0) {
                let tile = GridPosition(x: center.x + dx, y: center.y + dy)
                if contains(tile) {
                    tiles.append(tile)
                }
            }
        }
        return tiles
    }

    /// The tiles an enemy's drafted attack will cover next resolve; empty when
    /// it isn't attacking. Used to telegraph threats while planning.
    func threatTiles(of enemy: Enemy) -> [GridPosition] {
        if let target = enemy.plannedThrowTarget, let thrown = enemy.weapon.thrown {
            return blastTiles(around: target, radius: thrown.blastRadius, includeCenter: true)
        }
        guard let direction = enemy.plannedDirection, let pattern = enemy.weapon.attackPattern else { return [] }
        let origin = enemy.plannedTarget ?? enemy.position
        var blockers = Set(enemies.filter { $0.id != enemy.id }.map(\.position))
        blockers.insert(playerPosition)
        return sweep(pattern, from: origin, facing: direction, pierces: enemy.weapon.pierces, blockers: blockers)
    }

    /// Tiles the player may pick this turn: every on-board tile within moveRange
    /// orthogonal steps (a diamond, no diagonals), including the current tile
    /// (planning to stay) but excluding tiles occupied by enemies or obstacles.
    func legalMoveTargets() -> Set<GridPosition> {
        let occupied = Set(enemies.map(\.position)).union(obstacles.map(\.position))
        var targets: Set<GridPosition> = []
        for dx in -moveRange...moveRange {
            let remaining = moveRange - abs(dx)
            for dy in -remaining...remaining {
                let candidate = GridPosition(x: playerPosition.x + dx, y: playerPosition.y + dy)
                if contains(candidate) && !occupied.contains(candidate) {
                    targets.insert(candidate)
                }
            }
        }
        return targets
    }

    /// Tiles the equipped thrown weapon could land on from the drafted
    /// destination: anything within its range except wall tiles. Empty for
    /// directional weapons.
    func throwTargets() -> Set<GridPosition> {
        guard let thrown = equippedWeapon.thrown else { return [] }
        var targets: Set<GridPosition> = []
        let origin = attackOrigin
        for dx in -thrown.range...thrown.range {
            let remaining = thrown.range - abs(dx)
            for dy in -remaining...remaining {
                let candidate = GridPosition(x: origin.x + dx, y: origin.y + dy)
                if contains(candidate) && obstacle(at: candidate)?.kind != .wall {
                    targets.insert(candidate)
                }
            }
        }
        return targets
    }

    /// Swaps the equipped and holstered weapons. Swapping is the player's whole
    /// turn: any drafted move and attack are discarded, and the caller should
    /// resolve the turn immediately after.
    mutating func swapWeapons() {
        (equippedWeapon, holsteredWeapon) = (holsteredWeapon, equippedWeapon)
        plannedTarget = nil
        plannedAttackDirection = nil
        plannedThrowTarget = nil
    }

    /// Stores the player's chosen destination without moving yet. A drafted
    /// throw that the new origin can no longer reach is cleared.
    /// Returns false if the target is not a legal move.
    @discardableResult
    mutating func planMove(to target: GridPosition) -> Bool {
        guard !isGameOver, legalMoveTargets().contains(target) else { return false }
        plannedTarget = target
        if let throwTarget = plannedThrowTarget, !throwTargets().contains(throwTarget) {
            plannedThrowTarget = nil
        }
        return true
    }

    /// Drafts the equipped weapon's attack toward/at the given tile: directional
    /// weapons face the tile, thrown weapons land on it (so the tile must be in
    /// range). Fails when the weapon is on cooldown or the tile is the origin
    /// itself.
    @discardableResult
    mutating func planAttack(toward tile: GridPosition) -> Bool {
        guard !isGameOver, canAttack else { return false }
        if equippedWeapon.thrown != nil {
            guard throwTargets().contains(tile) else { return false }
            plannedThrowTarget = tile
            plannedAttackDirection = nil
            return true
        }
        guard let direction = Direction.aiming(
            from: attackOrigin,
            toward: tile,
            allowDiagonals: equippedWeapon.attackPattern?.supportsDiagonals ?? false
        ) else { return false }
        plannedAttackDirection = direction
        plannedThrowTarget = nil
        return true
    }

    mutating func clearPlannedAttack() {
        plannedAttackDirection = nil
        plannedThrowTarget = nil
    }

    /// Leaves a damaging hazard on the given tiles for `duration` turns;
    /// anything standing on one when the turn resolves takes damage. Re-applying
    /// to a tile refreshes it. Walls can't burn.
    mutating func addLingeringEffect(at tiles: [GridPosition], damagePerTurn: Int, duration: Int) {
        for tile in tiles where contains(tile) && obstacle(at: tile)?.kind != .wall {
            lingeringEffects.removeAll { $0.position == tile }
            lingeringEffects.append(LingeringEffect(position: tile, damagePerTurn: damagePerTurn, turnsRemaining: duration))
        }
    }

    /// Resolves the turn in order: the player commits the planned move, enemies
    /// execute their drafted moves, the player's attack goes off (throwers caught
    /// in their own blast take damage; dead enemies never swing; struck barrels
    /// explode), surviving enemies swing — hitting the player, each other, and
    /// barrels alike — and finally lingering hazards burn whoever is standing in
    /// them. Weapons with a lingering effect leave it on every tile they covered.
    /// Armor regenerates on every second turn without damage, weapon cooldowns
    /// tick, and enemies draft against the new positions.
    /// Returns a record of what happened so the scene can animate it.
    @discardableResult
    mutating func resolveTurn() -> TurnResolution {
        let playerStart = playerPosition
        playerPosition = plannedTarget ?? playerPosition
        plannedTarget = nil

        // Enemy weapon cooldowns tick at the start of the turn, so a fresh shot
        // still reads at its full value on the hover display while planning.
        for index in enemies.indices where enemies[index].cooldownRemaining > 0 {
            enemies[index].cooldownRemaining -= 1
        }

        let healthBefore = playerHealth
        let armorBefore = playerArmor

        var moves: [TurnResolution.EnemyMove] = []
        for index in enemies.indices {
            let from = enemies[index].position
            var to = enemies[index].plannedTarget ?? from
            // The drafted tile may have been taken since drafting (by the player
            // dodging into it or another enemy); a blocked enemy stays put.
            if to != from {
                let occupied = Set(enemies.map(\.position))
                    .union(obstacles.map(\.position))
                    .union([playerPosition])
                if !contains(to) || occupied.contains(to) {
                    to = from
                }
            }
            enemies[index].position = to
            enemies[index].plannedTarget = nil
            moves.append(TurnResolution.EnemyMove(enemyID: enemies[index].id, from: from, to: to))
        }

        var attackTiles: [GridPosition] = []
        var playerPhaseHits: [TurnResolution.EnemyHit] = []
        var playerExplosions: [TurnResolution.Explosion] = []
        var didAttack = false
        if let direction = plannedAttackDirection, let pattern = equippedWeapon.attackPattern {
            didAttack = true
            attackTiles = sweep(
                pattern,
                from: playerPosition,
                facing: direction,
                pierces: equippedWeapon.pierces,
                blockers: Set(enemies.map(\.position))
            )
        } else if let target = plannedThrowTarget, let thrown = equippedWeapon.thrown {
            didAttack = true
            attackTiles = blastTiles(around: target, radius: thrown.blastRadius, includeCenter: true)
        }
        if didAttack {
            let struck = Set(attackTiles)
            playerPhaseHits += damageEnemies(on: struck, damage: equippedWeapon.damage)
            // A lobbed blast has no friendly immunity: catch yourself, hurt yourself.
            if equippedWeapon.thrown != nil && !isGameOver && struck.contains(playerPosition) {
                applyDamage(equippedWeapon.damage)
            }
            let blast = detonateBarrels(struckTiles: struck)
            playerExplosions = blast.explosions
            playerPhaseHits += blast.hits
            if let lingering = equippedWeapon.lingering {
                addLingeringEffect(at: attackTiles, damagePerTurn: lingering.damagePerTurn, duration: lingering.duration)
            }
        }
        plannedAttackDirection = nil
        plannedThrowTarget = nil

        // Moving far without attacking earns one dodge: the first enemy hit
        // this turn misses.
        var dodgeCharges = (!didAttack && playerStart.distance(to: playerPosition) >= Self.dodgeDistance) ? 1 : 0

        var enemyAttacks: [TurnResolution.EnemyAttack] = []
        var friendlyFireHits: [TurnResolution.EnemyHit] = []
        var enemyExplosions: [TurnResolution.Explosion] = []
        // Iterate by ID: an attacker can die to a comrade's swing or an
        // explosion before its own turn to act.
        let attackerIDs = enemies.compactMap {
            ($0.plannedDirection != nil || $0.plannedThrowTarget != nil) ? $0.id : nil
        }
        for attackerID in attackerIDs {
            guard let attackerIndex = enemies.firstIndex(where: { $0.id == attackerID }) else { continue }
            let attacker = enemies[attackerIndex]

            var tiles: [GridPosition] = []
            var throwerIncluded = false
            if let direction = attacker.plannedDirection, let pattern = attacker.weapon.attackPattern {
                var blockers = Set(enemies.filter { $0.id != attackerID }.map(\.position))
                blockers.insert(playerPosition)
                tiles = sweep(pattern, from: attacker.position, facing: direction, pierces: attacker.weapon.pierces, blockers: blockers)
            } else if let target = attacker.plannedThrowTarget, let thrown = attacker.weapon.thrown {
                tiles = blastTiles(around: target, radius: thrown.blastRadius, includeCenter: true)
                throwerIncluded = true
            } else {
                continue
            }
            enemies[attackerIndex].plannedDirection = nil
            enemies[attackerIndex].plannedThrowTarget = nil
            enemies[attackerIndex].cooldownRemaining = attacker.weapon.cooldown

            let struck = Set(tiles)
            var hitsPlayer = !isGameOver && struck.contains(playerPosition)
            var dodged = false
            if hitsPlayer && dodgeCharges > 0 {
                dodgeCharges -= 1
                dodged = true
                hitsPlayer = false
            }
            if hitsPlayer {
                applyDamage(attacker.damage)
            }
            // Friendly fire: comrades in the sweep take the hit; a thrower caught
            // in its own blast does too.
            var struckEnemies = struck
            if !throwerIncluded {
                struckEnemies.remove(attacker.position)
            }
            friendlyFireHits += damageEnemies(on: struckEnemies, damage: attacker.damage)
            let blast = detonateBarrels(struckTiles: struck)
            enemyExplosions += blast.explosions
            friendlyFireHits += blast.hits
            if let lingering = attacker.weapon.lingering {
                addLingeringEffect(at: tiles, damagePerTurn: lingering.damagePerTurn, duration: lingering.duration)
            }

            enemyAttacks.append(TurnResolution.EnemyAttack(
                enemyID: attackerID,
                tiles: tiles,
                hitsPlayer: hitsPlayer,
                dodged: dodged
            ))
        }

        // Lingering hazards burn whoever ended the turn in them. Effects placed
        // this turn skip their first tick so they last their full duration.
        var hazardHits: [TurnResolution.EnemyHit] = []
        for index in lingeringEffects.indices {
            if lingeringEffects[index].justPlaced {
                lingeringEffects[index].justPlaced = false
                continue
            }
            let effect = lingeringEffects[index]
            hazardHits += damageEnemies(on: [effect.position], damage: effect.damagePerTurn)
            if !isGameOver && effect.position == playerPosition {
                applyDamage(effect.damagePerTurn)
            }
            lingeringEffects[index].turnsRemaining -= 1
        }
        lingeringEffects.removeAll { $0.turnsRemaining <= 0 }

        // Reinforcements: the telegraphed spawns materialize. Anyone standing on
        // a spawn tile blocks it, taking 1 damage for the trouble.
        var spawns: [TurnResolution.SpawnEvent] = []
        for tile in pendingSpawns {
            if tile == playerPosition {
                if !isGameOver {
                    applyDamage(1)
                }
                spawns.append(TurnResolution.SpawnEvent(position: tile, enemyID: nil))
            } else if enemies.contains(where: { $0.position == tile }) {
                hazardHits += damageEnemies(on: [tile], damage: 1)
                spawns.append(TurnResolution.SpawnEvent(position: tile, enemyID: nil))
            } else if obstacle(at: tile) != nil {
                spawns.append(TurnResolution.SpawnEvent(position: tile, enemyID: nil))
            } else {
                let recruit = Enemy(id: nextEnemyID, position: tile)
                nextEnemyID += 1
                enemies.append(recruit)
                spawns.append(TurnResolution.SpawnEvent(position: tile, enemyID: recruit.id))
            }
        }
        pendingSpawns = []

        let tookDamage = playerHealth < healthBefore || playerArmor < armorBefore
        if tookDamage {
            undamagedTurns = 0
        } else {
            undamagedTurns += 1
            if undamagedTurns.isMultiple(of: 2) && playerArmor < maxArmor {
                playerArmor += 1
            }
        }

        for name in weaponCooldowns.keys {
            weaponCooldowns[name] = max(0, (weaponCooldowns[name] ?? 0) - 1)
        }
        if didAttack {
            weaponCooldowns[equippedWeapon.name] = equippedWeapon.cooldown
        }

        turnNumber += 1
        if !isGameOver {
            score += Self.survivalScore
        }
        scheduleSpawns()

        draftEnemyPlans()

        return TurnResolution(
            playerDestination: playerPosition,
            attackTiles: attackTiles,
            enemyHits: playerPhaseHits,
            playerExplosions: playerExplosions,
            enemyMoves: moves,
            enemyAttacks: enemyAttacks,
            friendlyFireHits: friendlyFireHits,
            enemyExplosions: enemyExplosions,
            hazardHits: hazardHits,
            spawns: spawns,
            healthLost: healthBefore - playerHealth,
            armorLost: max(0, armorBefore - playerArmor),
            playerHealth: playerHealth,
            playerArmor: playerArmor
        )
    }

    /// Damages every enemy standing on the given tiles and removes the dead.
    /// Returns the hits for animation.
    private mutating func damageEnemies(on tiles: Set<GridPosition>, damage: Int) -> [TurnResolution.EnemyHit] {
        var hits: [TurnResolution.EnemyHit] = []
        for index in enemies.indices where tiles.contains(enemies[index].position) {
            enemies[index].health -= damage
            let died = enemies[index].health <= 0
            if died {
                score += Self.killScore
            }
            hits.append(TurnResolution.EnemyHit(
                enemyID: enemies[index].id,
                healthAfter: max(0, enemies[index].health),
                died: died
            ))
        }
        enemies.removeAll { $0.health <= 0 }
        return hits
    }

    /// Picks the next wave's telegraphed spawn tiles: random open edge tiles a
    /// safe distance from the player, batch size growing as the run goes on.
    private mutating func scheduleSpawns() {
        pendingSpawns = []
        guard turnNumber % Self.spawnInterval == 0 else { return }
        let batch = 1 + turnNumber / Self.spawnGrowthInterval

        var edges: [GridPosition] = []
        for x in 0..<columns {
            edges.append(GridPosition(x: x, y: 0))
            edges.append(GridPosition(x: x, y: rows - 1))
        }
        for y in 1..<(rows - 1) {
            edges.append(GridPosition(x: 0, y: y))
            edges.append(GridPosition(x: columns - 1, y: y))
        }

        let taken = Set(enemies.map(\.position))
            .union(obstacles.map(\.position))
            .union(lingeringEffects.map(\.position))
        let candidates = edges.filter {
            !taken.contains($0) && $0.distance(to: playerPosition) > 3
        }
        pendingSpawns = Array(candidates.shuffled().prefix(batch))
    }

    /// The tiles an attack actually covers, in authored order: clipped to the
    /// board, stopped dead by walls (which can't be hit), and truncated just
    /// after the first blocker or barrel when the weapon doesn't pierce.
    private func sweep(_ pattern: AttackPattern, from origin: GridPosition, facing direction: Direction, pierces: Bool, blockers: Set<GridPosition>) -> [GridPosition] {
        var result: [GridPosition] = []
        for tile in pattern.tiles(from: origin, facing: direction) where contains(tile) {
            let obstacle = obstacle(at: tile)
            if obstacle?.kind == .wall {
                break
            }
            result.append(tile)
            if !pierces && (blockers.contains(tile) || obstacle != nil) {
                break
            }
        }
        return result
    }

    /// Detonates every barrel in the struck tiles: each blast damages the player
    /// and enemies on surrounding tiles and sets off neighboring barrels in a
    /// chain. Detonated barrels are removed from the board.
    private mutating func detonateBarrels(struckTiles: Set<GridPosition>) -> (explosions: [TurnResolution.Explosion], hits: [TurnResolution.EnemyHit]) {
        var queue = obstacles.filter { $0.kind == .barrel && struckTiles.contains($0.position) }
        var detonatedIDs = Set<Int>()
        var explosions: [TurnResolution.Explosion] = []
        var hits: [TurnResolution.EnemyHit] = []

        while let barrel = queue.popLast() {
            guard !detonatedIDs.contains(barrel.id) else { continue }
            detonatedIDs.insert(barrel.id)

            let blast = blastTiles(around: barrel.position, radius: Self.barrelBlastRadius)
            explosions.append(TurnResolution.Explosion(center: barrel.position, tiles: blast))

            let blastSet = Set(blast)
            hits += damageEnemies(on: blastSet, damage: Self.barrelDamage)
            if !isGameOver && blastSet.contains(playerPosition) {
                applyDamage(Self.barrelDamage)
            }
            queue += obstacles.filter {
                $0.kind == .barrel && !detonatedIDs.contains($0.id) && blastSet.contains($0.position)
            }
        }

        obstacles.removeAll { detonatedIDs.contains($0.id) }
        return (explosions, hits)
    }

    /// Armor absorbs damage first; only the overflow reaches health.
    private mutating func applyDamage(_ amount: Int) {
        let absorbed = min(playerArmor, amount)
        playerArmor -= absorbed
        playerHealth -= amount - absorbed
    }

    /// Each enemy drafts its next turn: hold position when its weapon can already
    /// reach the player, otherwise walk up to its weapon's moveRange toward a
    /// firing position (stopping early the moment the player is in reach, and
    /// so ranged weapons keep their distance instead of charging to melee). It
    /// drafts an aim — a facing for directional weapons, the player's tile for
    /// thrown ones — whenever its weapon is off cooldown and could hit the
    /// player's current tile from the drafted position.
    private mutating func draftEnemyPlans() {
        // Hazard tiles count as blocked so enemies path around lingering pools
        // rather than through (or into) them.
        var claimed = Set(enemies.map(\.position))
            .union(obstacles.map(\.position))
            .union(lingeringEffects.map(\.position))
            .union([playerPosition])
        for index in enemies.indices {
            let enemy = enemies[index]
            let ready = enemy.cooldownRemaining == 0

            var target = enemy.position
            if !canHitPlayer(enemy, from: enemy.position) {
                let goal = attackGoal(for: enemy, avoiding: claimed)
                for _ in 0..<enemy.weapon.moveRange {
                    let next = stepToward(goal, from: target, avoiding: claimed)
                    if next == target {
                        break
                    }
                    target = next
                    if canHitPlayer(enemy, from: target) {
                        break
                    }
                }
            }
            enemies[index].plannedTarget = target
            enemies[index].plannedDirection = nil
            enemies[index].plannedThrowTarget = nil
            if ready && canHitPlayer(enemy, from: target) {
                if enemy.weapon.thrown != nil {
                    enemies[index].plannedThrowTarget = playerPosition
                } else {
                    enemies[index].plannedDirection = aimDirection(for: enemy, from: target)
                }
            }
            claimed.insert(target)
        }
    }

    /// Whether the enemy's weapon could reach the player's current tile from
    /// `tile` — throws just need range (they arc over everything); swings need a
    /// clear line for some facing.
    private func canHitPlayer(_ enemy: Enemy, from tile: GridPosition) -> Bool {
        if let thrown = enemy.weapon.thrown {
            return tile != playerPosition && tile.distance(to: playerPosition) <= thrown.range
        }
        return aimDirection(for: enemy, from: tile) != nil
    }

    /// A tile this enemy should head for: a pick from the two furthest rings of
    /// open firing positions (so ranged weapons kite near max range without
    /// being fully predictable), chosen randomly among the closest approaches so
    /// nobody treks across the board. Falls back to a random tile beside the
    /// player when every firing position is taken.
    private func attackGoal(for enemy: Enemy, avoiding claimed: Set<GridPosition>) -> GridPosition {
        let goals = attackPositions(for: enemy.weapon).filter { !claimed.contains($0) }
        guard let bestRange = goals.map({ $0.distance(to: playerPosition) }).max() else {
            return randomAttackTile(avoiding: claimed)
        }
        let topRings = goals.filter { $0.distance(to: playerPosition) >= bestRange - 1 }
        let byWalk = topRings.sorted { $0.distance(to: enemy.position) < $1.distance(to: enemy.position) }
        return byWalk.prefix(4).randomElement()!
    }

    /// Every open board tile from which the weapon could hit the player's
    /// current tile (ignoring walls in the way for swings; the aim check at
    /// draft time settles that).
    private func attackPositions(for weapon: Weapon) -> [GridPosition] {
        var positions: Set<GridPosition> = []
        if let thrown = weapon.thrown {
            for dx in -thrown.range...thrown.range {
                let remaining = thrown.range - abs(dx)
                for dy in -remaining...remaining {
                    let candidate = GridPosition(x: playerPosition.x + dx, y: playerPosition.y + dy)
                    if candidate != playerPosition && contains(candidate) && obstacle(at: candidate) == nil {
                        positions.insert(candidate)
                    }
                }
            }
            return Array(positions)
        }
        guard let pattern = weapon.attackPattern else { return [] }
        for direction in Direction.allCases {
            for reach in pattern.tiles(from: GridPosition(x: 0, y: 0), facing: direction) {
                let candidate = GridPosition(x: playerPosition.x - reach.x, y: playerPosition.y - reach.y)
                if candidate != playerPosition && contains(candidate) && obstacle(at: candidate) == nil {
                    positions.insert(candidate)
                }
            }
        }
        return Array(positions)
    }

    /// The first facing from which this enemy's swing would actually reach the
    /// player from `tile` — walls and bodies in the way are respected.
    private func aimDirection(for enemy: Enemy, from tile: GridPosition) -> Direction? {
        guard let pattern = enemy.weapon.attackPattern else { return nil }
        let blockers = Set(enemies.filter { $0.id != enemy.id }.map(\.position))
        return Direction.allCases.first { direction in
            sweep(pattern, from: tile, facing: direction, pierces: enemy.weapon.pierces, blockers: blockers)
                .contains(playerPosition)
        }
    }

    /// A random open tile beside the player (diagonals count) to navigate toward;
    /// falls back to the player's own tile when all eight are spoken for.
    private func randomAttackTile(avoiding claimed: Set<GridPosition>) -> GridPosition {
        var candidates: [GridPosition] = []
        for dx in -1...1 {
            for dy in -1...1 where !(dx == 0 && dy == 0) {
                let tile = GridPosition(x: playerPosition.x + dx, y: playerPosition.y + dy)
                if contains(tile) && !claimed.contains(tile) {
                    candidates.append(tile)
                }
            }
        }
        return candidates.randomElement() ?? playerPosition
    }

    /// One orthogonal tile toward the goal, preferring the axis with the larger
    /// gap; blocked enemies stay put.
    private func stepToward(_ goal: GridPosition, from: GridPosition, avoiding claimed: Set<GridPosition>) -> GridPosition {
        let dx = (goal.x - from.x).signum()
        let dy = (goal.y - from.y).signum()
        let stepX = GridPosition(x: from.x + dx, y: from.y)
        let stepY = GridPosition(x: from.x, y: from.y + dy)
        let xGapIsLarger = abs(goal.x - from.x) >= abs(goal.y - from.y)
        let candidates = xGapIsLarger ? [stepX, stepY] : [stepY, stepX]
        for candidate in candidates where candidate != from && contains(candidate) && !claimed.contains(candidate) {
            return candidate
        }
        return from
    }
}
