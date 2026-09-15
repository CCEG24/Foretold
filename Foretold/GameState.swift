//
//  GameState.swift
//  Foretold
//
//  Name idea - The Final Draft

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
    /// Toggling spike traps scattered on the floor.
    let spikeTraps: Int
    /// Linked teleporter pairs on the floor.
    let teleporterPairs: Int
    /// Ice strips scattered on the floor (each a short run you slide across).
    let icePatches: Int
    /// Mud tiles scattered on the floor (each costs a step of movement).
    let mudPatches: Int

    static func forLevel(_ level: Int) -> LevelConfig {
        LevelConfig(
            startingEnemies: min(3 + level, 8),
            spawnInterval: max(2, 3 - (level - 1) / 4),
            spawnBatch: 1 + (level - 1) / 3,
            walls: 10,
            barrels: min(3 + level, 12),
            spikeTraps: min(2 + level / 2, 6),
            teleporterPairs: level >= 2 ? 1 : 0,
            icePatches: level >= 2 ? min(1 + level / 3, 3) : 0,
            mudPatches: level >= 2 ? min(2 + level / 2, 5) : 0
        )
    }
}

/// A run "condition." Each is atomic and cleanly good (a boon) or bad (a curse);
/// a run's pact pairs one random boon with one random curse, so they balance each
/// other and no single modifier needs internal tuning. See `RunRules`, which
/// folds a chosen set into the plain knobs the turn logic reads.
enum RunModifier: String, CaseIterable {
    // Boons ⚡ — purely in the player's favor.
    case sharpened, quickdraw, quickhands, bulwark, vigor, momentum, warded, rampage, sidestep
    case deadeye, lifelink, breach
    // Curses ☠ — purely against the player.
    case fragile, swarm, brittle, warband, frenzy, powderKeg, scarcity, leadfoot, volatile, sappers, impaler, barricades, blindfold
    case rusting, overgrowth

    var isBoon: Bool {
        switch self {
        case .sharpened, .quickdraw, .quickhands, .bulwark, .vigor, .momentum,
             .warded, .rampage, .sidestep, .deadeye, .lifelink, .breach: return true
        case .fragile, .swarm, .brittle, .warband, .frenzy, .powderKeg,
             .scarcity, .leadfoot, .volatile, .sappers, .impaler, .barricades, .blindfold,
             .rusting, .overgrowth: return false
        }
    }

    static var boons: [RunModifier] { allCases.filter(\.isBoon) }
    static var curses: [RunModifier] { allCases.filter { !$0.isBoon } }

    var title: String {
        switch self {
        case .sharpened: return "Sharpened"
        case .quickdraw: return "Quickdraw"
        case .quickhands: return "Quickhands"
        case .bulwark: return "Bulwark"
        case .vigor: return "Vigor"
        case .momentum: return "Momentum"
        case .warded: return "Warded"
        case .rampage: return "Rampage"
        case .sidestep: return "Sidestep"
        case .deadeye: return "Deadeye"
        case .lifelink: return "Lifelink"
        case .breach: return "Breach"
        case .fragile: return "Fragile"
        case .swarm: return "Swarm"
        case .brittle: return "Brittle"
        case .warband: return "Warband"
        case .frenzy: return "Frenzy"
        case .powderKeg: return "Powder Keg"
        case .scarcity: return "Scarcity"
        case .leadfoot: return "Leadfoot"
        case .volatile: return "Volatile"
        case .sappers: return "Sappers"
        case .impaler: return "Impaler"
        case .barricades: return "Barricades"
        case .blindfold: return "Blindfold"
        case .rusting: return "Rusting"
        case .overgrowth: return "Overgrowth"
        }
    }

    var blurb: String {
        switch self {
        case .sharpened: return "your attacks deal double"
        case .quickdraw: return "your cooldowns −1"
        case .quickhands: return "weapon swaps are free"
        case .bulwark: return "+2 max armor"
        case .vigor: return "+2 max health"
        case .momentum: return "+1 move range"
        case .warded: return "immune to barrel blasts"
        case .rampage: return "a kill shaves your reload"
        case .sidestep: return "dodge by moving just 1"
        case .deadeye: return "your shots pierce foes and walls"
        case .lifelink: return "every 3rd kill heals you 1 HP"
        case .breach: return "your blasts level any wall"
        case .fragile: return "you take double damage"
        case .swarm: return "bigger, faster waves"
        case .brittle: return "no armor regen"
        case .warband: return "every gate is a boss"
        case .frenzy: return "enemies' cooldowns −1"
        case .powderKeg: return "walls become barrels"
        case .scarcity: return "no weapons drop"
        case .leadfoot: return "you can't dodge"
        case .volatile: return "barrel blasts are bigger"
        case .sappers: return "every foe is a bomber"
        case .impaler: return "spikes never retract"
        case .barricades: return "every tile starts walled — blast through"
        case .blindfold: return "your health is hidden"
        case .rusting: return "armor mends slower — every 3 turns"
        case .overgrowth: return "spikes overrun the floor"
        }
    }
}

/// The chosen modifiers folded into flat knobs the turn logic reads, computed
/// once so the rules never scatter `if modifiers.contains(...)` checks around.
struct RunRules {
    var allBarrels = false
    var spawnBatchBonus = 0
    var spawnIntervalDelta = 0
    var startingEnemiesBonus = 0
    var damageDealtMult = 1.0
    var damageTakenMult = 1.0
    var playerCooldownDelta = 0
    var enemyCooldownDelta = 0
    var bonusMaxArmor = 0
    var bonusMaxHealth = 0
    var bonusMoveRange = 0
    var armorRegen = true
    var bossEveryGate = false
    var freeSwap = false
    var barrelImmune = false
    var killRefundsCooldown = false
    var noLoot = false
    var barrelBlastBonus = 0
    var allBombers = false
    /// Spike traps stay armed every turn instead of toggling off.
    var spikesAlwaysLive = false
    /// Every open tile starts as a crumbling wall — blast/hack your way out.
    var wallsEverywhere = false
    /// The player's health readout is hidden — fight by feel.
    var hideHealth = false
    /// Your fired shots pierce foes and bore through walls.
    var piercingShots = false
    /// A kill restores 1 health.
    var killHeals = false
    /// Your attacks shatter any wall, not only crumbling ones.
    var bustsAllWalls = false
    /// Extra spike traps scattered on every level's floor.
    var spikeTrapBonus = 0
    /// Undamaged turns between each point of armor regen (Rusting stretches it).
    var armorRegenInterval = 2
    /// nil = normal dodge distance; 1 = easy dodge; huge = never dodge.
    var dodgeDistanceOverride: Int?

