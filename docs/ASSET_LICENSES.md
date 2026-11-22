# Asset License Register

**Status: NO asset in this project is cleared for a commercial release.** Every integrated image below is a region cropped (at runtime, through `data/art/art_catalog.json`) from two AI-generated concept boards whose commercial terms have not been verified. Each catalog entry carries `"release_cleared": false`; `AssetCatalog.release_blockers()` lists them and `tests/art/run_art_tests.gd` asserts that none is marked cleared. Do not ship a release build until each entry is replaced by cleared production art or the generation terms are verified by the project owner.

## Source files

| File | Size | Source | License / terms | Commercial-use verification | Notes |
|---|---|---|---|---|---|
| `assets_pack/visuals/voidfarer_initial_concept_board.png` (original, untouched) | 1536x1024 PNG | ChatGPT image generation | Verify applicable OpenAI terms for the account/tier used | **Pending project owner review** | Concept board with several illustrations in one image |
| `assets_pack/visuals/voidfarer_detailed_asset_board.png` (original, untouched) | 1536x1024 PNG | ChatGPT image generation | as above | **Pending project owner review** | Concept board |
| `assets/concept/*.png` | same | byte-identical copies of the two files above (checked by a test) | as above | Pending | The only files the catalog reads. The originals in `assets_pack/` were not modified |

No third-party fonts, plugins, audio or other art are used. UI text uses Godot's built-in default font.
Attribution: none required by a known license; none recorded. Date obtained: with the project pack (before Milestone 4). Restrictions: unknown until the generation terms are checked; AGENTS.md section 16.4 requires recording the platform, tier and terms.

## Integrated assets (all derived from the boards, status `concept_crop`, release cleared: NO)

Crops are rectangles of a board that are visually separated from the rest of the sheet; no board is used whole. Regions are in the catalog; none of the crops changes the pixels.

| Catalog id(s) | Source board / region (x,y,w,h) | Used for | Limitation |
|---|---|---|---|
| `face_bianca` | initial; Bianca bust panel (776,170,136,136) | Face-centred avatar crop | Small source |
| `portrait_chiara`, `portrait_bianca` | initial; separate bust panels (312,128,178,352) / (808,128,106,190, face-centred) | Face crops in combat, overview, rest, selection, victory | Face crop is the top square of the bust |
| `figure_chiara`, `figure_bianca` | initial; full-figure panels (0,20,320,435) / (497,20,278,460; centred on the body) | Main menu, character selection | Name plate cropped out; Bianca shows a partial class emblem at the top-right edge |
| `bg_royal_chambers`, `bg_resting_room`, `bg_merchant`, `bg_training`, `bg_throne`, `bg_exit` | detailed; six room thumbnails (224x151 each, captions excluded) | Room backdrops, menus | Only about 224x151 px, upscaled about 6x (soft); shown under a veil |
| `icon_energy`, `icon_heal`, `icon_holy`, `icon_arcane`, `icon_frost`, `icon_fire`, `icon_lightning` | initial; icon strip | Energy gem, potion/heal, specialization badges | About 50 px sources; frost/lightning currently unused |
| `icon_health`, `icon_block`, `icon_burn`, `icon_chilled` | detailed; status icon row (labels excluded) | HP, Block, Burn, Chilled | About 44 px sources |
| `icon_combat`, `icon_rest`, `icon_gold`, `icon_event`, `icon_exit` | initial; room-type icon row (labels excluded) | Map nodes, legend, gold counter, merchant | `icon_gold` doubles as the merchant icon |
| `art_arcane_orb`, `art_fireball`, `art_shield`, `art_holy_blade`, `art_mana_silhouette`, `art_healing_hands`, `art_aura_silhouette`, `art_frost` | detailed; illustration area of eight sample cards (122x70, frames/costs/names excluded) | Card illustrations, reused by specialization/type (`card_art` rules) | Not unique per card; `art_frost` unused |


