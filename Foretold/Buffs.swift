//
//  Buffs.swift
//  Foretold
//

import Foundation

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
