//
//  Buffs.swift
//  Foretold
//

/// A boon granted on level-up. Author buffs by setting only the knobs they
/// use — everything defaults to "no effect":
/// - `instantHeal` / `instantArmorRepair` apply once, when granted.
/// - The damage reductions, immunities, and bonuses apply continuously while
///   the buff is held (a buff with only instant effects is never "held").
/// - `levelDuration` is how many level-ups the buff survives: 1 lasts just the
///   current level, 2 wears off two level-ups later, nil lasts the whole run.
/// - `turnDuration` is the other clock: a buff dug out of a mud cache burns off
///   after this many turns instead of surviving to a level-up. Set one clock or
///   the other, never both.
/// - `stackable: false` removes it from the pool while owned.
struct Buff: Equatable {
    let name: String
    let levelDuration: Int?
    /// Turns this buff lasts when it came out of a cache; nil for the
    /// level-scoped boons the level-up screen hands out.
    let turnDuration: Int?
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
    // Rule/trigger effects — how the game plays, not just the numbers.
    /// Weapon swaps no longer cost the turn's attack.
    let freeSwap: Bool
    /// A kill this turn shaves a turn off the weapon's reload.
    let killRefundsCooldown: Bool
    /// A move of just one tile (no action) earns the dodge.
    let dodgeAtOne: Bool
    /// Landing a dodge repairs one armor.
    let dodgeRepairsArmor: Bool
    /// Each kill charges the ultimate by two instead of one.
    let killChargesExtra: Bool
    /// Your fired shots pierce enemies and bore straight through walls.
    let piercingShots: Bool
    /// A kill restores 1 health.
    let killHeals: Bool
    /// A melee attacker that lands a hit on you takes 1 damage back.
    let retaliation: Bool
    /// Your attacks shatter any wall, not only the crumbling kind.
    let siege: Bool

    init(
        name: String,
        levelDuration: Int? = nil,
        turnDuration: Int? = nil,
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
        freeSwap: Bool = false,
        killRefundsCooldown: Bool = false,
        dodgeAtOne: Bool = false,
        dodgeRepairsArmor: Bool = false,
        killChargesExtra: Bool = false,
        piercingShots: Bool = false,
        killHeals: Bool = false,
        retaliation: Bool = false,
        siege: Bool = false,
    ) {
        self.name = name
        self.levelDuration = levelDuration
        self.turnDuration = turnDuration
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
        self.freeSwap = freeSwap
        self.killRefundsCooldown = killRefundsCooldown
        self.dodgeAtOne = dodgeAtOne
        self.dodgeRepairsArmor = dodgeRepairsArmor
        self.killChargesExtra = killChargesExtra
        self.piercingShots = piercingShots
        self.killHeals = killHeals
        self.retaliation = retaliation
        self.siege = siege
    }

    /// Purely instant buffs aren't kept in the held list after applying.
    var isInstantOnly: Bool {
        meleeDamageReduction == 0 && rangedDamageReduction == 0
            && !barrelImmunity && !hazardImmunity
            && bonusMoveRange == 0 && bonusDamage == 0
            && bonusArmor == 0
            && !freeSwap && !killRefundsCooldown && !dodgeAtOne
            && !dodgeRepairsArmor && !killChargesExtra
            && !piercingShots && !killHeals && !retaliation && !siege
    }
}

// MARK: - Buffs
// Author level-up boons here; the pool below is what level-ups draw from.
extension Buff {
    static let barrelImmune = Buff(name: "Immune to barrels", levelDuration: 2, stackable: false, barrelImmunity: true)
    static let poolWard = Buff(name: "Immune to hazard pools", levelDuration: 2, stackable: false, hazardImmunity: true)
    static let thickSkin = Buff(name: "-1 melee dmg taken", levelDuration: 3, meleeDamageReduction: 1)
    static let secondWind = Buff(name: "Recover 2 HP", instantHeal: 2)
    static let longStride = Buff(name: "+1 move", levelDuration: 1, bonusMoveRange: 1)
    static let whetstone = Buff(name: "+1 dmg", levelDuration: 1, bonusDamage: 1)
    static let hardenedArmour = Buff(name: "+1 max armour", levelDuration: 1, instantArmorRepair: 1, bonusArmor: 1)
    // Rule/effect boons — change how the run plays, not the numbers.
    static let quickHands = Buff(name: "Quick Hands · free swaps", levelDuration: 2, stackable: false, freeSwap: true)
    static let rampage = Buff(name: "Rampage · a kill shaves your reload", levelDuration: 2, stackable: false, killRefundsCooldown: true)
    static let sureFeet = Buff(name: "Sure Feet · dodge on a 1-tile move", levelDuration: 2, stackable: false, dodgeAtOne: true)
    static let aftershock = Buff(name: "Aftershock · a dodge repairs 1 armour", levelDuration: 2, stackable: false, dodgeRepairsArmor: true)
    static let executioner = Buff(name: "Executioner · kills charge the omen ×2", levelDuration: 2, stackable: false, killChargesExtra: true)
    static let deadeye = Buff(name: "Deadeye · your shots pierce", levelDuration: 3, stackable: false, piercingShots: true)
    static let bloodthirst = Buff(name: "Bloodthirst · every 3rd kill heals 1 HP", levelDuration: 1, stackable: false, killHeals: true)
    static let thorns = Buff(name: "Thorns · melee attackers take 1", levelDuration: 2, stackable: false, retaliation: true)
    static let siegecraft = Buff(name: "Siegecraft · your blows shatter any wall", levelDuration: 3, stackable: false, siege: true)
    /// The pool level-ups draw from.
    static let all: [Buff] = [
        .barrelImmune, .poolWard, .thickSkin, .secondWind, .longStride, .whetstone, .hardenedArmour,
        .quickHands, .rampage, .sureFeet, .aftershock, .executioner,
        .deadeye, .bloodthirst, .thorns, .siegecraft,
    ]

