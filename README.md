# Foretold

A turn-drafting tactics roguelite for macOS, built with SpriteKit.

Every turn is drafted before it resolves: you plan a move plus an attack (or a
throw) while seeing every enemy's telegraphed move, aim, and incoming spawn —
then everything plays out at once. You know the future; the game is about
outplaying it.

## Mechanics

- **Two-slot loadout.** Carry two weapons, Soul Knight style; swapping costs
  the whole turn. Each weapon sets your move range, damage, pierce, cooldown,
  and attack shape — heavier weapons hit harder but slow you down.
- **Attack patterns.** Directional weapons swing an authored tile pattern
  (rotated to 4 or, with a diagonal shape, 8 facings); thrown weapons (grenade,
  poison potion) lob at any tile in range and blast a diamond — hitting the
  thrower too if they're caught in it.
- **Armor vs HP.** Armor absorbs damage first and regenerates on every second
  quiet turn; health never comes back.
- **Dodge.** Move 2+ tiles without attacking and the first hit that turn
  misses.
- **Enemies play by the same rules.** Random weapons, kiting to firing range,
  weapon-scaled health and damage, cooldown reloads — and friendly fire.
- **The board fights too.** Walls block movement and shots; explosive barrels
  chain-react in a radius-2 diamond; lingering hazards burn whoever ends a
  turn standing in them.
- **Endless waves.** Reinforcements telegraph their spawn tiles a turn ahead;
  standing on a marker blocks that spawn for 1 damage. Score +1 per turn
  survived, +10 per kill — however it dies.

## Controls

| Input | Action |
|---|---|
| Left click | Draft a move |
| Right click | Aim an attack / target a throw |
| Esc | Cancel the drafted attack |
| Space / Return | Resolve the turn (GO) |
| Tab / Q | Swap weapons (costs the turn) |
| R ×2 | Restart and reroll (single R once defeated) |
| B | Boom mode: next restart replaces walls with barrels |

Hover any enemy to see its weapon, health, reload status, and exactly which
tiles its drafted attack will sweep. Hover a barrel to see its blast radius.

## Tuning

All the rules live in `Foretold/GameState.swift`, deliberately free of
SpriteKit: weapon stats and attack patterns, barrel damage/radius, dodge
distance, spawn cadence, and scoring are constants and presets near the top of
the file. `GameScene.swift` only draws and animates.
