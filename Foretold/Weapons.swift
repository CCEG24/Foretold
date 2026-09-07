//
//  Weapons.swift
//  Foretold
//

import Foundation

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
    /// True for swings that wrap all the way around the attacker (rings and
    /// circles, and the hammer's full surround): they have no meaningful front
    /// or back, so they slip past a shieldbearer's guard and never backstab.
    let isRadial: Bool

    init(offsets: [GridPosition], diagonalOffsets: [GridPosition]? = nil, isLine: Bool = false, isRadial: Bool = false) {
        self.offsets = offsets
        self.diagonalOffsets = diagonalOffsets
        self.isLine = isLine
        self.isRadial = isRadial
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
        return AttackPattern(offsets: offsets, diagonalOffsets: offsets, isRadial: true)
    }

    /// Every tile within `radius` of the attacker — a filled ring, i.e. a
    /// bigger hammer swing. radius 1 is exactly the 8 surrounding tiles.
    static func circle(radius: Int) -> AttackPattern {
        ring(from: 1, to: radius)
    }

    static let dagger = AttackPattern.line(length: 1)
    static let sword = AttackPattern(
        offsets: [
            GridPosition(x: 2, y: -1),
            GridPosition(x: 2, y: 0),
            GridPosition(x: 1, y: 0),
            GridPosition(x: 2, y: 1),
        ],
        diagonalOffsets: [
            GridPosition(x: 1, y: 1),
            GridPosition(x: 2, y: 2),
            GridPosition(x: 2, y: 1),
            GridPosition(x: 1, y: 2),
        ]
    )
    static let trident = AttackPattern(
        offsets: [
            GridPosition(x: 1, y: 0), GridPosition(x: 2, y: 0),
            GridPosition(x: 1, y: 1), GridPosition(x: 2, y: 2),
            GridPosition(x: 1, y: -1), GridPosition(x: 2, y: -2),
        ],
        diagonalOffsets: [
            GridPosition(x: 1, y: 1), GridPosition(x: 2, y: 2),
            GridPosition(x: 1, y: 0), GridPosition(x: 2, y: 0),
            GridPosition(x: 0, y: 1), GridPosition(x: 0, y: 2),
        ]
    )
    static let hammer = AttackPattern(
        offsets: [
            GridPosition(x: -1, y: -1), GridPosition(x: 0, y: -1), GridPosition(x: 1, y: -1),
            GridPosition(x: -1, y: 0), GridPosition(x: 1, y: 0),
            GridPosition(x: -1, y: 1), GridPosition(x: 0, y: 1), GridPosition(x: 1, y: 1),
        ],
        isRadial: true
    )
    static let pike = AttackPattern.line(length: 3)
    static let bow = AttackPattern.line(length: 10)
    static let crossbow = AttackPattern.line(length: 14)
    static let greataxe = AttackPattern.circle(radius: 2)
    static let scythe = AttackPattern.ring(from: 2, to: 2)
    static let explosiveCrossbow = AttackPattern.line(length: 14)
    static let hi = AttackPattern.circle(radius: 15)
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

    /// Damage over time stuck to whoever survives the hit (a bleed, a poison):
    /// the target takes `damagePerTurn` at the end of each of the next
    /// `duration` turns, wherever it goes. Re-applying refreshes the clock.
    struct Affliction: Equatable {
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
    /// Damage over time applied to struck survivors; nil for clean hits.
    let affliction: Affliction?
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
        lingering: Lingering? = nil,
        affliction: Affliction? = nil
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
        self.affliction = affliction
    }
}

