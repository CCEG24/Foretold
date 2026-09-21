# Foretold — Asset Spec (for the artist who can't run it)

A brief for drawing this game sight-unseen. Pair it with a few screen
recordings from the dev and you have everything the game can tell you.

**Weapons are first.** The rig that holds them is already in the game
(`Foretold/rendering/ActorSprites.swift`). Drop a PNG in with the right name
and it appears in three places at once: in the hand, on the floor as loot, and
on the HUD button. A weapon with no art yet is simply not drawn — nothing
stands in for it.

## What the game is

A turn-based tactics roguelite on a 15×15 dark checkerboard, viewed square-on
from above (no perspective). You draft a move and an attack while seeing every
enemy's telegraphed plan, then the whole turn resolves at once. Tone: grim
little arena, deadpan comedy on top — the narrator is an oracle who tries to
sound mystical and fumbles it (gold Papyrus text collapsing into plain type).
Accent palette already in use: parchment gold `#EECC73`, comms blue `#8CBFF2`,
danger red, hazard orange, elite purple.

## Global rules

- **Canvas**: square, transparent PNG, **256×256 px = exactly one board tile**
  (a tile is 48pt on screen, so there's plenty of headroom). Everything is
  drawn at its true size *within* that canvas — a 0.5-tile enemy fills half of
  it. Don't scale subjects to fill the frame; the canvas is the ruler.
- Subject centered on the canvas unless a table below says otherwise.
- Everything sits ON a tile center. No drop shadows baked in (tiles are dark;
  glow/rim-light reads better than shadow).
- Tiles get tinted by game state (green = walkable, red = incoming attack,
  orange = your attack, purple = spawn telegraph). Sprites must stay readable
  on all of those — bold silhouettes, strong outlines.
- Nothing rotates. Bodies change pose, weapons mirror left/right, and that's
  the whole transform vocabulary (the one exception is the flying bolt).

## Facing: three poses, mirrored

Every body — the player and all ten enemies — is three drawings:

| Suffix | When it's used | What it shows |
|---|---|---|
| `-front` | moving or aiming **down** the screen; also the resting pose | the face |
| `-back` | moving or aiming **up** | back of the head |
| `-side` | left, right, and all four diagonals | profile, **drawn facing right** |

The game mirrors `-side` for leftward facing, so there is no left-facing art to
keep in sync. Draw the profile facing right.

Straight up and down carry no left/right information, so the front and back
poses keep whichever way the actor was already mirrored — someone who was
facing left and then walks up keeps their weapon hand on the same side. Draw
`-front` and `-back` so they read either way round.

## Held weapons: the rig

**Bodies are drawn empty-handed.** The weapon is a separate sprite the game
pins into the hand every frame.

- The hand sits at **40% of the body's own width out to the right, just below
  the middle** — so for a 0.5-tile fighter that's +20% of a tile (~51px right,
  ~8px down on the 256 canvas), and for the 0.85-tile boss it's +34%. It rides
  out with the body rather than staying put, so a big elite doesn't hold its
  weapon inside its own chest. Same place in all three poses; in `-front` and
  `-back` that's the figure's near hand held slightly out from the body.
- Bigger bodies are also drawn holding **bigger weapons** — the weapon sprite
  scales by the square root of the body's size, so the boss's is ×1.3 and a
  swift's is ×0.95 against a fighter's. Draw each weapon once, at fighter
  scale; the game handles the rest.
- Weapon art is authored **pointing right**, centered on its canvas, and is
  mirrored (never rotated) when the wielder faces left.
- The game grips it a little left of center — so keep the handle/butt in the
  **left third** of the canvas and the business end in the right. How far left
  depends on the weapon:

  | Family | Grip, from canvas center | Draw so that… |
  |---|---|---|
  | swung hafts (dagger → pike) | 14–22% of a tile left | the butt of the haft sits there |
  | bows | 6% left | the limb's middle sits there |
  | crossbows, cannon, grapple | 10% left | the stock/trigger sits there |
  | thrown flasks (grenade, potion, keg, vortex) | dead center | it sits in the palm |

  Per-weapon nudges are a one-line code tweak (`Art.gripOverrides`), not a
  redraw.
- Keep a held weapon within ~0.7 of the canvas width. A pike reaches three
  tiles in the rules; the object in the hand still has to read at 48pt.
- Facing up (`-back`), the weapon is drawn behind the body automatically.

## Weapons (priority 1) — 22 sprites

One sprite per weapon, used in all three places: held in the hand (~0.5 tile),
lying inside the gold pickup ring on the floor (~0.52 tile, canted), and as the
icon on the HUD's weapon button (34pt). Readable-at-small is the constraint —
think bold prop, not illustration. File name is `weapon-<slug>`.

