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
}

/// A buff the player currently holds, with its remaining lifetime.
struct HeldBuff {
    let buff: Buff
    /// Level-ups left before it wears off; nil = the whole run.
    var levelsRemaining: Int?
}
