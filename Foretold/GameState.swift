//
//  GameState.swift
//  Foretold
//  The Final Draft?
//  Name ^

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

    /// One tile of travel along this direction (diagonal steps move both axes).
    var unitStep: GridPosition {
        isDiagonal ? rotated(GridPosition(x: 1, y: 1)) : rotated(GridPosition(x: 1, y: 0))
    }

    /// Compass glyph for HUD readouts.
    var arrow: String {
        switch self {
        case .right: return "→"
        case .up: return "↑"
        case .left: return "←"
        case .down: return "↓"
        case .upRight: return "↗"
        case .upLeft: return "↖"
        case .downLeft: return "↙"
        case .downRight: return "↘"
        }
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
    /// True for straight thrusts (the `line` factory): a wall stops everything
    /// behind it. Shaped swings (arcs, rings) just can't hit the wall tile
    /// itself — they sweep around it.
    let isLine: Bool

    init(offsets: [GridPosition], diagonalOffsets: [GridPosition]? = nil, isLine: Bool = false) {
        self.offsets = offsets
        self.diagonalOffsets = diagonalOffsets
        self.isLine = isLine
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
            diagonalOffsets: (1...length).map { GridPosition(x: $0, y: $0) },
            isLine: true
        )
    }

    /// A hollow circle: every tile between innerRadius and outerRadius of the
    /// attacker (rounded grid circle, own tile excluded). ring(from: 2, to: 2)
    /// strikes only at two tiles out, leaving a blind spot right beside the
    /// attacker. The shape is identical from any facing, diagonals included, so
    /// aiming direction doesn't matter; offsets are ordered nearest-first in
    /// case a non-piercing weapon uses it.
    static func ring(from innerRadius: Int, to outerRadius: Int) -> AttackPattern {
        let outerBound = outerRadius * outerRadius + outerRadius
        let inner = innerRadius - 1
        let innerBound = inner * inner + inner
        var offsets: [GridPosition] = []
        for dx in -outerRadius...outerRadius {
            for dy in -outerRadius...outerRadius where !(dx == 0 && dy == 0) {
                let distanceSquared = dx * dx + dy * dy
                if distanceSquared <= outerBound && distanceSquared > innerBound {
                    offsets.append(GridPosition(x: dx, y: dy))
                }
            }
        }
        offsets.sort { ($0.x * $0.x + $0.y * $0.y) < ($1.x * $1.x + $1.y * $1.y) }
        return AttackPattern(offsets: offsets, diagonalOffsets: offsets)
    }

    /// Every tile within `radius` of the attacker — a filled ring, i.e. a
    /// bigger hammer swing. radius 1 is exactly the 8 surrounding tiles.
    static func circle(radius: Int) -> AttackPattern {
        ring(from: 1, to: radius)
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
    static let greataxe = AttackPattern.circle(radius: 2)
    static let scythe = AttackPattern.ring(from: 2, to: 2)
}

/// Gear anyone can carry. A weapon attacks either directionally (via
/// `attackPattern`) or by being lobbed at a tile (via `thrown`) — exactly one of
/// the two. Heavier weapons restrict how far the wielder can move but hit
/// harder, so weapon choice is a mobility/damage trade-off.
//MARK: - Weapons
struct Weapon: Equatable {
    /// A lobbed attack: pick any tile within `range`, and the blast covers a
    /// diamond of `blastRadius` around it. Throws arc over walls and bodies, and
    /// the blast hits everyone caught in it — the thrower included.
    struct Thrown: Equatable {
        /// Max Manhattan distance the weapon can be thrown.
        let range: Int
        /// Manhattan radius of the blast diamond around the impact tile.
        let blastRadius: Int
        /// Turns the projectile spends airborne before detonating; 0 lands the
        /// same turn it's thrown. While in flight the impact zone is telegraphed,
        /// so slower projectiles are easier to walk out of — escape needs
        /// moveRange × (1 + flightTurns) > blastRadius.
        let flightTurns: Int

        init(range: Int, blastRadius: Int, flightTurns: Int = 0) {
            self.range = range
            self.blastRadius = blastRadius
            self.flightTurns = flightTurns
        }
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
    /// Declares the weapon ranged (bows, thrown flasks…). Melee hits are the
    /// ones blunted by meleeDamageReduction buffs; ranged hits by
    /// rangedDamageReduction ones.
    let isRanged: Bool
    /// When set on a directional weapon (line patterns), attacks fire a
    /// traveling bolt instead of striking instantly: it advances this many
    /// tiles per turn along the aimed line — low values make slow, dodgeable
    /// cannonballs. Range comes from the pattern's length.
    let projectileSpeed: Int?
    /// For bolts only: the shot detonates a diamond blast of this radius
    /// wherever its flight ends — striking a body, hitting scenery, or falling
    /// at max range. The blast replaces the single-target hit. 0 = no blast.
    let impactBlastRadius: Int

    var isMelee: Bool { !isRanged }