**Optional second state.** Any weapon may add `weapon-<slug>-cooldown`: the
art shown while the attack is reloading — a bow with the arrow loosed, a
crossbow mid-crank, a flask already thrown. The game picks it in the hand and
on the HUD button whenever that weapon can't swing this turn, and falls back
to the ready art for weapons that never draw one. Floor loot always shows the
ready art. Only weapons with a cooldown benefit: Bow, Tipped Bow, Serrated
Bow, Concussion Bow, Crossbow, Explosive Crossbow, Cannon, Hammer, Greataxe,
Grenade, Poison Potion, Trident, Maul, Grapple, Keg, Vortex.

Order matters: the first three are what every new run starts with, so they're
in front of the player constantly.

| # | Weapon | File | Character |
|---|---|---|---|
| 1 | Dagger | `weapon-dagger` | fast, 1 tile, 3 move — the darting starter |
| 2 | Sword | `weapon-sword` | the default; a 3-tile arc two tiles out |
| 3 | Bow | `weapon-bow` | fires a traveling arrow down a full row |
| 4 | Hammer | `weapon-hammer` | heavy; smashes all 8 around it, stuns |
| 5 | Pike | `weapon-pike` | a 3-tile thrust; long haft |
| 6 | Greataxe | `weapon-greataxe` | elite trophy; huge radius-2 sweep |
| 7 | Grenade | `weapon-grenade` | lobbed, one turn in the air, leaves fire |
| 8 | Crossbow | `weapon-crossbow` | slower, harder, pierces |
| 9 | Scythe | `weapon-scythe` | strikes a ring two tiles out — blind up close |
| 10 | Maul | `weapon-maul` | frontal crush that flings bodies two tiles |
| 11 | Trident | `weapon-trident` | three prongs, three lanes |
| 12 | Poison Potion | `weapon-poison-potion` | lobbed flask; leaves a big lingering pool |
| 13 | Tipped Bow | `weapon-tipped-bow` | bow whose arrows leave burning ground |
| 14 | Serrated Bow | `weapon-serrated-bow` | bow that leaves a bleed on survivors |
| 15 | Concussion Bow | `weapon-concussion-bow` | blunt-tipped; stuns at range |
| 16 | Explosive Crossbow | `weapon-explosive-crossbow` | bolts that burst on impact |
| 17 | Cannon | `weapon-cannon` | **boss-only** trophy; slow, huge, bursts |
| 18 | Ram | `weapon-ram` | barely scratches, shoves 3 tiles — a tool, not a blade |
| 19 | Grapple | `weapon-grapple` | hooked line; reels enemies in or you across |
| 20 | Slipstep | `weapon-slipstep` | an escape hatch, not a weapon: 7 tiles of blink |
| 21 | Keg | `weapon-keg` | lobs a live barrel onto a tile; no damage |
| 22 | Vortex | `weapon-vortex` | lobbed eye that drags everything one tile inward |

Two dev-only toys (Wrath of God, Yeet) never need art.

## The cast (priority 2) — 11 bodies × 3 poses

All enemies are currently colored diamonds. Size is the footprint within the
256 canvas; silhouette differences matter more than color. Files are
`player-front` / `player-back` / `player-side`, `enemy-fighter-front`, and so
on. A set can land one pose at a time — a missing pose falls back to whichever
of the three has been drawn (preferring `-front`, then `-side`), and a body with
no art at all falls back to the diamond. So the first pose you deliver shows for
every facing; the rest sharpen it.

| File prefix | Size (of tile) | Current placeholder | Character |
|---|---|---|---|
| `player` | 0.65 | cyan circle, white rim | the drafted hero; cyan identity, reads at a glance |
| `enemy-fighter` | 0.5 | red diamond | rank-and-file with a random weapon; generic grunt |
| `enemy-berserker` | 0.5 | orange diamond | melee zealot; charges through fire and shells |
| `enemy-swift` | 0.45 | sky-blue diamond | lighter, faster; +1 move |
| `enemy-shieldbearer` | 0.55 | slate diamond, pale rim | parries the first head-on swing; flank it |
| `enemy-reaver` | 0.5 | dark-red diamond, gold rim | rare; every hit bites through your armor |
| `enemy-bomber` | 0.45 | near-black diamond, orange rim | walking bomb, closes to detonate |
| `enemy-bomber-armed` | 0.45 | red rim + pulsing | **separate set**: fuse lit, about to blow — should scream "leave" |
| `enemy-juggernaut` | 0.7 | purple diamond | gatekeeper; big, slow, huge weapon |
| `enemy-summoner` | 0.75 | teal diamond | gatekeeper; frail caster that floods the board |
| `enemy-bombardier` | 0.75 | slate + amber diamond | gatekeeper; explosives handler, rains barrels |
| `enemy-boss` | 0.85 | dark-purple diamond, thick rim | THE gatekeeper; carries **two** weapons |