Not integrated (still reference only): the logo, card frames, banners and the card-type frame set from the boards.

## Production art still needed
- Individual illustrations for all 38 cards (and every future card), as separate files referenced by `art_path` or a catalog `path` entry.
- Character art as separate files: a proper portrait (square), full-body and combat sprite per princess; ideally per-specialization outfit/aura variants.
- Enemy illustrations (Practice Automaton, Guard Recruit, etc.); currently initial-letter tokens.
- Full-resolution (about 1920x1080) backdrops for each room, plus distinct art for the Fountain Courtyard and Royal Library (they reuse the Castle Exit and Resting Room).
- A clean icon set (health, block, energy, burn, gold, potion, rest, merchant, event, combat, exit, specializations) at 64+ px, a logo, card frames, UI panels and fonts.
- Audio (none exists).

## Process for every new asset
Record creator, source URL, exact license, attribution, date, commercial-use status and restrictions here before integration, then add it to the catalog with `"path"` and `"release_cleared": true` only after the rights have actually been verified. This register is not legal advice.

## Release gate
Run `godot --headless --path . --script res://tests/art/check_release_art.gd` before exporting; it exits 1 while any shipped art lacks `release_cleared: true`: catalog entries, the effect, UI, combat, recut and forest sprite manifests, and every `assets/generated/*/generation_log.json` entry (612 blockers on 2026-11-21). Release builds also log a warning at startup.

## Combat effect atlases and derived sprites (Milestone 4B)

**Not cleared for a commercial release.** Same status as the concept boards: the source of both atlases is AI image generation and the applicable terms have not been verified. The project owner stated only that the files were added to the project; no license text or generation platform/tier was provided, so none is recorded here.

| File | Size | Source | License / terms | Commercial-use verification | Notes |
|---|---|---|---|---|---|
| `assets/effects/sources/combat_effects_atlas_01.png` (original, untouched) | 1672x941 PNG | AI-generated (generator and account tier not recorded) | Unknown: verify the generation platform's terms | **Pending project owner review** | 30 effects on a near-black background |
| `assets/effects/sources/combat_effects_atlas_02.png` (original, untouched) | 1672x941 PNG | AI-generated (generator and account tier not recorded) | Unknown | **Pending project owner review** | 30 effects on a dark blue background, with title and captions |
| `assets/effects/sprites/<element>/*.png` (58 files) | 120-305 px wide | Derived from the two atlases by `scripts/tools/extract_effects.py` (background removal and cropping only; no repainting) | Inherits the atlases' unknown terms | **Pending**: not cleared | Full list with source atlas and label: `docs/EFFECTS_INVENTORY.md`. `assets/effects/sprites/manifest.json` records each sprite's source region |

Attribution: none known to be required. Restrictions: unknown. `tests/art/check_release_art.gd` also lists these sprites as release blockers.


## Royal Castle map background (Milestone 4C)

**Not cleared for a commercial release.** The project owner added `assets/environments/maps/royal_castle_map.png` (1672x941 PNG, top-down castle) as generated artwork. The generator, account tier and terms were not provided, so no license is recorded and commercial use is unverified. It is shown whole and uncropped by the map screen and registered in `data/art/art_catalog.json` as `map_royal_castle` with `release_cleared: false`. It replaces the earlier crop of the concept board (`map_castle`), which is no longer used.

## Royal Castle parchment background (Milestone 4C, final)
`assets/environments/maps/royal_castle_background.png` (1672x941, parchment map with painted castle and gold-blue frame, no nodes or text) was added by the project owner as generated art. Generator and terms were not provided: **commercial use unverified, not release-cleared**. Registered as `map_royal_castle_background` in `data/art/art_catalog.json`; used through `data/maps/royal_castle_layout.json`. It replaces the earlier top-down image `royal_castle_map.png`, which is no longer referenced (the file is still in the folder and can be deleted).

## Premium UI redesign assets (Milestone 5)

