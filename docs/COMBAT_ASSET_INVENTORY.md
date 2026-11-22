# Combat asset inventory (Milestone 6)

All eight sheets below were added by the project owner as generated art. Generator, account tier and terms were not provided: **commercial use unverified, not release-cleared**. Originals are untouched. Runtime copies are written by `scripts/tools/extract_combat_sprites.py` next to each source (`<folder>/processed/`) and listed in `assets/combat_manifest.json`. Extraction only removes the baked-in checkerboard and crops; nothing is repainted and no animation is invented.

| Source | Size | Contents | Background | Extracted |
|---|---|---|---|---|
| `assets/characters/chiara/basic.jpg` | 1057x992 | Chiara pose grid: idle, attack, cast, block, charge, hit | fake checkerboard | `idle, attack, cast, block, charge, hit` |
| `assets/characters/chiara/fire.jpg` | 1057x992 | Fire tier artwork T1-T4 | checkerboard | `fire_t1..t4` (cut-ins) |
| `assets/characters/chiara/arcane.jpg` | 1057x992 | Arcana tier artwork T1-T4 | checkerboard | `arcane_t1..t4` |
| `assets/characters/bianca/basic.jpg` | 960x1093 | Bianca poses: idle, idle side, attack, attack 2, strike, block, guard, down | checkerboard | one PNG per pose |
| `assets/characters/bianca/holy.jpg` | 960x1093 | Holy tier artwork T1-T4 (T3 summon + release) | checkerboard | `holy_t1, t2, t3_summon, t3_release, t4` |
| `assets/characters/bianca/tanking.jpg` | 960x1093 | Tanking tier artwork T1-T4 | checkerboard | `tanking_t1, t2, t3_summon, t3_release, t4` |
| `assets/enemies/tutorial/knight_generic.jpg` | 960x1093 | Hall Guard: idle, prep/attack, hit, block, crit block (no swing pose) | checkerboard | `knight_generic_*` |
| `assets/enemies/tutorial/knight_captain.jpg` | 960x1093 | Hall Captain: idle, prep, swing, hit, block, crit block | checkerboard (darker tone) | `knight_captain_*` |

## Usable states
- Characters: idle, attack, cast, block, hit, charge (Chiara). Bianca: idle, attack, cast (uses strike), block, hit (uses guard), down. Chiara "down" reuses her hit pose (no dedicated art).
- Enemies: idle, attack (generic uses the prep pose), prep, hit, block, captain swing. Defeated enemies are greyed.
- Tier artwork is used only for cut-ins at tier 2 or higher.

## Tier mapping
Explicit data in `data/combat/combat_presentation.json` (`card_tiers`); never inferred from rarity or damage. Fire: ember 1, immolate 2, fuel 2, fireball 2, wave 3, inferno 4. Holy: strike 1, smite 2, bulwark 2, judgment 4. Arcana: bolt 1, lance 2, twinbolt 2, starfall 3. Tanking: strike 1, slam 2, sweep 3. Cards not listed have no cut-in.

## Missing / quality issues
- No Chiara down pose, no generic-knight swing pose, no enemy defeat art.
- The generic knight sheet keeps a few small checker specks after flood-fill removal.
- A stale `assets/enemies/tutorial/processed/knight_generic_swing.png` from an earlier extraction attempt is unused; it could not be deleted automatically (deletion needs your approval).
- Tier art T3 summon/release pairs are shown as single cut-ins (first image only).

## Performance
Desktop only: the battlefield refreshes in place (no node churn); cut-ins free themselves. Not measured on a phone or tablet; device testing is still needed.

## Update: Chiara poses re-extracted
The dark background of `chiara/basic.jpg` is as dark as her boots and leggings, so the first flood fill erased her legs. `scripts/tools/extract_combat_sprites.py` now protects bluish and gold pixels (grown by 2 px) from the flood fill and peels leftover neutral dark texture from the edge; the cast pose box is narrower and a small enclosed background patch is cleared. Remaining flaws: a few dark specks near the cape edges, dim boots, and the right glove of the cast pose is partly lost. Combat tests check that the lowest rows of every Chiara pose stay opaque.


