//
//  GameState.swift
//  Foretold
//  The Final Draft?
//  Name ^

import Foundation

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

/// Elite scaling by level. Every gatekeeper knob — health, damage, summon
/// sizes, and the boss's cannon-nova radius — ramps with the run so late elites
/// keep pace with the player, each capped so the climb stays hard but fair.
struct BossConfig {
    /// Juggernaut miniboss starting health.
    let juggernautHealth: Int
    /// Boss starting health.
    let bossHealth: Int
    /// Added on top of the elite's weapon damage.
    let eliteDamageBonus: Int
    /// Recruits the juggernaut passively calls in each wave.
    let juggernautSummonCount: Int
    /// Recruits the boss calls in per summon intent.
    let bossSummonCount: Int
    /// Either elite stops summoning while this many rank-and-file are already up.
    let retinueCap: Int
    /// Radius of the boss's point-blank cannon nova (its own tile spared).
    let novaRadius: Int
    /// Explosive barrels the boss rains around the player per barrage intent.
    let bossBarrageCount: Int

    static func forLevel(_ level: Int) -> BossConfig {
        // base, then +step for every `every` levels cleared, never past cap.
        func ramp(_ base: Int, step: Int, every: Int, cap: Int) -> Int {
            min(cap, base + step * ((max(1, level) - 1) / every))
        }
        return BossConfig(
            juggernautHealth: ramp(12, step: 1, every: 1, cap: 30),
            bossHealth: ramp(20, step: 2, every: 1, cap: 56),
            eliteDamageBonus: ramp(0, step: 1, every: 3, cap: 4),
            juggernautSummonCount: ramp(2, step: 1, every: 5, cap: 3),
            bossSummonCount: ramp(3, step: 1, every: 3, cap: 5),
            retinueCap: ramp(4, step: 1, every: 3, cap: 6),
            novaRadius: ramp(3, step: 1, every: 3, cap: 4),
            bossBarrageCount: ramp(2, step: 1, every: 4, cap: 4)
        )
    }
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
    static let weaponDropInterval = 8
    /// …unless this many are already lying around (boss drops don't count).
    static let weaponDropCap = 2
    /// Once the floor has been at the weapon cap this many turns, the oldest
    /// drop expires.
    static let weaponExpiryTurns = 3
    /// A bomber arms once within this Manhattan distance of the player…
    static let bomberArmDistance = 2
    /// …then detonates after this many enemy phases…
    static let bomberFuseTurns = 2
    /// …blasting a diamond of this radius for this much damage.
    static let bomberBlastRadius = 2
    static let bomberDamage = 3
    // Elite health, damage, summon sizes, and nova radius now scale with the
    // level — see BossConfig.forLevel(_:).
    /// Extra damage a hit deals when it lands in a shieldbearer's exposed back.
    static let shieldbearerBackstabBonus = 1
    /// An enemy only refuses to line a shot up through an ally that's within this
    /// many tiles (the one right in front of it — a shield wall). Comrades farther
    /// down the lane are fair game, so long-range friendly fire stays exploitable.
    static let friendlyAimGuardRange = 2
    /// Chance (percent) that an eligible wave arrives as a whole formation
    /// instead of the usual trickle.
    static let formationChance = 30
    /// A formation's arrivals suppress this fraction of that many future waves,
    /// so a squad is a net gain but buys a lull rather than free extra bodies.
    static let formationSpawnDebtFactor = 0.6
    /// A marching squad holds formation until its anchor (or nearest member)
    /// closes to within this many tiles of the player, then breaks and engages.
    /// Kept below the spawn distance (>3) so a squad doesn't break the instant
    /// it lands.
    static let formationBreakDistance = 3
    /// A bomber holding formation peels off to charge once it's this close —
    /// larger than the squad's break so it pulls ahead and detonates in open
    /// ground, clear of the escorts it was marching with.
    static let bomberBreakDistance = 6
    // Squad shapes and makeup are authored in Enemy.swift as `Formation.all`.
    /// Minimum turns between the boss's summon intents, so a retinue thinned by
    /// friendly fire and the player's blasts doesn't retrigger a summon every
    /// single turn (the cap limits how many, this limits how often).
    static let bossSummonInterval = 2

    /// Score needed to reach a level: 100 for level 2, 300 for 3, 600 for 4…
    /// (Tetris-style widening gaps).
    static func scoreThreshold(forLevel level: Int) -> Int {
        100 * (level - 1) * level / 2
    }

    let columns: Int
    let rows: Int
    /// The arsenal this run draws from for loot, loadouts, and enemy weapons —
    /// the core weapons plus whichever elite trophies the profile has claimed.
    let weaponPool: [Weapon]
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
    /// This run's kills per credited source (weapon names, plus "Barrels") —
    /// the scene folds these into lifetime tallies that gate weapon unlocks.
    private(set) var killTallies: [String: Int] = [:]
    /// Tiles the player has moved this run (feeds movement milestones).
    private(set) var tilesMoved = 0
    /// Attacks dodged this run.
    private(set) var dodgesMade = 0
    /// Enemies struck by the player's weapon this resolve (for focus tracking).
    private var struckByPlayerThisTurn: Set<Int> = []
    /// The enemy the player has been hitting on consecutive turns, and for how
    /// many turns running.
    private var focusTargetID: Int?
    private var focusHitRun = 0
    /// Times the player has hit the same enemy 3 turns running this run.
    private(set) var focusStreaks = 0
    /// Turns with three or more kills this run.
    private(set) var comboTurns = 0
    /// Times the kill streak climbed to ×3 this run.
    private(set) var streakPeaks = 0

    /// Everything milestone-worthy this run: kill tallies plus the non-kill
    /// counters, under the keys the milestone table uses.
    var progressTallies: [String: Int] {
        var tallies = killTallies
        tallies["TilesMoved"] = tilesMoved
        tallies["Dodges"] = dodgesMade
        tallies["ComboTurns"] = comboTurns
        tallies["Streaks"] = streakPeaks
        tallies["Focus"] = focusStreaks
        return tallies
    }
    // Run-long tallies for the death recap.
    private(set) var totalKills = 0
    private(set) var elitesSlain = 0
    private(set) var bestCombo = 0
    private(set) var bestStreak = 0
    private(set) var totalDamageTaken = 0
    /// What landed the killing blow, recorded by the first fatal applyDamage.
    private(set) var causeOfDeath: String?
    private(set) var level = 1
    /// Consecutive turns (before this one) that scored at least one kill.
    private(set) var killStreak = 0
    /// Kills banked so far during the current resolve; drives combo bonuses.
    private var killsThisTurn = 0
    /// Explosions accumulated mid-phase (bomber deaths and their chains); each
    /// resolve phase drains these into its own animation list.
    private var pendingExplosions: [TurnResolution.Explosion] = []
    /// True from the moment the level's elite spawns until it dies: waves,
    /// barrels, floor drops, and score gains all pause — the elite is the gate.
    private(set) var bossPhase = false
    private(set) var bossDefeatedThisLevel = false
    /// Spawn tiles the boss called in this resolve via its summon intent;
    /// they telegraph next turn like any reinforcement, skipping wave cadence.
    private var queuedBossSummons: [GridPosition] = []
    /// Tiles where the boss's barrage will drop explosive barrels this resolve;
    /// telegraphed next turn like any barrel delivery, skipping wave cadence.
    private var queuedBossBarrels: [GridPosition] = []
    /// Pending barrel tiles that came from a boss barrage — marked volatile
    /// (drawn red) once they land.
    private var primedBarrelTiles: Set<GridPosition> = []
    /// Turn the boss last committed a summon intent; gates the summon cadence.
    private var lastBossSummonTurn = -100
    /// Ordinary waves owed silence after a formation marched in — a squad buys
    /// a lull rather than stacking on top of the normal trickle.
    private var spawnDebt = 0
    /// The advancing anchor each live squad marches from; members hold their
    /// slot relative to it until the squad breaks. Keyed by formation id.
    private var formationAnchors: [Int: GridPosition] = [:]
    private var nextFormationID = 0
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
    /// Next turn's arrivals, pre-rolled at schedule time so the telegraph can
    /// say WHAT is coming — hover a marker to see it before committing.
    private(set) var pendingArrivals: [Enemy] = []
    /// The telegraphed spawn tiles (for markers, highlights, and pathing).
    var pendingSpawns: [GridPosition] { pendingArrivals.map(\.position) }
    /// Tiles where next turn's fresh barrels drop; telegraphed during planning.
    /// Standing on one blocks the delivery harmlessly.
    private(set) var pendingBarrelSpawns: [GridPosition] = []
    private(set) var weaponDrops: [WeaponDrop] = []
    /// True when the player has drafted picking up the weapon underfoot.
    private(set) var plannedPickup = false
    /// True when the player has drafted swapping to the holstered weapon.
    private(set) var plannedSwap = false
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

    /// A reloading ranged weapon still jabs: 1 damage, one adjacent tile.
    static let bashDamage = 1
    /// True when the drafted attack is the reload-jab rather than the weapon's
    /// real attack.
    private(set) var plannedBash = false

    /// A bleed or poison riding on the player; ticks at the end of each turn.
    private(set) var playerAffliction: ActiveAffliction?

    /// Sticks a weapon's damage-over-time to every survivor of a strike.
    private mutating func afflict(
        _ hits: [TurnResolution.EnemyHit],
        with affliction: Weapon.Affliction?,
        chargesUltimate: Bool,
        credit: String?
    ) {
        guard let affliction else { return }
        for hit in hits where !hit.died {
            guard let index = enemies.firstIndex(where: { $0.id == hit.enemyID }) else { continue }
            enemies[index].affliction = ActiveAffliction(
                damagePerTurn: affliction.damagePerTurn,
                turnsRemaining: affliction.duration,
                chargesUltimate: chargesUltimate,
                credit: credit
            )
        }
    }

    /// Sticks a weapon's damage-over-time to the player.
    private mutating func afflictPlayer(with affliction: Weapon.Affliction?) {
        guard let affliction, !isGameOver else { return }
        playerAffliction = ActiveAffliction(
            damagePerTurn: affliction.damagePerTurn,
            turnsRemaining: affliction.duration,
            chargesUltimate: false,
            credit: nil
        )
    }

    /// True when the current draft earns the dodge: no attack or throw drafted,
    /// no weapon pickup, and a move of at least dodgeDistance tiles.
    var plannedDodgeReady: Bool {
        guard plannedAttackDirection == nil, plannedThrowTarget == nil, !plannedPickup,
              !plannedUltimate, !plannedSwap, let target = plannedTarget else { return false }
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
        if !plannedBash, let speed = equippedWeapon.projectileSpeed {
            return Array(full.prefix(speed))
        }
        return full
    }

