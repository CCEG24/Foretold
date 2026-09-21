//
//  TurnResolution.swift
//  Foretold
//

/// Everything that happened during one resolve phase, so the scene can animate it.
struct TurnResolution {
    struct EnemyMove {
        let enemyID: Int
        let from: GridPosition
        let to: GridPosition
    }

    /// An enemy flung by a knockback weapon during the player's action, for the
    /// scene to slide it from `from` to `to` (any barrel it slammed into shows
    /// up in `playerExplosions`).
    struct Shove {
        let enemyID: Int
        let from: GridPosition
        let to: GridPosition
    }

    /// A barrel shoved (knockback) or reeled (grapple) to a new tile this turn,
    /// so the scene slides it there like any other mover before it detonates or
    /// settles.
    struct BarrelMove {
        let from: GridPosition
        let to: GridPosition
    }

    /// A mover warped between the ends of a teleporter this turn (nil id = the
    /// player), so the scene can pop it across rather than slide.
    struct Teleport {
        let enemyID: Int?
        let from: GridPosition
        let to: GridPosition
    }

    /// The grapple line the player fired this turn, for the scene to whip a hook
    /// out from `from` to the tile it bit (`to`). The reel itself shows through
    /// `shoves` (a dragged enemy) and `playerGrappleTo` (a self-pull).
    struct GrappleHook {
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
        /// The gatekeeper's own grand entrance, summoned at end-of-turn by the
        /// very kills that crossed the score gate — so the scene materializes it
        /// *after* those deaths animate, not with the head-of-turn arrivals.
        var late = false
    }

    /// Where the player moved to this turn (their drafted tile) — the initial
    /// move animation, the ultimate's origin, and the enemies' lunge all key off
    /// this, so it stays the drafted tile even when knockback shoves the player.
    let playerDestination: GridPosition
    /// Where the player was flung to by enemy knockback during the enemy phase,
    /// or nil if they weren't shoved. The scene slides them here as the hit lands.
    let playerShoveTo: GridPosition?
    /// Tiles the player's attack covered — a directional sweep or a throw's
    /// blast; empty when no attack was drafted.
    let attackTiles: [GridPosition]
    /// Tiles the omen touched this turn — bodies for Smite and Stillness,
    /// barrels for Detonation, the player's own tile for Quickening.
    let ultimateTiles: [GridPosition]
    /// Which omen went off, or nil if none did.
    let omenFired: Omen?
    /// Enemies damaged during the player's phase (weapon and explosions).
    let enemyHits: [EnemyHit]
    let playerExplosions: [Explosion]
    /// Enemies flung by a knockback weapon this turn, in the order they were shoved.
    let shoves: [Shove]
    /// Barrels shoved or reeled to a new tile this turn.
    let barrelMoves: [BarrelMove]
    /// Movers that warped through a teleporter this turn.
    let teleports: [Teleport]
    /// The player's grapple hook fired this turn, or nil if none.
    let grappleHook: GrappleHook?
    /// Where a wall/barrel grapple yanked the player to, or nil if they didn't
    /// pull themselves this turn.
    let playerGrappleTo: GridPosition?
    /// Hooks enemies threw at the player this turn (each `from` an enemy, `to`
    /// the tile it grabbed the player on), for the scene to draw as they reel.
    let enemyGrappleHooks: [GrappleHook]
    /// Enemies dragged during the enemies' own phase (the eye of an enemy's
    /// Vortex hauling its comrades in). Animated with the enemy attacks rather
    /// than with `shoves`, which belongs to the player's phase.
    let enemyShoves: [Shove]
    /// Barrels dragged during that same phase — `barrelMoves`' enemy-side twin.
    let enemyBarrelMoves: [BarrelMove]
    /// Kegs an enemy lobbed this turn. Unlike `barrelSpawns`, which is a
    /// telegraphed delivery landing at the head of the turn, these drop as the
    /// throw resolves, so the scene pops them in during the enemy phase.
    let enemyBarrelSpawns: [GridPosition]
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
    /// The cache the player's move ended on this turn, carried whole so the
    /// scene knows both what was inside and which tile to play the reveal on.
    /// Unlike `pickedUpWeapon` this was never drafted — it's dug up just by
    /// arriving — and nothing on the board said what was in it, so the scene
    /// announcing this *is* the reveal.
    let openedCache: Cache?
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
    /// True when the player's drafted action was voided by a stun this turn.
    let playerActionStunned: Bool
    /// True when the cold hit its limit this turn: the stacks reset and the
    /// player loses next turn's action. Announced rather than inferred — the
    /// freeze counter resetting to zero looks identical to it bleeding off.
    let frostbite: Bool
    /// Enemies the cold seized up this turn, so the scene can call out that a
    /// threat just went quiet for a reason the player caused.
    let frostbittenEnemies: [Int]
}
