# Foretold — Asset Spec (for the artist who can't run it)

A brief for drawing this game sight-unseen. Pair it with a few screen
recordings from the dev and you have everything the game can tell you.

## What the game is

A turn-based tactics roguelite on a 15×15 dark checkerboard, viewed square-on
from above (no perspective). You draft a move and an attack while seeing every
enemy's telegraphed plan, then the whole turn resolves at once. Tone: grim
little arena, deadpan comedy on top — the narrator is an oracle who tries to
sound mystical and fumbles it (gold Papyrus text collapsing into plain type).
Accent palette already in use: parchment gold `#EECC73`, comms blue `#8CBFF2`,
danger red, hazard orange, elite purple.

## Global rules

- **Canvas**: square tiles. One tile = 48pt on screen; author sprites at
  **256×256 px** with the subject centered and ~10% padding — the game scales
  down. Transparent PNG.
- Everything sits ON a tile center. No drop shadows baked in (tiles are dark;
  glow/rim-light reads better than shadow).
- Tiles get tinted by game state (green = walkable, red = incoming attack,
  orange = your attack, purple = spawn telegraph). Sprites must stay readable
  on all of those — bold silhouettes, strong outlines.
- Facing: pieces never rotate for movement (they glide). Only the bolt
  projectile rotates. Sprites can be drawn facing "south"/camera.

## The cast (priority 1 — replaces colored diamonds)

All enemies are currently diamonds (rotated squares); sizes below are the
footprint relative to one tile. Silhouette differences matter more than color.

| Sprite | Size (of tile) | Current placeholder | Character |
|---|---|---|---|
| Player | 0.65 | cyan circle, white rim | the drafted hero; readable at a glance, cyan identity |
| Fighter | 0.5 | red diamond | rank-and-file with a random weapon; generic grunt |
| Berserker | 0.5 | orange diamond | melee zealot, charges through fire and shells |
| Swift | 0.45 | sky-blue diamond | lighter, faster; +1 move |
| Bomber | 0.45 | near-black diamond, orange rim | walking bomb; needs an **armed** state (currently: red rim + pulsing) — lit fuse, glow, anything that screams "leave" |
| Juggernaut | 0.7 | purple diamond | mini-boss gatekeeper; big, slow, carries a huge weapon |
| Boss | 0.85 | dark-purple diamond, thick rim | THE gatekeeper; carries a weapon **plus a cannon** — worth showing both |

States the art should survive: damage flicker (alpha dip), death
(shrink+fade), spawn (scale-in). All handled in code — single static sprite
per entity is enough, bomber needs the armed variant.

## Board & pickups (priority 2)

| Sprite | Size | Current placeholder | Notes |
|---|---|---|---|
| Wall | 1.0 (fills tile) | flat gray square | blocks movement and line shots |
| Barrel | 0.6 | orange circle, brown rim | explodes in a radius-2 diamond; chain-reacts |
| Weapon drop | 0.6 | gold ring + weapon initial | a weapon lying on the floor; see icon list below |
| Elite trophy drop | 0.68 | purple ring, thicker | same but dropped by a slain gatekeeper — should feel special |
| Spawn marker | ~0.4 | pink "!" (orange "!" for barrels) | telegraphs next turn's arrival on that tile |

### Weapon icons (12) — used on drops now, HUD/buttons later

Dagger, Sword, Hammer, Pike, Bow, Tipped Bow, Crossbow, Grenade,
Poison Potion, Greataxe, Scythe, Cannon. Simple, readable at ~24px — think
pictogram over illustration. One set, single color/white; the game tints
(gold on the floor, purple for trophies).

## Projectiles & effects (priority 3 — current placeholders work fine)

| Sprite | Current placeholder | Notes |
|---|---|---|
| Bolt / arrow | steel sliver 0.45×0.12, rotates to flight direction | used by bow/crossbow shots |
| Cannonball | same sliver (wants its own ball sprite) | slow, menacing, bursts on impact |
| Lobbed shell | dark bead 0.28 | grenade/potion in flight, arcs between tiles |
| Hazard tile | orange-tinted tile | poison/fire pool; could become an overlay texture |
| Blast flash | orange tile flash | could become a one-shot burst sprite |

## What NOT to draw (procedural, staying that way for now)

Tile highlights, plan arrows, HP/armor pips, bars, text, the ultimate
shockwave ring, dodge ghost, UI panels.

## For the dev to record for the artist

1. One full turn: draft move + attack, hit GO (shows the resolve rhythm).
2. A bomber arming and detonating.
3. A gatekeeper fight and its trophy drop.
4. The ultimate (oracle text + shockwave).
That's the whole visual language in ~90 seconds of video.

## Integration promise

Each placeholder is one `SKShapeNode` construction in `GameScene.swift`
(`setUpPlayer`, `addEnemyNode`, `addObstacleNode`, `updateWeaponDropNodes`,
`makeBoltSliver`, `updateProjectileNodes`). Swapping any of them for an
`SKSpriteNode(texture:)` at the same size is a few lines — art can land one
sprite at a time, in any order.
