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
  heralded by an oracle who tries very hard to sound mystical. Kills your
  enemies score for you — friendly fire, their trails, chains they set off —
  don't charge it. Full is full: firing always costs the whole ten-kill climb.
- **The bash.** A reloading ranged weapon still jabs: right-click while it
  reloads for a 1-damage poke at an adjacent tile, without resetting the
  reload.
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
- **Endless waves.** Reinforcements are pre-rolled and telegraphed a turn
  ahead — hover the marker to see exactly what's coming. They materialize at
  the START of the turn, so a pre-aimed attack greets them (spawn camping is
  legal); standing on a marker blocks the spawn for 1 damage. Score +1 per
  turn survived, +10 per kill plus combo and streak bonuses, +30/+50 elite
  bounties.
- **Projectiles are solid.** A shell mid-flight is ordnance: enemies path
  around it, and anything that walks into (or dashes straight through) its
  tile sets it off on contact. Crossing a lingering pool burns per tile, too.
- **The roguelite part.** A fresh profile starts with Dagger, Sword, and Bow;
  the rest of the arsenal unlocks through lifetime milestones (kills per
  weapon, barrel chains, movement, combos, streaks, dodges), while the
  gatekeepers' greataxe and cannon must be claimed off their corpses. The
  MILESTONES page tracks progress; unlocks, tallies, and the high score
  persist between runs.

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
| ` | Dev panel (the oracle pretends not to see it) |

Hover any enemy to see its weapon, health, reload status, and exactly which
tiles its drafted attack will sweep — the boss also announces its next play.
Hover a barrel to see its blast radius, or a spawn marker to see what's
coming. New players can click "i'm too lazy to read" under the instructions
for a four-step (fine, five-step) interactive tutorial.

## Tuning

The rules are pure Swift, deliberately free of SpriteKit, split by concept:

- `GameState.swift` — the turn engine, scoring, spawn cadence, dodge and
  bash rules, level configs, and the dev-mode hooks
- `Weapons.swift` — weapon stats, attack patterns, the loot table, and the
  milestone/trophy unlock tables
- `Enemy.swift` — archetypes, their odds, and the elite factories
- `Buffs.swift` — every boon
- `Projectiles.swift` — bolts, lobs, and lingering hazards
- `Board.swift` — grid math, obstacles, and weapon drops
- `TurnResolution.swift` — the per-turn event record the scene animates from

`GameScene.swift` only draws, animates, and persists meta-progress. An
`ASSET_SPEC.md` at the repo root briefs artists who can't run the game.
