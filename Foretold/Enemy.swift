//
//  Enemy.swift
//  Foretold
//

/// Which end of the arsenal a spawn should draw from — lets a formation slot
/// ask for a melee bruiser or a ranged skirmisher specifically.
enum WeaponClass {
    case any, melee, ranged
}

/// Behavior templates layered on top of a weapon.
enum Archetype: Equatable {
    /// The standard enemy: weapon defines everything.
    case fighter
    /// Fearless melee: ignores hazards and telegraphed danger entirely.
    case berserker
    /// +1 move range on top of its weapon.
    case swift
    /// Charges adjacent, arms a visible fuse, then detonates — and detonates
    /// on death too, so finish it from outside the blast.
    case bomber
    /// Raises a shield toward the player: the first swing driven into its front
    /// each turn is parried. Flank it, wait for it to turn, or use AoE.
    case shieldbearer
    /// Rending melee: one point of every hit it lands bites straight through
    /// your armor to your health. Rare — respect it.
    case reaver
    /// Miniboss: heavy melee with a deep health pool.
    case juggernaut
    /// The real thing: huge, hard-hitting, worth a fat bounty.
    case boss
    /// Gate elite: a frail caster that leans on its retinue, calling in fresh
    /// reinforcements far faster than a juggernaut and poking with a bow.
    case summoner
    /// Gate elite: an explosives handler that calls in swarms of bombers and
    /// lobs grenades from range — every reinforcement it summons is a walking bomb.
    case bombardier
}

/// A foe on the board. Enemies draft a move toward the player and, when their
/// weapon can reach the player's tile from the drafted position (and isn't on
/// cooldown), an aimed swing or a lobbed throw — all telegraphed during the
/// planning phase.
struct Enemy {
    /// The boss drafts one of these each turn, telegraphed like any plan:
    /// fire both weapons at once, sweep the cannon in a circle around itself,
    /// rain explosive barrels around the player, set off barrels it already
    /// laid, or call reinforcements.
    enum BossIntent {
        case volley, nova, barrage, detonate, summon
    }

    let id: Int
    var position: GridPosition
    var health: Int
    /// Where this enemy intends to move next resolve; visible to the player while planning.
    var plannedTarget: GridPosition?
    /// The tiles it will step through to get there (destination included) —
    /// crossing a lingering hazard burns the mover per tile stepped.
    var plannedPath: [GridPosition] = []
    /// The facing of the swing this enemy intends after moving (directional weapons).
    var plannedDirection: Direction?
    /// The tile this enemy intends to lob its weapon at (thrown weapons).
    var plannedThrowTarget: GridPosition?
    /// A crumbling wall this enemy will smash this turn when it's otherwise
    /// boxed in (Barricades), opening a path toward the player. Telegraphed.
    var plannedDigTile: GridPosition?
    /// Turns left before this enemy's weapon is ready again.
    var cooldownRemaining = 0
    /// Bosses only: the cannon reloads on its own clock, so a nova and a volley
    /// can interleave — one weapon firing while the other is still cooling.
    var secondaryCooldownRemaining = 0
    /// Bombers only: turns until detonation once armed; nil = not armed yet.
    var fuse: Int?
    /// A bleed or poison riding on this enemy; ticks at the end of each turn.
    var affliction: ActiveAffliction?
    /// Turns this enemy is stunned. While >0 it plans nothing — no move, no
    /// attack, no boss intent — and any telegraphed attack this resolve fizzles.
    /// Decremented as it drafts each turn.
    var stunTurns = 0
    /// Bosses only: the drafted intent for next resolve.
    var plannedIntent: BossIntent?
    /// Volley only: the facing of the cannon shot alongside the primary swing.
    var plannedSecondaryDirection: Direction?
    /// Detonate only: the barrel the boss will set off this resolve.
    var plannedDetonateTile: GridPosition?
    /// While set, the enemy is holding its slot in a marching squad: it heads
    /// for `formationOffset` from the squad's advancing anchor rather than
    /// pathing solo, until the squad closes on the player and breaks.
    var formationID: Int?
    /// This enemy's tile offset from its squad's anchor (already rotated to the
    /// entry edge).
    var formationOffset = GridPosition(x: 0, y: 0)
    /// Shieldbearer only: the way its shield points (toward the player), set
    /// while drafting and telegraphed so the player can plan a flank.
    var facing: Direction?
    /// Shieldbearer only: turns until the shield is raised again — 0 means up.
    /// A parry drops it, and it stays down a full turn, so it can't block on
    /// back-to-back turns.
    var shieldCooldown = 0
    /// Whether the shield is currently raised.
    var shieldReady: Bool { shieldCooldown == 0 }
    let weapon: Weapon
    /// Bosses only: the cannon carried alongside the primary weapon.
    let secondaryWeapon: Weapon?
    /// Damage dealt per hit; defaults to the weapon's damage.
    let damage: Int
    let archetype: Archetype