## Forest assets (Milestone 8)
All owner-supplied generated art, generator and terms unknown: **NOT release-cleared**. Originals untouched; copies made by `scripts/tools/extract_forest_sprites.py` and listed in `assets/forest_manifest.json`.

| Source | Size | Contents | Extracted |
|---|---|---|---|
| `assets/enemies/1_forest/{wolf,boar,bear}.jpg` | 1408x768 | labelled 3x2 pose sheets (Still, Attack Prep, Attack Swipe, Taking Hit, Blocking, Stagger) on a baked grey checkerboard | `processed/<enemy>_{idle,prep,swing,hit,block,stagger}.png` |
| `assets/enemies/1_forest/{spider,drake,troll,boss_serpent}.jpg` | 1376x768 | same layout | same |
| `assets/effects/sprites/poison/poison_attack.jpg` | 784x1168 | one poison burst on a white checkerboard (the only file in the folder) | `poison_burst.png` |
| `assets/environments/maps/1_forest.jpg` | 1360x768 | forest map picture with a gold-blue frame | used as is for the map; `assets/environments/1_forest/forest_battle.jpg` is an interior crop (no frame) used as the forest battle backdrop |

Used states: idle, attack (swing), prep, hit. The "Blocking" pictures keep checkerboard inside the shield glow, so block uses the idle picture plus the existing guard effect; "Stagger" is extracted but unused.
Quality issues: small checker remnants inside swipe arcs and a few specks on the serpent, drake and troll; some dust and debris of the hit poses was removed with the background; the wolf sheet is cut with a narrower tolerance because its grey fur matches the checkerboard. There is no dedicated forest battle background, no poison projectile and no death art.
Chiara's idle pose was re-extracted again with hand-traced leg outlines so both legs and boots are fully kept.

### Spider re-extraction
The spider's glossy highlights are neutral grey like the checkerboard, so the flood fill left see-through holes in its body. The spider now uses a narrow flood fill, peels the leftover dark squares, and restores every region enclosed by the dark body from the original art unless it looks like checkerboard (`restore_enclosed_highlights` in `scripts/tools/extract_forest_sprites.py`, needs scipy). Idle and prep are solid; the swing and hit pictures still keep checkerboard inside the slash and the debris, so the spider attacks with its prep pose and reacts to hits with its idle pose (plus the hit flash and recoil).

## Re-cut with BiRefNet (combat animation pass)
Every pose used in combat (Chiara, Bianca, both knights, the seven forest sheets) is now cut from its original sheet by `scripts/tools/recut_sprites_birefnet.py`: BiRefNet (MIT, run locally in ComfyUI) gives the mask, then tiny detached islands are dropped and the half-transparent edge takes the colour of its solid neighbour (no grey checker fringe). Output: `<sheet folder>/recut/` and `assets/recut_manifest.json`; the old `processed/` files are kept for comparison and are no longer referenced by `data/combat/combat_presentation.json`.
- Fixed by the re-cut: checkerboard squares inside slashes, dust and debris; Chiara's black leggings (no hand-traced outline needed any more); the spider's legs and highlights.
- Forest beasts: the sheet's hit and block cells have dust and a hex shield painted over the checkerboard, so combat uses the clean **stagger** pose for hits and as the wounded idle (below 30% HP), and the idle pose plus the game's blue shield outline for blocks. The serpent attacks with its prep pose (its swipe cell carries a solid dust slab).
- Attacks show the **prep** pose during the wind-up and swap to the strike pose at the lunge.
- Same licence status as the sources: generated art, **not release-cleared**.

- `knight_captain_idle_sword.png` (Hall Captain and Knight Commander idle): the idle pose with the sword from his block pose, turned to hang from his right fist and drawn behind him (`scripts/tools/add_captain_sword.py`). The original `knight_captain_idle.png` is kept.
