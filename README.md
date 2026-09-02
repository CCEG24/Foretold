# Foretold

A turn-drafting tactics roguelite for macOS, built with SpriteKit.

Every turn is drafted before it resolves: you plan a move plus an action while
seeing every enemy's telegraphed move, aim, and incoming spawn — then
everything plays out at once. You know the future; the game is about
outplaying it.

## Mechanics

- **Two-slot loadout.** Carry two weapons, Soul Knight style. Each weapon sets
  your move range, damage, pierce, cooldown, and attack shape — heavier
  weapons hit harder but slow you down. Starting pairs always cover melee +
  ranged.
- **One action per turn.** Attacking, throwing, swapping weapons, picking one
  up, or firing the ultimate all spend the same action — but your drafted move
  still happens.
- **Attack patterns.** Directional weapons swing an authored tile pattern
  (rotated to 4 or, with a diagonal shape, 8 facings); bows, crossbows, and
  cannons fire traveling bolts that cross the board over turns; thrown weapons
  (grenade, poison potion) lob at any tile in range and blast a diamond —
  hitting the thrower too if they're caught in it.
- **Armor vs HP.** Armor absorbs damage first and regenerates on every second
  quiet turn; health never comes back (short of a boon).
- **Dodge.** Move 2+ tiles while taking no action and the first hit that turn
  misses. Projectiles, blasts, and hazards can't be dodged — only sidestepped.
- **The ultimate.** Ten of your own kills charge a board-wide smite (F),
  heralded by increasingly suspicious radio traffic. Kills your enemies score
  for you — friendly fire, bomber blasts, chains they set off — don't charge
  it. Overflow kills bank toward the next one.
- **Enemy archetypes.** Fighters carry random weapons and kite to firing
  range; berserkers charge through danger; swifts move one tile further;
  bombers rush in, arm, and detonate on a fuse — or on death. Friendly fire
  is always on.
- **Elite gates.** Reaching the score milestone summons the level's
  gatekeeper and freezes score and waves until it falls. Juggernauts (every
  level) summon recruits to their side each wave; the boss (every third
  level) drafts a visible intent each turn — fire both its weapons, sweep its
  cannon in a circle around itself, or summon reinforcements. Elites drop
  their weapons on death; the boss's cannon is found nowhere else. Elite
  drops never expire and survive the level change.
- **Level-ups.** Killing the gatekeeper turns the level over: the board
  regenerates harder, and you choose one of two boons (heals, damage,
  resistances, mobility, immunities — some for a few levels, some forever).
- **The board fights too.** Walls block movement and shots; explosive barrels
  chain-react in a radius-2 diamond; lingering hazards burn whoever ends a
  turn standing in them. Floor weapons appear every few turns (capped, and
  they crumble if ignored).
- **Endless waves.** Reinforcements telegraph their spawn tiles a turn ahead;
  standing on a marker blocks that spawn for 1 damage. Score +1 per turn
  survived, +10 per kill plus combo and streak bonuses, +30/+50 elite
  bounties. High score persists between runs.

## Controls

| Input | Action |
|---|---|
| Left click | Draft a move |
| Right click | Aim an attack / target a throw |
| Esc | Cancel the drafted action |
| Space / Return | Resolve the turn (GO) |
| Tab / Q | Draft a weapon swap (costs the action) |
| E | Draft a pickup of the weapon underfoot (costs the action) |
| F | Draft the ultimate once charged (costs the action) |
| 1 / 2 | Pick a boon on level-up |
| R ×2 | Restart and reroll (single R once defeated) |
| B | Boom mode: next restart replaces walls with barrels |

Hover any enemy to see its weapon, health, reload status, and exactly which
tiles its drafted attack will sweep — the boss also announces its next play.
Hover a barrel to see its blast radius, or a spawn marker to see what's
coming.

## Tuning

All the rules live in `Foretold/GameState.swift`, deliberately free of
SpriteKit: weapon stats and attack patterns, archetype odds, elite health and
summon counts, barrel damage/radius, dodge distance, spawn cadence, drop
rates, buff definitions, and scoring are constants and presets near the top
of the file. `GameScene.swift` only draws and animates.