**All generated artwork below is NOT cleared for commercial release.** The eight JPGs were added by the project owner as generated art; the generator, account tier and terms were not provided. Originals are kept untouched in `assets/ui/general/`. Runtime copies are produced by `scripts/tools/extract_ui_assets.py` (checkerboard removal and cropping only; no repainting) and listed with their source box in `assets/ui/manifest.json` (33 files). `tests/art/check_release_art.gd` reports them as release blockers.

| Original (assets/ui/general) | Size | Type | Background | Used for |
|---|---|---|---|---|
| `main_menu_background.jpg` | 1376x768 | complete illustration | opaque (used as is) | menu backdrop (`menu_background` in the art catalog) |
| `Game_logo.jpg` | 1376x768 | single logo | fake checkerboard baked in | `processed/logo.png` (checker removed, including letter counters) |
| `chiara.jpg` | 1057x992 | full-body character | fake checkerboard baked in | `processed/chiara_cutout.png`; glow ring tiles removed (the magic ring behind her hand is lost) |
| `bianca.jpg` | 960x1093 | figure + bust composite | fake checkerboard baked in | `processed/bianca_cutout.png`; art touches the canvas edges, so the menu fades her left, right and bottom edges |
| `Menu _buttons.jpg` | 1376x768 | asset sheet (5 buttons) | fake checkerboard | `buttons/button_ornate.png`, `button_plain.png`, `button_small_square.png`. The grey "disabled" button and the glowing "hover" button could not be extracted cleanly (neutral grey frame / glow bleed): disabled and hover looks are tints of the plain frame |
| `Decorative _panels_and _frames.jpg` | 1376x768 | asset sheet (frames, corners, divider) | fake checkerboard | `panels/panel_rect_ornate`, `panel_banner`, `frame_circle`, `frame_portrait`, `divider` (corner pieces, wide plain panel and ornate wide panel are not extracted yet) |
| `UI_icons.jpg` | 1024x1024 | asset sheet (4x4 icons) | fake checkerboard | `icons/icon_*.png` (16 icons: heart, shield, combat, gold, potion, flame, star, rune, silhouette, chest, settings, sound, music, back, check, close) |
| `main_menu_atmospheric_effects.jpg` | 1376x768 | particle sheet | fake checkerboard | `effects/fx_*.png` (6 single sprites: gold dust, sparkle, blue orb, ember, swirl, glitter) via brightness-based alpha |

Face crops of the two cutouts (`face_chiara_cutout`, `face_bianca_cutout`), the cutouts and the menu background are registered in `data/art/art_catalog.json` with `release_cleared: false`.

**Font:** Cinzel (variable weight), `resources/fonts/Cinzel.ttf`, downloaded from the Google Fonts repository (github.com/google/fonts, ofl/cinzel), licensed under the SIL Open Font License 1.1, copyright 2020 The Cinzel Project Authors. License text: `resources/fonts/Cinzel_OFL.txt`. The OFL permits commercial use, embedding and redistribution; the font may not be sold on its own. Verified from the license file shipped with the font: **cleared**. Body text keeps Godot's built-in default font. No new code dependencies.

## Combat battlefield art (Milestone 6)
Eight generated sheets added by the project owner: `assets/characters/{chiara,bianca}/{basic,...}.jpg` and `assets/enemies/tutorial/knight_{generic,captain}.jpg` (see `docs/COMBAT_ASSET_INVENTORY.md`). Generator and terms not provided: **commercial use unverified, NOT release-cleared**. Originals kept; processed PNGs in the `processed/` folders are derived by `scripts/tools/extract_combat_sprites.py` (checkerboard removal and cropping only) and listed in `assets/combat_manifest.json`.


## Combat backdrop (Milestone 7 session)
`assets/environments/0_castle/castle_generic.jpg` (1376x768): generic castle hall used as the side-view battle backdrop (`battle_castle_generic` in the art catalog). Added by the project owner as generated art; generator and terms not provided: **commercial use unverified, NOT release-cleared**. The star and chest icons used for elite and treasure nodes come from the Milestone 5 icon sheet (already listed, not release-cleared).