    init(
        name: String,
        moveRange: Int,
        damage: Int,
        pierces: Bool = true,
        cooldown: Int = 0,
        enemyHealth: Int = 3,
        isRanged: Bool = false,
        projectileSpeed: Int? = nil,
        impactBlastRadius: Int = 0,
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
        self.isRanged = isRanged
        self.projectileSpeed = projectileSpeed
        self.impactBlastRadius = impactBlastRadius
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
    static let bow = Weapon(name: "Bow", moveRange: 2, damage: 2, pierces: false, cooldown: 1, enemyHealth: 2, isRanged: true, projectileSpeed: 5, attackPattern: .bow)
    static let tippedBow = Weapon(name: "Tipped Bow", moveRange: 2, damage: 1, pierces: false, cooldown: 2, enemyHealth: 2, isRanged: true, projectileSpeed: 5, attackPattern: .bow, lingering: Lingering(damagePerTurn: 1, duration: 2))
    static let crossbow = Weapon(name: "Crossbow", moveRange: 1, damage: 3, pierces: true , cooldown: 2, enemyHealth: 2, isRanged: true, projectileSpeed: 7, attackPattern: .crossbow)
    /// A slow, devastating ball you can see coming for turns; it bursts in a
    /// diamond wherever its flight ends.
    static let cannon = Weapon(name: "Cannon", moveRange: 1, damage: 5, pierces: false, cooldown: 2, enemyHealth: 3, isRanged: true, projectileSpeed: 2, impactBlastRadius: 1, attackPattern: .crossbow)
    static let grenade = Weapon(
        name: "Grenade",
        moveRange: 2,
        damage: 3,
        cooldown: 1,
        enemyHealth: 2,
        isRanged: true,
        thrown: Thrown(range: 8, blastRadius: 1, flightTurns: 1),
        lingering: Lingering(damagePerTurn: 1, duration: 1),
    )
    static let poisonPotion = Weapon(
        name: "Poison Potion",
        moveRange: 2,
        damage: 1,
        cooldown: 2,
        enemyHealth: 2,
        isRanged: true,
        thrown: Thrown(range: 4, blastRadius: 2, flightTurns: 2),
        lingering: Lingering(damagePerTurn: 3, duration: 3)
    )
    static let greataxe = Weapon(name: "Greataxe", moveRange: 1, damage: 4, cooldown: 2, enemyHealth: 4, attackPattern: .greataxe)
    static let scythe = Weapon(name: "Scythe", moveRange: 2, damage: 2, enemyHealth: 3, attackPattern: .scythe)
    /// The pool random loadouts and enemy weapons draw from.
    static let all: [Weapon] = [.dagger, .sword, .hammer, .pike, .bow, .crossbow, .grenade, .poisonPotion, .tippedBow, .greataxe, .scythe, .cannon]
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

/// A weapon lying on the ground. While standing on one the player may draft a
/// pickup, spending their attack (and dodge) for the turn to swap it with the
/// equipped weapon — the old weapon stays on the tile for trading back later.
struct WeaponDrop {
    let id: Int
    let weapon: Weapon
    let position: GridPosition
}

/// A boon granted on level-up. Author buffs by setting only the knobs they
/// use — everything defaults to "no effect":
/// - `instantHeal` / `instantArmorRepair` apply once, when granted.
/// - The damage reductions, immunities, and bonuses apply continuously while
///   the buff is held (a buff with only instant effects is never "held").
/// - `levelDuration` is how many level-ups the buff survives: 1 lasts just the
///   current level, 2 wears off two level-ups later, nil lasts the whole run.
/// - `stackable: false` removes it from the pool while owned.
struct Buff: Equatable {
    let name: String
    let levelDuration: Int?
    let stackable: Bool
    let instantHeal: Int
    let instantArmorRepair: Int
    /// Damage removed from each melee weapon hit (reach ≤ 3, not thrown).
    let meleeDamageReduction: Int
    /// Damage removed from each ranged or thrown weapon hit.
    let rangedDamageReduction: Int
    /// Barrel blasts no longer hurt the player.
    let barrelImmunity: Bool
    /// Lingering pools no longer burn the player.
    let hazardImmunity: Bool
    /// Added to the equipped weapon's move range.
    let bonusMoveRange: Int
    /// Added to the equipped weapon's damage.
    let bonusDamage: Int
    /// Added to the player's max armor
    let bonusArmor: Int

    init(
        name: String,
        levelDuration: Int? = nil,
        stackable: Bool = true,
        instantHeal: Int = 0,
        instantArmorRepair: Int = 0,
        meleeDamageReduction: Int = 0,
        rangedDamageReduction: Int = 0,
        barrelImmunity: Bool = false,
        hazardImmunity: Bool = false,
        bonusMoveRange: Int = 0,
        bonusDamage: Int = 0,
        bonusArmor: Int = 0,
    ) {
        self.name = name
        self.levelDuration = levelDuration
        self.stackable = stackable
        self.instantHeal = instantHeal
        self.instantArmorRepair = instantArmorRepair
        self.meleeDamageReduction = meleeDamageReduction
        self.rangedDamageReduction = rangedDamageReduction
        self.barrelImmunity = barrelImmunity
        self.hazardImmunity = hazardImmunity
        self.bonusMoveRange = bonusMoveRange
        self.bonusDamage = bonusDamage
        self.bonusArmor = bonusArmor
    }

    /// Purely instant buffs aren't kept in the held list after applying.
    var isInstantOnly: Bool {
        meleeDamageReduction == 0 && rangedDamageReduction == 0
            && !barrelImmunity && !hazardImmunity
            && bonusMoveRange == 0 && bonusDamage == 0
            && bonusArmor == 0
    }
}

// MARK: - Buffs
// Author level-up boons here; the pool below is what level-ups draw from.
extension Buff {
    static let barrelImmune = Buff(name: "Immune to barrels", levelDuration: 2, stackable: false, barrelImmunity: true)
    static let thickSkin = Buff(name: "-1 melee dmg taken", levelDuration: 3, meleeDamageReduction: 1)
    static let secondWind = Buff(name: "+2 HP", instantHeal: 2)
    static let longStride = Buff(name: "+1 move", levelDuration: 1, bonusMoveRange: 1)
    static let whetstone = Buff(name: "+1 dmg", levelDuration: 1, bonusDamage: 1)
    static let hardenedArmour = Buff(name: "+1 max armour", levelDuration: 1, instantArmorRepair: 1, bonusArmor: 1)
    /// The pool level-ups draw from.
    static let all: [Buff] = [.barrelImmune, .thickSkin, .secondWind, .longStride, .whetstone, .hardenedArmour]
}

/// A buff the player currently holds, with its remaining lifetime.
struct HeldBuff {
    let buff: Buff
    /// Level-ups left before it wears off; nil = the whole run.
    var levelsRemaining: Int?
}

/// A lobbed shot in flight: it lands on a fixed tile after a fixed number of
/// turns and blasts a diamond there. The impact zone is telegraphed the whole
/// time it's airborne — nothing can stop a shell already in the air.
struct Projectile {
    let id: Int
    let origin: GridPosition
    let target: GridPosition
    let blastRadius: Int
    let damage: Int
    let lingering: Weapon.Lingering?
    let totalFlightTurns: Int
    var turnsUntilImpact: Int
}

/// An arrow or cannonball flying along a straight line: each resolve it
/// advances up to `speed` tiles, striking the first body it meets (everything
/// in its path, if it pierces), detonating barrels, and dying against walls.
/// Its next stretch of travel is telegraphed while it flies.
struct Bolt {
    let id: Int
    /// The last tile the bolt passed through (starts at the shooter).
    var position: GridPosition
    let direction: Direction
    /// Tiles advanced per turn — the "slow cannonball" knob.
    let speed: Int
    var remainingRange: Int
    let damage: Int
    let pierces: Bool
    /// Detonates a diamond blast of this radius wherever the flight ends;
    /// 0 = plain arrow.
    let impactBlastRadius: Int
    /// Left burning on the tiles the bolt passes through.
    let lingering: Weapon.Lingering?
}

/// Difficulty knobs for one level — the Tetris-style ramp.
struct LevelConfig {
    /// Enemies placed when the level's board is generated.
    let startingEnemies: Int
    /// Turns between reinforcement waves.
    let spawnInterval: Int
    /// Enemies per wave.
    let spawnBatch: Int
    /// Walls scattered on the level's board.
    let walls: Int
    /// Barrels scattered on the level's board — more powder as the run goes on.
    let barrels: Int

    static func forLevel(_ level: Int) -> LevelConfig {
        LevelConfig(
            startingEnemies: min(3 + level, 8),
            spawnInterval: max(2, 3 - (level - 1) / 4),
            spawnBatch: 1 + (level - 1) / 3,
            walls: 10,
            barrels: min(3 + level, 12)
        )
    }
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
    /// Enemy tiles smitten by the ultimate this turn.
    let ultimateTiles: [GridPosition]
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
    /// One bolt's travel this turn, for the scene to glide its sprite along.
    struct BoltFlight {
        let boltID: Int
        let from: GridPosition
        /// The furthest tile it reached — its resting place, or where it died.
        let to: GridPosition
        let direction: Direction
    }

    /// Airborne shells that landed this turn (after everyone moved).
    let projectileImpacts: [Explosion]
    /// Enemies caught in those landings.
    let projectileHits: [EnemyHit]
    /// Every bolt's travel this turn.
    let boltFlights: [BoltFlight]
    /// Reinforcements that arrived (or were blocked) this turn.
    let spawns: [SpawnEvent]
    /// Fresh barrels that dropped in this turn (blocked deliveries just vanish).
    let barrelSpawns: [GridPosition]
    /// The weapon the player picked up this turn, if any.
    let pickedUpWeapon: Weapon?
    /// Set when the score crossed a threshold: the level reached. The board has
    /// been fully regenerated (the scene should rebuild its entities) and
    /// `pendingBuffChoices` holds the boons awaiting the player's pick.
    let leveledUpTo: Int?
    /// Enemies that died this turn (any cause), for combo callouts.
    let killsThisTurn: Int
    /// The kill streak after this turn's update.
    let killStreak: Int
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
    // Wave cadence and size live in LevelConfig and ramp with the level.
    /// Points for a kill, however it dies.
    static let killScore = 10
    /// Extra points per kill already banked this turn (multi-kills escalate:
    /// 10, 15, 20…).
    static let comboKillBonus = 5
    /// Extra points per kill for each consecutive prior turn with a kill.
    static let streakKillBonus = 5
    /// Damage the ultimate deals to every enemy on the board. High enough to
    /// wipe today's roster; a beefier future enemy would crawl away bloodied.
    static let ultimateDamage = 5
    /// Kills needed to charge the ultimate. Its own smite kills don't count
    /// toward the next charge.
    static let ultimateChargeKills = 10
    /// Points for surviving a turn.
    static let survivalScore = 1
    /// Waves stop delivering fresh barrels while this many are on the board.
    static let barrelSpawnCap = 8
    /// A random weapon drops every this many turns…
    static let weaponDropInterval = 5
    /// …unless this many are already lying around.
    static let weaponDropCap = 3
    /// Once the floor has been at the weapon cap this many turns, the oldest
    /// drop expires.
    static let weaponExpiryTurns = 3

    /// Score needed to reach a level: 100 for level 2, 300 for 3, 600 for 4…
    /// (Tetris-style widening gaps).
    static func scoreThreshold(forLevel level: Int) -> Int {
        100 * (level - 1) * level / 2
    }

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
    private(set) var level = 1
    /// Consecutive turns (before this one) that scored at least one kill.
    private(set) var killStreak = 0
    /// Kills banked so far during the current resolve; drives combo bonuses.
    private var killsThisTurn = 0
    /// Boon options awaiting the player's pick after a level-up; planning is
    /// paused while this is non-empty.
    private(set) var pendingBuffChoices: [Buff] = []
    /// Boons collected on level-ups, each with its own remaining lifetime;
    /// stackable buffs may appear multiple times.
    private(set) var heldBuffs: [HeldBuff] = []
    /// The buff effects currently applying to the player.
    var buffs: [Buff] { heldBuffs.map(\.buff) }
    /// Health can never regrow past this (set from the starting health).
    let maxHealth: Int
    /// Tiles where next turn's reinforcements will appear; telegraphed during
    /// planning. Anyone standing on one blocks that spawn but takes 1 damage.
    private(set) var pendingSpawns: [GridPosition] = []
    /// Tiles where next turn's fresh barrels drop; telegraphed during planning.
    /// Standing on one blocks the delivery harmlessly.
    private(set) var pendingBarrelSpawns: [GridPosition] = []
    private(set) var weaponDrops: [WeaponDrop] = []
    /// True when the player has drafted picking up the weapon underfoot.
    private(set) var plannedPickup = false
    /// True when the player has drafted the ultimate for this turn.
    private(set) var plannedUltimate = false
    /// Kills banked toward the ultimate; it fires once this reaches
    /// ultimateChargeKills.
    private(set) var ultimateKillCharge = 0
    /// Lobbed shots currently in the air, impact zones telegraphed.
    private(set) var projectiles: [Projectile] = []
    /// Arrows and cannonballs currently traveling their lines.
    private(set) var bolts: [Bolt] = []
    private var nextEnemyID = 0
    private var nextObstacleID = 0
    private var nextDropID = 0
    private var nextProjectileID = 0
    private var turnsAtWeaponCap = 0

    /// How many tiles the player may move per turn: the equipped weapon's range
    /// plus any buff bonuses.
    var moveRange: Int { equippedWeapon.moveRange + buffs.reduce(0) { $0 + $1.bonusMoveRange } }
    /// Damage the player's attacks deal: the equipped weapon's plus buff bonuses.
    var attackDamage: Int { equippedWeapon.damage + buffs.reduce(0) { $0 + $1.bonusDamage } }
    /// The armor ceiling right now: the base cap plus buff bonuses.
    var armorCap: Int { maxArmor + buffs.reduce(0) { $0 + $1.bonusArmor } }
    var isGameOver: Bool { playerHealth <= 0 }

    /// Where a drafted attack or throw would originate right now.
    var attackOrigin: GridPosition { plannedTarget ?? playerPosition }

    /// Turns before the given carried weapon can attack again; 0 means ready.
    func attackCooldownRemaining(of weapon: Weapon) -> Int {
        weaponCooldowns[weapon.name] ?? 0
    }

    var canAttack: Bool { attackCooldownRemaining(of: equippedWeapon) == 0 }

    /// True when the current draft earns the dodge: no attack or throw drafted,
    /// no weapon pickup, and a move of at least dodgeDistance tiles.
    var plannedDodgeReady: Bool {
        guard plannedAttackDirection == nil, plannedThrowTarget == nil, !plannedPickup,
              !plannedUltimate, let target = plannedTarget else { return false }
        return playerPosition.distance(to: target) >= Self.dodgeDistance
    }

    /// The on-board tiles the drafted attack hits right away: the directional
    /// sweep, the throw's blast, or — for bolt weapons — just the first flight
    /// window. Empty when nothing is drafted.
    var plannedAttackTiles: [GridPosition] {
        if let target = plannedThrowTarget, let thrown = equippedWeapon.thrown {
            return blastTiles(around: target, radius: thrown.blastRadius, includeCenter: true)
        }
        let full = plannedSweep()
        if let speed = equippedWeapon.projectileSpeed {
            return Array(full.prefix(speed))
        }
        return full
    }

    /// The rest of a drafted bolt's trajectory — tiles it only reaches on later
    /// turns; empty for instant weapons.
    var plannedAttackLaterTiles: [GridPosition] {
        guard let speed = equippedWeapon.projectileSpeed else { return [] }
        return Array(plannedSweep().dropFirst(speed))
    }

    private func plannedSweep() -> [GridPosition] {
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
        self.maxHealth = playerHealth
        // MARK: - Temp
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
        self.nextObstacleID = (self.obstacles.map(\.id).max() ?? -1) + 1
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

    func weaponDrop(at position: GridPosition) -> WeaponDrop? {
        weaponDrops.first { $0.position == position }
    }

    func lingeringEffect(at position: GridPosition) -> LingeringEffect? {
        lingeringEffects.first { $0.position == position }
    }

    /// Every tile threatened by something in the air: lob impact zones plus
    /// each bolt's next stretch of travel.
    var projectileThreatTiles: [GridPosition] {
        let lobZones = projectiles.flatMap {
            blastTiles(around: $0.target, radius: $0.blastRadius, includeCenter: true)
        }
        return lobZones + bolts.flatMap(boltPath)
    }

    /// The soonest-landing shell whose blast covers the given tile, if any.
    func projectileImpact(at tile: GridPosition) -> Projectile? {
        projectiles
            .filter { blastTiles(around: $0.target, radius: $0.blastRadius, includeCenter: true).contains(tile) }
            .min { $0.turnsUntilImpact < $1.turnsUntilImpact }
    }

    /// The bolt whose next advancement crosses the given tile, if any.
    func bolt(threatening tile: GridPosition) -> Bolt? {
        bolts.first { boltPath($0).contains(tile) }
    }

    /// The bolt currently sitting on the given tile, if any.
    func bolt(at tile: GridPosition) -> Bolt? {
        bolts.first { $0.position == tile }
    }

    /// Fractional board coordinates of a lob's bead: always partway between
    /// thrower and target, never sitting on either.
    func lobBeadCoordinates(of shell: Projectile) -> (x: Double, y: Double) {
        let total = Double(max(shell.totalFlightTurns, 1))
        let elapsed = total - Double(shell.turnsUntilImpact)
        let progress = (elapsed + 0.5) / total
        return (
            Double(shell.origin.x) + Double(shell.target.x - shell.origin.x) * progress,
            Double(shell.origin.y) + Double(shell.target.y - shell.origin.y) * progress
        )
    }

    /// The airborne lob whose bead is visually over the given tile, if any.
    func lobShell(over tile: GridPosition) -> Projectile? {
        projectiles.first { shell in
            let coordinates = lobBeadCoordinates(of: shell)
            return GridPosition(x: Int(coordinates.x.rounded()), y: Int(coordinates.y.rounded())) == tile
        }
    }

    /// The tiles a bolt will cross on its next advancement: up to `speed` tiles
    /// ahead, stopping at walls and the board edge (bodies don't shorten the
    /// telegraph — they might move). The scene renders the bolt at this path's
    /// far end.
    func boltPath(_ bolt: Bolt) -> [GridPosition] {
        var tiles: [GridPosition] = []
        var position = bolt.position
        let step = bolt.direction.unitStep
        var travel = min(bolt.speed, bolt.remainingRange)
        while travel > 0 {
            position = GridPosition(x: position.x + step.x, y: position.y + step.y)
            guard contains(position), obstacle(at: position)?.kind != .wall else { break }
            tiles.append(position)
            if obstacle(at: position) != nil {
                break // a barrel would stop (and detonate on) the bolt
            }
            travel -= 1
        }
        return tiles
    }

    /// The weapon the drafted pickup would grab (the one underfoot), if a
    /// pickup is drafted.
    var plannedPickupWeapon: Weapon? {
        plannedPickup ? weaponDrop(at: playerPosition)?.weapon : nil
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
        plannedPickup = false
        plannedUltimate = false
    }

    /// Stores the player's chosen destination without moving yet. A drafted
    /// throw that the new origin can no longer reach is cleared.
    /// Returns false if the target is not a legal move.
    @discardableResult
    mutating func planMove(to target: GridPosition) -> Bool {
        guard !isGameOver, pendingBuffChoices.isEmpty, legalMoveTargets().contains(target) else { return false }
        plannedTarget = target
        if let throwTarget = plannedThrowTarget, !throwTargets().contains(throwTarget) {
            plannedThrowTarget = nil
        }
        return true
    }

    /// Drafts picking up the weapon underfoot; it spends this turn's attack and
    /// dodge, though the drafted move still happens. Fails when not standing on
    /// a drop.
    @discardableResult
    mutating func planPickup() -> Bool {
        guard !isGameOver, pendingBuffChoices.isEmpty, weaponDrop(at: playerPosition) != nil else { return false }
        plannedPickup = true
        plannedAttackDirection = nil
        plannedThrowTarget = nil
        plannedUltimate = false
        return true
    }

    mutating func clearPlannedPickup() {
        plannedPickup = false
    }

    /// Drafts the ultimate: a board-wide smite that replaces this turn's attack
    /// (the drafted move still happens). Fails while recharging.
    @discardableResult
    mutating func planUltimate() -> Bool {
        guard !isGameOver, pendingBuffChoices.isEmpty,
              ultimateKillCharge >= Self.ultimateChargeKills else { return false }
        plannedUltimate = true
        plannedAttackDirection = nil
        plannedThrowTarget = nil
        plannedPickup = false
        return true
    }

    mutating func clearPlannedUltimate() {
        plannedUltimate = false
    }

    /// Drafts the equipped weapon's attack toward/at the given tile: directional
    /// weapons face the tile, thrown weapons land on it (so the tile must be in
    /// range). Fails when the weapon is on cooldown or the tile is the origin
    /// itself.
    @discardableResult
    mutating func planAttack(toward tile: GridPosition) -> Bool {
        guard !isGameOver, pendingBuffChoices.isEmpty, canAttack else { return false }
        if equippedWeapon.thrown != nil {
            guard throwTargets().contains(tile) else { return false }
            plannedThrowTarget = tile
            plannedAttackDirection = nil
            plannedPickup = false
            plannedUltimate = false
            return true
        }
        guard let direction = Direction.aiming(
            from: attackOrigin,
            toward: tile,
            allowDiagonals: equippedWeapon.attackPattern?.supportsDiagonals ?? false
        ) else { return false }
        plannedAttackDirection = direction
        plannedThrowTarget = nil
        plannedPickup = false
        plannedUltimate = false
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
        killsThisTurn = 0

        // A drafted pickup swaps the weapon underfoot (at the tile the player is
        // leaving from) with the equipped one; the old weapon stays on that tile.
        // The pickup spent the attack, and the dodge won't arm below — but the
        // drafted move still happens.
        var pickedUp: Weapon?
        if plannedPickup,
           let dropIndex = weaponDrops.firstIndex(where: { $0.position == playerStart }) {
            let drop = weaponDrops[dropIndex]
            pickedUp = drop.weapon
            weaponDrops[dropIndex] = WeaponDrop(id: nextDropID, weapon: equippedWeapon, position: drop.position)
            nextDropID += 1
            equippedWeapon = drop.weapon
        }
        plannedPickup = false

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

        // Airborne shells descend; those reaching the ground detonate now, after
        // everyone has moved — a shell in the air can't be stopped, only dodged
        // by not standing in its telegraphed zone.
        var projectileImpacts: [TurnResolution.Explosion] = []
        var projectileHits: [TurnResolution.EnemyHit] = []
        for index in projectiles.indices {
            projectiles[index].turnsUntilImpact -= 1
        }
        let landing = projectiles.filter { $0.turnsUntilImpact <= 0 }
        projectiles.removeAll { $0.turnsUntilImpact <= 0 }
        for shell in landing {
            let blast = blastTiles(around: shell.target, radius: shell.blastRadius, includeCenter: true)
            let blastSet = Set(blast)
            projectileImpacts.append(TurnResolution.Explosion(center: shell.target, tiles: blast))
            projectileHits += damageEnemies(on: blastSet, damage: shell.damage)
            if !isGameOver && blastSet.contains(playerPosition) {
                let reduction = buffs.reduce(0) { $0 + $1.rangedDamageReduction }
                applyDamage(max(0, shell.damage - reduction))
            }
            let chained = detonateBarrels(struckTiles: blastSet)
            projectileImpacts += chained.explosions
            projectileHits += chained.hits
            if let lingering = shell.lingering {
                addLingeringEffect(at: blast, damagePerTurn: lingering.damagePerTurn, duration: lingering.duration)
            }
        }

        // Bolts already in the air fly their next stretch, striking whatever
        // stands in the way.
        var boltFlights: [TurnResolution.BoltFlight] = []
        let airborne = bolts
        bolts = []
        for bolt in airborne {
            if let survivor = fly(bolt, impacts: &projectileImpacts, hits: &projectileHits, flights: &boltFlights) {
                bolts.append(survivor)
            }
        }

        var attackTiles: [GridPosition] = []
        var playerPhaseHits: [TurnResolution.EnemyHit] = []
        var playerExplosions: [TurnResolution.Explosion] = []
        var didAttack = false

        // The ultimate smites every enemy on the board at once, wherever they
        // ended up after moving.
        var ultimateTiles: [GridPosition] = []
        let ultimateFired = plannedUltimate
        if ultimateFired {
            ultimateTiles = enemies.map(\.position)
            ultimateKillCharge -= Self.ultimateChargeKills
            playerPhaseHits += damageEnemies(on: Set(ultimateTiles), damage: Self.ultimateDamage, chargesUltimate: false)
        }
        plannedUltimate = false
        if let direction = plannedAttackDirection, let pattern = equippedWeapon.attackPattern {
            didAttack = true
            if let speed = equippedWeapon.projectileSpeed {
                // The shot becomes a traveling bolt: it flies its first window
                // right now, then keeps going in later turns' projectile phases.
                let shot = Bolt(
                    id: nextProjectileID,
                    position: playerPosition,
                    direction: direction,
                    speed: speed,
                    remainingRange: pattern.tiles(from: playerPosition, facing: direction).count,
                    damage: attackDamage,
                    pierces: equippedWeapon.pierces,
                    impactBlastRadius: equippedWeapon.impactBlastRadius,
                    lingering: equippedWeapon.lingering
                )
                nextProjectileID += 1
                if let survivor = fly(shot, impacts: &projectileImpacts, hits: &projectileHits, flights: &boltFlights) {
                    bolts.append(survivor)
                }
            } else {
                attackTiles = sweep(
                    pattern,
                    from: playerPosition,
                    facing: direction,
                    pierces: equippedWeapon.pierces,
                    blockers: Set(enemies.map(\.position))
                )
            }
        } else if let target = plannedThrowTarget, let thrown = equippedWeapon.thrown {
            didAttack = true
            if thrown.flightTurns > 0 {
                // The shot goes airborne instead of landing this turn.
                projectiles.append(Projectile(
                    id: nextProjectileID,
                    origin: playerPosition,
                    target: target,
                    blastRadius: thrown.blastRadius,
                    damage: attackDamage,
                    lingering: equippedWeapon.lingering,
                    totalFlightTurns: thrown.flightTurns,
                    turnsUntilImpact: thrown.flightTurns
                ))
                nextProjectileID += 1
            } else {
                attackTiles = blastTiles(around: target, radius: thrown.blastRadius, includeCenter: true)
            }
        }
        if didAttack && !attackTiles.isEmpty {
            let struck = Set(attackTiles)
            playerPhaseHits += damageEnemies(on: struck, damage: attackDamage)
            // A lobbed blast has no friendly immunity: catch yourself, hurt yourself.
            if equippedWeapon.thrown != nil && !isGameOver && struck.contains(playerPosition) {
                applyDamage(attackDamage)
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

        // Moving far without attacking (or grabbing a weapon) earns one dodge:
        // the first enemy hit this turn misses.
        var dodgeCharges = (!didAttack && pickedUp == nil && !ultimateFired
            && playerStart.distance(to: playerPosition) >= Self.dodgeDistance) ? 1 : 0

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
            // Indexed bookkeeping happens before the attack: firing a bolt can
            // kill enemies mid-flight (even the attacker, via a barrel burst),
            // which would leave attackerIndex stale.
            enemies[attackerIndex].plannedDirection = nil
            enemies[attackerIndex].plannedThrowTarget = nil
            enemies[attackerIndex].cooldownRemaining = attacker.weapon.cooldown

            var tiles: [GridPosition] = []
            var throwerIncluded = false
            if let direction = attacker.plannedDirection, let pattern = attacker.weapon.attackPattern {
                if let speed = attacker.weapon.projectileSpeed {
                    // The shot becomes a traveling bolt, flying its first window
                    // immediately; nothing is swept in place this turn.
                    let shot = Bolt(
                        id: nextProjectileID,
                        position: attacker.position,
                        direction: direction,
                        speed: speed,
                        remainingRange: pattern.tiles(from: attacker.position, facing: direction).count,
                        damage: attacker.damage,
                        pierces: attacker.weapon.pierces,
                        impactBlastRadius: attacker.weapon.impactBlastRadius,
                        lingering: attacker.weapon.lingering
                    )
                    nextProjectileID += 1
                    if let survivor = fly(shot, impacts: &projectileImpacts, hits: &projectileHits, flights: &boltFlights) {
                        bolts.append(survivor)
                    }
                } else {
                    var blockers = Set(enemies.filter { $0.id != attackerID }.map(\.position))
                    blockers.insert(playerPosition)
                    tiles = sweep(pattern, from: attacker.position, facing: direction, pierces: attacker.weapon.pierces, blockers: blockers)
                }
            } else if let target = attacker.plannedThrowTarget, let thrown = attacker.weapon.thrown {
                if thrown.flightTurns > 0 {
                    // The lob goes airborne; its zone is telegraphed until it lands.
                    projectiles.append(Projectile(
                        id: nextProjectileID,
                        origin: attacker.position,
                        target: target,
                        blastRadius: thrown.blastRadius,
                        damage: attacker.damage,
                        lingering: attacker.weapon.lingering,
                        totalFlightTurns: thrown.flightTurns,
                        turnsUntilImpact: thrown.flightTurns
                    ))
                    nextProjectileID += 1
                    // tiles stays empty: nothing swept this turn.
                } else {
                    tiles = blastTiles(around: target, radius: thrown.blastRadius, includeCenter: true)
                    throwerIncluded = true
                }
            } else {
                continue
            }

            let struck = Set(tiles)
            var hitsPlayer = !isGameOver && struck.contains(playerPosition)
            var dodged = false
            if hitsPlayer && dodgeCharges > 0 {
                dodgeCharges -= 1
                dodged = true
                hitsPlayer = false
            }
            if hitsPlayer {
                // Buffs blunt incoming weapon hits (but never below zero).
                let reduction = buffs.reduce(0) {
                    $0 + (attacker.weapon.isMelee ? $1.meleeDamageReduction : $1.rangedDamageReduction)
                }
                applyDamage(max(0, attacker.damage - reduction))
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
            if !isGameOver && effect.position == playerPosition && !buffs.contains(where: \.hazardImmunity) {
                applyDamage(effect.damagePerTurn)
            }
            lingeringEffects[index].turnsRemaining -= 1
        }
        lingeringEffects.removeAll { $0.turnsRemaining <= 0 }

        // Fresh barrels drop first; a blocked delivery is simply lost.
        var barrelSpawns: [GridPosition] = []
        for tile in pendingBarrelSpawns {
            let blocked = tile == playerPosition
                || enemies.contains { $0.position == tile }
                || obstacle(at: tile) != nil
            if !blocked {
                obstacles.append(Obstacle(id: nextObstacleID, kind: .barrel, position: tile))
                nextObstacleID += 1
                barrelSpawns.append(tile)
            }
        }
        pendingBarrelSpawns = []

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
            if undamagedTurns.isMultiple(of: 2) && playerArmor < armorCap {
                playerArmor += 1
            }
        }

        for name in weaponCooldowns.keys {
            weaponCooldowns[name] = max(0, (weaponCooldowns[name] ?? 0) - 1)
        }
        if didAttack {
            weaponCooldowns[equippedWeapon.name] = equippedWeapon.cooldown
        }

        // The streak extends on any turn with a kill and snaps on a dry one.
        killStreak = killsThisTurn > 0 ? killStreak + 1 : 0

        turnNumber += 1
        if !isGameOver {
            score += Self.survivalScore
        }

        // Tetris-style ramp: crossing the score threshold regenerates the whole
        // board at the next difficulty and offers a choice of boons. The fresh
        // board gets a scheduling grace turn.
        var leveledUpTo: Int?
        if !isGameOver && score >= Self.scoreThreshold(forLevel: level + 1) {
            advanceLevel()
            leveledUpTo = level
        } else {
            scheduleSpawns()
            spawnWeaponDrop()
            expireWeaponDrops()
        }

        draftEnemyPlans()

        return TurnResolution(
            playerDestination: playerPosition,
            attackTiles: attackTiles,
            ultimateTiles: ultimateTiles,
            enemyHits: playerPhaseHits,
            playerExplosions: playerExplosions,
            enemyMoves: moves,
            enemyAttacks: enemyAttacks,
            friendlyFireHits: friendlyFireHits,
            enemyExplosions: enemyExplosions,
            hazardHits: hazardHits,
            projectileImpacts: projectileImpacts,
            projectileHits: projectileHits,
            boltFlights: boltFlights,
            spawns: spawns,
            barrelSpawns: barrelSpawns,
            pickedUpWeapon: pickedUp,
            leveledUpTo: leveledUpTo,
            killsThisTurn: killsThisTurn,
            killStreak: killStreak,
            healthLost: healthBefore - playerHealth,
            armorLost: max(0, armorBefore - playerArmor),
            playerHealth: playerHealth,
            playerArmor: playerArmor
        )
    }

    /// Damages every enemy standing on the given tiles and removes the dead.
    /// Returns the hits for animation.
    private mutating func damageEnemies(on tiles: Set<GridPosition>, damage: Int, chargesUltimate: Bool = true) -> [TurnResolution.EnemyHit] {
        var hits: [TurnResolution.EnemyHit] = []
        for index in enemies.indices where tiles.contains(enemies[index].position) {
            enemies[index].health -= damage
            let died = enemies[index].health <= 0
            if died {
                // Kills escalate within a turn and ride the multi-turn streak.
                score += Self.killScore
                    + Self.comboKillBonus * killsThisTurn
                    + Self.streakKillBonus * killStreak
                killsThisTurn += 1
                if chargesUltimate {
                    ultimateKillCharge += 1
                }
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

    /// Advances to the next level: the board fully regenerates at the new
    /// difficulty (fresh enemies, obstacles, and floor — the player keeps
    /// position, health, armor, loadout, and score) and two boons are drawn for
    /// the player to choose between; play pauses until `chooseBuff` is called.
    private mutating func advanceLevel() {
        level += 1
        let config = LevelConfig.forLevel(level)

        lingeringEffects = []
        weaponDrops = []
        pendingSpawns = []
        pendingBarrelSpawns = []
        projectiles = []
        bolts = []
        turnsAtWeaponCap = 0

        var fresh: [Enemy] = []
        for tile in edgeTiles().shuffled() where fresh.count < config.startingEnemies {
            guard tile.distance(to: playerPosition) > 3 else { continue }
            fresh.append(Enemy(id: nextEnemyID, position: tile))
            nextEnemyID += 1
        }
        enemies = fresh

        obstacles = Self.scatterObstacles(
            columns: columns,
            rows: rows,
            walls: config.walls,
            barrels: config.barrels,
            keepClear: Set(enemies.map(\.position)),
            playerStart: playerPosition
        )
        nextObstacleID = max(nextObstacleID, (obstacles.map(\.id).max() ?? -1) + 1)

        // Held buffs age by one level and expired ones wear off; then a new boon
        // is granted. Non-stackable buffs leave the pool while owned.
        for index in heldBuffs.indices {
            if let remaining = heldBuffs[index].levelsRemaining {
                heldBuffs[index].levelsRemaining = remaining - 1
            }
        }
        heldBuffs.removeAll { ($0.levelsRemaining ?? 1) <= 0 }
        // Armor above a shrunken cap (an expired armor buff) falls off.
        playerArmor = min(playerArmor, armorCap)

        // Draw the boon options; play pauses until the player picks one.
        let pool = Buff.all.filter { $0.stackable || !buffs.contains($0) }
        pendingBuffChoices = Array(pool.shuffled().prefix(2))
        if pendingBuffChoices.isEmpty {
            pendingBuffChoices = [.secondWind]
        }
    }

    /// Applies the picked boon and resumes play.
    mutating func chooseBuff(at index: Int) {
        guard pendingBuffChoices.indices.contains(index) else { return }
        let buff = pendingBuffChoices[index]
        pendingBuffChoices = []
        if !buff.isInstantOnly {
            heldBuffs.append(HeldBuff(buff: buff, levelsRemaining: buff.levelDuration))
        }
        // Instant effects apply after the buff is held, so a buff combining
        // bonusArmor with instantArmorRepair fills to its own raised cap.
        playerHealth = min(maxHealth, playerHealth + buff.instantHeal)
        playerArmor = min(armorCap, playerArmor + buff.instantArmorRepair)
    }

    /// Every tile on the board's rim.
    private func edgeTiles() -> [GridPosition] {
        var edges: [GridPosition] = []
        for x in 0..<columns {
            edges.append(GridPosition(x: x, y: 0))
            edges.append(GridPosition(x: x, y: rows - 1))
        }
        for y in 1..<(rows - 1) {
            edges.append(GridPosition(x: 0, y: y))
            edges.append(GridPosition(x: columns - 1, y: y))
        }
        return edges
    }

    /// Picks the next wave's telegraphed arrivals: enemies on random open edge
    /// tiles a safe distance from the player (cadence and batch size set by the
    /// level), plus one fresh barrel anywhere open while under the cap — so
    /// there's always new powder to blow the reinforcements up with.
    private mutating func scheduleSpawns() {
        pendingSpawns = []
        pendingBarrelSpawns = []
        let config = LevelConfig.forLevel(level)
        guard turnNumber % config.spawnInterval == 0 else { return }

        let taken = Set(enemies.map(\.position))
            .union(obstacles.map(\.position))
            .union(lingeringEffects.map(\.position))
        let candidates = edgeTiles().filter {
            !taken.contains($0) && $0.distance(to: playerPosition) > 3
        }
        pendingSpawns = Array(candidates.shuffled().prefix(config.spawnBatch))

        guard obstacles.filter({ $0.kind == .barrel }).count < Self.barrelSpawnCap else { return }
        var open: [GridPosition] = []
        for x in 0..<columns {
            for y in 0..<rows {
                let tile = GridPosition(x: x, y: y)
                if !taken.contains(tile)
                    && !pendingSpawns.contains(tile)
                    && tile.distance(to: playerPosition) > 2 {
                    open.append(tile)
                }
            }
        }
        if let drop = open.randomElement() {
            pendingBarrelSpawns = [drop]
        }
    }

    /// Every few turns a random weapon appears on an open tile (up to a cap),
    /// so the player can trade their loadout mid-run.
    private mutating func spawnWeaponDrop() {
        guard turnNumber % Self.weaponDropInterval == 0,
              weaponDrops.count < Self.weaponDropCap else { return }
        let taken = Set(enemies.map(\.position))
            .union(obstacles.map(\.position))
            .union(lingeringEffects.map(\.position))
            .union(weaponDrops.map(\.position))
            .union(pendingSpawns)
            .union(pendingBarrelSpawns)
            .union([playerPosition])
        var open: [GridPosition] = []
        for x in 0..<columns {
            for y in 0..<rows {
                let tile = GridPosition(x: x, y: y)
                if !taken.contains(tile) && tile.distance(to: playerPosition) > 1 {
                    open.append(tile)
                }
            }
        }
        guard let tile = open.randomElement() else { return }
        weaponDrops.append(WeaponDrop(id: nextDropID, weapon: Weapon.all.randomElement()!, position: tile))
        nextDropID += 1
    }

    /// Once the floor has sat at the weapon cap for a few turns, the oldest
    /// drop crumbles away so fresh ones keep coming.
    private mutating func expireWeaponDrops() {
        guard weaponDrops.count >= Self.weaponDropCap else {
            turnsAtWeaponCap = 0
            return
        }
        turnsAtWeaponCap += 1
        if turnsAtWeaponCap >= Self.weaponExpiryTurns {
            turnsAtWeaponCap = 0
            if let oldest = weaponDrops.indices.min(by: { weaponDrops[$0].id < weaponDrops[$1].id }) {
                weaponDrops.remove(at: oldest)
            }
        }
    }

    /// Flies a bolt through one window of travel (up to its speed): it strikes
    /// bodies it meets, detonates barrels, dies against walls and the board
    /// edge, and records the flight for animation. Returns the bolt if it's
    /// still airborne afterward.
    private mutating func fly(
        _ bolt: Bolt,
        impacts: inout [TurnResolution.Explosion],
        hits: inout [TurnResolution.EnemyHit],
        flights: inout [TurnResolution.BoltFlight]
    ) -> Bolt? {
        var bolt = bolt
        let flightStart = bolt.position
        var steps = min(bolt.speed, bolt.remainingRange)
        var alive = true
        let step = bolt.direction.unitStep
        while steps > 0 && alive {
            let next = GridPosition(x: bolt.position.x + step.x, y: bolt.position.y + step.y)
            guard contains(next) else {
                alive = false
                break
            }
            if let obstacle = obstacle(at: next) {
                if obstacle.kind == .barrel {
                    let chained = detonateBarrels(struckTiles: [next])
                    impacts += chained.explosions
                    hits += chained.hits
                }
                alive = false
                break
            }
            bolt.position = next
            bolt.remainingRange -= 1
            steps -= 1

            // A lingering payload paints every tile the bolt passes through —
            // a burning/poisoned trail in its wake.
            if let lingering = bolt.lingering {
                addLingeringEffect(at: [next], damagePerTurn: lingering.damagePerTurn, duration: lingering.duration)
            }

            let struckSomething = (next == playerPosition && !isGameOver)
                || enemies.contains { $0.position == next }
            if struckSomething {
                if bolt.impactBlastRadius > 0 {
                    // Detonating shells stop here; the blast below does the damage.
                    alive = false
                } else {
                    if next == playerPosition {
                        let reduction = buffs.reduce(0) { $0 + $1.rangedDamageReduction }
                        applyDamage(max(0, bolt.damage - reduction))
                    } else {
                        hits += damageEnemies(on: [next], damage: bolt.damage)
                    }
                    impacts.append(TurnResolution.Explosion(center: next, tiles: [next]))
                    if !bolt.pierces {
                        alive = false
                    }
                }
            }
        }

        let spent = !(alive && bolt.remainingRange > 0)
        if spent && bolt.impactBlastRadius > 0 {
            // The shell bursts wherever its flight ended — on a victim, against
            // scenery, or falling at max range.
            let blast = blastTiles(around: bolt.position, radius: bolt.impactBlastRadius, includeCenter: true)
            let blastSet = Set(blast)
            impacts.append(TurnResolution.Explosion(center: bolt.position, tiles: blast))
            hits += damageEnemies(on: blastSet, damage: bolt.damage)
            if !isGameOver && blastSet.contains(playerPosition) {
                let reduction = buffs.reduce(0) { $0 + $1.rangedDamageReduction }
                applyDamage(max(0, bolt.damage - reduction))
            }
            let chained = detonateBarrels(struckTiles: blastSet)
            impacts += chained.explosions
            hits += chained.hits
            if let lingering = bolt.lingering {
                addLingeringEffect(at: blast, damagePerTurn: lingering.damagePerTurn, duration: lingering.duration)
            }
        }

        flights.append(TurnResolution.BoltFlight(
            boltID: bolt.id,
            from: flightStart,
            to: bolt.position,
            direction: bolt.direction
        ))
        return spent ? nil : bolt
    }

    /// The tiles an attack actually covers, in authored order: clipped to the
    /// board, stopped dead by walls (which can't be hit), and truncated just
    /// after the first blocker or barrel when the weapon doesn't pierce.
    private func sweep(_ pattern: AttackPattern, from origin: GridPosition, facing direction: Direction, pierces: Bool, blockers: Set<GridPosition>) -> [GridPosition] {
        var result: [GridPosition] = []
        for tile in pattern.tiles(from: origin, facing: direction) where contains(tile) {
            let obstacle = obstacle(at: tile)
            if obstacle?.kind == .wall {
                // A wall stops a thrust dead, but a shaped swing just can't hit
                // the wall tile itself — it sweeps around it.
                if pattern.isLine {
                    break
                }
                continue
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
            if !isGameOver && blastSet.contains(playerPosition) && !buffs.contains(where: \.barrelImmunity) {
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
        let hazardTiles = Set(lingeringEffects.map(\.position))
        // Telegraphed danger: tiles taking a hit next turn (landing shells, bolt
        // paths, arriving reinforcements). Enemies won't step into them — or
        // into lingering pools — so both count as blocked for pathing.
        let incomingTiles = Set(projectileThreatTiles).union(pendingSpawns)
        var claimed = Set(enemies.map(\.position))
            .union(obstacles.map(\.position))
            .union(hazardTiles)
            .union(incomingTiles)
            .union([playerPosition])
        for index in enemies.indices {
            let enemy = enemies[index]
            let ready = enemy.cooldownRemaining == 0

            // An enemy standing somewhere that burns or is about to be hit
            // repositions even if it could attack from here.
            let inDanger = hazardTiles.contains(enemy.position) || incomingTiles.contains(enemy.position)
            var target = enemy.position
            if !canHitPlayer(enemy, from: enemy.position) || inDanger {
                let goal = attackGoal(for: enemy, avoiding: claimed)
                for _ in 0..<enemy.weapon.moveRange {
                    var next = stepToward(goal, from: target, avoiding: claimed)
                    if next == target && (hazardTiles.contains(target) || incomingTiles.contains(target)) {
                        // Trapped inside a pool or a telegraphed blast with no
                        // clean exit: wading through danger toward the rim beats
                        // standing at ground zero.
                        next = stepToward(
                            goal,
                            from: target,
                            avoiding: claimed.subtracting(hazardTiles).subtracting(incomingTiles)
                        )
                    }
                    if next == target {
                        break
                    }
                    target = next
                    let safeHere = !hazardTiles.contains(target) && !incomingTiles.contains(target)
                    if canHitPlayer(enemy, from: target) && safeHere {
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