    // MARK: Cache boons
    // What's buried in the mud. These run on the turn clock, not the level
    // clock, so they're a window to spend rather than a stat to carry — which
    // is why every one of them is a verb. A flat +1 for four turns can pass
    // without the player ever seeing it change an outcome; "your shots pierce"
    // announces itself the first time you fire.
    //
    // Four turns, not three: you dig these out while standing in mud, so the
    // first turn or two goes on slogging back to anything worth using them on.
    static let flintEdge = Buff(name: "Flint Edge · your shots pierce", turnDuration: 4, piercingShots: true)
    static let maulHead = Buff(name: "Maul Head · your blows shatter any wall", turnDuration: 4, siege: true)
    static let oiledStrap = Buff(name: "Oiled Strap · swaps are free", turnDuration: 4, freeSwap: true)
    static let warHorn = Buff(name: "War Horn · a kill shaves your reload", turnDuration: 4, killRefundsCooldown: true)
    /// The boons a mud cache can hold.
    static let cacheBoons: [Buff] = [.flintEdge, .maulHead, .oiledStrap, .warHorn]
}

// MARK: - Omens

/// The ultimate the player carries for the run, chosen at the draft. Each is a
/// different verb rather than a different number — damage, board state, tempo,
/// freedom — so the pick shapes how a run is played rather than how hard it
/// hits. The charge cost rides along with the omen: a cheap omen is one you
/// lean on, an expensive one is a run-defining moment.
///
/// `smite` is the starter and keeps the original board-wide behaviour, so an
/// existing run plays exactly as it did before omens were selectable.
enum Omen: String, CaseIterable {
    /// The sky falls on every enemy, wherever they stand.
    case smite
    /// Banks charges; each sets off one barrel of your choosing, on your turn.
    case detonation
    /// Every enemy is frozen solid — no move, no attack — for two turns.
    case stillness
    /// Both carried weapons ignore their reload for two turns.
    case quickening

    var title: String {
        switch self {
        case .smite: return "Smite"
        case .detonation: return "Detonation"
        case .stillness: return "Stillness"
        case .quickening: return "Quickening"
        }
    }

    var blurb: String {
        switch self {
        case .smite: return "the sky falls on every enemy at once"
        case .detonation: return "3 charges — set off a barrel of your choosing"
        case .stillness: return "every enemy freezes for two turns"
        case .quickening: return "your weapons ignore their reload for two turns"
        }
    }

    /// Kills needed to charge it.
    var chargeKills: Int {
        switch self {
        case .smite, .stillness: return 10
        case .detonation, .quickening: return 5
        }
    }

    /// Charges banked when it fires, for omens that pay out over several turns
    /// rather than all at once. Detonating the whole board in one go fell off a
    /// cliff late on, when too few barrels spawn to be worth 5 kills; banked
    /// charges let the omen wait for targets instead of wasting itself on an
    /// empty board.
    var charges: Int {
        switch self {
        case .detonation: return 3
        case .smite, .stillness, .quickening: return 0
        }
    }

    /// Turns the effect lingers for, where that applies.
    var duration: Int {
        switch self {
        case .stillness, .quickening: return 2
        case .smite, .detonation: return 0
        }
    }

    /// The order the draft cycles them in: the blunt, legible one first, the
    /// ones that need you to read the board last. Unlocks are expected to
    /// follow the same order.
    static let ordered: [Omen] = [.smite, .quickening, .detonation, .stillness]
}

/// A buff the player currently holds, with its remaining lifetime. Exactly one
/// of the two clocks runs: level-up boons age on `levelsRemaining`, cache boons
/// on `turnsRemaining`. The other stays nil, which reads as "this clock doesn't
/// apply" rather than "never expires" — each decay pass only culls buffs whose
/// own clock has run out.
struct HeldBuff {
    let buff: Buff
    /// Level-ups left before it wears off; nil = not on the level clock.
    var levelsRemaining: Int? = nil
    /// Turns left before it burns off; nil = not on the turn clock.
    var turnsRemaining: Int? = nil
}