## Enchanted Forest assets (Milestone 8)
Added by the project owner as generated art; generator, account tier and terms not provided: **commercial use unverified, NOT release-cleared**.
- `assets/environments/maps/1_forest.jpg` (map background) and its derived crop `assets/environments/1_forest/forest_battle.jpg`.
- `assets/enemies/1_forest/{wolf,boar,bear,spider,drake,troll,boss_serpent}.jpg` and the derived pose cut-outs in `assets/enemies/1_forest/processed/`.
- `assets/effects/sprites/poison/poison_attack.jpg` and the derived `poison_burst.png`.
Derived files are produced by `scripts/tools/extract_forest_sprites.py` (background removal and cropping only) and listed in `assets/forest_manifest.json`. Catalog entries (`map_forest_background`, `battle_forest`) are marked `release_cleared: false`. No new fonts, plugins or code dependencies.

## Crystal Hollow demo art (generated locally with ComfyUI)
All files in `assets/generated/demo/` were generated on the project owner's computer with ComfyUI (`scripts/tools/comfy_generate.py`; every prompt, seed, size and model is recorded in `assets/generated/demo/generation_log.json`).
- **Image model:** FLUX.1 [schnell] by Black Forest Labs, licence **Apache 2.0** (commercial use of outputs allowed), used as the GGUF Q3_K_S quantisation by city96 (`city96/FLUX.1-schnell-gguf`, same licence). VAE: FLUX `ae.safetensors` (Apache 2.0, downloaded from the Comfy-Org repackaged mirror).
- **Text encoders:** CLIP-L (OpenAI CLIP, MIT) and T5-XXL v1.1 encoder (Google, Apache 2.0) as GGUF Q3_K_M by city96.
- **Background removal:** BiRefNet (MIT) through ComfyUI's RemoveBackground node.
- **Tools (not shipped with the game):** ComfyUI (GPL-3.0) and the ComfyUI-GGUF custom node (Apache 2.0) run only on the development machine; the GPL does not extend to generated images.
Status: the model licences permit commercial use, but generated images still need an IP review (no recognisable third-party characters or styles were prompted) before release, so the catalog marks them `release_cleared: false` until that review is done.


## Derived combat sprites (BiRefNet re-cut)
`assets/characters/*/recut/`, `assets/enemies/*/recut/`: cut from the owner-supplied sheets listed above with BiRefNet (MIT, local ComfyUI; tool not shipped). Derived files inherit the licence status of their sources: **not release-cleared** until the sheets' commercial terms are verified. Manifest: `assets/recut_manifest.json`.


## Frost specialization and equipment art (generated locally)
`assets/generated/frost/` (9 card illustrations, 3 cast cut-ins, 3 spell effects, the Chill icon) and `assets/generated/items/` (14 equipment icons) were generated on this machine with ComfyUI and FLUX.1 [schnell] (Apache 2.0) using the same models as the Crystal Hollow demo. Item icons were cut out with BiRefNet (MIT). Prompts and seeds: each folder's `generation_log.json`; generator `scripts/tools/comfy_generate.py`.
- Commercial use: the model licences allow it. **Not release-cleared** until an IP review of the outputs. The cut-ins are meant to resemble Chiara and are not exact.


## Sunlit Coast art (generated locally)
`assets/generated/beach/` (map, battle background, 8 monsters, 4 attack effects, 3 status icons) and 6 more icons in `assets/generated/items/` were generated on this machine with ComfyUI and FLUX.1 [schnell] (Apache 2.0). Sprites and icons were cut out with BiRefNet (MIT). Prompts and seeds: `generation_log.json` in each folder. **Not release-cleared** pending IP review.