extension Weapon {
    static let dagger = Weapon(name: "Dagger", moveRange: 3, damage: 2, enemyHealth: 4, attackPattern: .dagger)
    static let sword = Weapon(name: "Sword", moveRange: 2, damage: 2, enemyHealth: 4, attackPattern: .sword)
    static let hammer = Weapon(name: "Hammer", moveRange: 2, damage: 4, cooldown: 1, enemyHealth: 5, attackPattern: .hammer)
    static let pike = Weapon(name: "Pike", moveRange: 2, damage: 2, enemyHealth: 3, attackPattern: .pike)
    static let bow = Weapon(name: "Bow", moveRange: 2, damage: 2, pierces: false, cooldown: 1, enemyHealth: 2, isRanged: true, projectileSpeed: 5, attackPattern: .bow)
    static let tippedBow = Weapon(name: "Tipped Bow", moveRange: 2, damage: 1, pierces: false, cooldown: 1, enemyHealth: 2, isRanged: true, projectileSpeed: 5, attackPattern: .bow, lingering: Lingering(damagePerTurn: 1, duration: 2))
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
    static let explosiveCrossbow = Weapon(name: "Explosive Crossbow", moveRange: 1, damage: 1, pierces: false, cooldown: 2, enemyHealth: 2, isRanged: true, projectileSpeed: 5, impactBlastRadius: 1, attackPattern: .crossbow)
    static let serratedBow = Weapon(name: "Serrated Bow", moveRange: 2, damage: 1, pierces: true, cooldown: 1, enemyHealth: 2, isRanged: true, projectileSpeed: 5, attackPattern: .bow, affliction: Affliction(damagePerTurn: 1, duration: 2))
    static let trident = Weapon(name: "Trident", moveRange: 2, damage: 2, cooldown: 1, enemyHealth: 3, attackPattern: .trident)
    /// A dev-only toy: kept out of `all`, loot, and milestones, so it can only
    /// be handed out through the dev panel's weapon cycler.
    static let hi = Weapon(name: "Wrath of God", moveRange: 30, damage: 20, enemyHealth: 1, attackPattern: .hi)
    static let all: [Weapon] = [.dagger, .sword, .hammer, .pike, .bow, .crossbow, .grenade, .poisonPotion, .tippedBow, .greataxe, .scythe, .cannon, .explosiveCrossbow, .serratedBow, .trident]

    /// Weapons reachable only through the dev panel — the full arsenal plus the
    /// dev-only toys. Kept separate from `all` so these never leak into loot,
    /// the loadout draft, or milestone unlocks.
    static let devArsenal: [Weapon] = all + [.hi]

    /// Everything that can appear as floor loot, arm rank-and-file enemies, or
    /// seed the starting loadout. The cannon is boss-exclusive: it only enters
    /// a run as the boss's trophy drop.
    static let lootTable: [Weapon] = all.filter { $0.name != Weapon.cannon.name }

    /// Elite trophies: wielded by gatekeepers, absent from every pool until
    /// the player claims one off a fallen elite — from then on they join the
    /// loot of future runs.
    static let eliteTrophies: [Weapon] = [.greataxe, .cannon]

    /// What a brand-new profile starts with; the rest is earned.
    static let baseArsenal: [Weapon] = [.dagger, .sword, .bow]

    /// A lifetime-tally gate for one weapon: hit the count on its tally
    /// (kills with a weapon, barrel-chain kills, tiles moved…) and it joins
    /// future runs' loot.
    struct Milestone {
        let weapon: Weapon
        /// Key into the lifetime tallies (a weapon name, "Barrels", "TilesMoved"…).
        let tally: String
        let count: Int
        /// Human-readable unlock condition.
        let requirement: String
    }

    /// The unlock paths, a mix of weapon mastery and playstyle feats:
    /// kills teach the chains (Sword → Pike, Bow → Crossbow, Barrels →
    /// Grenade), while movement, combos, streaks, and dodges earn the rest.
    /// Elite trophies unlock by pickup.
    static let milestones: [Milestone] = [
        Milestone(weapon: .pike, tally: Weapon.sword.name, count: 10, requirement: "10 kills with the Sword"),
        Milestone(weapon: .hammer, tally: "ComboTurns", count: 5, requirement: "kill 3+ in a single turn, 5 times"),
        Milestone(weapon: .scythe, tally: "TilesMoved", count: 200, requirement: "move 200 tiles, lifetime"),
        Milestone(weapon: .crossbow, tally: Weapon.bow.name, count: 10, requirement: "10 kills with the Bow"),
        Milestone(weapon: .tippedBow, tally: "Streaks", count: 3, requirement: "reach a ×3 kill streak, 3 times"),
        Milestone(weapon: .grenade, tally: "Barrels", count: 10, requirement: "10 kills with exploding barrels"),
        Milestone(weapon: .poisonPotion, tally: "Dodges", count: 10, requirement: "dodge 10 attacks"),
        Milestone(weapon: .explosiveCrossbow, tally: Weapon.crossbow.name, count: 10, requirement: "10 kills with the Crossbow"),
        Milestone(weapon: .serratedBow, tally: "Focus", count: 5, requirement: "hit the same enemy 3 turns running, 5 times"),
        Milestone(weapon: .trident, tally: Weapon.pike.name, count: 10, requirement: "10 kills with the Pike")
    ]
}