    /// The rest of a drafted bolt's trajectory — tiles it only reaches on later
    /// turns; empty for instant weapons (and for the reload jab).
    var plannedAttackLaterTiles: [GridPosition] {
        guard !plannedBash, let speed = equippedWeapon.projectileSpeed else { return [] }
        return Array(plannedSweep().dropFirst(speed))
    }

    private func plannedSweep() -> [GridPosition] {
        guard let direction = plannedAttackDirection,
              let pattern = plannedBash ? AttackPattern.dagger : equippedWeapon.attackPattern else { return [] }
        return sweep(
            pattern,
            from: attackOrigin,
            facing: direction,
            pierces: plannedBash ? false : equippedWeapon.pierces,
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
        obstacles: [Obstacle]? = nil,
        weaponPool: [Weapon] = Weapon.lootTable
    ) {
        precondition(columns > 0 && rows > 0, "Board must have at least one tile")
        self.columns = columns
        self.rows = rows
        self.weaponPool = weaponPool
        // The starting loadout always covers both ranges — one melee, one
        // ranged/thrown — so threats like bombers can be dealt with from afar.
        // Unspecified slots are drawn to complete the pair.
        let meleePool = weaponPool.filter(\.isMelee)
        let rangedPool = weaponPool.filter(\.isRanged)
        switch (weapon, holsteredWeapon) {
        case let (equipped?, holstered?):
            self.equippedWeapon = equipped
            self.holsteredWeapon = holstered
        case let (equipped?, nil):
            self.equippedWeapon = equipped
            self.holsteredWeapon = (equipped.isMelee ? rangedPool : meleePool).randomElement()!
        case let (nil, holstered?):
            self.equippedWeapon = (holstered.isMelee ? rangedPool : meleePool).randomElement()!
            self.holsteredWeapon = holstered
        case (nil, nil):
            let pair = [meleePool.randomElement()!, rangedPool.randomElement()!].shuffled()
            self.equippedWeapon = pair[0]
            self.holsteredWeapon = pair[1]
        }
        self.playerHealth = playerHealth
        self.maxHealth = playerHealth
        self.maxArmor = maxArmor
        self.playerArmor = maxArmor
        let start = playerStart ?? GridPosition(x: columns / 2, y: rows / 2)
        self.playerPosition = start
        self.enemies = enemies ?? [
            Enemy(id: 0, position: GridPosition(x: 0, y: 0), weapon: weaponPool.randomElement()!),
            Enemy(id: 1, position: GridPosition(x: columns - 1, y: 0), weapon: weaponPool.randomElement()!),
            Enemy(id: 2, position: GridPosition(x: 0, y: rows - 1), weapon: weaponPool.randomElement()!),
            Enemy(id: 3, position: GridPosition(x: columns - 1, y: rows - 1), weapon: weaponPool.randomElement()!),
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
        if enemy.archetype == .bomber {
            // Its blast is worth previewing even before it arms, so hovering an
            // unarmed bomber shows the radius rather than an irrelevant dagger jab.
            return blastTiles(around: enemy.position, radius: Self.bomberBlastRadius, includeCenter: true)
        }
        if let target = enemy.plannedThrowTarget, let thrown = enemy.weapon.thrown {
            return blastTiles(around: target, radius: thrown.blastRadius, includeCenter: true)
        }
        // The boss's nova rings its destination; a volley adds the cannon's
        // line to the primary sweep. A summon or barrage threatens no tiles
        // directly — the recruits and barrels telegraph as spawns once cast.
        if enemy.archetype == .boss, let intent = enemy.plannedIntent {
            let origin = enemy.plannedTarget ?? enemy.position
            switch intent {
            case .nova:
                return blastTiles(around: origin, radius: BossConfig.forLevel(level).novaRadius)
            case .detonate:
                // Show the full chain the boss is about to set off so it can be
                // walked out of.
                return enemy.plannedDetonateTile.map { barrelChainBlast(from: $0) } ?? []
            case .summon, .barrage:
                return []
            case .volley:
                var blockers = Set(enemies.filter { $0.id != enemy.id }.map(\.position))
                blockers.insert(playerPosition)
                var tiles: [GridPosition] = []
                if let direction = enemy.plannedDirection, let pattern = enemy.weapon.attackPattern {
                    tiles += sweep(pattern, from: origin, facing: direction, pierces: enemy.weapon.pierces, blockers: blockers)
                }
                if let direction = enemy.plannedSecondaryDirection,
                   let cannon = enemy.secondaryWeapon, let pattern = cannon.attackPattern {
                    tiles += sweep(pattern, from: origin, facing: direction, pierces: cannon.pierces, blockers: blockers)
                }
                return tiles
            }
        }
        guard let direction = enemy.plannedDirection, let pattern = enemy.weapon.attackPattern else { return [] }
        let origin = enemy.plannedTarget ?? enemy.position
        var blockers = Set(enemies.filter { $0.id != enemy.id }.map(\.position))
        blockers.insert(playerPosition)
        return sweep(pattern, from: origin, facing: direction, pierces: enemy.weapon.pierces, blockers: blockers)
    }

    /// Blast zones of every armed bomber — certain incoming damage, shown red
    /// and avoided by everyone (including other enemies).
    var bomberThreatTiles: [GridPosition] {
        enemies
            .filter { $0.archetype == .bomber && $0.fuse != nil }
            .flatMap { blastTiles(around: $0.position, radius: Self.bomberBlastRadius, includeCenter: true) }
    }

    /// Tiles the player may pick this turn: every on-board tile within moveRange
    /// orthogonal steps (a diamond, no diagonals), including the current tile
    /// (planning to stay) but excluding tiles occupied by enemies or obstacles.
    func legalMoveTargets() -> Set<GridPosition> {
        // Enemies drafted to move off their tile don't block it — you can slip
        // into the space they're vacating (they'll have stepped away by the
        // time you land, and are shoved aside if their own move gets blocked).
        let occupied = Set(enemies.filter { !$0.isVacating }.map(\.position)).union(obstacles.map(\.position))
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

    /// Drafts swapping the equipped and holstered weapons: like a pickup, it
    /// spends this turn's attack (and dodge), the drafted move still happens,
    /// and the exchange lands during the resolve — the new weapon's move range
    /// applies from next turn.
    @discardableResult
    mutating func planSwap() -> Bool {
        guard !isGameOver, pendingBuffChoices.isEmpty else { return false }
        plannedSwap = true
        plannedAttackDirection = nil
        plannedThrowTarget = nil
        plannedPickup = false
        plannedUltimate = false
        return true
    }

    mutating func clearPlannedSwap() {
        plannedSwap = false
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
        plannedSwap = false
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
        plannedSwap = false
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
        guard !isGameOver, pendingBuffChoices.isEmpty else { return false }
        // A ranged weapon mid-reload still jabs: 1 damage, one adjacent tile.
        // Melee weapons recovering their swing get nothing.
        let bashing = !canAttack && equippedWeapon.isRanged
        guard canAttack || bashing else { return false }
        if !bashing, equippedWeapon.thrown != nil {
            guard throwTargets().contains(tile) else { return false }
            plannedThrowTarget = tile
            plannedAttackDirection = nil
            plannedBash = false
            plannedPickup = false
            plannedUltimate = false
            plannedSwap = false
            return true
        }
        let pattern = bashing ? AttackPattern.dagger : equippedWeapon.attackPattern
        guard let direction = Direction.aiming(
            from: attackOrigin,
            toward: tile,
            allowDiagonals: pattern?.supportsDiagonals ?? false
        ) else { return false }
        plannedAttackDirection = direction
        plannedBash = bashing
        plannedThrowTarget = nil
        plannedPickup = false
        plannedUltimate = false
        plannedSwap = false
        return true
    }

    mutating func clearPlannedAttack() {
        plannedAttackDirection = nil
        plannedThrowTarget = nil
        plannedBash = false
    }

    /// Leaves a damaging hazard on the given tiles for `duration` turns;
    /// anything standing on one when the turn resolves takes damage. Re-applying
    /// to a tile refreshes it. Walls can't burn.
    mutating func addLingeringEffect(at tiles: [GridPosition], damagePerTurn: Int, duration: Int, chargesUltimate: Bool = true, creditName: String? = nil) {
        for tile in tiles where contains(tile) && obstacle(at: tile)?.kind != .wall {
            lingeringEffects.removeAll { $0.position == tile }
            lingeringEffects.append(LingeringEffect(position: tile, damagePerTurn: damagePerTurn, chargesUltimate: chargesUltimate, creditName: creditName, turnsRemaining: duration))
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
        tilesMoved += playerStart.distance(to: playerPosition)
        plannedTarget = nil
        killsThisTurn = 0
        struckByPlayerThisTurn = []
        pendingExplosions = []

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

        // A drafted swap exchanges the carried weapons — the attack was its
        // price; the new weapon's move range applies from next turn.
        let swapped = plannedSwap
        if swapped {
            (equippedWeapon, holsteredWeapon) = (holsteredWeapon, equippedWeapon)
        }
        plannedSwap = false

        // Enemy weapon cooldowns tick at the start of the turn, so a fresh shot
        // still reads at its full value on the hover display while planning.
        for index in enemies.indices {
            if enemies[index].cooldownRemaining > 0 {
                enemies[index].cooldownRemaining -= 1
            }
            if enemies[index].secondaryCooldownRemaining > 0 {
                enemies[index].secondaryCooldownRemaining -= 1
            }
            // A parried shield stays down a turn before it comes back up.
            if enemies[index].shieldCooldown > 0 {
                enemies[index].shieldCooldown -= 1
            }
        }

        let healthBefore = playerHealth
        let armorBefore = playerArmor

        // A shell mid-flight is solid ordnance for the player too: ending the
        // move on its tile — or dashing straight through it along a row or
        // column — sets it off on contact. Sidestepping around it is a dodge.
        var playerCollisionHits: [TurnResolution.EnemyHit] = []
        if playerPosition != playerStart {
            for boltID in bolts.map(\.id) {
                guard let index = bolts.firstIndex(where: { $0.id == boltID }) else { continue }
                let bolt = bolts[index]
                let tile = bolt.position
                let throughRow = playerStart.y == playerPosition.y && tile.y == playerStart.y
                    && (min(playerStart.x, playerPosition.x)...max(playerStart.x, playerPosition.x)).contains(tile.x)
                let throughColumn = playerStart.x == playerPosition.x && tile.x == playerStart.x
                    && (min(playerStart.y, playerPosition.y)...max(playerStart.y, playerPosition.y)).contains(tile.y)
                guard tile == playerPosition || throughRow || throughColumn else { continue }
                // Contact fuze: the collider is hit no matter where they end up.
                let reduction = buffs.reduce(0) { $0 + $1.rangedDamageReduction }
                if !isGameOver {
                    applyDamage(max(0, bolt.damage - reduction), from: bolt.sourceName)
                }
                if bolt.impactBlastRadius > 0 {
                    let blast = blastTiles(around: tile, radius: bolt.impactBlastRadius, includeCenter: true)
                    let blastSet = Set(blast)
                    pendingExplosions.append(TurnResolution.Explosion(center: tile, tiles: blast))
                    playerCollisionHits += damageEnemies(on: blastSet, damage: bolt.damage, chargesUltimate: bolt.chargesUltimate, credit: bolt.creditName)
                    let chained = detonateBarrels(struckTiles: blastSet, chargesUltimate: bolt.chargesUltimate)
                    pendingExplosions += chained.explosions
                    playerCollisionHits += chained.hits
                    if let lingering = bolt.lingering {
                        addLingeringEffect(at: blast, damagePerTurn: lingering.damagePerTurn, duration: lingering.duration, chargesUltimate: bolt.chargesUltimate, creditName: bolt.creditName)
                    }
                    bolts.remove(at: index)
                } else {
                    pendingExplosions.append(TurnResolution.Explosion(center: tile, tiles: [tile]))
                    if !bolt.pierces {
                        bolts.remove(at: index)
                    }
                }
            }
        }

        // Reinforcements materialize at the START of the turn: they arrive
        // before anyone acts, so a pre-aimed attack at the telegraph greets
        // them — spawn camping is legal. Anyone standing on a spawn tile
        // blocks it, taking 1 damage for the trouble. Fresh arrivals have no
        // plans yet: they stand still this turn and draft at its end.
        var barrelSpawns: [GridPosition] = []
        for tile in pendingBarrelSpawns {
            let blocked = tile == playerPosition
                || enemies.contains { $0.position == tile }
                || obstacle(at: tile) != nil
                || weaponDrops.contains { $0.position == tile }
            if !blocked {
                obstacles.append(Obstacle(id: nextObstacleID, kind: .barrel, position: tile, volatile: primedBarrelTiles.contains(tile)))
                nextObstacleID += 1
                barrelSpawns.append(tile)
            }
        }
        pendingBarrelSpawns = []
        primedBarrelTiles = []

        var spawns: [TurnResolution.SpawnEvent] = []
        for arrival in pendingArrivals {
            let tile = arrival.position
            if tile == playerPosition {
                if !isGameOver {
                    applyDamage(1, from: "blocking a reinforcement")
                }
                spawns.append(TurnResolution.SpawnEvent(position: tile, enemyID: nil))
            } else if enemies.contains(where: { $0.position == tile }) {
                playerCollisionHits += damageEnemies(on: [tile], damage: 1, chargesUltimate: false)
                spawns.append(TurnResolution.SpawnEvent(position: tile, enemyID: nil))
            } else if obstacle(at: tile) != nil {
                spawns.append(TurnResolution.SpawnEvent(position: tile, enemyID: nil))
            } else {
                enemies.append(arrival)
                spawns.append(TurnResolution.SpawnEvent(position: tile, enemyID: arrival.id))
            }
        }
        pendingArrivals = []

        var moves: [TurnResolution.EnemyMove] = []
        var crossingHits: [TurnResolution.EnemyHit] = playerCollisionHits
        // Iterate by ID: crossing a pool can kill the mover (even chain a
        // bomber), which would leave positional indices stale.
        for enemyID in enemies.map(\.id) {
            guard let index = enemies.firstIndex(where: { $0.id == enemyID }) else { continue }
            let from = enemies[index].position
            var to = enemies[index].plannedTarget ?? from
            let path = enemies[index].plannedPath
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
            // The player stepped onto the tile this enemy is leaving, but its own
            // move got blocked — it can't share the tile, so it's shoved to any
            // free neighbour (staying put only if truly boxed in).
            if to == from && from == playerPosition {
                let occupied = Set(enemies.filter { $0.id != enemyID }.map(\.position))
                    .union(obstacles.map(\.position))
                    .union([playerPosition])
                let step = [GridPosition(x: from.x + 1, y: from.y), GridPosition(x: from.x - 1, y: from.y),
                            GridPosition(x: from.x, y: from.y + 1), GridPosition(x: from.x, y: from.y - 1)]
                if let free = step.first(where: { contains($0) && !occupied.contains($0) }) {
                    to = free
                }
            }
            enemies[index].position = to
            enemies[index].plannedTarget = nil
            enemies[index].plannedPath = []
            moves.append(TurnResolution.EnemyMove(enemyID: enemyID, from: from, to: to))

            // Wading through a hazard burns per tile stepped — the destination
            // itself is left to the end-of-turn tick. Careful enemies path
            // around pools anyway; the fearless pay in blood. Only kills in
            // player-made pools charge the ultimate.
            if to != from {
                let crossed = lingeringEffects.filter { effect in
                    path.contains(effect.position) && effect.position != to
                }
                let chargedBurn = crossed.filter(\.chargesUltimate).reduce(0) { $0 + $1.damagePerTurn }
                let plainBurn = crossed.filter { !$0.chargesUltimate }.reduce(0) { $0 + $1.damagePerTurn }
                // One tile, one occupant: the mover. Full death bookkeeping
                // (score, drops, bomber chains) rides along.
                if chargedBurn > 0 {
                    let credit = crossed.first { $0.chargesUltimate && $0.creditName != nil }?.creditName
                    crossingHits += damageEnemies(on: [to], damage: chargedBurn, credit: credit)
                }
                if plainBurn > 0 {
                    crossingHits += damageEnemies(on: [to], damage: plainBurn, chargesUltimate: false)
                }

                // Walking through a tile where a shell is mid-flight is a
                // collision: the bolt strikes the mover there (bursting, if
                // it's the exploding kind). Careful enemies path around it.
                for boltID in bolts.map(\.id) {
                    guard let boltIndex = bolts.firstIndex(where: { $0.id == boltID }) else { continue }
                    let bolt = bolts[boltIndex]
                    guard path.contains(bolt.position) else { continue }
                    if bolt.impactBlastRadius > 0 {
                        let blast = blastTiles(around: bolt.position, radius: bolt.impactBlastRadius, includeCenter: true)
                        let blastSet = Set(blast)
                        pendingExplosions.append(TurnResolution.Explosion(center: bolt.position, tiles: blast))
                        crossingHits += damageEnemies(on: blastSet, damage: bolt.damage, chargesUltimate: bolt.chargesUltimate, credit: bolt.creditName)
                        if !isGameOver && blastSet.contains(playerPosition) {
                            let reduction = buffs.reduce(0) { $0 + $1.rangedDamageReduction }
                            applyDamage(max(0, bolt.damage - reduction), from: bolt.sourceName)
                        }
                        let chained = detonateBarrels(struckTiles: blastSet, chargesUltimate: bolt.chargesUltimate)
                        pendingExplosions += chained.explosions
                        crossingHits += chained.hits
                        if let lingering = bolt.lingering {
                            addLingeringEffect(at: blast, damagePerTurn: lingering.damagePerTurn, duration: lingering.duration, chargesUltimate: bolt.chargesUltimate, creditName: bolt.creditName)
                        }
                        bolts.remove(at: boltIndex)
                    } else {
                        pendingExplosions.append(TurnResolution.Explosion(center: bolt.position, tiles: [bolt.position]))
                        crossingHits += damageEnemies(on: [to], damage: bolt.damage, chargesUltimate: bolt.chargesUltimate, credit: bolt.creditName, travelling: bolt.direction)
                        if !bolt.pierces {
                            bolts.remove(at: boltIndex)
                        }
                    }
                }
            }
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
            let landingHits = damageEnemies(on: blastSet, damage: shell.damage, chargesUltimate: shell.chargesUltimate, credit: shell.creditName)
            afflict(landingHits, with: shell.affliction, chargesUltimate: shell.chargesUltimate, credit: shell.creditName)
            if shell.creditName != nil {
                struckByPlayerThisTurn.formUnion(landingHits.map(\.enemyID))
            }
            projectileHits += landingHits
            if !isGameOver && blastSet.contains(playerPosition) {
                let reduction = buffs.reduce(0) { $0 + $1.rangedDamageReduction }
                applyDamage(max(0, shell.damage - reduction), from: shell.sourceName)
                afflictPlayer(with: shell.affliction)
            }
            let chained = detonateBarrels(struckTiles: blastSet, chargesUltimate: shell.chargesUltimate)
            projectileImpacts += chained.explosions
            projectileHits += chained.hits
            if let lingering = shell.lingering {
                addLingeringEffect(at: blast, damagePerTurn: lingering.damagePerTurn, duration: lingering.duration, chargesUltimate: shell.chargesUltimate, creditName: shell.creditName)
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
        projectileImpacts += drainPendingExplosions()

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
            ultimateKillCharge = 0
            playerPhaseHits += damageEnemies(on: Set(ultimateTiles), damage: Self.ultimateDamage, chargesUltimate: false)
        }
        plannedUltimate = false
        let bashing = plannedBash
        if bashing, let direction = plannedAttackDirection {
            // The reload jab: a bare 1-damage poke that leaves the reload
            // ticking and the weapon's tricks (bolts, trails) holstered.
            didAttack = true
            attackTiles = sweep(
                AttackPattern.dagger,
                from: playerPosition,
                facing: direction,
                pierces: false,
                blockers: Set(enemies.map(\.position))
            )
        } else if let direction = plannedAttackDirection, let pattern = equippedWeapon.attackPattern {
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
                    lingering: equippedWeapon.lingering,
                    chargesUltimate: true,
                    sourceName: "your own \(equippedWeapon.name)",
                    creditName: equippedWeapon.name,
                    affliction: equippedWeapon.affliction
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
                    chargesUltimate: true,
                    totalFlightTurns: thrown.flightTurns,
                    turnsUntilImpact: thrown.flightTurns,
                    sourceName: "your own \(equippedWeapon.name)",
                    creditName: equippedWeapon.name,
                    affliction: equippedWeapon.affliction
                ))
                nextProjectileID += 1
            } else {
                attackTiles = blastTiles(around: target, radius: thrown.blastRadius, includeCenter: true)
            }
        }
        if didAttack && !attackTiles.isEmpty {
            let struck = Set(attackTiles)
            let strikeDamage = bashing ? Self.bashDamage : attackDamage
            // A directional swing can be parried from the front and rewards a
            // backstab; a thrown blast or a radial swing (greataxe/hammer/scythe)
            // carries no meaningful facing, so it slips past the shield and
            // triggers no backstab — it's area damage, not a pointed strike.
            let radial = equippedWeapon.attackPattern?.isRadial ?? false
            let facing = (equippedWeapon.thrown == nil && !radial) ? plannedAttackDirection : nil
            let sweepHits = damageEnemies(on: struck, damage: strikeDamage, credit: bashing ? nil : equippedWeapon.name, travelling: facing)
            afflict(sweepHits, with: bashing ? nil : equippedWeapon.affliction, chargesUltimate: true, credit: equippedWeapon.name)
            struckByPlayerThisTurn.formUnion(sweepHits.map(\.enemyID))
            playerPhaseHits += sweepHits
            // A lobbed blast has no friendly immunity: catch yourself, hurt yourself.
            if equippedWeapon.thrown != nil && !bashing && !isGameOver && struck.contains(playerPosition) {
                applyDamage(attackDamage, from: "your own \(equippedWeapon.name)")
            }
            let blast = detonateBarrels(struckTiles: struck)
            playerExplosions = blast.explosions
            playerPhaseHits += blast.hits
            if !bashing, let lingering = equippedWeapon.lingering {
                addLingeringEffect(at: attackTiles, damagePerTurn: lingering.damagePerTurn, duration: lingering.duration, creditName: equippedWeapon.name)
            }
        }
        playerExplosions += drainPendingExplosions()
        plannedAttackDirection = nil
        plannedThrowTarget = nil
        plannedBash = false

        // Moving far without attacking (or grabbing a weapon) earns one dodge:
        // the first enemy hit this turn misses.
        var dodgeCharges = (!didAttack && pickedUp == nil && !ultimateFired && !swapped
            && playerStart.distance(to: playerPosition) >= Self.dodgeDistance) ? 1 : 0

        var enemyAttacks: [TurnResolution.EnemyAttack] = []
        var friendlyFireHits: [TurnResolution.EnemyHit] = []
        var enemyExplosions: [TurnResolution.Explosion] = []

        // Armed bombers burn their fuses first — and blow.
        for bomberID in enemies.compactMap({ $0.archetype == .bomber && $0.fuse != nil ? $0.id : nil }) {
            guard let index = enemies.firstIndex(where: { $0.id == bomberID }),
                  let fuse = enemies[index].fuse else { continue }
            if fuse > 1 {
                enemies[index].fuse = fuse - 1
            } else {
                // Its own detonation, not a kill: no bounty, no charge. The
                // bomber still gets a death event so the scene retires its
                // sprite with the blast.
                let center = enemies[index].position
                enemies.remove(at: index)
                friendlyFireHits.append(TurnResolution.EnemyHit(enemyID: bomberID, healthAfter: 0, died: true))
                friendlyFireHits += detonateBomber(at: center, chargesUltimate: false)
            }
        }

        // Iterate by ID: an attacker can die to a comrade's swing or an
        // explosion before its own turn to act.
        let attackerIDs = enemies.compactMap {
            ($0.plannedDirection != nil || $0.plannedThrowTarget != nil || $0.plannedIntent != nil) ? $0.id : nil
        }
        for attackerID in attackerIDs {
            guard let attackerIndex = enemies.firstIndex(where: { $0.id == attackerID }) else { continue }
            let attacker = enemies[attackerIndex]
            // Indexed bookkeeping happens before the attack: firing a bolt can
            // kill enemies mid-flight (even the attacker, via a barrel burst),
            // which would leave attackerIndex stale.
            enemies[attackerIndex].plannedDirection = nil
            enemies[attackerIndex].plannedThrowTarget = nil
            enemies[attackerIndex].plannedIntent = nil
            enemies[attackerIndex].plannedSecondaryDirection = nil
            switch attacker.plannedIntent {
            case .volley:
                // Only the weapons that actually fired go on cooldown, each on
                // its own clock — so nova and volley can alternate.
                if attacker.plannedDirection != nil {
                    enemies[attackerIndex].cooldownRemaining = attacker.weapon.cooldown
                }
                if attacker.plannedSecondaryDirection != nil {
                    enemies[attackerIndex].secondaryCooldownRemaining = attacker.secondaryWeapon?.cooldown ?? 0
                }
            case .nova:
                enemies[attackerIndex].secondaryCooldownRemaining = attacker.secondaryWeapon?.cooldown ?? attacker.weapon.cooldown
            case .summon, .barrage, .detonate:
                // Abilities don't spend a weapon's reload; their own gates
                // (summon cadence, barrel cap, a live red barrel) pace them.
                break
            case nil:
                enemies[attackerIndex].cooldownRemaining = attacker.weapon.cooldown
            }
            enemies[attackerIndex].plannedDetonateTile = nil

            if attacker.plannedIntent == .summon {
                // The boss spends its action calling recruits to its side; they
                // telegraph like any reinforcement and land the turn after.
                let taken = Set(enemies.map(\.position))
                    .union(obstacles.map(\.position))
                    .union(lingeringEffects.map(\.position))
                    .union([playerPosition])
                let ring = blastTiles(around: attacker.position, radius: 2).filter {
                    !taken.contains($0) && $0.distance(to: playerPosition) > 1
                }
                queuedBossSummons = Array(ring.shuffled().prefix(BossConfig.forLevel(level).bossSummonCount))
                lastBossSummonTurn = turnNumber
                continue
            }

            if attacker.plannedIntent == .barrage {
                // The boss hurls a cluster of live barrels to rain down 1–3
                // tiles from the player: telegraphed like any barrel delivery,
                // and set off later with a detonate intent — reintroducing the
                // board hazards a boss fight otherwise strips away.
                queuedBossBarrels = Array(barrageTiles().shuffled().prefix(BossConfig.forLevel(level).bossBarrageCount))
                continue
            }

            if attacker.plannedIntent == .detonate {
                // The boss sets off a barrel it primed earlier; the chain runs
                // through detonateBarrels just like a player-lit blast.
                if let target = attacker.plannedDetonateTile {
                    let blast = detonateBarrels(struckTiles: [target], chargesUltimate: false)
                    enemyExplosions += blast.explosions
                    friendlyFireHits += blast.hits
                }
                continue
            }

            // The nova strikes with the cannon, not the primary — damage and
            // damage-reduction type follow the weapon actually swung.
            let strikingWeapon = attacker.plannedIntent == .nova
                ? (attacker.secondaryWeapon ?? attacker.weapon)
                : attacker.weapon
            let attackDamage = attacker.plannedIntent == .nova ? strikingWeapon.damage : attacker.damage

            var tiles: [GridPosition] = []
            var throwerIncluded = false
            if attacker.plannedIntent == .nova {
                // The cannon swept in a circle: everything around the boss
                // takes a shell, its own tile spared.
                tiles = blastTiles(around: attacker.position, radius: BossConfig.forLevel(level).novaRadius)
            } else if let direction = attacker.plannedDirection, let pattern = attacker.weapon.attackPattern {
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
                        lingering: attacker.weapon.lingering,
                        chargesUltimate: false,
                        sourceName: attacker.slayerName,
                        creditName: nil,
                        affliction: attacker.weapon.affliction
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
                        chargesUltimate: false,
                        totalFlightTurns: thrown.flightTurns,
                        turnsUntilImpact: thrown.flightTurns,
                        sourceName: attacker.slayerName,
                        creditName: nil,
                        affliction: attacker.weapon.affliction
                    ))
                    nextProjectileID += 1
                    // tiles stays empty: nothing swept this turn.
                } else {
                    tiles = blastTiles(around: target, radius: thrown.blastRadius, includeCenter: true)
                    throwerIncluded = true
                }
            } else if attacker.plannedSecondaryDirection == nil {
                continue
            }

            // Volley: the cannon fires alongside (or instead of) the primary,
            // its shell a traveling bolt like any other. Elite +1 damage.
            if let direction = attacker.plannedSecondaryDirection,
               let cannon = attacker.secondaryWeapon,
               let pattern = cannon.attackPattern,
               let speed = cannon.projectileSpeed {
                let shell = Bolt(
                    id: nextProjectileID,
                    position: attacker.position,
                    direction: direction,
                    speed: speed,
                    remainingRange: pattern.tiles(from: attacker.position, facing: direction).count,
                    damage: cannon.damage + 1,
                    pierces: cannon.pierces,
                    impactBlastRadius: cannon.impactBlastRadius,
                    lingering: cannon.lingering,
                    chargesUltimate: false,
                    sourceName: "the gatekeeper's cannon",
                    creditName: nil,
                    affliction: cannon.affliction
                )
                nextProjectileID += 1
                if let survivor = fly(shell, impacts: &projectileImpacts, hits: &projectileHits, flights: &boltFlights) {
                    bolts.append(survivor)
                }
            }

            let struck = Set(tiles)
            var hitsPlayer = !isGameOver && struck.contains(playerPosition)
            var dodged = false
            if hitsPlayer && dodgeCharges > 0 {
                dodgeCharges -= 1
                dodged = true
                dodgesMade += 1
                hitsPlayer = false
            }
            if hitsPlayer {
                // Buffs blunt incoming weapon hits (but never below zero).
                let reduction = buffs.reduce(0) {
                    $0 + (strikingWeapon.isMelee ? $1.meleeDamageReduction : $1.rangedDamageReduction)
                }
                let killer = attacker.plannedIntent == .nova
                    ? "the boss's cannon nova"
                    : attacker.slayerName
                applyDamage(max(0, attackDamage - reduction), from: killer)
                afflictPlayer(with: strikingWeapon.affliction)
            }
            // Friendly fire: comrades in the sweep take the hit; a thrower caught
            // in its own blast does too.
            var struckEnemies = struck
            if !throwerIncluded {
                struckEnemies.remove(attacker.position)
            }
            let comradeHits = damageEnemies(on: struckEnemies, damage: attackDamage, chargesUltimate: false)
            afflict(comradeHits, with: strikingWeapon.affliction, chargesUltimate: false, credit: nil)
            friendlyFireHits += comradeHits
            let blast = detonateBarrels(struckTiles: struck, chargesUltimate: false)
            enemyExplosions += blast.explosions
            friendlyFireHits += blast.hits
            if let lingering = strikingWeapon.lingering {
                addLingeringEffect(at: tiles, damagePerTurn: lingering.damagePerTurn, duration: lingering.duration, chargesUltimate: false)
            }

            enemyAttacks.append(TurnResolution.EnemyAttack(
                enemyID: attackerID,
                tiles: tiles,
                hitsPlayer: hitsPlayer,
                dodged: dodged
            ))
        }
        enemyExplosions += drainPendingExplosions()

