//
//  TurnResolution.swift
//  Foretold
//

import Foundation

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
        /// A shieldbearer that raised its shield into this hit: no damage dealt,
        /// shown as a parry rather than a flinch.
        var blocked = false
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
    /// Explosions from that late phase (bombers dying to hazards, etc.).
    let hazardExplosions: [Explosion]
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