    init(_ modifiers: Set<RunModifier> = []) {
        for modifier in modifiers {
            switch modifier {
            case .sharpened: damageDealtMult *= 2
            case .quickdraw: playerCooldownDelta -= 1
            case .quickhands: freeSwap = true
            case .bulwark: bonusMaxArmor += 2
            case .vigor: bonusMaxHealth += 2
            case .momentum: bonusMoveRange += 1
            case .warded: barrelImmune = true
            case .rampage: killRefundsCooldown = true
            case .sidestep: dodgeDistanceOverride = 1
            case .fragile: damageTakenMult *= 2
            case .swarm:
                spawnBatchBonus += 1
                spawnIntervalDelta -= 1
                startingEnemiesBonus += 2
            case .brittle: armorRegen = false
            case .warband: bossEveryGate = true
            case .frenzy: enemyCooldownDelta -= 1
            case .powderKeg: allBarrels = true
            case .scarcity: noLoot = true
            case .leadfoot: dodgeDistanceOverride = .max
            case .volatile: barrelBlastBonus += 1
            case .sappers: allBombers = true
            case .impaler: spikesAlwaysLive = true
            case .barricades: wallsEverywhere = true
            case .blindfold: hideHealth = true
            case .deadeye: piercingShots = true
            case .lifelink: killHeals = true
            case .breach: bustsAllWalls = true
            case .rusting: armorRegenInterval = 3
            case .overgrowth: spikeTrapBonus += 3
            }
        }
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
    /// Summoner elite starting health.
    let summonerHealth: Int
    /// Recruits the summoner calls in per summon intent — a touch bigger than the
    /// boss's, since flooding the board with fodder is its whole identity.
    let summonerSummonCount: Int
    /// Bombardier elite starting health.
    let bombardierHealth: Int
    /// Bombers the bombardier calls in per summon intent (kept smaller than the
    /// summoner's fodder — a swarm of walking bombs is far deadlier).
    let bombardierSummonCount: Int

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
            bossBarrageCount: ramp(2, step: 1, every: 4, cap: 4),
            summonerHealth: ramp(14, step: 1, every: 1, cap: 30),
            summonerSummonCount: ramp(4, step: 1, every: 3, cap: 6),
            bombardierHealth: ramp(14, step: 1, every: 1, cap: 30),
            bombardierSummonCount: ramp(2, step: 1, every: 3, cap: 4)
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
    /// Damage an active spike trap deals to whoever ends the turn on it.
    static let spikeDamage = 2
    /// Damage each body takes when a knockback flings one enemy into another.
    static let knockbackImpactDamage = 2
    /// Extra damage from being flung into a wall or the board's edge.
    static let wallSlamDamage = 1
    /// A barrel reeled in by a grapple bursts softer than a normal blast — the
    /// price of a controlled pop at your own feet.
    static let grappleBarrelDamage = 2
    /// A yellow (Keg-lobbed) barrel's blast — half a standard barrel's.
    static let weakBarrelDamage = 2
    /// Yellow barrels are light empty kegs, so a knockback skids them this many
    /// extra tiles.
    static let weakBarrelPushBonus = 2
    /// A green barrel deals no blast damage; it leaves fire burning this hot for
    /// this many turns on the tiles it covered.
    static let fireBarrelDamage = 2
    static let fireBarrelDuration = 2
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
    /// The conditions switched on for this run, and their folded-down rules.
    let modifiers: Set<RunModifier>
    let rules: RunRules
    /// Armor absorbs damage before health and regenerates 1 on every second
    /// consecutive turn without taking damage (Soul Knight style); health never
    /// regenerates.
    let maxArmor: Int
    private(set) var equippedWeapon: Weapon
    /// The backup weapon. Only two can be carried (Soul Knight style); swapping
    /// exchanges it with the equipped one.
    private(set) var holsteredWeapon: Weapon
    /// The weapon equipped at the start of this planning phase. A net swap away
    /// from it spends the turn's action (unless the run grants free swaps) —
    /// swapping back to it refunds, so fiddling costs nothing.
    private var turnStartWeapon: Weapon

    /// Swaps are free (no attack spent) if a pact (Quickhands) or a held boon
    /// (Quick Hands) grants it.
    var swapsAreFree: Bool { devFreeSwap || rules.freeSwap || buffs.contains(where: \.freeSwap) }
    /// A kill this turn shaves the reload, from a pact (Rampage) or a boon.
    var killShavesReload: Bool { rules.killRefundsCooldown || buffs.contains(where: \.killRefundsCooldown) }
    /// True when the player has swapped to a different weapon this turn and the
    /// swap wasn't free — it has spent this turn's attack.
    var weaponSwapCostsAttack: Bool { !swapsAreFree && equippedWeapon != turnStartWeapon }
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
    /// Toggling floor spikes and linked teleporter pairs — non-blocking board
    /// hazards scattered into every level.
    private(set) var spikes: [SpikeTrap] = []
    private(set) var teleporters: [Teleporter] = []
    /// Movement-warping floor patches (ice, mud); affect player and enemies
    /// alike — see `TerrainPatch`.
    private(set) var terrain: [TerrainPatch] = []
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
    /// Kills banked toward the next Lifelink/Bloodthirst heal (every 3rd mends 1).
    private var lifelinkKills = 0
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
    /// True when the queued summons are the bombardier's — every arrival a bomber.
    private var queuedSummonsBomberOnly = false
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
    /// Shuffle-bag of the non-boss gate elites, so every gate cycles through all
    /// three (juggernaut/summoner/artillery) rather than repeating on a streak.
    private var lesserEliteBag: [Archetype] = []
    /// The last lesser elite drawn, so a refilled bag doesn't repeat it back-to-back.
    private var lastLesserElite: Archetype?
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
    /// plus any buff bonuses. Dev infinite-speed opens the whole board.
    var moveRange: Int {
        if devInfiniteSpeed { return columns + rows }
        let base = equippedWeapon.moveRange + buffs.reduce(0) { $0 + $1.bonusMoveRange } + rules.bonusMoveRange
        // The floor underfoot gives (ice) or takes (mud) a step, never below 1.
        return max(1, base + terrainMoveDelta(at: playerPosition))
    }
    /// Damage the player's attacks deal: the equipped weapon's plus buff
    /// bonuses. Dev damage mode overrides it for testing — one-shot everything,
    /// or deal nothing so a struck enemy survives repeated stun/knockback trials.
    var attackDamage: Int {
        switch devDamageMode {
        case .instakill: return 999
        case .zero: return 0
        case .normal:
            let base = equippedWeapon.damage + buffs.reduce(0) { $0 + $1.bonusDamage }
            return Int((Double(base) * rules.damageDealtMult).rounded())
        }
    }
    /// The armor ceiling right now: the base cap plus buff bonuses.
    var armorCap: Int { maxArmor + buffs.reduce(0) { $0 + $1.bonusArmor } }
    var isGameOver: Bool { playerHealth <= 0 }

    /// The tile the drafted move truly ends on: the chosen tile, or — if that
    /// tile is ice — wherever the ensuing slide comes to rest. This is what the
    /// scene should draw as the destination, and where an attack originates.
    var plannedLanding: GridPosition {
        guard let target = plannedTarget else { return playerPosition }
        guard terrainKind(at: target) == .ice,
              let direction = Direction.aiming(from: playerPosition, toward: target, allowDiagonals: true)
        else { return target }
        return iceSlide(landingOn: target, heading: direction, moverIsPlayer: true, extraBlocked: []).destination
    }

    /// Where a drafted attack or throw would originate right now — the post-slide
    /// landing, so aiming previews from where the player actually ends up.
    var attackOrigin: GridPosition { plannedLanding }

    /// Turns before the given carried weapon can attack again; 0 means ready.
    /// Dev no-cooldown reports every weapon as ready so it can be fired each turn.
    func attackCooldownRemaining(of weapon: Weapon) -> Int {
        devNoCooldown ? 0 : (weaponCooldowns[weapon.name] ?? 0)
    }

    /// A player weapon's reload with this run's conditions applied (Quickdraw
    /// shaves a turn off). Never below zero.
    func effectivePlayerCooldown(_ base: Int) -> Int {
        max(0, base + rules.playerCooldownDelta)
    }

    /// An enemy weapon's reload with this run's conditions applied (Frenzy shaves
    /// a turn off). Never below zero.
    func effectiveEnemyCooldown(_ base: Int) -> Int {
        max(0, base + rules.enemyCooldownDelta)
    }

    var canAttack: Bool { attackCooldownRemaining(of: equippedWeapon) == 0 }

    /// A reloading ranged weapon still jabs: 1 damage, one adjacent tile.
    static let bashDamage = 1
    /// True when the drafted attack is the reload-jab rather than the weapon's
    /// real attack.
    private(set) var plannedBash = false

    /// A bleed or poison riding on the player; ticks at the end of each turn.
    private(set) var playerAffliction: ActiveAffliction?

    /// Turns the player's *action* is disabled by a stun. The move is never
    /// taken away — only the drafted attack/throw/ultimate fizzles — so the
    /// player is never denied a choice they can't see coming.
    private(set) var playerStunTurns = 0

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

    /// Dazes every survivor of a stunning strike. Refreshes to the longer of
    /// any existing stun and the new one, so overlapping hits don't cut it short.
    private mutating func applyStun(_ hits: [TurnResolution.EnemyHit], turns: Int) {
        guard turns > 0 else { return }
        for hit in hits where !hit.died {
            guard let index = enemies.firstIndex(where: { $0.id == hit.enemyID }) else { continue }
            enemies[index].stunTurns = max(enemies[index].stunTurns, turns)
        }
    }

    /// Dazes the player: their next action is voided, but not their move.
    private mutating func applyPlayerStun(_ turns: Int) {
        guard turns > 0, !isGameOver, !devStunImmune else { return }
        playerStunTurns = max(playerStunTurns, turns)
    }

    /// Flings the given enemies up to `distance` tiles down `direction`, one
    /// step at a time. The shove follows the actual swing — a diagonal hit shoves
    /// diagonally — so a body can be driven into scenery lined up at 45°. It stops
    /// short of the board edge, a wall, another body, or the player; driving one
    /// into a barrel detonates it (the marquee interaction). An enemy that ends on
    /// a hazard pool just burns there at the usual end-of-turn tick.
    private mutating func shoveEnemies(
        ids: [Int],
        direction: Direction,
        distance: Int
    ) -> (shoves: [TurnResolution.Shove], explosions: [TurnResolution.Explosion], hits: [TurnResolution.EnemyHit]) {
        // Push straight down the swing's facing (unitStep is already a clean
        // ±1 step on each axis it touches, cardinal or diagonal).
        let push = direction.unitStep

        var shoves: [TurnResolution.Shove] = []
        var explosions: [TurnResolution.Explosion] = []
        var hits: [TurnResolution.EnemyHit] = []

        // Push the enemy furthest along the shove first, so the tile ahead of
        // the one behind it has already cleared.
        let sortedIDs = ids.sorted { lhs, rhs in
            let lp = enemies.first(where: { $0.id == lhs })?.position ?? GridPosition(x: 0, y: 0)
            let rp = enemies.first(where: { $0.id == rhs })?.position ?? GridPosition(x: 0, y: 0)
            return (lp.x * push.x + lp.y * push.y) > (rp.x * push.x + rp.y * push.y)
        }

        for id in sortedIDs {
            guard let index = enemies.firstIndex(where: { $0.id == id }) else { continue }
            let from = enemies[index].position
            var current = from
            var crossed: [GridPosition] = []
            var slammedBarrel: GridPosition?
            var slammedEnemyTile: GridPosition?
            var slammedWall = false
            for _ in 0..<distance {
                let next = GridPosition(x: current.x + push.x, y: current.y + push.y)
                guard contains(next) else { slammedWall = true; break }
                if let scenery = obstacle(at: next) {
                    if scenery.kind == .barrel { slammedBarrel = next } else { slammedWall = true }
                    break
                }
                if next == playerPosition { break }
                if let other = enemies.first(where: { $0.id != id && $0.position == next }) {
                    slammedEnemyTile = other.position
                    break
                }
                current = next
                crossed.append(next)
            }
            if current != from {
                enemies[index].position = current
                shoves.append(TurnResolution.Shove(enemyID: id, from: from, to: current))
            }
            // Live spikes it was flung *across* bite it in passing — the tile it
            // ends on is left to the usual end-of-turn tick, so it isn't double-
            // counted. Route each bite through the enemy's resting tile so it
            // lands on this specific body (which has already moved off the spike).
            let raked = crossed.dropLast().filter { tile in
                spikes.contains { $0.active && $0.position == tile }
            }.count
            for _ in 0..<raked {
                hits += damageEnemies(on: [current], damage: Self.spikeDamage, chargesUltimate: false)
            }
            if let barrel = slammedBarrel {
                let blast = detonateBarrels(struckTiles: [barrel])
                explosions += blast.explosions
                hits += blast.hits
            }
            // Flung into another body: the crash rattles both — the one shoved
            // (resting one tile short) and the one it slammed into.
            if let bumpTile = slammedEnemyTile {
                hits += damageEnemies(on: [bumpTile], damage: Self.knockbackImpactDamage, chargesUltimate: false)
                hits += damageEnemies(on: [current], damage: Self.knockbackImpactDamage, chargesUltimate: false)
            }
            // Slammed into a wall or the board's edge: a bruising extra bump.
            if slammedWall {
                hits += damageEnemies(on: [current], damage: Self.wallSlamDamage, chargesUltimate: false)
            }
        }
        return (shoves, explosions, hits)
    }

    /// Drags every enemy within the diamond one tile toward `center` (the eye of
    /// a lobbed Vortex): bodies cluster onto the eye, over live spikes, into your
    /// reach, or off their telegraphed tiles. Nearest-first so a tile a closer
    /// body vacates opens for the one behind it; a foe hauled into a barrel sets
    /// it off; walls, the player, and occupied tiles stop the pull.
    private mutating func performVortex(center: GridPosition, radius: Int)
        -> (shoves: [TurnResolution.Shove], explosions: [TurnResolution.Explosion], hits: [TurnResolution.EnemyHit]) {
        var shoves: [TurnResolution.Shove] = []
        var explosions: [TurnResolution.Explosion] = []
        var hits: [TurnResolution.EnemyHit] = []

        let pulled = enemies
            .filter { $0.position != center && $0.position.distance(to: center) <= radius }
            .map(\.id)
            .sorted { a, b in
                let pa = enemies.first { $0.id == a }?.position ?? center
                let pb = enemies.first { $0.id == b }?.position ?? center
                return pa.distance(to: center) < pb.distance(to: center)
            }

        for id in pulled {
            guard let index = enemies.firstIndex(where: { $0.id == id }) else { continue }
            let from = enemies[index].position
            guard let dir = Direction.aiming(from: from, toward: center, allowDiagonals: true) else { continue }
            let step = dir.unitStep
            let next = GridPosition(x: from.x + step.x, y: from.y + step.y)
            guard next != from, contains(next) else { continue }
            if let scenery = obstacle(at: next) {
                // Reeled into a barrel: it goes off. A wall just stops the pull.
                if scenery.kind == .barrel {
                    let blast = detonateBarrels(struckTiles: [next])
                    explosions += blast.explosions
                    hits += blast.hits
                }
                continue
            }
            if next == playerPosition { continue }
            if enemies.contains(where: { $0.id != id && $0.position == next }) { continue }
            enemies[index].position = next
            shoves.append(TurnResolution.Shove(enemyID: id, from: from, to: next))
        }
        return (shoves, explosions, hits)
    }

    /// Knocks the player `distance` tiles down `direction`, one step at a time
    /// (diagonally for a diagonal blow) — stopping at the board edge, a wall, or
    /// an enemy, and detonating (and being caught by) any barrel they're driven
    /// into. Movement only; the hit's own damage is applied by the caller.
    /// Returns any barrel blast so the enemy phase can animate it.
    private mutating func shovePlayer(direction: Direction, distance: Int)
        -> (explosions: [TurnResolution.Explosion], hits: [TurnResolution.EnemyHit]) {
        let push = direction.unitStep
        var explosions: [TurnResolution.Explosion] = []
        var hits: [TurnResolution.EnemyHit] = []
        var current = playerPosition
        var crossed: [GridPosition] = []
        var slammedBarrel: GridPosition?
        var slammedWall = false
        for _ in 0..<distance {
            let next = GridPosition(x: current.x + push.x, y: current.y + push.y)
            guard contains(next) else { slammedWall = true; break }
            if let scenery = obstacle(at: next) {
                if scenery.kind == .barrel { slammedBarrel = next } else { slammedWall = true }
                break
            }
            if enemies.contains(where: { $0.position == next }) { break }
            current = next
            crossed.append(next)
        }
        playerPosition = current
        // Spikes raked over in transit bite the player too (the resting tile is
        // left to the end-of-turn tick), unless they're warded against hazards.
        if !buffs.contains(where: \.hazardImmunity) {
            let raked = crossed.dropLast().filter { tile in
                spikes.contains { $0.active && $0.position == tile }
            }.count
            for _ in 0..<raked where !isGameOver {
                applyDamage(Self.spikeDamage, from: "a spike trap")
            }
        }
        // Slammed into a wall or the board's edge takes the same bruise it deals.
        if slammedWall && !isGameOver {
            applyDamage(Self.wallSlamDamage, from: "a wall")
        }
        if let barrel = slammedBarrel {
            // Enemy-lit: no ultimate charge, no barrel-kill credit to the player.
            let blast = detonateBarrels(struckTiles: [barrel], chargesUltimate: false)
            explosions += blast.explosions
            hits += blast.hits
        }
        return (explosions, hits)
    }

    /// Shoves every barrel on `tiles` up to `distance` down `direction`, one step
    /// at a time. A barrel driven into a wall, body, edge, or another barrel
    /// detonates where it ends up (full blast, chains as usual); one that stops on
    /// open floor simply relocates, still live. Furthest-along barrels move first
    /// so a row of them doesn't jam.
    private mutating func shoveBarrels(
        on tiles: Set<GridPosition>,
        direction: Direction,
        distance: Int
    ) -> (explosions: [TurnResolution.Explosion], hits: [TurnResolution.EnemyHit], moves: [TurnResolution.BarrelMove]) {
        let push = direction.unitStep
        var explosions: [TurnResolution.Explosion] = []
        var hits: [TurnResolution.EnemyHit] = []
        var moves: [TurnResolution.BarrelMove] = []
        let ids = obstacles
            .filter { $0.kind == .barrel && tiles.contains($0.position) }
            .sorted { ($0.position.x * push.x + $0.position.y * push.y) > ($1.position.x * push.x + $1.position.y * push.y) }
            .map(\.id)
        for id in ids {
            guard let index = obstacles.firstIndex(where: { $0.id == id }) else { continue }
            let from = obstacles[index].position
            var current = from
            var rammed = false
            // Light empty kegs (yellow) skid further than a full barrel.
            let reach = obstacles[index].barrelKind == .weak ? distance + Self.weakBarrelPushBonus : distance
            for _ in 0..<reach {
                let next = GridPosition(x: current.x + push.x, y: current.y + push.y)
                guard contains(next), obstacle(at: next) == nil,
                      next != playerPosition,
                      !enemies.contains(where: { $0.position == next }) else { rammed = true; break }
                current = next
            }
            obstacles[index].position = current
            if current != from { moves.append(TurnResolution.BarrelMove(from: from, to: current)) }
            if rammed {
                let blast = detonateBarrels(struckTiles: [current])
                explosions += blast.explosions
                hits += blast.hits
            }
        }
        return (explosions, hits, moves)
    }

    /// Fires the grapple down its aim: it bites the first thing in the line and
    /// reels. An enemy is damaged and dragged toward you (raking live spikes on
    /// the way); a wall pulls *you* to it; a barrel pulls you in and detonates,
    /// catching you in the blast. A shot into open space just whips out and back.
    /// Returns the hook's reach (for the visual) and where you were pulled, if
    /// anywhere.
    private mutating func performGrapple(
        direction: Direction,
        hits: inout [TurnResolution.EnemyHit],
        explosions: inout [TurnResolution.Explosion],
        shoves: inout [TurnResolution.Shove],
        barrelMoves: inout [TurnResolution.BarrelMove]
    ) -> (hook: TurnResolution.GrappleHook, playerTo: GridPosition?) {
        enum Bite { case enemy(Int), wall, barrel, edge }
        let step = direction.unitStep
        let range = effectivePattern?.tiles(from: playerPosition, facing: direction).count ?? 0
        let origin = playerPosition
        var reach = playerPosition
        var bite: Bite?
        for _ in 0..<range {
            let next = GridPosition(x: reach.x + step.x, y: reach.y + step.y)
            // The board's rim is an anchor too: the hook catches the ledge and
            // hauls you to the edge tile.
            guard contains(next) else { bite = .edge; break }
            if let scenery = obstacle(at: next) {
                reach = next
                bite = scenery.kind == .barrel ? .barrel : .wall
                break
            }
            if let enemy = enemies.first(where: { $0.position == next }) {
                reach = next
                bite = .enemy(enemy.id)
                break
            }
            reach = next
        }

        var playerTo: GridPosition?
        switch bite {
        case .enemy(let id):
            let strike = damageEnemies(on: [reach], damage: attackDamage, credit: equippedWeapon.name, travelling: direction)
            struckByPlayerThisTurn.formUnion(strike.map(\.enemyID))
            applyStun(strike, turns: equippedWeapon.stun)
            hits += strike
            // Reel a survivor in, one step at a time, stopping just shy of you,
            // a body, or scenery — and rake any live spikes it's dragged over.
            if let hit = strike.first, !hit.died, let index = enemies.firstIndex(where: { $0.id == id }) {
                let pull = GridPosition(x: -step.x, y: -step.y)
                var current = reach
                var crossed: [GridPosition] = []
                while true {
                    let next = GridPosition(x: current.x + pull.x, y: current.y + pull.y)
                    if next == origin { break }
                    guard contains(next), obstacle(at: next) == nil,
                          !enemies.contains(where: { $0.id != id && $0.position == next }) else { break }
                    current = next
                    crossed.append(next)
                }
                if current != reach {
                    enemies[index].position = current
                    shoves.append(TurnResolution.Shove(enemyID: id, from: reach, to: current))
                    let raked = crossed.dropLast().filter { tile in
                        spikes.contains { $0.active && $0.position == tile }
                    }.count
                    for _ in 0..<raked {
                        hits += damageEnemies(on: [current], damage: Self.spikeDamage, chargesUltimate: false)
                    }
                }
            }
        case .edge:
            // No blocker tile ahead — the ledge is `reach` itself, so aim the
            // stop one tile past it so the pull lands you on the rim.
            let past = GridPosition(x: reach.x + step.x, y: reach.y + step.y)
            playerTo = zipPlayer(toward: step, upTo: past, hits: &hits)
        case .wall:
            playerTo = zipPlayer(toward: step, upTo: reach, hits: &hits)
        case .barrel:
            // Reel the barrel in toward you instead of hauling yourself into it:
            // it comes to rest just in front of you (or against whatever blocks
            // the pull) and bursts soft — a controlled 2, blast and chains intact.
            if let index = obstacles.firstIndex(where: { $0.kind == .barrel && $0.position == reach }) {
                let pull = GridPosition(x: -step.x, y: -step.y)
                var current = reach
                while true {
                    let next = GridPosition(x: current.x + pull.x, y: current.y + pull.y)
                    if next == origin { break }
                    guard contains(next), obstacle(at: next) == nil,
                          !enemies.contains(where: { $0.position == next }) else { break }
                    current = next
                }
                obstacles[index].position = current
                if current != reach { barrelMoves.append(TurnResolution.BarrelMove(from: reach, to: current)) }
                let blast = detonateBarrels(struckTiles: [current], damageOverride: Self.grappleBarrelDamage)
                explosions += blast.explosions
                hits += blast.hits
            }
        case nil:
            break
        }
        return (TurnResolution.GrappleHook(from: origin, to: reach), playerTo)
    }

    /// Reels the player along `step` toward the thing at `stop`, halting on the
    /// tile just before it (or before any body/scenery/edge in the way), raking
    /// live spikes crossed. Returns the tile landed on, or nil if they didn't move.
    private mutating func zipPlayer(
        toward step: GridPosition,
        upTo stop: GridPosition,
        hits: inout [TurnResolution.EnemyHit]
    ) -> GridPosition? {
        var current = playerPosition
        var crossed: [GridPosition] = []
        while true {
            let next = GridPosition(x: current.x + step.x, y: current.y + step.y)
            if next == stop { break }
            guard contains(next), obstacle(at: next) == nil,
                  !enemies.contains(where: { $0.position == next }) else { break }
            current = next
            crossed.append(next)
        }
        guard current != playerPosition else { return nil }
        playerPosition = current
        if !buffs.contains(where: \.hazardImmunity) {
            let raked = crossed.dropLast().filter { tile in
                spikes.contains { $0.active && $0.position == tile }
            }.count
            for _ in 0..<raked where !isGameOver {
                applyDamage(Self.spikeDamage, from: "a spike trap")
            }
        }
        return current
    }

    /// Tiles the player must move (without acting) to earn a dodge. A pact can
    /// make it trivial (Sidestep) or impossible (Leadfoot); the Sure Feet boon
    /// also drops it to one (but Leadfoot's ban wins).
    var effectiveDodgeDistance: Int {
        if rules.dodgeDistanceOverride == .max { return .max }   // Leadfoot: never
        let base = rules.dodgeDistanceOverride ?? Self.dodgeDistance
        return buffs.contains(where: \.dodgeAtOne) ? min(base, 1) : base
    }

    /// True when the current draft earns the dodge: no attack or throw drafted,
    /// no weapon pickup, and a move of at least dodgeDistance tiles.
    var plannedDodgeReady: Bool {
        guard plannedAttackDirection == nil, plannedThrowTarget == nil, !plannedPickup,
              !plannedUltimate, !weaponSwapCostsAttack, let target = plannedTarget else { return false }
        return playerPosition.distance(to: target) >= effectiveDodgeDistance
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

    /// The equipped weapon's attack shape, stretched to span the board when the
    /// dev infinite-range toggle is on — line thrusts and bolts only; shaped
    /// swings (arcs, rings) keep their footprint.
    private var effectivePattern: AttackPattern? {
        guard let pattern = equippedWeapon.attackPattern else { return nil }
        if devInfiniteRange && pattern.isLine {
            return AttackPattern.line(length: columns + rows)
        }
        return pattern
    }

    private func plannedSweep() -> [GridPosition] {
        guard let direction = plannedAttackDirection,
              let pattern = plannedBash ? AttackPattern.dagger : effectivePattern else { return [] }
        // Deadeye/piercing shots (ranged only) bore through walls, so the preview
        // must foresee the shot carrying on rather than stopping at scenery.
        let shotsPierce = equippedWeapon.projectileSpeed != nil
            && (rules.piercingShots || buffs.contains(where: \.piercingShots))
        return sweep(
            pattern,
            from: attackOrigin,
            facing: direction,
            pierces: plannedBash ? false : (equippedWeapon.pierces || shotsPierce),
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
        weaponPool: [Weapon] = Weapon.lootTable,
        modifiers: Set<RunModifier> = []
    ) {
        precondition(columns > 0 && rows > 0, "Board must have at least one tile")
        self.columns = columns
        self.rows = rows
        self.weaponPool = weaponPool
        self.modifiers = modifiers
        self.rules = RunRules(modifiers)
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
        self.turnStartWeapon = self.equippedWeapon
        // Boons that raise the ceilings (Vigor, Bulwark) fold in here, so the
        // player starts the run already topped up at the higher max.
        self.maxHealth = playerHealth + self.rules.bonusMaxHealth
        self.playerHealth = self.maxHealth
        self.maxArmor = maxArmor + self.rules.bonusMaxArmor
        self.playerArmor = self.maxArmor
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
        // Board hazards for the opening level (spikes from the start; teleporters
        // begin appearing at level 2 per LevelConfig).
        let openingConfig = LevelConfig.forLevel(1)
        let occupied = Set(self.obstacles.map(\.position)).union(self.enemies.map(\.position)).union([start])
        self.spikes = Self.scatterSpikes(count: openingConfig.spikeTraps + self.rules.spikeTrapBonus, columns: columns, rows: rows, occupied: occupied, playerStart: start)
        if self.rules.spikesAlwaysLive {
            for index in self.spikes.indices { self.spikes[index].active = true }
        }
        self.teleporters = Self.scatterTeleporters(pairs: openingConfig.teleporterPairs, columns: columns, rows: rows, occupied: occupied.union(self.spikes.map(\.position)), playerStart: start)
        self.terrain = Self.scatterTerrain(icePatches: openingConfig.icePatches, mudPatches: openingConfig.mudPatches, columns: columns, rows: rows, occupied: occupied.union(self.spikes.map(\.position)).union(self.teleporters.flatMap { [$0.a, $0.b] }), playerStart: start)
        if self.rules.wallsEverywhere { fillWithDestructibleWalls() }
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
                // Roughly a third of natural barrels are green fire barrels, and
                // a third of natural walls are crumbling ones.
                let barrelKind: Obstacle.BarrelKind = (kind == .barrel && Int.random(in: 0..<3) == 0) ? .fire : .standard
                let destructible = kind == .wall && Int.random(in: 0..<3) == 0
                placed.append(Obstacle(id: nextID, kind: kind, position: candidate, barrelKind: barrelKind, destructible: destructible))
                blocked.insert(candidate)
                nextID += 1
                break
            }
        }
        return placed
    }

    /// Scatters spike traps on open floor, each with a random starting phase so
    /// they don't all bite in lockstep.
    private static func scatterSpikes(count: Int, columns: Int, rows: Int, occupied: Set<GridPosition>, playerStart: GridPosition) -> [SpikeTrap] {
        var placed: [SpikeTrap] = []
        var blocked = occupied
        for _ in 0..<count {
            for _ in 0..<50 {
                let candidate = GridPosition(x: Int.random(in: 0..<columns), y: Int.random(in: 0..<rows))
                guard !blocked.contains(candidate), candidate.distance(to: playerStart) > 2 else { continue }
                placed.append(SpikeTrap(position: candidate, active: Bool.random()))
                blocked.insert(candidate)
                break
            }
        }
        return placed
    }

    /// Scatters linked teleporter pairs on open floor; the two ends of a pair are
    /// kept a few tiles apart so a warp actually relocates you.
    private static func scatterTeleporters(pairs: Int, columns: Int, rows: Int, occupied: Set<GridPosition>, playerStart: GridPosition) -> [Teleporter] {
        var placed: [Teleporter] = []
        var blocked = occupied
        func freeTile() -> GridPosition? {
            for _ in 0..<50 {
                let candidate = GridPosition(x: Int.random(in: 0..<columns), y: Int.random(in: 0..<rows))
                if !blocked.contains(candidate), candidate.distance(to: playerStart) > 2 { return candidate }
            }
            return nil
        }
        for _ in 0..<pairs {
            guard let a = freeTile() else { continue }
            blocked.insert(a)
            guard let b = freeTile(), b.distance(to: a) > 3 else { continue }
            blocked.insert(b)
            placed.append(Teleporter(id: placed.count, a: a, b: b))
        }
        return placed
    }

    /// Scatters movement terrain on open floor: each ice patch is a short
    /// contiguous strip (a random cardinal run of 2–4 tiles, so a slide has room
    /// to build), and each mud patch is a single tile. Kept off scenery, other
    /// board features, and the player's immediate surroundings.
    private static func scatterTerrain(icePatches: Int, mudPatches: Int, columns: Int, rows: Int, occupied: Set<GridPosition>, playerStart: GridPosition) -> [TerrainPatch] {
        var placed: [TerrainPatch] = []
        var blocked = occupied
        let cardinals = [GridPosition(x: 1, y: 0), GridPosition(x: -1, y: 0),
                         GridPosition(x: 0, y: 1), GridPosition(x: 0, y: -1)]
        for _ in 0..<icePatches {
            for _ in 0..<50 {
                let start = GridPosition(x: Int.random(in: 0..<columns), y: Int.random(in: 0..<rows))
                guard !blocked.contains(start), start.distance(to: playerStart) > 2 else { continue }
                let step = cardinals.randomElement()!
                let length = Int.random(in: 2...4)
                var strip: [GridPosition] = []
                var current = start
                for _ in 0..<length {
                    guard current.x >= 0, current.x < columns, current.y >= 0, current.y < rows,
                          !blocked.contains(current) else { break }
                    strip.append(current)
                    current = GridPosition(x: current.x + step.x, y: current.y + step.y)
                }
                guard strip.count >= 2 else { continue }
                for tile in strip {
                    placed.append(TerrainPatch(position: tile, kind: .ice))
                    blocked.insert(tile)
                }
                break
            }
        }
        for _ in 0..<mudPatches {
            for _ in 0..<50 {
                let candidate = GridPosition(x: Int.random(in: 0..<columns), y: Int.random(in: 0..<rows))
                guard !blocked.contains(candidate), candidate.distance(to: playerStart) > 2 else { continue }
                placed.append(TerrainPatch(position: candidate, kind: .mud))
                blocked.insert(candidate)
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

    /// Where a mover ending on `tile` actually lands: the far end of a teleporter
    /// (a single hop, and only if that end is free of scenery, an enemy, or the
    /// player), otherwise `tile` itself.
    func teleportDestination(from tile: GridPosition) -> GridPosition {
        guard let exit = teleporters.compactMap({ $0.exit(from: tile) }).first else { return tile }
        let blocked = obstacle(at: exit) != nil
            || enemies.contains { $0.position == exit }
            || exit == playerPosition
        return blocked ? tile : exit
    }

    /// Board-feature tiles new arrivals steer clear of: spike traps and
    /// teleporter ends. They don't block movement, but nothing should *spawn*
    /// sitting on one (an enemy materializing onto live spikes, or inside a
    /// portal, reads as a bug).
    var spawnAvoidTiles: Set<GridPosition> {
        Set(spikes.map(\.position))
            .union(teleporters.flatMap { [$0.a, $0.b] })
            .union(terrain.map(\.position))
    }

    /// The kind of movement terrain on `position` (ice/mud), or nil for plain
    /// floor.
    func terrainKind(at position: GridPosition) -> TerrainPatch.Kind? {
        terrain.first { $0.position == position }?.kind
    }

    /// The start-of-turn move-range bonus the floor a mover stands on grants —
    /// only ice (+1). Mud isn't a standing penalty; it's paid per step *entering*
    /// it (see `stepCost(onto:)`), so slogging through it eats extra movement.
    /// Shared by the player's `moveRange` and enemies' `movementBudget`.
    func terrainMoveDelta(at tile: GridPosition) -> Int {
        terrainKind(at: tile) == .ice ? 1 : 0
    }

    /// Movement points to step onto `tile`: mud costs 2, everything else 1.
    func stepCost(onto tile: GridPosition) -> Int {
        terrainKind(at: tile) == .mud ? 2 : 1
    }

    /// An enemy's move range with the floor it stands on folded in (never below
    /// 1) — the enemy-side mirror of the player's terrain-aware `moveRange`.
    func movementBudget(for enemy: Enemy) -> Int {
        max(1, enemy.moveRange + terrainMoveDelta(at: enemy.position))
    }

    /// A move that ends on ice slides on: from `start`, step along `direction`
    /// across every ice tile and then one tile *past* the ice onto solid ground
    /// (the momentum carry), stopping short only if something blocks the way — a
    /// wall/barrel, a body, the board edge, or an `extraBlocked` tile. Returns the
    /// resting tile and the tiles crossed to reach it. If `start` isn't ice, the
    /// mover stays put. `moverIsPlayer` decides whether the player's tile blocks;
    /// `extraBlocked` lets an enemy slide respect the tiles its squad has already
    /// claimed, so the telegraph stays honest.
    func iceSlide(landingOn start: GridPosition, heading direction: Direction, moverIsPlayer: Bool, extraBlocked: Set<GridPosition>) -> (destination: GridPosition, crossed: [GridPosition]) {
        guard terrainKind(at: start) == .ice else { return (start, []) }
        let step = direction.unitStep
        // A tile that halts the slide entirely (as opposed to merely ending the
        // ice). An enemy drafted to step off its tile doesn't block — you glide
        // onto the space it's vacating, as with `legalMoveTargets`.
        func blocked(_ tile: GridPosition) -> Bool {
            !contains(tile) || obstacle(at: tile) != nil || extraBlocked.contains(tile)
                || enemies.contains(where: { !$0.isVacating && $0.position == tile })
                || (!moverIsPlayer && tile == playerPosition)
        }
        var current = start
        var crossed: [GridPosition] = []
        while true {
            let next = GridPosition(x: current.x + step.x, y: current.y + step.y)
            guard terrainKind(at: next) == .ice, !blocked(next) else { break }
            current = next
            crossed.append(next)
        }
        // Momentum carries one tile past the ice onto the solid ground beyond,
        // when that tile is clear.
        let past = GridPosition(x: current.x + step.x, y: current.y + step.y)
        if !blocked(past) {
            current = past
            crossed.append(past)
        }
        return (current, crossed)
    }

    /// Extends a drafted enemy move that ends on ice by the ensuing slide, folded
    /// into the plan so the telegraph shows the true resting tile. `heading` is
    /// taken from the last step into the ice; the slide stops before any tile in
    /// `blocked` (the enemy's own avoid set). No move, or a non-ice landing, is
    /// returned unchanged.
    func slideEnemyPlan(from origin: GridPosition, target: GridPosition, path: [GridPosition], blocked: Set<GridPosition>) -> (target: GridPosition, path: [GridPosition]) {
        guard target != origin, terrainKind(at: target) == .ice else { return (target, path) }
        let prev = path.count >= 2 ? path[path.count - 2] : origin
        guard let direction = Direction.aiming(from: prev, toward: target, allowDiagonals: true) else { return (target, path) }
        let slid = iceSlide(landingOn: target, heading: direction, moverIsPlayer: false, extraBlocked: blocked)
        guard slid.destination != target else { return (target, path) }
        return (slid.destination, path + slid.crossed)
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
        if enemy.usesEliteIntents, let intent = enemy.plannedIntent {
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

    /// Tiles the player may pick this turn: every on-board tile reachable within
    /// the move budget, where each orthogonal step costs 1 — or 2 to enter mud, so
    /// slogging through mud eats an extra tile. A move still glides over walls
    /// (transit is free, as it always has been); only mud adds cost. The current
    /// tile (planning to stay) is excluded, as are tiles occupied by enemies or
    /// obstacles (enemies vacating their tile don't block — you land as they leave).
    func legalMoveTargets() -> Set<GridPosition> {
        let budget = moveRange
        guard budget > 0 else { return [] }
        let occupied = Set(enemies.filter { !$0.isVacating }.map(\.position)).union(obstacles.map(\.position))
        // Dijkstra: cheapest cost from the player to every tile (grid is small).
        var cost: [GridPosition: Int] = [playerPosition: 0]
        var settled: Set<GridPosition> = []
        while let current = cost.lazy.filter({ !settled.contains($0.key) }).min(by: { $0.value < $1.value })?.key {
            let here = cost[current]!
            if here >= budget { break }   // any neighbour would exceed the budget
            settled.insert(current)
            for step in [GridPosition(x: current.x + 1, y: current.y),
                         GridPosition(x: current.x - 1, y: current.y),
                         GridPosition(x: current.x, y: current.y + 1),
                         GridPosition(x: current.x, y: current.y - 1)] {
                guard contains(step) else { continue }
                let next = here + stepCost(onto: step)
                if next < cost[step, default: .max] { cost[step] = next }
            }
        }
        var targets: Set<GridPosition> = []
        for (tile, c) in cost where c > 0 && c <= budget && !occupied.contains(tile) {
            targets.insert(tile)
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
        let range = devInfiniteRange ? (columns + rows) : thrown.range
        for dx in -range...range {
            let remaining = range - abs(dx)
            for dy in -remaining...remaining {
                let candidate = GridPosition(x: origin.x + dx, y: origin.y + dy)
                if contains(candidate) && obstacle(at: candidate)?.kind != .wall {
                    targets.insert(candidate)
                }
            }
        }
        return targets
    }

    /// Instantly flips the equipped and holstered weapons during planning —
    /// free, no turn cost. The new weapon's move range and attack pattern take
    /// effect at once, so any drafted attack is cleared (re-aim with the new
    /// weapon) and a now-unreachable move is dropped.
    @discardableResult
    mutating func swapEquipped() -> Bool {
        guard !isGameOver, pendingBuffChoices.isEmpty else { return false }
        (equippedWeapon, holsteredWeapon) = (holsteredWeapon, equippedWeapon)
        // A swap re-picks your action for the turn: any drafted attack/throw/
        // pickup/ultimate is dropped (re-draft with the new weapon).
        plannedAttackDirection = nil
        plannedThrowTarget = nil
        plannedBash = false
        plannedPickup = false
        plannedUltimate = false
        if let target = plannedTarget, !legalMoveTargets().contains(target) {
            plannedTarget = nil
        }
        return true
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
        guard !isGameOver, pendingBuffChoices.isEmpty, !weaponSwapCostsAttack,
              weaponDrop(at: playerPosition) != nil else { return false }
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
        guard !isGameOver, pendingBuffChoices.isEmpty, !weaponSwapCostsAttack,
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
        guard !isGameOver, pendingBuffChoices.isEmpty else { return false }
        // A weapon swap this turn already spent the attack (unless swaps are free).
        guard !weaponSwapCostsAttack else { return false }
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
        var teleports: [TurnResolution.Teleport] = []
        let playerStart = playerPosition
        // A move onto ice slides on to its resting tile; the drafted tile is the
        // legal pick, the slide carries the player the rest of the way.
        var steppedTile = plannedTarget ?? playerPosition
        if let target = plannedTarget, terrainKind(at: target) == .ice,
           let direction = Direction.aiming(from: playerStart, toward: target, allowDiagonals: true) {
            steppedTile = iceSlide(landingOn: target, heading: direction, moverIsPlayer: true, extraBlocked: []).destination
        }
        tilesMoved += playerStart.distance(to: steppedTile)
        plannedTarget = nil
        playerPosition = steppedTile
        // The tile the player visibly walks to (the scene slides here; a warp
        // then pops from it). Captured before any enemy knockback shoves them.
        let draftedDestination = steppedTile
        // Stepping onto a teleporter this turn warps the player to its far end.
        if steppedTile != playerStart {
            let warped = teleportDestination(from: steppedTile)
            if warped != steppedTile {
                teleports.append(TurnResolution.Teleport(enemyID: nil, from: steppedTile, to: warped))
                playerPosition = warped
            }
        }
        var playerShoveTo: GridPosition?
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

        // Weapon swaps happen instantly during planning (see swapEquipped), so
        // there's nothing to resolve here.

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
            // A stun burns off as its frozen turn is played out — decremented
            // here (not at draft) so the daze stays visible, stars and all,
            // through the planning phase the player is reading.
            if enemies[index].stunTurns > 0 {
                enemies[index].stunTurns -= 1
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

            // Boxed-in enemy smashes the wall it drafted to dig, opening a lane.
            if let dig = enemies[index].plannedDigTile {
                crumbleWalls(in: [dig])
                enemies[index].plannedDigTile = nil
            }

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

            // Stepping onto a teleporter warps the mover to its far end, after
            // any hazards/bolts along the walk have resolved. It may have died
            // crossing, so re-check it still exists.
            if to != from, let idx = enemies.firstIndex(where: { $0.id == enemyID }) {
                let warped = teleportDestination(from: to)
                if warped != to {
                    teleports.append(TurnResolution.Teleport(enemyID: enemyID, from: to, to: warped))
                    enemies[idx].position = warped
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
        var shoves: [TurnResolution.Shove] = []
        var barrelMoves: [TurnResolution.BarrelMove] = []
        var grappleHook: TurnResolution.GrappleHook?
        var playerGrappleTo: GridPosition?
        var didAttack = false

        // A stun eats only this turn's action: the player still moved, and a
        // drafted swap/pickup already stood, but the drafted attack/throw/
        // ultimate is voided (the ultimate keeps its charge). The daze then
        // wears off. Movement is never taken away, so foresight is preserved.
        let actionStunned = playerStunTurns > 0
        let playerActionStunned = actionStunned
            && (plannedUltimate || plannedBash || plannedAttackDirection != nil || plannedThrowTarget != nil)
        if playerStunTurns > 0 { playerStunTurns -= 1 }

        // The ultimate smites every enemy on the board at once, wherever they
        // ended up after moving.
        var ultimateTiles: [GridPosition] = []
        let ultimateFired = plannedUltimate && !actionStunned
        if ultimateFired {
            ultimateTiles = enemies.map(\.position)
            ultimateKillCharge = 0
            playerPhaseHits += damageEnemies(on: Set(ultimateTiles), damage: Self.ultimateDamage, chargesUltimate: false)
        }
        plannedUltimate = false
        let bashing = plannedBash && !actionStunned
        if actionStunned {
            // The drafted action fizzles; the planned flags are cleared below.
        } else if bashing, let direction = plannedAttackDirection {
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
        } else if let direction = plannedAttackDirection, let pattern = effectivePattern {
            didAttack = true
            if equippedWeapon.grapples {
                // The grapple resolves entirely here (reel/self-pull/detonate);
                // it sweeps no tiles, so the generic strike block is skipped.
                let result = performGrapple(direction: direction, hits: &playerPhaseHits, explosions: &playerExplosions, shoves: &shoves, barrelMoves: &barrelMoves)
                grappleHook = result.hook
                playerGrappleTo = result.playerTo
            } else if let speed = equippedWeapon.projectileSpeed {
                // The shot becomes a traveling bolt: it flies its first window
                // right now, then keeps going in later turns' projectile phases.
                let shot = Bolt(
                    id: nextProjectileID,
                    position: playerPosition,
                    direction: direction,
                    speed: speed,
                    remainingRange: pattern.tiles(from: playerPosition, facing: direction).count,
                    damage: attackDamage,
                    pierces: equippedWeapon.pierces || rules.piercingShots || buffs.contains(where: \.piercingShots),
                    impactBlastRadius: equippedWeapon.impactBlastRadius,
                    lingering: equippedWeapon.lingering,
                    chargesUltimate: true,
                    sourceName: "your own \(equippedWeapon.name)",
                    creditName: equippedWeapon.name,
                    affliction: equippedWeapon.affliction,
                    stun: equippedWeapon.stun
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
            if equippedWeapon.placesBarrel {
                // Lob a keg: drop a live barrel on the target if the tile's clear
                // (no scenery, body, or you). No damage — the payoff is setting it
                // off later. barrelSpawns animates it popping in.
                let blocked = obstacle(at: target) != nil
                    || enemies.contains { $0.position == target }
                    || target == playerPosition
                if !blocked {
                    obstacles.append(Obstacle(id: nextObstacleID, kind: .barrel, position: target, barrelKind: .weak))
                    nextObstacleID += 1
                    barrelSpawns.append(target)
                }
            } else if equippedWeapon.vortex {
                // Crush everyone caught in the eye, then drag the survivors one
                // tile inward (onto spikes, into barrels, into your next swing).
                if attackDamage > 0 {
                    let diamond = Set(blastTiles(around: target, radius: thrown.blastRadius, includeCenter: true))
                    playerPhaseHits += damageEnemies(on: diamond, damage: attackDamage, credit: equippedWeapon.name)
                }
                let suck = performVortex(center: target, radius: thrown.blastRadius)
                shoves += suck.shoves
                playerExplosions += suck.explosions
                playerPhaseHits += suck.hits
            } else if thrown.flightTurns > 0 {
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
            // Bash rides the deal-double boon too (attackDamage already does).
            let strikeDamage = bashing
                ? Int((Double(Self.bashDamage) * rules.damageDealtMult).rounded())
                : attackDamage
            // A directional swing can be parried from the front and rewards a
            // backstab; a thrown blast or a radial swing (greataxe/hammer/scythe)
            // carries no meaningful facing, so it slips past the shield and
            // triggers no backstab — it's area damage, not a pointed strike.
            let radial = equippedWeapon.attackPattern?.isRadial ?? false
            let facing = (equippedWeapon.thrown == nil && !radial) ? plannedAttackDirection : nil
            let sweepHits = damageEnemies(on: struck, damage: strikeDamage, credit: bashing ? nil : equippedWeapon.name, travelling: facing)
            afflict(sweepHits, with: bashing ? nil : equippedWeapon.affliction, chargesUltimate: true, credit: equippedWeapon.name)
            // The daze lands now, in the player's phase — a survivor's telegraphed
            // attack this very turn fizzles in the enemy phase that follows. (A
            // bare reload jab carries none of the weapon's tricks.)
            applyStun(sweepHits, turns: bashing ? 0 : equippedWeapon.stun)
            struckByPlayerThisTurn.formUnion(sweepHits.map(\.enemyID))
            playerPhaseHits += sweepHits
            // A lobbed blast has no friendly immunity: catch yourself, hurt yourself.
            if equippedWeapon.thrown != nil && !bashing && !isGameOver && struck.contains(playerPosition) {
                applyDamage(attackDamage, from: "your own \(equippedWeapon.name)")
            }
            // Knockback flings the survivors of a direct hit down the swing's
            // facing — into walls, off their telegraphed tiles, or into a barrel
            // that then goes off — and shoves any barrels the swing swept along
            // with them (a rammed barrel detonates; one that stops on open floor
            // just relocates). Radial/thrown weapons carry no facing (and no
            // knockback), so every other attack just pops swept barrels in place.
            if !bashing, equippedWeapon.knockback > 0, let facing = plannedAttackDirection {
                let survivors = sweepHits.filter { !$0.died }.map(\.enemyID)
                let flung = shoveEnemies(ids: survivors, direction: facing, distance: equippedWeapon.knockback)
                shoves += flung.shoves
                playerExplosions += flung.explosions
                playerPhaseHits += flung.hits
                let pushed = shoveBarrels(on: struck, direction: facing, distance: equippedWeapon.knockback)
                playerExplosions += pushed.explosions
                playerPhaseHits += pushed.hits
                barrelMoves += pushed.moves
            } else {
                let blast = detonateBarrels(struckTiles: struck)
                playerExplosions += blast.explosions
                playerPhaseHits += blast.hits
            }
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
        var dodgeCharges = (!didAttack && pickedUp == nil && !ultimateFired && !weaponSwapCostsAttack
            && playerStart.distance(to: playerPosition) >= effectiveDodgeDistance) ? 1 : 0

        var enemyAttacks: [TurnResolution.EnemyAttack] = []
        var friendlyFireHits: [TurnResolution.EnemyHit] = []
        var enemyExplosions: [TurnResolution.Explosion] = []
        var enemyGrappleHooks: [TurnResolution.GrappleHook] = []

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
            // A stun eats the telegraphed attack outright: the enemy doesn't
            // fire (so its weapon isn't even spent on cooldown), and its plan
            // is dropped. It stays frozen through draftEnemyPlans until the
            // daze wears off.
            if attacker.stunTurns > 0 {
                enemies[attackerIndex].plannedDirection = nil
                enemies[attackerIndex].plannedThrowTarget = nil
                enemies[attackerIndex].plannedIntent = nil
                enemies[attackerIndex].plannedSecondaryDirection = nil
                enemies[attackerIndex].plannedDetonateTile = nil
                continue
            }
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
                    enemies[attackerIndex].cooldownRemaining = effectiveEnemyCooldown(attacker.weapon.cooldown)
                }
                if attacker.plannedSecondaryDirection != nil {
                    enemies[attackerIndex].secondaryCooldownRemaining = effectiveEnemyCooldown(attacker.secondaryWeapon?.cooldown ?? 0)
                }
            case .nova:
                enemies[attackerIndex].secondaryCooldownRemaining = effectiveEnemyCooldown(attacker.secondaryWeapon?.cooldown ?? attacker.weapon.cooldown)
            case .summon, .barrage, .detonate:
                // Abilities don't spend a weapon's reload; their own gates
                // (summon cadence, barrel cap, a live red barrel) pace them.
                break
            case nil:
                enemies[attackerIndex].cooldownRemaining = effectiveEnemyCooldown(attacker.weapon.cooldown)
            }
            enemies[attackerIndex].plannedDetonateTile = nil

            if attacker.plannedIntent == .summon {
                // The boss spends its action calling recruits to its side; they
                // telegraph like any reinforcement and land the turn after.
                let taken = Set(enemies.map(\.position))
                    .union(obstacles.map(\.position))
                    .union(lingeringEffects.map(\.position))
                    .union(spawnAvoidTiles)
                    .union([playerPosition])
                let ring = blastTiles(around: attacker.position, radius: 2).filter {
                    !taken.contains($0) && $0.distance(to: playerPosition) > 1
                }
                let config = BossConfig.forLevel(level)
                let summonCount: Int
                switch attacker.archetype {
                case .summoner: summonCount = config.summonerSummonCount
                case .bombardier: summonCount = config.bombardierSummonCount
                default: summonCount = config.bossSummonCount
                }
                queuedBossSummons = Array(ring.shuffled().prefix(summonCount))
                // The bombardier's whole retinue is walking bombs.
                queuedSummonsBomberOnly = attacker.archetype == .bombardier
                lastBossSummonTurn = turnNumber
                continue
            }

            if attacker.plannedIntent == .barrage {
                // The boss hurls a cluster of live barrels to rain down 1–3
                // tiles from the player: telegraphed like any barrel delivery,
                // and set off later with a detonate intent — reintroducing the
                // board hazards a boss fight otherwise strips away.
                // Only the boss barrages now, so this is always its count.
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
                        affliction: attacker.weapon.affliction,
                        stun: attacker.weapon.stun
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
                // Aftershock: sidestepping a blow patches 1 armor back.
                if buffs.contains(where: \.dodgeRepairsArmor) {
                    playerArmor = min(armorCap, playerArmor + 1)
                }
            }
            if hitsPlayer {
                // Buffs blunt incoming weapon hits (but never below zero).
                let reduction = buffs.reduce(0) {
                    $0 + (strikingWeapon.isMelee ? $1.meleeDamageReduction : $1.rangedDamageReduction)
                }
                let killer = attacker.plannedIntent == .nova
                    ? "the boss's cannon nova"
                    : attacker.slayerName
                // A reaver drives one point straight through armor to the flesh.
                let armorPiercing = attacker.archetype == .reaver ? 1 : 0
                applyDamage(max(0, attackDamage - reduction), from: killer, armorPiercing: armorPiercing)
                afflictPlayer(with: strikingWeapon.affliction)
                applyPlayerStun(strikingWeapon.stun)
                // Thorns: a melee attacker that draws blood takes a point back,
                // striking its own tile (full kill bookkeeping included).
                if strikingWeapon.isMelee, buffs.contains(where: \.retaliation), !isGameOver {
                    friendlyFireHits += damageEnemies(on: [attacker.position], damage: 1)
                }
                // A knockback weapon flings the player down its swing — into a
                // wall, an enemy, or a barrel that then goes off around them.
                if strikingWeapon.knockback > 0, let facing = attacker.plannedDirection, !isGameOver, !devKnockbackImmune {
                    let before = playerPosition
                    let flung = shovePlayer(direction: facing, distance: strikingWeapon.knockback)
                    enemyExplosions += flung.explosions
                    friendlyFireHits += flung.hits
                    if playerPosition != before { playerShoveTo = playerPosition }
                }
                // A grapple reels the player IN toward the attacker — the inverse
                // of knockback — dragging them back up the line (over any live
                // spikes) to just in front of the enemy.
                if strikingWeapon.grapples, let facing = attacker.plannedDirection, !isGameOver, !devKnockbackImmune {
                    let before = playerPosition
                    enemyGrappleHooks.append(TurnResolution.GrappleHook(from: attacker.position, to: before))
                    let pull = GridPosition(x: -facing.unitStep.x, y: -facing.unitStep.y)
                    let landed = zipPlayer(toward: pull, upTo: attacker.position, hits: &friendlyFireHits)
                    if let landed, landed != before { playerShoveTo = landed }
                }
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

        // Active spike traps bite whoever ended the turn on them (player and
        // enemies alike), then every spike flips — so the state the player saw
        // while planning is the one that bit, and next turn shows the flip.
        for spike in spikes where spike.active {
            hazardHits += damageEnemies(on: [spike.position], damage: Self.spikeDamage, chargesUltimate: false)
            if !isGameOver && spike.position == playerPosition && !buffs.contains(where: \.hazardImmunity) {
                applyDamage(Self.spikeDamage, from: "a spike trap")
            }
        }
        // Impaler keeps every spike armed; otherwise they flip for next turn.
        if !rules.spikesAlwaysLive {
            for index in spikes.indices { spikes[index].active.toggle() }
        }

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
            // Rusting stretches the cadence: a point of armor every few clean turns.
            if rules.armorRegen && undamagedTurns.isMultiple(of: rules.armorRegenInterval) && playerArmor < armorCap {
                playerArmor += 1
            }
        }

        for name in weaponCooldowns.keys {
            weaponCooldowns[name] = max(0, (weaponCooldowns[name] ?? 0) - 1)
        }
        // The jab doesn't restart the reload — the real weapon keeps counting.
        if didAttack && !bashing {
            // Rampage: a kill this turn shaves a turn off the reload.
            let refund = (killShavesReload && killsThisTurn > 0) ? 1 : 0
            weaponCooldowns[equippedWeapon.name] = max(0, effectivePlayerCooldown(equippedWeapon.cooldown) - refund)
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
        // Normally the milestone only turns the level over once the gatekeeper
        // is down. With elites disabled in dev there's no gate to kill, so the
        // milestone advances directly — otherwise boons could never be reached.
        if !isGameOver && score >= milestone && (bossDefeatedThisLevel || devNoElites) {
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
        // The next planning phase starts from whatever's equipped now, so a
        // swap only costs the turn it's actually made on.
        turnStartWeapon = equippedWeapon

        return TurnResolution(
            playerDestination: draftedDestination,
            playerShoveTo: playerShoveTo,
            attackTiles: attackTiles,
            ultimateTiles: ultimateTiles,
            enemyHits: playerPhaseHits,
            playerExplosions: playerExplosions,
            shoves: shoves,
            barrelMoves: barrelMoves,
            teleports: teleports,
            grappleHook: grappleHook,
            playerGrappleTo: playerGrappleTo,
            enemyGrappleHooks: enemyGrappleHooks,
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
            playerArmor: playerArmor,
            playerActionStunned: playerActionStunned
        )
    }

    /// Damages every enemy standing on the given tiles and removes the dead.
    /// Returns the hits for animation.
    private mutating func damageEnemies(on tiles: Set<GridPosition>, damage: Int, chargesUltimate: Bool = true, credit: String? = nil, travelling direction: Direction? = nil) -> [TurnResolution.EnemyHit] {
        // Anything that hits a tile smashes a destructible wall standing on it —
        // a melee sweep, a bolt, a blast. Solid walls are untouched.
        crumbleWalls(in: tiles)
        var hits: [TurnResolution.EnemyHit] = []
        var diedBomberPositions: [GridPosition] = []
        for index in enemies.indices where tiles.contains(enemies[index].position) {
            // A shieldbearer parries a blow driven into its front: no damage,
            // and the shield drops for a turn (shieldCooldown) so it can't block
            // again immediately.
            if !devIgnoreShields && enemies[index].parries(direction) {
                enemies[index].shieldCooldown = 2
                hits.append(TurnResolution.EnemyHit(enemyID: enemies[index].id, healthAfter: enemies[index].health, died: false, blocked: true))
                continue
            }
            // Struck in the exposed back: extra damage.
            let dealt = damage + (enemies[index].struckFromBehind(direction) ? Self.shieldbearerBackstabBonus : 0)
            enemies[index].health -= dealt
            let died = enemies[index].health <= 0
            if died {
                let isElite = enemies[index].isElite
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
                    // always costs the whole ten-kill climb. Executioner doubles
                    // the charge each kill grants.
                    let gain = buffs.contains(where: \.killChargesExtra) ? 2 : 1
                    ultimateKillCharge = min(ultimateKillCharge + gain, Self.ultimateChargeKills)
                    // Lifelink / Bloodthirst: every third kill mends a point.
                    if rules.killHeals || buffs.contains(where: \.killHeals) {
                        lifelinkKills += 1
                        if lifelinkKills >= 3 {
                            lifelinkKills = 0
                            playerHealth = min(maxHealth, playerHealth + 1)
                        }
                    }
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

    /// The level's difficulty knobs with this run's conditions folded in, so a
    /// modifier like Powder Keg or Swarm reshapes every board, not just the first.
    func effectiveLevelConfig(for level: Int) -> LevelConfig {
        let base = LevelConfig.forLevel(level)
        return LevelConfig(
            startingEnemies: base.startingEnemies + rules.startingEnemiesBonus,
            spawnInterval: max(2, base.spawnInterval + rules.spawnIntervalDelta),
            spawnBatch: max(1, base.spawnBatch + rules.spawnBatchBonus),
            walls: rules.allBarrels ? 0 : base.walls,
            barrels: rules.allBarrels ? min(14 + level, 20) : base.barrels,
            spikeTraps: base.spikeTraps + rules.spikeTrapBonus,
            teleporterPairs: base.teleporterPairs,
            icePatches: base.icePatches,
            mudPatches: base.mudPatches
        )
    }

    /// Advances to the next level: the board fully regenerates at the new
    /// difficulty (fresh enemies, obstacles, and floor — the player keeps
    /// position, health, armor, loadout, and score) and two boons are drawn for
    /// the player to choose between; play pauses until `chooseBuff` is called.
    private mutating func advanceLevel() {
        level += 1
        let config = effectiveLevelConfig(for: level)

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
        queuedSummonsBomberOnly = false
        queuedBossBarrels = []
        primedBarrelTiles = []
        lastBossSummonTurn = -100
        spawnDebt = 0
        formationAnchors = [:]
        playerAffliction = nil
        playerStunTurns = 0

        var fresh: [Enemy] = []
        for tile in edgeTiles().shuffled() where fresh.count < config.startingEnemies {
            guard tile.distance(to: playerPosition) > 3 else { continue }
            fresh.append(rollRecruit(id: nextEnemyID, at: tile))
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

        // Fresh floor hazards each level, kept off the obstacles/enemies/drops/player.
        let floorClear = Set(obstacles.map(\.position))
            .union(enemies.map(\.position))
            .union(weaponDrops.map(\.position))
            .union([playerPosition])
        spikes = Self.scatterSpikes(count: config.spikeTraps, columns: columns, rows: rows, occupied: floorClear, playerStart: playerPosition)
        if rules.spikesAlwaysLive {
            for index in spikes.indices { spikes[index].active = true }
        }
        teleporters = Self.scatterTeleporters(pairs: config.teleporterPairs, columns: columns, rows: rows, occupied: floorClear.union(spikes.map(\.position)), playerStart: playerPosition)
        terrain = Self.scatterTerrain(icePatches: config.icePatches, mudPatches: config.mudPatches, columns: columns, rows: rows, occupied: floorClear.union(spikes.map(\.position)).union(teleporters.flatMap { [$0.a, $0.b] }), playerStart: playerPosition)
        if rules.wallsEverywhere { fillWithDestructibleWalls() }

        // Held buffs age by one level and expired ones wear off; then a new boon
        // is granted. Non-stackable buffs leave the pool while owned.
        for index in heldBuffs.indices {
            if let remaining = heldBuffs[index].levelsRemaining {
                heldBuffs[index].levelsRemaining = remaining - 1
            }
        }
        heldBuffs.removeAll { ($0.levelsRemaining ?? 1) <= 0 }
        // Clearing a level tops armor back up to its (possibly newly-shrunken)
        // cap — a breather each level, though health still never regenerates.
        playerArmor = armorCap

        // Dev: pin the level-up offer for testing. Either slot can be set; both
        // set reproduces the exact two options, one set offers just that one.
        let forcedBuffs = [devForcedBuff, devForcedBuff2].compactMap { $0 }
        if !forcedBuffs.isEmpty {
            pendingBuffChoices = forcedBuffs
            return
        }
        // Draw the boon options; play pauses until the player picks one. Boons a
        // pact already fully provides (barrel immunity under Warded, free swaps
        // under Quickhands, etc.) are dropped so a pick is never a dead effect.
        let pool = Buff.all.filter { buff in
            guard buff.stackable || !buffs.contains(buff) else { return false }
            if buff.barrelImmunity && rules.barrelImmune { return false }
            if buff.freeSwap && rules.freeSwap { return false }
            if buff.killRefundsCooldown && rules.killRefundsCooldown { return false }
            if buff.dodgeAtOne && rules.dodgeDistanceOverride == 1 { return false }
            return true
        }
        pendingBuffChoices = Array(pool.shuffled().prefix(2))
        if pendingBuffChoices.isEmpty {
            pendingBuffChoices = [.secondWind]
        }
    }

    // MARK: - Tutorial showcase
    // Force-plays systems the player can't reach on turn one. These only ever
    // run on a sandbox copy of the state (the scene snapshots before, restores
    // after), so they don't need to be gentle about side effects.

    /// Drops a formation onto the board at once, telegraphs and all.
    mutating func tutorialSpawnFormation() {
        _ = spawnFormation(nil)
        enemies.append(contentsOf: pendingArrivals)
        pendingArrivals = []
        draftEnemyPlans()
    }

    /// Drops the level's gatekeeper on the board with its intent telegraphed.
    mutating func tutorialSpawnGatekeeper() {
        var ignored: [TurnResolution.SpawnEvent] = []
        summonElite(into: &ignored)
        draftEnemyPlans()
    }

    /// Runs a real level-up: fresh board, refilled armor, a boon to pick.
    mutating func tutorialLevelUp() {
        advanceLevel()
    }

    /// One illustrative board per advanced-tutorial beat. Sandbox only: wipes the
    /// board clean and lays out the props (and equips the weapon) for one lesson.
    enum TutorialDemo { case barrels, spikes, teleporters, walls, grapple, slipstep, ice, mud }

    mutating func tutorialSetupDemo(_ demo: TutorialDemo) {
        enemies.removeAll()
        obstacles.removeAll()
        spikes.removeAll()
        teleporters.removeAll()
        terrain.removeAll()
        lingeringEffects.removeAll()
        projectiles.removeAll()
        bolts.removeAll()
        pendingArrivals.removeAll()
        pendingBarrelSpawns.removeAll()
        plannedTarget = nil
        plannedAttackDirection = nil
        plannedThrowTarget = nil
        // The board is live between lessons, so the player drifts; recenter them
        // so every demo lays out consistently and no prop falls off the board.
        playerPosition = GridPosition(x: columns / 2, y: rows / 2)

        let p = playerPosition
        func tile(_ dx: Int, _ dy: Int) -> GridPosition { GridPosition(x: p.x + dx, y: p.y + dy) }
        func addEnemy(_ dx: Int, _ dy: Int) {
            let t = tile(dx, dy)
            guard contains(t) else { return }
            enemies.append(Enemy(id: nextEnemyID, position: t, weapon: .dagger))
            nextEnemyID += 1
        }
        func addObstacle(_ kind: Obstacle.Kind, _ dx: Int, _ dy: Int, barrelKind: Obstacle.BarrelKind = .standard, destructible: Bool = false) {
            let t = tile(dx, dy)
            guard contains(t) else { return }
            obstacles.append(Obstacle(id: nextObstacleID, kind: kind, position: t, barrelKind: barrelKind, destructible: destructible))
            nextObstacleID += 1
        }
        func addTerrain(_ kind: TerrainPatch.Kind, _ dx: Int, _ dy: Int) {
            let t = tile(dx, dy)
            guard contains(t) else { return }
            terrain.append(TerrainPatch(position: t, kind: kind))
        }

        switch demo {
        case .barrels:
            // Ram the adjacent foe into the (orange) barrel behind it; a green
            // one to the side leaves fire, a yellow one is the Keg's weak powder.
            equippedWeapon = .ram
            holsteredWeapon = .keg
            addEnemy(1, 0)
            addObstacle(.barrel, 2, 0)
            addObstacle(.barrel, -2, 1, barrelKind: .fire)
            addObstacle(.barrel, -2, -1, barrelKind: .weak)
        case .spikes:
            // Fling the foe across the live spikes with a knockback swing.
            equippedWeapon = .ram
            holsteredWeapon = .dagger
            addEnemy(1, 0)
            spikes.append(SpikeTrap(position: tile(2, 0), active: true))
            spikes.append(SpikeTrap(position: tile(3, 0), active: true))
            spikes.append(SpikeTrap(position: tile(2, 2), active: false))
        case .teleporters:
            // Step onto the portal to warp across.
            equippedWeapon = .dagger
            holsteredWeapon = .bow
            let a = tile(2, 0), b = tile(-3, -2)
            if contains(a) && contains(b) { teleporters.append(Teleporter(id: 0, a: a, b: b)) }
        case .walls:
            // Crumbling (brown) walls give way to any hit or blast; the grey one
            // won't. A barrel to blow a hole, and a foe waiting behind the rubble.
            equippedWeapon = .ram
            holsteredWeapon = .grapple
            addObstacle(.wall, 1, 0, destructible: true)
            addObstacle(.wall, 2, 0, destructible: true)
            addObstacle(.wall, 1, 2)
            addObstacle(.barrel, 2, 3)
            addEnemy(3, 0)
        case .grapple:
            // Aim right for the enemy, up for the wall, left for the barrel.
            equippedWeapon = .grapple
            holsteredWeapon = .sword
            addEnemy(4, 0)
            addObstacle(.wall, 0, 4)
            addObstacle(.barrel, -3, 0)
        case .slipstep:
            // Blink in, swap to the sword (free), strike; next turn swap back out.
            equippedWeapon = .slipstep
            holsteredWeapon = .sword
            addEnemy(5, 3)
        case .ice:
            // Step onto the ice strip and slide down it into the waiting foe.
            equippedWeapon = .sword
            holsteredWeapon = .bow
            for dx in 1...5 { addTerrain(.ice, dx, 0) }
            addEnemy(6, 0)
        case .mud:
            // Mud between you and the foe: standing in it costs a step of move.
            equippedWeapon = .sword
            holsteredWeapon = .bow
            addTerrain(.mud, 1, 0)
            addTerrain(.mud, 2, 0)
            addEnemy(4, 0)
        }
        turnStartWeapon = equippedWeapon
        draftEnemyPlans()
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

    /// Draws the next non-boss gate elite from a shuffle-bag: each bag holds one
    /// of each (juggernaut/summoner/artillery), reshuffled when emptied, and never
    /// hands back the last one drawn — so gates cycle through all three.
    private mutating func nextLesserElite() -> Archetype {
        if lesserEliteBag.isEmpty {
            var bag: [Archetype] = [.juggernaut, .summoner, .bombardier].shuffled()
            if bag.first == lastLesserElite, bag.count > 1 {
                bag.swapAt(0, bag.count - 1)
            }
            lesserEliteBag = bag
        }
        let pick = lesserEliteBag.removeFirst()
        lastLesserElite = pick
        return pick
    }

    /// Picks the next wave's telegraphed arrivals: enemies on random open edge
    /// tiles a safe distance from the player (cadence and batch size set by the
    /// level), plus one fresh barrel anywhere open while under the cap — so
    /// there's always new powder to blow the reinforcements up with.
    /// The level's gatekeeper arrives on an open edge tile: a juggernaut, or a
    /// full boss every third level. Waves pause until it falls.
    private mutating func summonElite(into spawns: inout [TurnResolution.SpawnEvent]) {
        // Every third level (or under the Warband pact) is a full boss; the
        // other gates draw from a shuffle-bag so they cycle through all three
        // lesser elites instead of streaking on one.
        let archetype: Archetype = (rules.bossEveryGate || level.isMultiple(of: 3))
            ? .boss
            : nextLesserElite()
        let taken = Set(enemies.map(\.position))
            .union(obstacles.map(\.position))
            .union(spawnAvoidTiles)
            .union([playerPosition])
        guard let tile = edgeTiles().shuffled().first(where: {
            !taken.contains($0) && $0.distance(to: playerPosition) > 3
        }) else { return }
        let elite = Enemy.elite(archetype, id: nextEnemyID, at: tile, config: BossConfig.forLevel(level))
        nextEnemyID += 1
        enemies.append(elite)
        spawns.append(TurnResolution.SpawnEvent(position: tile, enemyID: elite.id, late: true))
        bossPhase = true
    }

    /// A rank-and-file recruit for waves and level starts — every one a bomber
    /// under the Sappers curse, otherwise the usual mixed roll.
    private func rollRecruit(id: Int, at tile: GridPosition) -> Enemy {
        rules.allBombers
            ? Enemy.recruit(.bomber, id: id, at: tile, armory: weaponPool)
            : Enemy.recruit(id: id, at: tile, armory: weaponPool)
    }

    /// Rolls next turn's arrival for a telegraph tile — decided now, so the
    /// marker can honestly say what's coming.
    private mutating func rollArrival(at tile: GridPosition, bomberOnly: Bool = false) -> Enemy {
        let arrival = bomberOnly
            ? Enemy.recruit(.bomber, id: nextEnemyID, at: tile, armory: weaponPool)
            : rollRecruit(id: nextEnemyID, at: tile)
        nextEnemyID += 1
        return arrival
    }

    private mutating func scheduleSpawns() {
        pendingArrivals = []
        pendingBarrelSpawns = []
        // A drafted boss summon or barrage overrides the wave cadence: the
        // called recruits and lobbed barrels telegraph immediately.
        if !queuedBossSummons.isEmpty || !queuedBossBarrels.isEmpty {
            let bomberOnly = queuedSummonsBomberOnly
            pendingArrivals = queuedBossSummons.map { rollArrival(at: $0, bomberOnly: bomberOnly) }
            pendingBarrelSpawns = queuedBossBarrels
            primedBarrelTiles = Set(queuedBossBarrels)
            queuedBossSummons = []
            queuedSummonsBomberOnly = false
            queuedBossBarrels = []
            return
        }
        let config = effectiveLevelConfig(for: level)
        guard turnNumber % config.spawnInterval == 0 else { return }

        // During an elite fight, ordinary waves and barrel deliveries stop. The
        // juggernaut summons recruits on nearby open ground each wave — but only
        // up to the retinue cap, so it can't flood the board; the boss proper
        // only summons by drafting its summon intent.
        if bossPhase {
            guard let elite = enemies.first(where: { $0.archetype == .juggernaut }) else { return }
            let boss = BossConfig.forLevel(level)
            let retinue = enemies.filter { !$0.isElite }.count
            guard retinue < boss.retinueCap else { return }
            let taken = Set(enemies.map(\.position))
                .union(obstacles.map(\.position))
                .union(lingeringEffects.map(\.position))
                .union(spawnAvoidTiles)
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
            .union(spawnAvoidTiles)
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
            .union(spawnAvoidTiles)
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
        guard !rules.noLoot, !bossPhase,
              turnNumber % Self.weaponDropInterval == 0,
              weaponDrops.filter({ !$0.isBossDrop }).count < Self.weaponDropCap else { return }
        let taken = Set(enemies.map(\.position))
            .union(obstacles.map(\.position))
            .union(lingeringEffects.map(\.position))
            .union(weaponDrops.map(\.position))
            .union(pendingSpawns)
            .union(pendingBarrelSpawns)
            .union(spawnAvoidTiles)
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
        // A bolt can warp through a portal mid-window, so its flight is recorded
        // in straight segments split at each warp (this is the current segment's
        // origin; a fresh one opens on the far side of every portal).
        var segmentStart = bolt.position
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
                    alive = false
                    break
                }
                // A wall. crumbleWalls shatters it if it's destructible (or Breach
                // is active); a piercing bolt then bores straight on through any
                // wall, a plain one dies against it.
                crumbleWalls(in: [next])
                if !bolt.pierces {
                    alive = false
                    break
                }
                // Piercing: fall through and keep flying past this tile.
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
                        applyPlayerStun(bolt.stun)
                    } else {
                        let strike = damageEnemies(on: [next], damage: bolt.damage, chargesUltimate: bolt.chargesUltimate, credit: bolt.creditName, travelling: bolt.direction)
                        afflict(strike, with: bolt.affliction, chargesUltimate: bolt.chargesUltimate, credit: bolt.creditName)
                        applyStun(strike, turns: bolt.stun)
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

            // A bolt that flies onto a portal (with a clear far end) is whisked
            // across and flies on in the same heading — closing this segment and
            // opening a new one on the exit. Never consumes a step, so range is
            // measured by tiles travelled, not portals taken.
            if alive {
                let warped = teleportDestination(from: bolt.position)
                if warped != bolt.position {
                    flights.append(TurnResolution.BoltFlight(
                        boltID: bolt.id,
                        from: segmentStart,
                        to: bolt.position,
                        direction: bolt.direction
                    ))
                    bolt.position = warped
                    segmentStart = warped
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
            applyStun(blastHits, turns: bolt.stun)
            if bolt.creditName != nil {
                struckByPlayerThisTurn.formUnion(blastHits.map(\.enemyID))
            }
            hits += blastHits
            if !isGameOver && blastSet.contains(playerPosition) {
                let reduction = buffs.reduce(0) { $0 + $1.rangedDamageReduction }
                applyDamage(max(0, bolt.damage - reduction), from: bolt.sourceName)
                afflictPlayer(with: bolt.affliction)
                applyPlayerStun(bolt.stun)
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
            from: segmentStart,
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
            if let obstacle, obstacle.kind == .wall {
                // A crumbling wall can be struck: it's a hittable tile (so it
                // gets smashed), and it still stops a thrust like any wall.
                if obstacle.destructible {
                    result.append(tile)
                    if pattern.isLine { break }
                    continue
                }
                // A solid wall stops a thrust dead, but a shaped swing just can't
                // hit the wall tile itself — it sweeps around it.
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

    /// Packs every open tile with a crumbling wall (the Barricades pact): you and
    /// the enemies have to break out. Bodies, scenery, and board features are left
    /// in their clear spots.
    private mutating func fillWithDestructibleWalls() {
        let occupied = Set(obstacles.map(\.position))
            .union(enemies.map(\.position))
            .union(spikes.map(\.position))
            .union(teleporters.flatMap { [$0.a, $0.b] })
            .union(terrain.map(\.position))
            .union([playerPosition])
        for x in 0..<columns {
            for y in 0..<rows {
                let tile = GridPosition(x: x, y: y)
                guard !occupied.contains(tile) else { continue }
                obstacles.append(Obstacle(id: nextObstacleID, kind: .wall, position: tile, destructible: true))
                nextObstacleID += 1
            }
        }
    }

    /// Removes any destructible walls on the given tiles (a hit or a blast
    /// crumbles them). Solid walls and barrels are left alone.
    /// Whether the player's blows level even solid walls (Breach pact / Siegecraft boon).
    private var wallsAllBreakable: Bool {
        rules.bustsAllWalls || buffs.contains(where: \.siege)
    }

    private mutating func crumbleWalls(in tiles: Set<GridPosition>) {
        let bustAll = wallsAllBreakable
        obstacles.removeAll { $0.kind == .wall && (bustAll || $0.destructible) && tiles.contains($0.position) }
    }

    /// Detonates every barrel in the struck tiles: each blast damages the player
    /// and enemies on surrounding tiles and sets off neighboring barrels in a
    /// chain. Detonated barrels are removed from the board.
    private mutating func detonateBarrels(struckTiles: Set<GridPosition>, chargesUltimate: Bool = true, damageOverride: Int? = nil) -> (explosions: [TurnResolution.Explosion], hits: [TurnResolution.EnemyHit]) {
        var queue = obstacles.filter { $0.kind == .barrel && struckTiles.contains($0.position) }
        var detonatedIDs = Set<Int>()
        var explosions: [TurnResolution.Explosion] = []
        var hits: [TurnResolution.EnemyHit] = []

        while let barrel = queue.popLast() {
            guard !detonatedIDs.contains(barrel.id) else { continue }
            detonatedIDs.insert(barrel.id)

            let blast = blastTiles(around: barrel.position, radius: Self.barrelBlastRadius + rules.barrelBlastBonus)
            explosions.append(TurnResolution.Explosion(center: barrel.position, tiles: blast))

            let blastSet = Set(blast)
            if barrel.barrelKind == .fire {
                // A green barrel spreads flame instead of a concussion: no blast
                // damage, but the tiles it covered burn for a few turns. It still
                // crumbles walls and chains neighbors.
                crumbleWalls(in: blastSet)
                addLingeringEffect(at: blast, damagePerTurn: Self.fireBarrelDamage, duration: Self.fireBarrelDuration,
                                   chargesUltimate: chargesUltimate, creditName: chargesUltimate ? "Barrels" : nil)
            } else {
                // Standard barrels deal a full blast, the Keg's yellow ones half.
                let base = barrel.barrelKind == .weak ? Self.weakBarrelDamage : Self.barrelDamage
                // Player-lit chains tally toward the explosives milestones and ride
                // the deal-double boon (Sharpened); enemy-lit ones stay at base.
                let enemyBlastDamage = damageOverride ?? (chargesUltimate
                    ? Int((Double(base) * rules.damageDealtMult).rounded())
                    : base)
                hits += damageEnemies(on: blastSet, damage: enemyBlastDamage, chargesUltimate: chargesUltimate, credit: chargesUltimate ? "Barrels" : nil)
                // Damage to the player runs through applyDamage, which already
                // scales it by the take-double curse (Fragile).
                if !isGameOver && blastSet.contains(playerPosition)
                    && !buffs.contains(where: \.barrelImmunity) && !rules.barrelImmune {
                    applyDamage(damageOverride ?? base, from: "an exploding barrel")
                }
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
    /// Dev: while true, enemy attacks never stun the player's action.
    var devStunImmune = false
    /// Dev: while true, enemy knockback never shoves the player.
    var devKnockbackImmune = false
    /// Dev: while true, the player can move to any tile on the board, so it's
    /// easy to line up a shove into a barrel or reach anything to test it.
    var devInfiniteSpeed = false
    /// Dev: while true, the player's reach is unbounded — throws land anywhere,
    /// bolts fly the whole board, the grapple bites across it, and line swings
    /// extend to the far edge.
    var devInfiniteRange = false
    /// Dev: while true, the player's weapons never go on cooldown.
    var devNoCooldown = false
    /// Dev: while true, weapon swaps never cost the turn's attack.
    var devFreeSwap = false
    /// Dev: while true, shieldbearers never parry — every hit lands, so their
    /// shield facing can be ignored while testing.
    var devIgnoreShields = false
    /// Dev: when set, pins the level-up offer. `devForcedBuff` is the first
    /// option and `devForcedBuff2` the second; set both to reproduce an exact
    /// two-boon choice, or just one to narrow the offer.
    var devForcedBuff: Buff?
    var devForcedBuff2: Buff?
    /// Dev override for the player's attack damage.
    enum DevDamageMode: CaseIterable {
        /// The weapon's real damage.
        case normal
        /// Enough to one-shot anything.
        case instakill
        /// Zero — the hit lands (stun/knockback still apply) but nothing dies,
        /// so an enemy can be poked repeatedly for testing.
        case zero
    }
    var devDamageMode: DevDamageMode = .normal

    /// Dev-panel override for the next wave. When non-nil, `scheduleSpawns`
    /// forces this on wave turns; nil restores the standard spawn logic.
    enum DevSpawnOverride: Equatable {
        /// Force a shaped squad; nil index picks a random formation.
        case formation(index: Int?)
        /// Force a single enemy; nil archetype/weapon means "roll it normally".
        case single(archetype: Archetype?, weapon: Weapon?)
        /// Drop a gatekeeper of the given archetype (scaled to the level) and
        /// enter the boss phase — a dev shortcut to the gate fights.
        case elite(archetype: Archetype)
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
                .union(spawnAvoidTiles)
            guard let tile = edgeTiles().filter({
                !taken.contains($0) && $0.distance(to: playerPosition) > 3
            }).randomElement() else { return }
            pendingArrivals = [Enemy.devSpawn(archetype: archetype, weapon: weapon, id: nextEnemyID, at: tile, armory: weaponPool)]
            nextEnemyID += 1
        case .elite(let archetype):
            let taken = Set(enemies.map(\.position))
                .union(obstacles.map(\.position))
                .union(lingeringEffects.map(\.position))
                .union(spawnAvoidTiles)
            guard let tile = edgeTiles().filter({
                !taken.contains($0) && $0.distance(to: playerPosition) > 3
            }).randomElement() else { return }
            pendingArrivals = [Enemy.elite(archetype, id: nextEnemyID, at: tile, config: BossConfig.forLevel(level))]
            nextEnemyID += 1
            // Enter the gate fight: waves and score freeze until it falls, just
            // like a real gatekeeper.
            bossPhase = true
        }
    }

    mutating func devSetUltimateCharge(_ value: Int) {
        ultimateKillCharge = max(0, min(Self.ultimateChargeKills, value))
    }

    mutating func devHealFully() {
        playerHealth = maxHealth
        playerArmor = armorCap
    }

    /// Dev: immediately shakes off any active daze on the player — used when
    /// toggling stun immunity on mid-run so it takes effect right away.
    mutating func devClearPlayerStun() {
        playerStunTurns = 0
    }

    mutating func devAddScore(_ amount: Int) {
        score += amount
    }

    /// Armor absorbs damage first; only the overflow reaches health. The
    /// source label feeds the death recap when the hit proves fatal.
    private mutating func applyDamage(_ amount: Int, from source: String, armorPiercing: Int = 0) {
        guard !devInvincible else { return }
        // Glass and kin scale incoming damage as well as outgoing.
        let amount = Int((Double(amount) * rules.damageTakenMult).rounded())
        // A reaver rends past guard: this many points skip armor and bite health.
        let pierce = min(amount, max(0, armorPiercing))
        let throughArmor = amount - pierce
        let absorbed = min(playerArmor, throughArmor)
        playerArmor -= absorbed
        playerHealth -= (throughArmor - absorbed) + pierce
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
        // Active spike traps count as hazard tiles careful enemies route around
        // (the fearless still barrel through, as with pools).
        let hazardTiles = Set(lingeringEffects.map(\.position))
            .union(spikes.filter(\.active).map(\.position))
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
        // A squad marches only as fast as its slowest member, so the swift ranks
        // don't outrun the shieldbearers and tear the formation apart. Cached per
        // squad here and reused when its members draft their march below.
        var formationSpeed: [Int: Int] = [:]
        for (fid, anchor) in formationAnchors {
            let live = enemies.filter { $0.formationID == fid }
            let inbound = pendingArrivals.filter { $0.formationID == fid }.count
            // Bombers peel off on their own (below), so a forward bomber doesn't
            // drag the whole squad's break early — measure from the others.
            let nearest = live.filter { $0.archetype != .bomber }
                .map { $0.position.distance(to: playerPosition) }.min() ?? Int.max
            let packSpeed = max(1, live.map(\.moveRange).min() ?? 1)
            formationSpeed[fid] = packSpeed
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
                // shred the squad against the wall. It advances the pack's speed in
                // one turn so the whole squad keeps station as it closes in.
                let obstacleTiles = Set(obstacles.map(\.position))
                var marched = anchor
                for _ in 0..<packSpeed {
                    let next = stepToward(portalAwareGoal(playerPosition, from: marched), from: marched, avoiding: obstacleTiles)
                    if next == marched { break }
                    marched = next
                }
                formationAnchors[fid] = marched
            }
        }

        // Front-liners plan first so they vacate their tiles before the enemies
        // behind them draft — letting a column flow forward instead of jamming
        // up behind the leader (each mover frees its old tile from `claimed`).
        let draftOrder = enemies.indices.sorted {
            enemies[$0].position.distance(to: playerPosition) < enemies[$1].position.distance(to: playerPosition)
        }
        for index in draftOrder {
            // A stunned enemy plans nothing — it holds its tile, drafts no move
            // or attack, and shows no threat. The countdown ticks at the start
            // of its frozen turn (see resolveTurn), not here.
            if enemies[index].stunTurns > 0 {
                enemies[index].plannedTarget = enemies[index].position
                enemies[index].plannedPath = []
                enemies[index].plannedDirection = nil
                enemies[index].plannedThrowTarget = nil
                enemies[index].plannedIntent = nil
                enemies[index].plannedSecondaryDirection = nil
                enemies[index].plannedDetonateTile = nil
                continue
            }
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
                    // March at the squad's pace, not the member's own — a swift in
                    // the ranks keeps station instead of surging to its slot early.
                    var stride = formationSpeed[fid] ?? enemy.moveRange
                    while stride > 0 {
                        let next = stepToward(goal, from: target, avoiding: avoid)
                        if next == target { break }
                        let cost = stepCost(onto: next)
                        if cost > stride { break }   // mud eats the last step
                        stride -= cost
                        target = next
                        path.append(next)
                        if target == goal { break }
                    }
                    // A member marching onto ice slides on like anyone else.
                    (target, path) = slideEnemyPlan(from: enemy.position, target: target, path: path, blocked: avoid)
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
                        let goal = portalAwareGoal(attackGoal(for: enemy, avoiding: avoid), from: enemy.position)
                        var budget = movementBudget(for: enemy)
                        while budget > 0 {
                            let next = stepToward(goal, from: target, avoiding: avoid)
                            if next == target {
                                break
                            }
                            let cost = stepCost(onto: next)
                            if cost > budget { break }   // mud eats the last step
                            budget -= cost
                            target = next
                            path.append(next)
                            if target.distance(to: playerPosition) <= Self.bomberArmDistance {
                                break
                            }
                        }
                    }
                }
                // Ice carries the bomber on; arm from wherever the slide leaves it.
                (target, path) = slideEnemyPlan(from: enemy.position, target: target, path: path, blocked: avoid)
                if enemy.fuse == nil && target.distance(to: playerPosition) <= Self.bomberArmDistance {
                    enemies[index].fuse = Self.bomberFuseTurns
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
                    var budget = movementBudget(for: enemy)
                    while budget > 0 {
                        let next = stepToward(goal, from: target, avoiding: avoid)
                        if next == target {
                            break
                        }
                        let cost = stepCost(onto: next)
                        if cost > budget { break }   // mud eats the last step
                        budget -= cost
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
            // A move that lands on ice slides on; fold it in before drafting the
            // aim so the shot (and shield facing) come from the true resting tile.
            (target, path) = slideEnemyPlan(from: enemy.position, target: target, path: path, blocked: avoid)
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
            if enemy.usesEliteIntents {
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

        // Walled in (Barricades or just cornered): an enemy that can't advance
        // and isn't attacking smashes the crumbling wall between it and the
        // player, opening a path to move through next turn.
        for index in enemies.indices {
            enemies[index].plannedDigTile = nil
            let enemy = enemies[index]
            guard enemy.stunTurns == 0,
                  (enemy.plannedTarget ?? enemy.position) == enemy.position,
                  enemy.plannedDirection == nil, enemy.plannedThrowTarget == nil, enemy.plannedIntent == nil
            else { continue }
            let from = enemy.position
            let dx = (playerPosition.x - from.x).signum()
            let dy = (playerPosition.y - from.y).signum()
            let candidates = abs(playerPosition.x - from.x) >= abs(playerPosition.y - from.y)
                ? [GridPosition(x: from.x + dx, y: from.y), GridPosition(x: from.x, y: from.y + dy)]
                : [GridPosition(x: from.x, y: from.y + dy), GridPosition(x: from.x + dx, y: from.y)]
            for candidate in candidates where candidate != from && contains(candidate) {
                if let wall = obstacle(at: candidate), wall.kind == .wall, wall.destructible {
                    enemies[index].plannedDigTile = candidate
                    break
                }
            }
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
        let goal = portalAwareGoal(attackGoal(for: enemy, avoiding: blocked), from: enemy.position)
        var budget = movementBudget(for: enemy)
        while budget > 0 {
            var next = stepToward(goal, from: target, avoiding: blocked)
            if next == target && danger.contains(target) {
                next = stepToward(goal, from: target, avoiding: blocked.subtracting(danger))
            }
            if next == target {
                break
            }
            let cost = stepCost(onto: next)
            if cost > budget { break }   // mud eats the last step
            budget -= cost
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
        let retinue = enemies.filter { !$0.isElite }.count
        // Summoning is gated both by the retinue cap (how many) and a cadence
        // (how often) — a fresh wave of fodder mostly dies to bombers, the
        // boss's own greataxe/nova friendly fire, and the player's blasts, so
        // without the cadence the boss would resummon every single turn.
        let canSummon = retinue < config.retinueCap
            && turnNumber - lastBossSummonTurn >= Self.bossSummonInterval

        // The lesser casters (summoner, bombardier) share the summon intent but
        // carry no cannon, so they branch off here before the boss's nova/volley.
        if boss.archetype != .boss {
            let primaryReady = boss.cooldownRemaining == 0
            let primaryAim = primaryReady ? aimDirection(weapon: boss.weapon, attackerID: boss.id, from: tile) : nil
            switch boss.archetype {
            case .summoner:
                // Calls in fodder whenever it can; otherwise pokes with the bow.
                if canSummon {
                    enemies[index].plannedIntent = .summon
                } else if let aim = primaryAim {
                    enemies[index].plannedIntent = .volley
                    enemies[index].plannedDirection = aim
                }
            case .bombardier:
                // The explosives specialist, all under one theme: cash in a primed
                // barrel that boxes you, else call in a bomber swarm, else seed a
                // fresh barrel barrage, else fend you off with its ordnance — a
                // lobbed grenade or an exploding bolt.
                if let detonateTile = bossDetonationTarget() {
                    enemies[index].plannedIntent = .detonate
                    enemies[index].plannedDetonateTile = detonateTile
                } else if canSummon {
                    enemies[index].plannedIntent = .summon
                } else {
                    let liveVolatile = obstacles.filter { $0.kind == .barrel && $0.volatile }.count
                    if liveVolatile < config.bossBarrageCount && !barrageTiles().isEmpty {
                        enemies[index].plannedIntent = .barrage
                    } else if primaryReady && canHitPlayer(boss, from: tile) {
                        if boss.weapon.thrown != nil {
                            enemies[index].plannedThrowTarget = playerPosition
                        } else if let aim = primaryAim {
                            enemies[index].plannedIntent = .volley
                            enemies[index].plannedDirection = aim
                        }
                    }
                }
            default:
                break
            }
            return
        }

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
            .union(spawnAvoidTiles)
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
    /// The tile an enemy should actually head for, factoring in teleporters: if
    /// stepping onto a portal end and popping out the far side gets it meaningfully
    /// closer to `finalGoal`, that near end becomes the interim goal (the enemy
    /// walks onto it, stops, and warps at resolve). Otherwise `finalGoal` itself.
    private func portalAwareGoal(_ finalGoal: GridPosition, from: GridPosition) -> GridPosition {
        guard !teleporters.isEmpty else { return finalGoal }
        var best = finalGoal
        var bestCost = from.distance(to: finalGoal)
        for tp in teleporters {
            // Only route to an end whose exit is currently clear — otherwise the
            // warp would fizzle and the enemy would idle on a dead portal.
            if tp.a != from, teleportDestination(from: tp.a) == tp.b {
                let cost = from.distance(to: tp.a) + tp.b.distance(to: finalGoal)
                if cost < bestCost { bestCost = cost; best = tp.a }
            }
            if tp.b != from, teleportDestination(from: tp.b) == tp.a {
                let cost = from.distance(to: tp.b) + tp.a.distance(to: finalGoal)
                if cost < bestCost { bestCost = cost; best = tp.b }
            }
        }
        return best
    }

    private func stepToward(_ goal: GridPosition, from: GridPosition, avoiding claimed: Set<GridPosition>) -> GridPosition {
        let dx = (goal.x - from.x).signum()
        let dy = (goal.y - from.y).signum()
        let stepX = GridPosition(x: from.x + dx, y: from.y)
        let stepY = GridPosition(x: from.x, y: from.y + dy)
        let xGapIsLarger = abs(goal.x - from.x) >= abs(goal.y - from.y)
        // First choice: close the gap on whichever axis is wider.
        var candidates = xGapIsLarger ? [stepX, stepY] : [stepY, stepX]
        // Deflections: when the direct step is walled off, slide perpendicular to
        // round the obstacle instead of halting. Only added along an axis with no
        // remaining gap, so an approach straight down a row/column can still slip
        // past a wall parked in front of it (the old code just stopped dead here).
        if dx == 0 {
            candidates += [GridPosition(x: from.x + 1, y: from.y), GridPosition(x: from.x - 1, y: from.y)]
        }
        if dy == 0 {
            candidates += [GridPosition(x: from.x, y: from.y + 1), GridPosition(x: from.x, y: from.y - 1)]
        }
        for candidate in candidates where candidate != from && contains(candidate) && !claimed.contains(candidate) {
            return candidate
        }
        return from
    }
}
