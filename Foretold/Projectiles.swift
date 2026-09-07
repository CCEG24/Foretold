//
//  Projectiles.swift
//  Foretold
//

import Foundation

/// A hazard burning on one tile for a few turns; anything standing there when
/// the turn resolves takes damage.
struct LingeringEffect {
    let position: GridPosition
    let damagePerTurn: Int
    /// Player-made pools charge the ultimate with their kills; enemy trails don't.
    let chargesUltimate: Bool
    /// Kill-tally key for player pools (the painting weapon); nil for enemies'.
    let creditName: String?
    var turnsRemaining: Int
    /// Freshly placed this turn; the first end-of-turn tick skips it so the
    /// hazard lasts its full duration after the attack that created it.
    var justPlaced = true
}

/// Damage over time riding on a struck target (a bleed, a poison): it ticks
/// at the end of each turn wherever the victim goes, keeping the ownership of
/// whoever inflicted it for scoring, charge, and milestone credit.
struct ActiveAffliction {
    let damagePerTurn: Int
    var turnsRemaining: Int
    /// Player-inflicted wounds charge the ultimate with their kills.
    let chargesUltimate: Bool
    /// Kill-tally key for the inflicting weapon; nil for enemy wounds.
    let credit: String?
    /// Inflicted this turn; the first end-of-turn tick skips it so the wound
    /// bleeds its full duration after the hit that opened it.
    var fresh = true
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
    /// Player-thrown shells charge the ultimate with their kills; enemy ones don't.
    let chargesUltimate: Bool
    let totalFlightTurns: Int
    var turnsUntilImpact: Int
    /// Who threw it — named in the death recap if it proves fatal.
    let sourceName: String
    /// Kill-tally key for player lobs (the weapon's name); nil for enemies.
    let creditName: String?
    /// Damage over time stuck to blast survivors, if the weapon afflicts.
    let affliction: Weapon.Affliction?
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
    /// Player-fired bolts charge the ultimate with their kills; enemy ones don't.
    let chargesUltimate: Bool
    /// Who fired it — named in the death recap if it proves fatal.
    let sourceName: String
    /// Kill-tally key for player shots (the weapon's name); nil for enemies.
    let creditName: String?
    /// Damage over time stuck to struck survivors, if the weapon afflicts.
    let affliction: Weapon.Affliction?
}