- **Sea rooms (same terms):** ssets/generated/beach/battle_ship_deck.png (ship deck backdrop) and monster_shark_knight.png (Shark Knight, BiRefNet cut-out). Prompts and seeds are in the beach generation_log.json. **Not release-cleared** pending IP review.
- **Sand Scorpion (same terms):** `assets/generated/beach/monster_sand_scorpion.png` (seed 3232; seed 3231 was rejected for a doubled stinger), cut out with BiRefNet. **Not release-cleared** pending IP review.

- **Terrain art (same terms):** `assets/generated/terrain/`:
  - **Backdrops:** castle yard, forest mountain, forest deep wood, crystal chasm (seed 4131; a retry was rejected) and crystal ruins.
  - **Sprites:** Cliff Harpy and Will-o'-Wisp, cut out with BiRefNet.
  - Prompts and seeds are in its `generation_log.json`. **Not release-cleared** pending IP review.

- **Ashveil and new maps (same terms):**
  - `assets/generated/ashveil/`: 9 card arts, 3 cut-ins, 5 effects, and the Oiled and Ashveil icons.
  - Bianca's Ashveil battle poses (`assets/characters/bianca/ashveil/`) are cut from `assets/characters/bianca/ashveil_bianca.jpg`. That sheet was provided by the project owner, like her other character art, and keeps the same release status.
  - `assets/generated/maps/`: castle and forest maps.
  - Prompts, seeds and denoise values are in each folder's `generation_log.json`. **Not release-cleared** pending IP review. The restyled poses inherit the status of the source sprites.