        // Lingering hazards burn whoever ended the turn in them. Effects placed
        // this turn skip their first tick so they last their full duration.
        // Crossing burns from the move phase animate here too.
        var hazardHits: [TurnResolution.EnemyHit] = crossingHits
        for index in lingeringEffects.indices {
            if lingeringEffects[index].justPlaced {
                lingeringEffects[index].justPlaced = false
                continue
            }
            let effect = lingeringEffects[index]
            hazardHits += damageEnemies(on: [effect.position], damage: effect.damagePerTurn, chargesUltimate: effect.chargesUltimate, credit: effect.creditName)
            if !isGameOver && effect.position == playerPosition && !buffs.contains(where: \.hazardImmunity) {
                applyDamage(effect.damagePerTurn, from: "a lingering pool")
            }
            lingeringEffects[index].turnsRemaining -= 1
        }
        lingeringEffects.removeAll { $0.turnsRemaining <= 0 }

        // Wounds fester: afflicted survivors bleed at the end of the turn,
        // wherever they've run to. Fresh wounds skip their first tick.
        for enemyID in enemies.map(\.id) {
            guard let index = enemies.firstIndex(where: { $0.id == enemyID }),
                  var wound = enemies[index].affliction else { continue }
            if wound.fresh {
                wound.fresh = false
                enemies[index].affliction = wound
                continue
            }
            wound.turnsRemaining -= 1
            enemies[index].affliction = wound.turnsRemaining > 0 ? wound : nil
            hazardHits += damageEnemies(
                on: [enemies[index].position],
                damage: wound.damagePerTurn,
                chargesUltimate: wound.chargesUltimate,
                credit: wound.credit
            )
        }
        if var wound = playerAffliction {
            if wound.fresh {
                wound.fresh = false
                playerAffliction = wound
            } else {
                if !isGameOver {
                    applyDamage(wound.damagePerTurn, from: "a festering wound")
                }
                wound.turnsRemaining -= 1
                playerAffliction = wound.turnsRemaining > 0 ? wound : nil
            }
        }

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
        // The jab doesn't restart the reload — the real weapon keeps counting.
        if didAttack && !bashing {
            weaponCooldowns[equippedWeapon.name] = equippedWeapon.cooldown
        }

