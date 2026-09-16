# Foretold

A turn-drafting tactics roguelite — playable in your browser, also native on macOS.
Built with SpriteKit (and OpenSpriteKit/WebGPU for the web).

Every turn is drafted before it resolves: you plan a move plus an action while
seeing every enemy's telegraphed move, aim, and incoming spawn — then
everything plays out at once. You know the future; the game is about
outplaying it.

## Play

▶ **[Play in your browser →](https://foretold.onrender.com)**

Nothing to install — it just loads. Needs a WebGPU-capable browser (a current
Chrome/Edge/Safari; Chrome recommended). The whole game runs client-side as
WebAssembly. If the page can't get a working WebGPU device it says exactly
that in the status box instead of going blank — append `?log` to the URL to
see the full console output on-page.

There's nothing to read here to start: the game has a built-in interactive
tutorial and hover tooltips for everything, so this README sticks to the
overview rather than a controls manual.

## Mechanics

- **Two-slot loadout.** Carry two weapons, Soul Knight style. Each weapon sets
  your move range, damage, pierce, cooldown, and attack shape — heavier
  weapons hit harder but slow you down. Starting pairs always cover melee +
  ranged.
- **One action per turn.** Attacking, throwing, swapping weapons, picking one
  up, or firing the ultimate all spend the same action — but your drafted move
  still happens.
- **Attack patterns.** Directional weapons swing an authored tile pattern;
  bows, crossbows, and cannons fire traveling bolts that cross the board over
  turns; thrown weapons lob at any tile in range and blast a diamond — hitting
  the thrower too if they're caught in it.
- **Armor vs HP.** Armor absorbs damage first and regenerates on quiet turns;
  health never comes back (short of a boon).
- **Dodge.** Move 2+ tiles while taking no action and the first hit that turn
  misses. Projectiles, blasts, and hazards can't be dodged — only sidestepped.
- **The ultimate.** Ten of your own kills charge a board-wide smite, heralded
  by an oracle who tries very hard to sound mystical.
- **Enemy archetypes.** Fighters kite; berserkers charge; swifts move further;
  bombers arm and detonate on a fuse or on death; shieldbearers parry head-on.
  Friendly fire is always on.
- **Elite gates.** Reaching the score milestone summons the level's gatekeeper
  and freezes score and waves until it falls. It drops weapons found nowhere
  else; elite drops never expire.
- **Level-ups.** Killing the gatekeeper regenerates the board harder and lets
  you choose one of two boons.
- **The board fights too.** Walls block movement and shots; explosive barrels
  chain-react; lingering hazards burn whoever ends a turn in them; in-flight
  shells are solid ordnance that enemies path around.
- **The roguelite part.** A fresh profile starts with Dagger, Sword, and Bow;
  the rest of the arsenal unlocks through lifetime milestones, and gatekeeper
  weapons are claimed off their corpses. Unlocks, tallies, and the high score
  persist between runs.

## How it's built

The rules are pure Swift, deliberately free of any rendering framework, so the
same logic drives both platforms:

- `GameState.swift` — the turn engine, scoring, spawn cadence, dodge/bash rules,
  level configs
- `Weapons.swift` — weapon stats, attack patterns, loot and unlock tables
- `Enemy.swift` — archetypes and elite factories · `Buffs.swift` — boons
- `Projectiles.swift` — bolts, lobs, lingering hazards · `Board.swift` — grid math
- `TurnResolution.swift` — the per-turn event record the scene animates from
- `GameInput.swift` / `KeyValueStore.swift` — platform-neutral input + persistence shims

`rendering/GameScene.swift` is the one rendering/input file, shared across both
targets via `#if canImport(SpriteKit)` (Apple's SpriteKit) vs OpenSpriteKit (web).

## Running / building

- **macOS:** open `Foretold.xcodeproj` in Xcode and run.
- **Web:** the `web/` SwiftPM package compiles the shared source to WebAssembly
  against OpenSpriteKit; `web-spike/fetch-deps.sh` pins + patches the engine.
  GitHub Actions rebuilds `web/dist` on every push and Render serves it. See
  `web/patches/UPSTREAM-ISSUES.md` for the OpenSpriteKit fixes this port needed.