- **Card effects (same terms):** `assets/generated/vfx/`: oil splash, flask, smoke cloud, smoke veil and caltrops (cut out with BiRefNet; the smoke veil's centre was hollowed with a radial alpha mask), ember slash, shadow stab, card draw and energy burst, plus BiRefNet cut-outs of the last two (`*_cut.png`). Generated with ComfyUI and FLUX.1 [schnell] (Apache 2.0) by `scripts/tools/comfy_generate.py` (group `vfx`, seeds 5501-5514). **Not release-cleared** pending IP review.

- **Towns, merchants and slot glyphs (same terms):**
  - `assets/generated/towns/`: 9 town scenes (`town_*`) and 7 merchant scenes (`merchant_*`), shown on the town and merchant screens and as their backdrops.
  - `assets/generated/ui/`: 8 empty-slot glyphs (`slot_*`) for the equipment screen. They were generated as white-on-black emblems; brightness was turned into alpha.
  - Generated on this machine with ComfyUI (FLUX.1 [schnell], Apache 2.0; GGUF quantisation by city96) by `scripts/tools/comfy_generate.py` (groups `towns` and `ui`).
  - Prompts and seeds are in each folder's `generation_log.json`. Pictures that came out with stray lettering (fake signatures, sign text) were regenerated with new seeds.
  - **Not release-cleared** pending IP review.

- **Aether combo (same terms):**
  - `assets/generated/aether/`: 8 card arts (Ley Siphon, Arcane Echo, Leyline Weave, Aether Lance, Hymn of Dawn, Lightfall, Radiant Cascade, Wellspring Prayer), the Aether icon (cut out with BiRefNet) and the Aether release effect.
  - Generated on this machine with ComfyUI (FLUX.1 [schnell], Apache 2.0) by `scripts/tools/comfy_generate.py` (group `aether`, seeds 6401-6425; Ley Siphon, Arcane Echo and Hymn of Dawn were regenerated with new seeds to remove fake lettering, a hexagram and a doubled sword). Prompts and seeds are in its `generation_log.json`.
  - **Not release-cleared** pending IP review.
- **Wind, Venom and twin combos (same terms):**
  - `assets/generated/wind/`: 16 Wind card arts, including the Gust token. Also the Wind emblem and the Momentum icon (both cut out with BiRefNet).
  - `assets/generated/venom/`: 15 Venom card arts, plus the Venom emblem and the Blight icon (both cut out).
  - `assets/generated/combos/`: 9 cross-combo card arts (Runic Bastion, Momentum Bash, Branding Bash, Sunfire Smite, Psalm of Wings, Hexed Powder, Flashpoint, Wildfire, Ember Volley), plus the Combustion, Miasma and Blight effects.
  - Generated on this machine with ComfyUI (FLUX.1 [schnell], Apache 2.0) by `scripts/tools/comfy_generate.py` (groups `wind`, `venom` and `combos`, seeds 6501-6903; Tempest Blades, Envenom, Corrode, Distilled Venom, Death's Ledger and Momentum Bash were regenerated with new seeds to remove fake lettering, cross-like shapes and a franchise-like star). Prompts and seeds are in each folder's `generation_log.json`.
  - **Not release-cleared** pending IP review.
- **Gear for every slot (same terms):**
  - `assets/generated/gear/`: 39 item icons (helmets, amulets, gauntlets, belts, rings, boots and two weapons), cut out with BiRefNet.
  - Generated on this machine with ComfyUI (FLUX.1 [schnell], Apache 2.0) by `scripts/tools/comfy_generate.py --group gear` (seeds 7001-7039). Prompts and seeds are in the folder's `generation_log.json`.
  - **Not release-cleared** pending IP review.
- **Hall Captain idle with sword** (`assets/enemies/tutorial/recut/knight_captain_idle_sword.png`): composed from two existing poses of the same owner-provided sheet (`knight_captain.jpg`); same terms, **not release-cleared**.
- **Relics (same terms):**
  - `assets/generated/relics/`: 23 relic icons, cut out with BiRefNet.
  - Generated on this machine with ComfyUI (FLUX.1 [schnell], Apache 2.0) by `scripts/tools/comfy_generate.py --group relics` (seeds 8001-8023). Prompts and seeds are in the folder's `generation_log.json`.
  - **Not release-cleared** pending IP review.

- **Card-pool expansion and own art for every card (same terms):**
  - `assets/generated/cards/`: 111 card arts: the 72 expansion cards and 39 older cards that used to
    share a fallback picture (Fire, Arcana, Holy and Tanking starters, pools and epics).
  - Generated on this machine with ComfyUI (FLUX.1 [schnell], Apache 2.0) by
    `scripts/tools/comfy_generate.py --group cards` (prompts in `scripts/tools/card_expansion_prompts.json`,
    seeds 9101-9211; any regenerations are listed in the folder's `generation_log.json`).
  - **Not release-cleared** pending IP review.
- **Bianca HD figures (same terms as their sources):**
  - `assets/generated/figures/bianca_paladin.png` and `bianca_ashveil.png`: FLUX image-to-image
    redraws (low denoise) at about twice the size of `assets/ui/processed/bianca_cutout.png` and of the
    Ashveil idle pose cut from the owner-provided sheet, by `scripts/tools/comfy_upscale.py`. The
    sources are unchanged. **Not release-cleared.**

- **Frostpeak (same terms):** `assets/generated/mountain/` (two map pictures, four battle backdrops,
  10 monsters, the White Dragon and the Frostbitten icon), `assets/generated/towns/` (four town scenes
  and two merchants) and `assets/generated/items/item_yetifur_mantle.png` and `item_glacier_plate.png`.
  - Generated on this machine with ComfyUI (FLUX.1 [schnell], Apache 2.0); sprites and icons were cut out
    with BiRefNet (MIT). Prompts and seeds 9401-9473 are in `scripts/tools/mountain_prompts.json` and
    each folder's `generation_log.json`.
  - The map art is inspired by ink-wash landscape maps in general. No existing map or artwork was used as
    an input image or reproduced.
  - **Not release-cleared** pending IP review.

- **Persistent campaign (2026-11-22):** no new assets. Fusion cards reuse existing card art
  (`chiara_fire_ember`, `bianca_tanking_rally`, `chiara_fire_kindle`, `bianca_holy_shield`), bond relics
  reuse relic icons, castle and world screens reuse the UI kit, map pictures and menu background.