        // The streak extends on any turn with a kill and snaps on a dry one.
        killStreak = killsThisTurn > 0 ? killStreak + 1 : 0
        bestCombo = max(bestCombo, killsThisTurn)
        bestStreak = max(bestStreak, killStreak)
        if killsThisTurn >= 3 {
            comboTurns += 1
        }
        if killStreak == 3 {
            streakPeaks += 1
        }
        // Focus: a weapon hit on the same enemy on consecutive turns. Three
        // running scores one and the count restarts (the target keeps its mark).
        if let target = focusTargetID, struckByPlayerThisTurn.contains(target) {
            focusHitRun += 1
        } else if let fresh = struckByPlayerThisTurn.min() {
            focusTargetID = fresh
            focusHitRun = 1
        } else {
            focusTargetID = nil
            focusHitRun = 0
        }
        if focusHitRun >= 3 {
            focusStreaks += 1
            focusHitRun = 0
        }

        turnNumber += 1
        if !isGameOver && !bossPhase && !devFreezeScore {
            score += Self.survivalScore
        }

        // The score milestone summons the level's elite gatekeeper (a boss every
        // third level) and freezes progression; only killing it turns the level
        // over — regenerating the board and offering a choice of boons.
        var leveledUpTo: Int?
        let milestone = Self.scoreThreshold(forLevel: level + 1)
        if !isGameOver && score >= milestone && bossDefeatedThisLevel {
            advanceLevel()
            leveledUpTo = level
        } else {
            if !isGameOver && score >= milestone && !bossPhase && !bossDefeatedThisLevel && !devNoElites {
                summonElite(into: &spawns)
            }
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
            hazardExplosions: drainPendingExplosions(),
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
    private mutating func damageEnemies(on tiles: Set<GridPosition>, damage: Int, chargesUltimate: Bool = true, credit: String? = nil, travelling direction: Direction? = nil) -> [TurnResolution.EnemyHit] {
        var hits: [TurnResolution.EnemyHit] = []
        var diedBomberPositions: [GridPosition] = []
        for index in enemies.indices where tiles.contains(enemies[index].position) {
            // A shieldbearer parries a blow driven into its front: no damage,
            // and the shield drops for a turn (shieldCooldown) so it can't block
            // again immediately.
            if enemies[index].parries(direction) {
                enemies[index].shieldCooldown = 2
                hits.append(TurnResolution.EnemyHit(enemyID: enemies[index].id, healthAfter: enemies[index].health, died: false, blocked: true))
                continue
            }
            // Struck in the exposed back: extra damage.
            let dealt = damage + (enemies[index].struckFromBehind(direction) ? Self.shieldbearerBackstabBonus : 0)
            enemies[index].health -= dealt
            let died = enemies[index].health <= 0
            if died {
                let isElite = enemies[index].archetype == .juggernaut || enemies[index].archetype == .boss
                // Score is frozen during the boss fight — except the gate itself.
                if (!bossPhase || isElite) && !devFreezeScore {
                    // Kills escalate within a turn and ride the multi-turn streak.
                    score += enemies[index].bounty
                        + Self.comboKillBonus * killsThisTurn
                        + Self.streakKillBonus * killStreak
                }
                killsThisTurn += 1
                totalKills += 1
                if let credit {
                    killTallies[credit, default: 0] += 1
                }
                if isElite {
                    elitesSlain += 1
                }
                if chargesUltimate {
                    // Full is full: no banking past the threshold, so firing
                    // always costs the whole ten-kill climb.
                    ultimateKillCharge = min(ultimateKillCharge + 1, Self.ultimateChargeKills)
                }
                if isElite {
                    // The gate falls: its weapons drop where it died, and the
                    // level can now turn over. The boss's cannon lands on the
                    // nearest open tile beside its primary.
                    bossPhase = false
                    bossDefeatedThisLevel = true
                    weaponDrops.append(WeaponDrop(
                        id: nextDropID,
                        weapon: enemies[index].weapon,
                        position: enemies[index].position,
                        isBossDrop: true
                    ))
                    nextDropID += 1
                    if let secondary = enemies[index].secondaryWeapon {
                        let fallen = enemies[index].position
                        let spot = blastTiles(around: fallen, radius: 2)
                            .filter { tile in
                                obstacle(at: tile) == nil
                                    && tile != playerPosition
                                    && !weaponDrops.contains { $0.position == tile }
                            }
                            .min { $0.distance(to: fallen) < $1.distance(to: fallen) }
                        weaponDrops.append(WeaponDrop(
                            id: nextDropID,
                            weapon: secondary,
                            position: spot ?? fallen,
                            isBossDrop: true
                        ))
                        nextDropID += 1
                    }
                }
                if enemies[index].archetype == .bomber {
                    diedBomberPositions.append(enemies[index].position)
                }
            }
            hits.append(TurnResolution.EnemyHit(
                enemyID: enemies[index].id,
                healthAfter: max(0, enemies[index].health),
                died: died
            ))
        }
        enemies.removeAll { $0.health <= 0 }
        // Bombers go out with a bang, chaining freely into whatever's next.
        for position in diedBomberPositions {
            hits += detonateBomber(at: position, chargesUltimate: chargesUltimate)
        }
        return hits
    }

    /// A bomber blast: damages everything in the diamond (the player included),
    /// sets off barrels, and records the explosion for whichever phase drains it.
    private mutating func detonateBomber(at center: GridPosition, chargesUltimate: Bool) -> [TurnResolution.EnemyHit] {
        let blast = blastTiles(around: center, radius: Self.bomberBlastRadius, includeCenter: true)
        let blastSet = Set(blast)
        pendingExplosions.append(TurnResolution.Explosion(center: center, tiles: blast))
        var hits = damageEnemies(on: blastSet, damage: Self.bomberDamage, chargesUltimate: chargesUltimate)
        if !isGameOver && blastSet.contains(playerPosition) {
            applyDamage(Self.bomberDamage, from: "a bomber's blast")
        }
        let chained = detonateBarrels(struckTiles: blastSet, chargesUltimate: chargesUltimate)
        pendingExplosions += chained.explosions
        hits += chained.hits
        return hits
    }

    /// Hands the mid-phase explosion backlog to the current resolve phase.
    private mutating func drainPendingExplosions() -> [TurnResolution.Explosion] {
        defer { pendingExplosions = [] }
        return pendingExplosions
    }

    /// Advances to the next level: the board fully regenerates at the new
    /// difficulty (fresh enemies, obstacles, and floor — the player keeps
    /// position, health, armor, loadout, and score) and two boons are drawn for
    /// the player to choose between; play pauses until `chooseBuff` is called.
    private mutating func advanceLevel() {
        level += 1
        let config = LevelConfig.forLevel(level)

        lingeringEffects = []
        // The slain gatekeeper's weapon rides along to the new board.
        weaponDrops.removeAll { !$0.isBossDrop }
        pendingArrivals = []
        pendingBarrelSpawns = []
        projectiles = []
        bolts = []
        turnsAtWeaponCap = 0
        bossPhase = false
        bossDefeatedThisLevel = false
        queuedBossSummons = []
        queuedBossBarrels = []
        primedBarrelTiles = []
        lastBossSummonTurn = -100
        spawnDebt = 0
        formationAnchors = [:]
        playerAffliction = nil

        var fresh: [Enemy] = []
        for tile in edgeTiles().shuffled() where fresh.count < config.startingEnemies {
            guard tile.distance(to: playerPosition) > 3 else { continue }
            fresh.append(Enemy.recruit(id: nextEnemyID, at: tile, armory: weaponPool))
            nextEnemyID += 1
        }
        enemies = fresh

        obstacles = Self.scatterObstacles(
            columns: columns,
            rows: rows,
            walls: config.walls,
            barrels: config.barrels,
            keepClear: Set(enemies.map(\.position)).union(weaponDrops.map(\.position)),
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
    /// The level's gatekeeper arrives on an open edge tile: a juggernaut, or a
    /// full boss every third level. Waves pause until it falls.
    private mutating func summonElite(into spawns: inout [TurnResolution.SpawnEvent]) {
        let archetype: Archetype = level.isMultiple(of: 3) ? .boss : .juggernaut
        let taken = Set(enemies.map(\.position))
            .union(obstacles.map(\.position))
            .union([playerPosition])
        guard let tile = edgeTiles().shuffled().first(where: {
            !taken.contains($0) && $0.distance(to: playerPosition) > 3
        }) else { return }
        let elite = Enemy.elite(archetype, id: nextEnemyID, at: tile, config: BossConfig.forLevel(level))
        nextEnemyID += 1
        enemies.append(elite)
        spawns.append(TurnResolution.SpawnEvent(position: tile, enemyID: elite.id))
        bossPhase = true
    }

    /// Rolls next turn's arrival for a telegraph tile — decided now, so the
    /// marker can honestly say what's coming.
    private mutating func rollArrival(at tile: GridPosition) -> Enemy {
        let arrival = Enemy.recruit(id: nextEnemyID, at: tile, armory: weaponPool)
        nextEnemyID += 1
        return arrival
    }

    private mutating func scheduleSpawns() {
        pendingArrivals = []
        pendingBarrelSpawns = []
        // A drafted boss summon or barrage overrides the wave cadence: the
        // called recruits and lobbed barrels telegraph immediately.
        if !queuedBossSummons.isEmpty || !queuedBossBarrels.isEmpty {
            pendingArrivals = queuedBossSummons.map { rollArrival(at: $0) }
            pendingBarrelSpawns = queuedBossBarrels
            primedBarrelTiles = Set(queuedBossBarrels)
            queuedBossSummons = []
            queuedBossBarrels = []
            return
        }
        let config = LevelConfig.forLevel(level)
        guard turnNumber % config.spawnInterval == 0 else { return }

        // During an elite fight, ordinary waves and barrel deliveries stop. The
        // juggernaut summons recruits on nearby open ground each wave — but only
        // up to the retinue cap, so it can't flood the board; the boss proper
        // only summons by drafting its summon intent.
        if bossPhase {
            guard let elite = enemies.first(where: { $0.archetype == .juggernaut }) else { return }
            let boss = BossConfig.forLevel(level)
            let retinue = enemies.filter { $0.archetype != .juggernaut && $0.archetype != .boss }.count
            guard retinue < boss.retinueCap else { return }
            let taken = Set(enemies.map(\.position))
                .union(obstacles.map(\.position))
                .union(lingeringEffects.map(\.position))
                .union([playerPosition])
            let ring = blastTiles(around: elite.position, radius: 2).filter {
                !taken.contains($0) && $0.distance(to: playerPosition) > 1
            }
            pendingArrivals = ring.shuffled().prefix(boss.juggernautSummonCount).map { rollArrival(at: $0) }
            return
        }

        // Dev override forces this wave's makeup and skips the usual roll.
        if let override = devSpawnOverride {
            applyDevSpawn(override)
            return
        }

        // A formation just marched in: this wave (and a few after) stays quiet
        // so the squad is a net gain, not free extra bodies on top of the trickle.
        if spawnDebt > 0 {
            spawnDebt -= 1
            return
        }

        // Every so often (from level 2) a whole squad arrives together in a
        // shaped formation instead of the usual trickle; it then quiets the next
        // few waves by a fraction of its size.
        if level >= 2 && Int.random(in: 0..<100) < Self.formationChance {
            let count = spawnFormation()
            if count > 0 {
                spawnDebt = Int((Double(count) * Self.formationSpawnDebtFactor).rounded())
                return
            }
        }

        let taken = Set(enemies.map(\.position))
            .union(obstacles.map(\.position))
            .union(lingeringEffects.map(\.position))
        let candidates = edgeTiles().filter {
            !taken.contains($0) && $0.distance(to: playerPosition) > 3
        }
        pendingArrivals = candidates.shuffled().prefix(config.spawnBatch).map { rollArrival(at: $0) }

        guard obstacles.filter({ $0.kind == .barrel }).count < Self.barrelSpawnCap else { return }
        let drops = Set(weaponDrops.map(\.position))
        var open: [GridPosition] = []
        for x in 0..<columns {
            for y in 0..<rows {
                let tile = GridPosition(x: x, y: y)
                if !taken.contains(tile)
                    && !pendingSpawns.contains(tile)
                    && !drops.contains(tile)
                    && tile.distance(to: playerPosition) > 2 {
                    open.append(tile)
                }
            }
        }
        if let drop = open.randomElement() {
            pendingBarrelSpawns = [drop]
        }
    }

    /// Telegraphs a shaped squad marching in from a random edge: an anchor tile
    /// plus the formation's rotated offsets, dropping any that fall off-board or
    /// onto taken ground. Returns how many actually got placed.
    private mutating func spawnFormation(_ forced: Formation? = nil) -> Int {
        let taken = Set(enemies.map(\.position))
            .union(obstacles.map(\.position))
            .union(lingeringEffects.map(\.position))
        let anchorPool = edgeTiles()
            .filter { !taken.contains($0) && $0.distance(to: playerPosition) > 3 }
            .shuffled()
        guard let formation = forced ?? Formation.all.randomElement() else { return 0 }

        // Every slot that fits from a given anchor, with its rotated offset.
        func placement(at anchor: GridPosition) -> [(tile: GridPosition, offset: GridPosition, slot: Formation.Slot)] {
            let inward = inwardDirection(from: anchor)
            var used = taken
            var out: [(GridPosition, GridPosition, Formation.Slot)] = []
            for slot in formation.slots {
                let rotated = inward.rotated(slot.offset)
                let tile = GridPosition(x: anchor.x + rotated.x, y: anchor.y + rotated.y)
                guard contains(tile), !used.contains(tile), tile.distance(to: playerPosition) > 2 else { continue }
                used.insert(tile)
                out.append((tile, rotated, slot))
            }
            return out
        }

        // Prefer an anchor where the whole squad fits; else the fullest partial,
        // so a wall-crowded edge doesn't quietly cook members off the formation.
        var anchor: GridPosition?
        var chosen: [(tile: GridPosition, offset: GridPosition, slot: Formation.Slot)] = []
        for candidate in anchorPool.prefix(12) {
            let fit = placement(at: candidate)
            if fit.count == formation.slots.count { anchor = candidate; chosen = fit; break }
            if fit.count > chosen.count { anchor = candidate; chosen = fit }
        }
        guard let anchor, !chosen.isEmpty else { return 0 }

        let fid = nextFormationID
        var arrivals: [Enemy] = []
        for entry in chosen {
            var recruit = Enemy.recruit(entry.slot.archetype, weaponClass: entry.slot.weaponClass, id: nextEnemyID, at: entry.tile, armory: weaponPool)
            // Everyone marches in as a cohesive squad — bombers included, but they
            // peel off early (see draftEnemyPlans) so they don't blow up the line.
            recruit.formationID = fid
            recruit.formationOffset = entry.offset
            arrivals.append(recruit)
            nextEnemyID += 1
        }
        // A squad needs at least two to hold formation; a lone soldier just charges.
        if arrivals.filter({ $0.formationID == fid }).count >= 2 {
            formationAnchors[fid] = anchor
            nextFormationID += 1
        } else {
            for index in arrivals.indices { arrivals[index].formationID = nil }
        }
        pendingArrivals = arrivals
        return arrivals.count
    }

    /// The way a squad standing on an edge tile should march to reach the board:
    /// toward the centre.
    private func inwardDirection(from tile: GridPosition) -> Direction {
        if tile.x == 0 { return .right }
        if tile.x == columns - 1 { return .left }
        if tile.y == 0 { return .up }
        return .down
    }

    /// Every few turns a random weapon appears on an open tile (up to a cap),
    /// so the player can trade their loadout mid-run.
    private mutating func spawnWeaponDrop() {
        guard !bossPhase,
              turnNumber % Self.weaponDropInterval == 0,
              weaponDrops.filter({ !$0.isBossDrop }).count < Self.weaponDropCap else { return }
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
        weaponDrops.append(WeaponDrop(id: nextDropID, weapon: weaponPool.randomElement()!, position: tile))
        nextDropID += 1
    }

    /// Once the floor has sat at the weapon cap for a few turns, the oldest
    /// drop crumbles away so fresh ones keep coming.
    private mutating func expireWeaponDrops() {
        let ordinary = weaponDrops.indices.filter { !weaponDrops[$0].isBossDrop }
        guard ordinary.count >= Self.weaponDropCap else {
            turnsAtWeaponCap = 0
            return
        }
        turnsAtWeaponCap += 1
        if turnsAtWeaponCap >= Self.weaponExpiryTurns {
            turnsAtWeaponCap = 0
            if let oldest = ordinary.min(by: { weaponDrops[$0].id < weaponDrops[$1].id }) {
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
                    let chained = detonateBarrels(struckTiles: [next], chargesUltimate: bolt.chargesUltimate)
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
                addLingeringEffect(at: [next], damagePerTurn: lingering.damagePerTurn, duration: lingering.duration, chargesUltimate: bolt.chargesUltimate, creditName: bolt.creditName)
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
                        applyDamage(max(0, bolt.damage - reduction), from: bolt.sourceName)
                        afflictPlayer(with: bolt.affliction)
                    } else {
                        let strike = damageEnemies(on: [next], damage: bolt.damage, chargesUltimate: bolt.chargesUltimate, credit: bolt.creditName, travelling: bolt.direction)
                        afflict(strike, with: bolt.affliction, chargesUltimate: bolt.chargesUltimate, credit: bolt.creditName)
                        if bolt.creditName != nil {
                            struckByPlayerThisTurn.formUnion(strike.map(\.enemyID))
                        }
                        hits += strike
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
            let blastHits = damageEnemies(on: blastSet, damage: bolt.damage, chargesUltimate: bolt.chargesUltimate, credit: bolt.creditName)
            afflict(blastHits, with: bolt.affliction, chargesUltimate: bolt.chargesUltimate, credit: bolt.creditName)
            if bolt.creditName != nil {
                struckByPlayerThisTurn.formUnion(blastHits.map(\.enemyID))
            }
            hits += blastHits
            if !isGameOver && blastSet.contains(playerPosition) {
                let reduction = buffs.reduce(0) { $0 + $1.rangedDamageReduction }
                applyDamage(max(0, bolt.damage - reduction), from: bolt.sourceName)
                afflictPlayer(with: bolt.affliction)
            }
            let chained = detonateBarrels(struckTiles: blastSet, chargesUltimate: bolt.chargesUltimate)
            impacts += chained.explosions
            hits += chained.hits
            if let lingering = bolt.lingering {
                addLingeringEffect(at: blast, damagePerTurn: lingering.damagePerTurn, duration: lingering.duration, chargesUltimate: bolt.chargesUltimate, creditName: bolt.creditName)
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
    private mutating func detonateBarrels(struckTiles: Set<GridPosition>, chargesUltimate: Bool = true) -> (explosions: [TurnResolution.Explosion], hits: [TurnResolution.EnemyHit]) {
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
            // Player-lit barrel chains tally toward the explosives milestones.
            hits += damageEnemies(on: blastSet, damage: Self.barrelDamage, chargesUltimate: chargesUltimate, credit: chargesUltimate ? "Barrels" : nil)
            if !isGameOver && blastSet.contains(playerPosition) && !buffs.contains(where: \.barrelImmunity) {
                applyDamage(Self.barrelDamage, from: "an exploding barrel")
            }
            queue += obstacles.filter {
                $0.kind == .barrel && !detonatedIDs.contains($0.id) && blastSet.contains($0.position)
            }
        }

        obstacles.removeAll { detonatedIDs.contains($0.id) }
        return (explosions, hits)
    }

    // MARK: - Dev mode
    // God-mode hooks for the dev panel (backtick). No gameplay path sets these.

    /// While true the player ignores all damage.
    var devInvincible = false
    /// Dev: suppresses gameplay score gains (kills, survival) so clearing the
    /// board while testing doesn't trip the elite-gate milestone. Explicit dev
    /// score bumps still apply.
    var devFreezeScore = false
    /// Dev: while true, the score milestone never summons a juggernaut or boss.
    var devNoElites = false

    /// Dev-panel override for the next wave. When non-nil, `scheduleSpawns`
    /// forces this on wave turns; nil restores the standard spawn logic.
    enum DevSpawnOverride: Equatable {
        /// Force a shaped squad; nil index picks a random formation.
        case formation(index: Int?)
        /// Force a single enemy; nil archetype/weapon means "roll it normally".
        case single(archetype: Archetype?, weapon: Weapon?)
    }
    var devSpawnOverride: DevSpawnOverride?

    /// Applies a dev spawn override through the normal telegraph pipeline.
    private mutating func applyDevSpawn(_ override: DevSpawnOverride) {
        switch override {
        case .formation(let index):
            let forced = index.flatMap { Formation.all.indices.contains($0) ? Formation.all[$0] : nil }
            _ = spawnFormation(forced)
        case .single(let archetype, let weapon):
            let taken = Set(enemies.map(\.position))
                .union(obstacles.map(\.position))
                .union(lingeringEffects.map(\.position))
            guard let tile = edgeTiles().filter({
                !taken.contains($0) && $0.distance(to: playerPosition) > 3
            }).randomElement() else { return }
            pendingArrivals = [Enemy.devSpawn(archetype: archetype, weapon: weapon, id: nextEnemyID, at: tile, armory: weaponPool)]
            nextEnemyID += 1
        }
    }

    mutating func devSetUltimateCharge(_ value: Int) {
        ultimateKillCharge = max(0, min(Self.ultimateChargeKills, value))
    }

    mutating func devHealFully() {
        playerHealth = maxHealth
        playerArmor = armorCap
    }

    mutating func devAddScore(_ amount: Int) {
        score += amount
    }

    /// Armor absorbs damage first; only the overflow reaches health. The
    /// source label feeds the death recap when the hit proves fatal.
    private mutating func applyDamage(_ amount: Int, from source: String) {
        guard !devInvincible else { return }
        let absorbed = min(playerArmor, amount)
        playerArmor -= absorbed
        playerHealth -= amount - absorbed
        totalDamageTaken += amount
        if playerHealth <= 0 && causeOfDeath == nil {
            causeOfDeath = source
        }
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
        let incomingTiles = Set(projectileThreatTiles)
            .union(pendingSpawns)
            .union(bomberThreatTiles)
            // The tile a bolt is sitting on: walking through it is a collision.
            .union(bolts.map(\.position))
        // Slow arcing lobs specifically — the only telegraphed danger enemies
        // will gamble on (see the greedy fallback below). Bolts and bomber
        // blasts are not in here, so they stay strictly avoided.
        let lobZones = Set(projectiles.flatMap {
            blastTiles(around: $0.target, radius: $0.blastRadius, includeCenter: true)
        })
        var claimed = Set(enemies.map(\.position))
            .union(obstacles.map(\.position))
            .union(hazardTiles)
            .union(incomingTiles)
            .union([playerPosition])

        // Advance each live squad's anchor one tile toward the player, and
        // disband any that have closed in (or been whittled below two) so their
        // members break ranks and engage individually this very turn. Members
        // still inbound this turn count too, so a freshly drafted squad isn't
        // disbanded before it even lands; and the anchor only marches once the
        // squad is actually on the board.
        for (fid, anchor) in formationAnchors {
            let live = enemies.filter { $0.formationID == fid }
            let inbound = pendingArrivals.filter { $0.formationID == fid }.count
            // Bombers peel off on their own (below), so a forward bomber doesn't
            // drag the whole squad's break early — measure from the others.
            let nearest = live.filter { $0.archetype != .bomber }
                .map { $0.position.distance(to: playerPosition) }.min() ?? Int.max
            if live.count + inbound < 2
                || anchor.distance(to: playerPosition) <= Self.formationBreakDistance
                || nearest <= Self.formationBreakDistance {
                for index in enemies.indices where enemies[index].formationID == fid {
                    enemies[index].formationID = nil
                }
                formationAnchors[fid] = nil
            } else if !live.isEmpty {
                // Route the anchor around scenery — marching it straight through
                // walls would drag members' slots onto tiles they can't reach and
                // shred the squad against the wall.
                formationAnchors[fid] = stepToward(playerPosition, from: anchor, avoiding: Set(obstacles.map(\.position)))
            }
        }

        // Front-liners plan first so they vacate their tiles before the enemies
        // behind them draft — letting a column flow forward instead of jamming
        // up behind the leader (each mover frees its old tile from `claimed`).
        let draftOrder = enemies.indices.sorted {
            enemies[$0].position.distance(to: playerPosition) < enemies[$1].position.distance(to: playerPosition)
        }
        for index in draftOrder {
            let enemy = enemies[index]
            let ready = enemy.cooldownRemaining == 0
            // Fearless archetypes (berserkers, bombers) path straight through
            // pools and telegraphed danger.
            let fearless = enemy.isFearless
            let avoid = fearless
                ? claimed.subtracting(hazardTiles).subtracting(incomingTiles)
                : claimed

            // Formation cohesion comes first: a member holds its slot and marches
            // with the squad, looses a shot from its slot if it has a clean lane,
            // and doesn't engage until the squad breaks. Bombers hold too but
            // peel off early — once one is within bomberBreakDistance it drops
            // formation here and falls through to its charge below, so it detonates
            // out ahead of the escorts instead of among them.
            if let fid = enemy.formationID, let anchor = formationAnchors[fid] {
                if enemy.archetype == .bomber
                    && enemy.position.distance(to: playerPosition) <= Self.bomberBreakDistance {
                    enemies[index].formationID = nil
                } else {
                    let goal = GridPosition(x: anchor.x + enemy.formationOffset.x, y: anchor.y + enemy.formationOffset.y)
                    var target = enemy.position
                    var path: [GridPosition] = []
                    for _ in 0..<enemy.moveRange {
                        let next = stepToward(goal, from: target, avoiding: avoid)
                        if next == target { break }
                        target = next
                        path.append(next)
                        if target == goal { break }
                    }
                    enemies[index].plannedTarget = target
                    enemies[index].plannedPath = path
                    enemies[index].plannedDirection = nil
                    enemies[index].plannedThrowTarget = nil
                    // Shields stay squared toward the player even on the march.
                    if enemy.archetype == .shieldbearer {
                        enemies[index].facing = Direction.aiming(from: target, toward: playerPosition, allowDiagonals: true)
                    }
                    // A ranged member still fires from its slot with a clean lane;
                    // bombers never jab.
                    if ready && enemy.archetype != .bomber && canHitPlayer(enemy, from: target) {
                        if enemy.weapon.thrown != nil {
                            enemies[index].plannedThrowTarget = playerPosition
                        } else {
                            enemies[index].plannedDirection = aimDirection(for: enemy, from: target)
                        }
                    }
                    claimed.remove(enemy.position)
                    claimed.insert(target)
                    continue
                }
            }

            // An armed bomber sits on its fuse; an unarmed one just wants to be
            // next to you.
            if enemy.archetype == .bomber {
                enemies[index].plannedDirection = nil
                enemies[index].plannedThrowTarget = nil
                var target = enemy.position
                var path: [GridPosition] = []
                if enemy.fuse == nil {
                    // Close enough already: arm in place. Otherwise close in.
                    if enemy.position.distance(to: playerPosition) > Self.bomberArmDistance {
                        let goal = attackGoal(for: enemy, avoiding: avoid)
                        for _ in 0..<enemy.moveRange {
                            let next = stepToward(goal, from: target, avoiding: avoid)
                            if next == target {
                                break
                            }
                            target = next
                            path.append(next)
                            if target.distance(to: playerPosition) <= Self.bomberArmDistance {
                                break
                            }
                        }
                    }
                    if target.distance(to: playerPosition) <= Self.bomberArmDistance {
                        enemies[index].fuse = Self.bomberFuseTurns
                    }
                }
                enemies[index].plannedTarget = target
                enemies[index].plannedPath = path
                claimed.remove(enemy.position)
                claimed.insert(target)
                continue
            }

            // An enemy standing somewhere that burns or is about to be hit
            // repositions even if it could attack from here (fearless ones don't
            // care).
            let inDanger = !fearless
                && (hazardTiles.contains(enemy.position) || incomingTiles.contains(enemy.position))
            var target = enemy.position
            var path: [GridPosition] = []
            let canHitHere = canHitPlayer(enemy, from: enemy.position)
            let skirmisher = enemy.weapon.isRanged
                && enemy.archetype != .boss && enemy.archetype != .juggernaut
            let cautiousDanger: Set<GridPosition> = fearless ? [] : hazardTiles.union(incomingTiles)
            if !canHitHere || inDanger {
                (target, path) = pressApproach(enemy, blocked: avoid, danger: cautiousDanger)
                // Slow lobs are only a soft deterrent: if dodging them would cost
                // this enemy its attack, it presses in and braves the blast
                // instead of idling — its own miscalculation, symmetric with a
                // greedy player who eats a hit to land one. Fast, certain threats
                // (bolts, bomber blasts, arriving spawns) stay hard-avoided.
                if !fearless && !skirmisher && !lobZones.isEmpty
                    && !canHitPlayer(enemy, from: target) {
                    let reckless = pressApproach(
                        enemy,
                        blocked: avoid.subtracting(lobZones),
                        danger: cautiousDanger.subtracting(lobZones)
                    )
                    // Brave the blast only to attack from there, and only when
                    // the hit wouldn't kill it — enemies gamble on damage, not
                    // on death.
                    if canHitPlayer(enemy, from: reckless.target)
                        && lobDamage(at: reckless.target) < enemy.health {
                        (target, path) = reckless
                    }
                }
            } else if skirmisher {
                // Ranged skirmishers never stand still politely: with room to
                // kite they back off (still firing when ready), and pinned at
                // max range while reloading they duck out of the fight.
                let currentDistance = enemy.position.distance(to: playerPosition)
                let kite = attackGoal(for: enemy, avoiding: avoid)
                var goal: GridPosition?
                var mustKeepFiring = ready
                if kite.distance(to: playerPosition) > currentDistance {
                    goal = kite
                } else if !ready {
                    goal = hidingSpot(for: enemy, avoiding: avoid)
                    mustKeepFiring = false
                }
                if let goal {
                    var lastFiringTile: GridPosition?
                    var firingPath: [GridPosition] = []
                    for _ in 0..<enemy.moveRange {
                        let next = stepToward(goal, from: target, avoiding: avoid)
                        if next == target {
                            break
                        }
                        target = next
                        path.append(next)
                        if canHitPlayer(enemy, from: target) {
                            lastFiringTile = target
                            firingPath = path
                        }
                    }
                    // A ready archer won't drift anywhere it can't shoot from.
                    if mustKeepFiring && !canHitPlayer(enemy, from: target) {
                        target = lastFiringTile ?? enemy.position
                        path = lastFiringTile == nil ? [] : firingPath
                    }
                }
            }
            enemies[index].plannedTarget = target
            enemies[index].plannedPath = path
            enemies[index].plannedDirection = nil
            enemies[index].plannedThrowTarget = nil
            enemies[index].plannedIntent = nil
            enemies[index].plannedSecondaryDirection = nil
            enemies[index].plannedDetonateTile = nil
            // The shieldbearer squares its shield up toward the player from
            // wherever it plans to end — telegraphed, so a flank can be planned.
            if enemy.archetype == .shieldbearer {
                enemies[index].facing = Direction.aiming(from: target, toward: playerPosition, allowDiagonals: true)
            }
            if enemy.archetype == .boss {
                draftBossIntent(at: index, from: target)
            } else if ready && canHitPlayer(enemy, from: target) {
                if enemy.weapon.thrown != nil {
                    enemies[index].plannedThrowTarget = playerPosition
                } else {
                    enemies[index].plannedDirection = aimDirection(for: enemy, from: target)
                }
            }
            claimed.remove(enemy.position)
            claimed.insert(target)
        }
    }

    /// Total impact damage the airborne lobs would deal to a body ending on
    /// `tile` — what a greedy enemy weighs against its own health before it
    /// braves a blast to attack.
    private func lobDamage(at tile: GridPosition) -> Int {
        projectiles.reduce(0) { sum, lob in
            blastTiles(around: lob.target, radius: lob.blastRadius, includeCenter: true).contains(tile)
                ? sum + lob.damage : sum
        }
    }

    /// Walks an enemy up to its move range toward a tile it can attack the
    /// player from, avoiding `blocked`. `danger` is the subset it would rather
    /// not end on (pools, telegraphed blasts): trapped in one, it wades toward
    /// clear ground, and it won't call an attack position "good enough" to stop
    /// early while still standing in danger.
    private func pressApproach(_ enemy: Enemy, blocked: Set<GridPosition>, danger: Set<GridPosition>) -> (target: GridPosition, path: [GridPosition]) {
        var target = enemy.position
        var path: [GridPosition] = []
        let goal = attackGoal(for: enemy, avoiding: blocked)
        for _ in 0..<enemy.moveRange {
            var next = stepToward(goal, from: target, avoiding: blocked)
            if next == target && danger.contains(target) {
                next = stepToward(goal, from: target, avoiding: blocked.subtracting(danger))
            }
            if next == target {
                break
            }
            target = next
            path.append(next)
            if canHitPlayer(enemy, from: target) && !danger.contains(target) {
                break
            }
        }
        return (target, path)
    }

    /// The boss drafts one of three intents from wherever it plans to stand:
    /// a point-blank cannon nova when the player is in blast range, both
    /// weapons at once when either can reach, or a summon to rebuild its
    /// retinue when guns are down or ranks are thin.
    private mutating func draftBossIntent(at index: Int, from tile: GridPosition) {
        let boss = enemies[index]
        let config = BossConfig.forLevel(level)
        let retinue = enemies.filter { $0.archetype != .boss && $0.archetype != .juggernaut }.count
        // Summoning is gated both by the retinue cap (how many) and a cadence
        // (how often) — a fresh wave of fodder mostly dies to bombers, the
        // boss's own greataxe/nova friendly fire, and the player's blasts, so
        // without the cadence the boss would resummon every single turn.
        let canSummon = retinue < config.retinueCap
            && turnNumber - lastBossSummonTurn >= Self.bossSummonInterval

        // The cannon and primary reload independently, so nova and volley
        // interleave — one keeps pressure up while the other is cooling.
        let primaryReady = boss.cooldownRemaining == 0
        let cannonReady = boss.secondaryCooldownRemaining == 0

        // Weapons come first: a ready boss fires rather than fiddling with
        // abilities, so hugging it (with the cannon loaded) earns a nova and
        // standing at range a volley.
        if cannonReady && playerPosition.distance(to: tile) <= config.novaRadius {
            enemies[index].plannedIntent = .nova
            return
        }
        // A volley fires whichever weapons are both loaded and have a firing
        // line; a melee primary that can't reach the player is left holstered
        // so it doesn't scythe the boss's own retinue for nothing.
        let primaryAim = primaryReady ? aimDirection(weapon: boss.weapon, attackerID: boss.id, from: tile) : nil
        let cannonAim = (cannonReady ? boss.secondaryWeapon : nil)
            .flatMap { aimDirection(weapon: $0, attackerID: boss.id, from: tile) }
        if primaryAim != nil || cannonAim != nil {
            // With a firing solution the boss volleys, occasionally rebuilding
            // a thinned retinue instead so it isn't a pure turret.
            if canSummon && Int.random(in: 0..<4) == 0 {
                enemies[index].plannedIntent = .summon
            } else {
                enemies[index].plannedIntent = .volley
                enemies[index].plannedDirection = primaryAim
                enemies[index].plannedSecondaryDirection = cannonAim
            }
            return
        }

        // No shot available (reloading with no target, or out of every firing
        // line): fall back to a single ability, in priority order — this is
        // where the boss makes its downtime count rather than idling.
        // 1) Cash in a primed barrel that has the player boxed in.
        if let detonateTile = bossDetonationTarget() {
            enemies[index].plannedIntent = .detonate
            enemies[index].plannedDetonateTile = detonateTile
            return
        }
        // 2) Rebuild thinned ranks.
        if canSummon {
            enemies[index].plannedIntent = .summon
            return
        }
        // 3) Lay a fresh barrel trap — but only while few of its own are still
        //    live, so the arena isn't flooded with red barrels (and detonate
        //    stays an occasional payoff rather than a spam).
        let liveVolatile = obstacles.filter { $0.kind == .barrel && $0.volatile }.count
        if liveVolatile < config.bossBarrageCount && !barrageTiles().isEmpty {
            enemies[index].plannedIntent = .barrage
        }
    }

    /// Open tiles 1–3 tiles from the player the boss could drop barrels onto —
    /// free of bodies, scenery, and hazards.
    private func barrageTiles() -> [GridPosition] {
        let taken = Set(enemies.map(\.position))
            .union(obstacles.map(\.position))
            .union(lingeringEffects.map(\.position))
            .union([playerPosition])
        return blastTiles(around: playerPosition, radius: 3).filter { !taken.contains($0) }
    }

    /// The barrel the boss should set off: one of its own primed (red) barrels
    /// whose chain would catch the player. Ordinary orange barrels are off
    /// limits — red is the player's tell that the boss can trigger it. nil if
    /// none currently threaten the player.
    private func bossDetonationTarget() -> GridPosition? {
        obstacles.first {
            $0.kind == .barrel && $0.volatile && barrelChainBlast(from: $0.position).contains(playerPosition)
        }?.position
    }

    /// Every tile a chain detonation starting at `origin` would cover, walking
    /// the same barrel-to-barrel spread as detonateBarrels but read-only — used
    /// to telegraph the boss's detonate intent honestly.
    private func barrelChainBlast(from origin: GridPosition) -> [GridPosition] {
        var queue = obstacles.filter { $0.kind == .barrel && $0.position == origin }
        var done = Set<Int>()
        var tiles = Set<GridPosition>()
        while let barrel = queue.popLast() {
            guard !done.contains(barrel.id) else { continue }
            done.insert(barrel.id)
            let blast = blastTiles(around: barrel.position, radius: Self.barrelBlastRadius)
            tiles.formUnion(blast)
            let blastSet = Set(blast)
            queue += obstacles.filter {
                $0.kind == .barrel && !done.contains($0.id) && blastSet.contains($0.position)
            }
        }
        return Array(tiles)
    }

    /// A nearby open tile this enemy can't hit the player from — cover to duck
    /// behind (or, for throwers, ground beyond range) while the weapon reloads.
    /// Nearest wins; ties prefer more distance from the player.
    private func hidingSpot(for enemy: Enemy, avoiding claimed: Set<GridPosition>) -> GridPosition? {
        let reach = enemy.moveRange * 2
        var best: (tile: GridPosition, walk: Int, playerDistance: Int)?
        for dx in -reach...reach {
            let remaining = reach - abs(dx)
            for dy in -remaining...remaining {
                let tile = GridPosition(x: enemy.position.x + dx, y: enemy.position.y + dy)
                guard contains(tile), tile != enemy.position, !claimed.contains(tile),
                      !canHitPlayer(enemy, from: tile) else { continue }
                let walk = enemy.position.distance(to: tile)
                let playerDistance = tile.distance(to: playerPosition)
                if best == nil
                    || walk < best!.walk
                    || (walk == best!.walk && playerDistance > best!.playerDistance) {
                    best = (tile, walk, playerDistance)
                }
            }
        }
        return best?.tile
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
        aimDirection(weapon: enemy.weapon, attackerID: enemy.id, from: tile)
    }

    /// Same, for an explicit weapon — the boss aims its cannon independently
    /// of its primary.
    private func aimDirection(weapon: Weapon, attackerID: Int, from tile: GridPosition) -> Direction? {
        guard let pattern = weapon.attackPattern else { return nil }
        // Only nearby comrades block the aim — the shield right in front, not a
        // teammate way down the lane (who stays fair game, so long-range friendly
        // fire remains exploitable). Measured against where they'll BE, not where
        // they are: a marching shield wall steps forward in lockstep, so a lane
        // clear of a shield's current tile would still put it in front of the bolt
        // at resolve. Front-liners draft first, so their plannedTarget is known.
        let blockers = Set(enemies
            .filter { $0.id != attackerID }
            .map { $0.plannedTarget ?? $0.position }
            .filter { $0.distance(to: tile) <= Self.friendlyAimGuardRange })
        // A bolt won't be lined up through a comrade's back: even if the shot
        // itself pierces, the enemy only takes it when the player is the first
        // body on the line (so archers behind a shield wall hold or reposition
        // for a clear angle rather than shooting their own shields).
        let aimPierces = weapon.projectileSpeed == nil && weapon.pierces
        return Direction.allCases.first { direction in
            sweep(pattern, from: tile, facing: direction, pierces: aimPierces, blockers: blockers)
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