    init(id: Int, position: GridPosition, health: Int? = nil, weapon: Weapon? = nil, secondaryWeapon: Weapon? = nil, damage: Int? = nil, archetype: Archetype = .fighter) {
        self.id = id
        self.position = position
        let carried = weapon ?? Weapon.lootTable.randomElement()!
        self.weapon = carried
        self.secondaryWeapon = secondaryWeapon
        self.health = health ?? carried.enemyHealth
        self.damage = damage ?? carried.damage
        self.archetype = archetype
    }

    /// Tiles moved per turn: the weapon's range, plus haste for the swift, minus
    /// a step for the lumbering shieldbearer — but never below 1, so its wall
    /// still has to be kited, not simply outrun.
    var moveRange: Int {
        switch archetype {
        case .swift: return weapon.moveRange + 1
        case .shieldbearer: return max(1, weapon.moveRange - 1)
        default: return weapon.moveRange
        }
    }

    /// Fearless enemies path straight through hazards and telegraphed danger.
    var isFearless: Bool { archetype == .berserker || archetype == .bomber }

    /// A level's gatekeeper — worth a fat bounty, it gates the level, freezes
    /// score/waves until it falls, and survives the level's regeneration.
    var isElite: Bool {
        switch archetype {
        case .juggernaut, .boss, .summoner, .bombardier: return true
        default: return false
        }
    }

    /// Elites that draft a telegraphed caster intent each turn (summon, barrage,
    /// detonate, nova, volley) instead of a plain move-and-swing. The juggernaut
    /// is an elite but fights as a bruiser, so it's excluded.
    var usesEliteIntents: Bool {
        switch archetype {
        case .boss, .summoner, .bombardier: return true
        default: return false
        }
    }

    /// Reeling from a stun: skips planning and acting until it wears off.
    var isStunned: Bool { stunTurns > 0 }

    /// True when this enemy has drafted a move off its current tile — so the
    /// player may step onto the tile it's leaving.
    var isVacating: Bool {
        guard let plannedTarget else { return false }
        return plannedTarget != position
    }

    /// Whether the shieldbearer parries an attack driving in `direction`: only
    /// while the shield is still up, and only for a hit travelling roughly
    /// opposite the way the shield points (into its front). Directionless blows
    /// (blasts, hazards) pass no direction and are never parried.
    func parries(_ direction: Direction?) -> Bool {
        guard archetype == .shieldbearer, shieldReady, let facing, let direction else { return false }
        let f = facing.unitStep
        let t = direction.unitStep
        return f.x * t.x + f.y * t.y < 0
    }

    /// A hit driving in `direction` that lands in the shieldbearer's back — the
    /// way the shield points away from — where it's most exposed.
    func struckFromBehind(_ direction: Direction?) -> Bool {
        guard archetype == .shieldbearer, let facing, let direction else { return false }
        let f = facing.unitStep
        let t = direction.unitStep
        return f.x * t.x + f.y * t.y > 0
    }

    /// Kill score, before combo/streak bonuses.
    var bounty: Int {
        switch archetype {
        case .juggernaut: return 30
        case .summoner, .bombardier: return 40
        case .boss: return 50
        default: return GameState.killScore
        }
    }

    var displayName: String {
        switch archetype {
        case .fighter: return weapon.name
        case .berserker: return "Berserker · \(weapon.name)"
        case .swift: return "Swift · \(weapon.name)"
        case .bomber: return "Bomber"
        case .shieldbearer: return "Shieldbearer · \(weapon.name)"
        case .reaver: return "Reaver · \(weapon.name)"
        case .juggernaut: return "JUGGERNAUT · \(weapon.name)"
        case .boss: return "BOSS · \(weapon.name)\(secondaryWeapon.map { " + \($0.name)" } ?? "")"
        case .summoner: return "SUMMONER · \(weapon.name)"
        case .bombardier: return "BOMBARDIER · \(weapon.name)"
        }
    }