Notes for the cast:

- Enemies hold their weapon through the same rig, so the same hand rule
  applies to every body. The boss's second weapon goes in the off hand, drawn
  behind the body.
- The shieldbearer gets a steel plank drawn in code on the side its parry
  covers, so its shield can be modest in the art — the telegraph is procedural.
- States the art must survive, all handled in code: damage flicker (alpha dip
  and a color wash), death (shrink + fade), spawn (scale-in), stun (orbiting
  stars above the head). One static drawing per pose is enough.

## Board & pickups (priority 3)

| Sprite | Size | Current placeholder | Notes |
|---|---|---|---|
| Wall | 1.0 (fills tile) | flat gray square | blocks movement and line shots |
| Barrel | 0.6 | orange circle, brown rim | explodes in a radius-2 diamond; chain-reacts |
| Spikes | 0.6 | steel blades / flush holes | trap that toggles on and off each turn — two states |
| Teleporter | 0.6 | blue ring | warps whoever ends a turn on it |
| Spawn marker | ~0.4 | pink "!" (orange for barrels) | telegraphs next turn's arrival on that tile |

The pickup ring itself (gold, purple for elite trophies) stays procedural — the
weapon sprite sits inside it.

## Projectiles (priority 3) — ammo in flight

Same 256×256 canvas as everything else. **Arrows are the one thing that
rotates**: draw them pointing right, like weapons, and the game turns them to
their line of flight (all eight directions, plus a twist at each portal). A
lobbed shell tumbles instead, so it's drawn as it lies and never rotated.

| File | Used by | Current placeholder |
|---|---|---|
| `projectile-arrow` | every plain shot — Bow, Crossbow, Grapple line | steel sliver 0.45×0.12 |
| `projectile-shell` | Grenade, Poison Potion, Keg, Vortex mid-arc | dark bead 0.28 |

Those two cover everything. Four optional specialisations, each falling back
to `projectile-arrow` if it's never drawn:

| File | Used by | What it says |
|---|---|---|
| `projectile-arrow-fire` | Tipped Bow | leaves burning ground behind it |
| `projectile-arrow-barbed` | Serrated Bow | leaves a bleed on whoever it hits |
| `projectile-arrow-blunt` | Concussion Bow | dazes on impact |
| `projectile-cannonball` | Cannon, Explosive Crossbow | slow, menacing, bursts where it stops |

## Effects (priority 4 — current placeholders work fine)

| Sprite | Current placeholder | Notes |
|---|---|---|
| Hazard tile | orange-tinted tile | poison/fire pool; could become an overlay texture |
| Blast flash | orange tile flash | could become a one-shot burst sprite |

## What NOT to draw (procedural, staying that way)

Tile highlights, plan arrows, the shieldbearer's telegraph plank, stun stars,
HP/armor pips, bars, text, the ultimate shockwave ring, dodge ghost, UI panels.

## Delivery

Transparent PNG, 256×256, one file per name in the tables above (lower-case,
hyphenated, no extension in the name — `weapon-poison-potion.png`). They go
into `Foretold/Assets.xcassets` as image sets named exactly that; the game
looks each one up by name and silently keeps its placeholder until the file
exists, so any subset is shippable.

The numbers above aren't guesses — the rig was checked against a throwaway
calibration set (marker dots on the hand and the grip, a chevron for facing)
and the hand, grip and footprint figures are what came out of it. The first
real sprite can be dropped straight in against them.

## For the dev

- Rig and lookups: `Foretold/rendering/ActorSprites.swift` (`Art`, `ActorNode`).
  Hand offsets, grip formula and per-weapon overrides all live there.
  `Art.spritesEnabled = false` forces placeholders for an A/B.
- Board wiring: `setUpPlayer`, `addEnemyNode`, `refreshActorSprites`,
  `updateWeaponDropNodes`, `updateWeaponButtonIcon` in `GameScene.swift`.
- Removing art needs a clean build. Deleting an image set out of the
  synchronized asset folder doesn't invalidate the compiled `Assets.car`, so
  the old sprite keeps loading until `actool` is forced to re-run. Adding art
  is fine.
- **Web build**: OpenSpriteKit has no asset catalog, so the WASM target still
  needs a boot step that fetches the PNGs and hands them to
  `Art.register(_:named:)` before the scene is built (needs an `OpenFoundation`
  dependency for its `Data` type). Until then the web build draws placeholders
  — correct, just unstyled.

## For the dev to record for the artist

1. One full turn: draft move + attack, hit GO (shows the resolve rhythm).
2. A bomber arming and detonating.
3. A gatekeeper fight and its trophy drop.
4. The ultimate (oracle text + shockwave).

That's the whole visual language in ~90 seconds of video.