    /// How this enemy is credited as a killer in the death recap — "undone by
    /// a fighter's Bow" rather than the bare weapon name.
    var slayerName: String {
        switch archetype {
        case .fighter: return "a fighter's \(weapon.name)"
        case .berserker: return "a berserker's \(weapon.name)"
        case .swift: return "a swift's \(weapon.name)"
        case .bomber: return "a bomber"
        case .shieldbearer: return "a shieldbearer's \(weapon.name)"
        case .reaver: return "a reaver's \(weapon.name)"
        case .juggernaut: return "the juggernaut's \(weapon.name)"
        case .boss: return "the boss's \(weapon.name)"
        case .summoner: return "the summoner's \(weapon.name)"
        case .bombardier: return "the bombardier's \(weapon.name)"
        }
    }

    /// A random rank-and-file spawn: mostly fighters, seasoned with berserkers,
    /// swifts, shieldbearers, the occasional bomber, and a rare rending reaver.
    static func recruit(id: Int, at position: GridPosition, armory: [Weapon] = Weapon.lootTable) -> Enemy {
        let archetype: Archetype
        switch Int.random(in: 0..<100) {
        case ..<45: archetype = .fighter
        case ..<60: archetype = .berserker
        case ..<74: archetype = .swift
        case ..<86: archetype = .shieldbearer
        case ..<95: archetype = .bomber
        default: archetype = .reaver
        }
        return recruit(archetype, id: id, at: position, armory: armory)
    }

    /// A rank-and-file spawn of a specific archetype — used to fill formation
    /// slots. `weaponClass` narrows the fighter/swift armory to melee or ranged;
    /// berserkers and shieldbearers are melee by nature, bombers carry a dagger.
    /// Elites aren't summoned this way and fall back to a plain fighter.
    static func recruit(_ archetype: Archetype, weaponClass: WeaponClass = .any, id: Int, at position: GridPosition, armory: [Weapon] = Weapon.lootTable) -> Enemy {
        func pick() -> Weapon {
            let pool: [Weapon]
            switch weaponClass {
            case .any: pool = armory
            case .melee: pool = armory.filter(\.isMelee)
            case .ranged: pool = armory.filter(\.isRanged)
            }
            return pool.randomElement() ?? armory.randomElement() ?? .sword
        }
        switch archetype {
        case .fighter, .swift:
            return Enemy(id: id, position: position, weapon: pick(), archetype: archetype)
        case .reaver:
            // A rending skirmisher — melee by nature, so it has to close in to bite.
            let melee = armory.filter(\.isMelee).randomElement() ?? .sword
            return Enemy(id: id, position: position, weapon: melee, archetype: .reaver)
        case .berserker:
            let melee = armory.filter(\.isMelee).randomElement() ?? .sword
            return Enemy(id: id, position: position, weapon: melee, archetype: .berserker)
        case .shieldbearer:
            // A sturdy melee wall: parries head-on swings, so flank it or blast it.
            let melee = armory.filter(\.isMelee).randomElement() ?? .sword
            return Enemy(id: id, position: position, health: 5, weapon: melee, archetype: .shieldbearer)
        case .bomber:
            return Enemy(id: id, position: position, health: 2, weapon: .dagger, archetype: .bomber)
        case .juggernaut, .boss, .summoner, .bombardier:
            // Elites aren't summoned as rank-and-file; fall back to a plain fighter.
            return Enemy(id: id, position: position, weapon: armory.randomElement()!)
        }
    }

    /// A dev-panel spawn: a chosen archetype (nil rolls one) carrying a chosen
    /// weapon (nil rolls one via the normal recruit), keeping each archetype's
    /// health quirks even with a forced weapon.
    static func devSpawn(archetype: Archetype?, weapon: Weapon?, id: Int, at position: GridPosition, armory: [Weapon] = Weapon.lootTable) -> Enemy {
        let type = archetype ?? [.fighter, .berserker, .swift, .shieldbearer, .bomber, .reaver].randomElement()!
        guard let weapon else { return recruit(type, id: id, at: position, armory: armory) }
        switch type {
        case .shieldbearer:
            return Enemy(id: id, position: position, health: 5, weapon: weapon, archetype: .shieldbearer)
        case .bomber:
            return Enemy(id: id, position: position, health: 2, weapon: weapon, archetype: .bomber)
        default:
            return Enemy(id: id, position: position, weapon: weapon, archetype: type)
        }
    }

    /// A late-level elite: the juggernaut miniboss, or the boss proper. Health
    /// and damage ramp with the level via the supplied config.
    static func elite(_ archetype: Archetype, id: Int, at position: GridPosition, config: BossConfig) -> Enemy {
        switch archetype {
        case .boss:
            // Always the cannon as sidearm — it's the run's only source of one.
            let arsenal = [Weapon.greataxe, .crossbow].randomElement()!
            return Enemy(id: id, position: position, health: config.bossHealth, weapon: arsenal, secondaryWeapon: .cannon, damage: arsenal.damage + 1 + config.eliteDamageBonus, archetype: .boss)
        case .summoner:
            // A frail caster leaning on its retinue; a bow to poke when cornered.
            return Enemy(id: id, position: position, health: config.summonerHealth, weapon: .bow, damage: Weapon.bow.damage + config.eliteDamageBonus, archetype: .summoner)
        case .bombardier:
            // The explosives specialist: summons bomber swarms, rains barrel
            // barrages, and fights with a lobbed grenade or an exploding bolt.
            let ordnance = [Weapon.grenade, .explosiveCrossbow].randomElement()!
            return Enemy(id: id, position: position, health: config.bombardierHealth, weapon: ordnance, damage: ordnance.damage + config.eliteDamageBonus, archetype: .bombardier)
        default:
            let heavy = [Weapon.hammer, .greataxe].randomElement()!
            return Enemy(id: id, position: position, health: config.juggernautHealth, weapon: heavy, damage: heavy.damage + config.eliteDamageBonus, archetype: .juggernaut)
        }
    }
}

/// A shaped squad that can march in as one wave. Authored marching inward from
/// the left edge (+x, deeper into the board), rotated to whichever edge it
/// actually enters — kin to a weapon's attack pattern. Each slot fixes both a
/// tile offset and which kind of enemy stands there, so squads have a makeup:
/// a shield wall up front, a flock of swifts, a bomber charge.
struct Formation {
    struct Slot {
        let offset: GridPosition
        let archetype: Archetype
        /// Narrows a fighter/swift to a melee or ranged weapon; ignored by
        /// archetypes whose weapon is fixed (shieldbearer, berserker, bomber).
        let weaponClass: WeaponClass

        init(_ x: Int, _ y: Int, _ archetype: Archetype, _ weaponClass: WeaponClass = .any) {
            self.offset = GridPosition(x: x, y: y)
            self.archetype = archetype
            self.weaponClass = weaponClass
        }
    }

    /// Shown in the dev spawn picker.
    let name: String
    let slots: [Slot]

    static let all: [Formation] = [
        // Shield wall: a front rank of shields with an archer covered behind it.
        Formation(name: "Shield wall", slots: [Slot(1, 1, .shieldbearer), Slot(1, 0, .shieldbearer), Slot(1, -1, .shieldbearer), Slot(0, 0, .fighter, .ranged)]),
        // Firing line: two shields up front, a rank of archers behind them.
        Formation(name: "Firing line", slots: [Slot(1, 1, .shieldbearer), Slot(1, -1, .shieldbearer), Slot(0, 1, .fighter, .ranged), Slot(0, 0, .fighter, .ranged), Slot(0, -1, .fighter, .ranged)]),
        // Spearhead: a shield at the point, fighters flanking, a swift trailing.
        Formation(name: "Spearhead", slots: [Slot(2, 0, .shieldbearer), Slot(1, 1, .fighter, .melee), Slot(1, -1, .fighter, .ranged), Slot(0, 0, .swift)]),
        // A flying-V flock of swifts.
        Formation(name: "Swift flock", slots: [Slot(0, 0, .swift), Slot(1, 1, .swift), Slot(2, 2, .swift), Slot(1, -1, .swift), Slot(2, -2, .swift)]),
        // Bomber vanguard: a bomber at the tip that peels off to charge, a shield
        // pair and a covering archer marching behind it.
        Formation(name: "Bomber vanguard", slots: [Slot(2, 0, .bomber), Slot(1, 1, .shieldbearer), Slot(1, -1, .shieldbearer), Slot(0, 0, .fighter, .ranged)]),
        // Bomber escort: a screen of berserker, shield and archer up front with
        // the bomber tucked behind, breaking out to charge once it closes.
        Formation(name: "Bomber escort", slots: [Slot(1, 1, .berserker), Slot(1, 0, .shieldbearer), Slot(1, -1, .fighter, .ranged), Slot(0, 0, .bomber)]),
        // A 2×2 block of shields and fighters.
        Formation(name: "Block", slots: [Slot(1, 0, .shieldbearer), Slot(1, 1, .shieldbearer), Slot(0, 0, .fighter), Slot(0, 1, .fighter)]),
        // Spearhead but with all beserkers
        Formation(name: "Beserker Spearhead", slots: [Slot(1, 0, .berserker), Slot(0, 1, .berserker), Slot(0, -1, .berserker)]),
        // A full melee rush
        Formation(name: "Melee rush", slots: [Slot(0, 0, .reaver), Slot(1, 0, .shieldbearer), Slot(0, 1, .berserker), Slot(0, -1, .berserker)])
    ]
}
