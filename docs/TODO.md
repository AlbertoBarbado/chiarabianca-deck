# TODO

## Done in milestone 1 (first playable)
Foundation, navigation flow, characters + specialization selection, individual decks + shared party deck, combat (cards, intents, taunt, potions), tutorial map, rest / merchant / event rooms, exit screen.

## Done in milestone 2 (progression)
Card rewards (3 owner-tagged options, take or skip), card upgrades at rest sites with before/after preview, save/load with validation and Continue, autosave on the map. Tests: `tests/run_tests.gd` (65 checks), `tests/progression/run_progression_tests.gd` (49 checks), `tests/ui_smoke_test.tscn` UI walkthrough.

## Done in milestone 3 (Fire and Holy)
Chiara Fire + Bianca Holy (starters, 6-card pools, passives), data-driven statuses with Burn, passive runner, damage modifiers (bonus vs status, scale with Block), combat UI for Burn/passives, tests: `tests/specializations/run_specialization_tests.gd` (152 checks). Existing assertions changed only where content legitimately changed: card total 20 -> 38, "Fire is a template" -> Earth, and the UI test's "unplayable" pair is now Earth + Commander.

## Done in milestone 4 (art integration)
Central art catalog (`data/art/art_catalog.json`, `AssetCatalog`), reusable `CardView` (art, cost gem, owner, rarity, upgrade badge, scale factor), `PortraitView` (face/figure with specialization accent + badge), `RoomBackdrop` per map room, catalog icons (health, block, energy, burn, gold, potion, rest/merchant/event/combat/exit, specialization badges), enemy tokens + intent icons, floating damage/heal/block numbers, coloured victory/defeat panel. Tests: `tests/art/run_art_tests.gd` (28 checks); the three logic suites and the UI walkthrough are unchanged and pass (also at 844x390, 1024x768, 2560x1080).
**All art is provisional**: every asset is a crop of the two AI-generated concept boards (rights unverified) and is flagged `release_cleared: false`. See `docs/ASSET_LICENSES.md` for the inventory and the production art still needed.

## Current open items (reviewed 2026-11-21)
The milestone sections below keep their history; this list is what is still open today.

**Release blockers**
- No art or audio is cleared for commercial release. `tests/art/check_release_art.gd` now reads every source (catalog, all sprite manifests, every ComfyUI `generation_log.json`) and lists 612 blockers. See `docs/ASSET_LICENSES.md`.
- No audio at all.
- No export presets yet (include `*.json` in the export filter). Not tested on a phone or tablet; touch is covered only by mouse emulation. Portrait orientation is unsupported.

**Content**
- Four specializations are design templates: Earth and Lightning (Chiara), Retribution and Commander (Bianca).
- Skill trees: every specialization has an empty `skill_tree` (no nodes, no screen).
- Gear (done 2026-11-21): every slot has items, 31 of them with in-battle effects tied to a specialization or to the twins (CHARACTER_SYSTEM.md, "Gear for every slot"). Open: no item yet changes rest sites, shops or events (out-of-combat effects), and the bot equips the first item that fits rather than the best one.
- Relics (done 2026-11-21): 23 relics including 4 boss relics; elites leave one, bosses offer a choice of 3, chests roll one. Next steps are in docs/FUN_REVIEW.md (audio, bigger card pools with keywords, Weak/Vulnerable/Strength, potions, unlocks and Ascension).
- Wind has no pose set of its own; Venom Bianca reuses the Ashveil set.
- Generated monsters have one picture each (motion carries the animation).
- Card pools (done 2026-11-22): 72 new cards, 18-21 per specialization, with Powers, Retain and X cost; every card now has its own art (111 new ComfyUI pictures). Bianca's figures on the character and equipment screens were redrawn at twice the resolution (`scripts/tools/comfy_upscale.py`).

**Systems**
- Combat is a checkpoint save: quitting inside a fight restarts it.
- No seeded runs, run history, volume settings or localisation (see `TODO_ROADMAP.txt`, phase A).

**Balance**
- The bot never plans a turn ahead (Oil then Fire, Poison then detonate, build Aether then spend it), so combos are likely stronger for a person.
- Six-enemy fights are crowded at 1280x720.
- Difficulty pass done (2026-11-21): elite and boss scaling in run_rules `difficulty`, plus Shield Strike, Momentum Bash and Gust buffs. Every pairing simulates at 52-82% (average 70%; BALANCE.md). Tanking pairings remain the hardest.
- Venom tuned (2026-11-21; BALANCE.md, "Venom tuning"). Open: Frost + Venom still finds the Knight Commander a little too easy in the per-fight simulation (68% HP left against 74% in the regular final fight).
- The full-run simulation's 85% cap check can fail on noise at 60 runs (Fire + Ashveil: 87% at 60 runs, 79% at 200).

**Housekeeping**
- Unused files: `assets/environments/maps/royal_castle_map.png` and `assets/enemies/tutorial/processed/knight_generic_swing.png` (kept until the owner confirms deletion).
- `tests/vfx_gallery_test.tscn` fails intermittently when frames render slowly.

**Done in this review**
- Release gate reads every art source (above).
- Relics: a "Relics (N)" button on the map opens `RelicViewer` (`scripts/ui/components/relic_viewer.gd`) with each relic's effect.
- Damage preview: cards in hand show the damage they would really deal (`CardEffects.damage_preview`): Aether, Momentum, Block scaling, the owner's weapon bonus and Sandblind; the selected card also shows the enemy under the pointer (statuses, weaknesses, resistances), and with one enemy left every card does. Raised numbers are cyan, lowered ones red (`CardTextFormat`). Test: `tests/cards/run_damage_preview_tests.gd`.
- The simulation bot values Block by the attacks really aimed at its receiver and taunts the hardest attack aimed at the other princess (`tests/combat/sim_policy.gd`). See BALANCE.md.
- Stale entries checked and closed: all eight built specializations have passives; elites, treasure, card removal, shop cards and upgrades, delete-save and the pile viewer exist; coast shops sell equipment; gold now has uses (150-330 unspent at the end of a run).

## Done in milestone 4B (combat VFX)
58 transparent sprites extracted from the two effect atlases (`docs/EFFECTS_INVENTORY.md`), a data-driven `combat_vfx.json` (effects + event rules), `CombatVfx` scene/script, `CombatVfxManager` layer and `VfxCatalog`. `CombatManager.visual_event` is emitted after each gameplay effect, Burn tick and potion has resolved. Quality setting (Full / Reduced / Off) in Settings. Tests: `tests/combat/run_vfx_tests.gd` (56 checks), `tests/vfx_gallery_test.tscn` (plays 19 real cards, screenshots, cleanup). All earlier suites unchanged and passing.

Effects still needing dedicated artwork or work:
- All 58 sprites are provisional and uncleared (see `docs/ASSET_LICENSES.md`). They are single still images animated by code; real frame animations, enemy attack/hit effects and a dedicated Taunt-on-player effect do not exist.
- Enemy attacks and defends now show a slash (Wind Slash sprite) and a barrier, but these reuse sprites made for other purposes; dedicated enemy hit/guard artwork is still needed.
- Draw and Energy gain only have visuals for Arcana (Mana Surge); Fire/Tanking draws are silent by design.
- Frost, Wind, Lightning, Earth and Poison sprites are mapped by rule but no playable card uses them yet; Haste, Invisibility, Shadow Strike, Control, Time Warp, Meteor, Regrowth, Nature's Embrace, Fortify, Entangling Vines and others are extracted but unused.
- Divine Light / Judgment beam tops are flat, Meteor Shower is cut at the bottom, Invisibility and Shadow Strike lose their dark parts (see inventory notes).
- Mobile performance was not measured on a device (desktop: about 9 ms per frame with up to 4 simultaneous effects). Passive triggers (Kindled Spark, Blessed Aegis) have no dedicated effect yet.

## Done in milestone 4C (illustrated castle map)
The Royal Castle map now uses `assets/environments/maps/royal_castle_map.png`, shown whole (aspect-preserved, centred, never cropped). Node positions, room areas, corridor waypoints and label sides are presentation data in `data/art/art_catalog.json` ("maps"), separate from `data/maps/royal_castle_tutorial.json`, which is unchanged. Tests: `tests/map/run_map_view_tests.gd` (37 checks; run windowed for real mouse and touch input).
- Known: the map image is unverified generated art (see `docs/ASSET_LICENSES.md`). Paths overlap each other on the shared top corridor and some run across open rooms rather than strictly along corridors. Start marker shows both faces (concept-board crops). Wide windows letterbox the castle with dark side bars. No zoom or scrolling (not needed at the tested sizes).

## Milestone 4C update
The map uses `royal_castle_background.png` with `data/maps/royal_castle_layout.json` (see MAP_SYSTEM.md). Tests: `tests/map/run_map_view_tests.gd` (67 windowed / 66 headless), screenshots via `tests/map_screenshots_test.tscn`. Open: background rights unverified; start marker uses concept-board face crops; unused file `royal_castle_map.png`.

## Done in milestone 5 (premium UI redesign)
Textured theme (`UITheme`: ornate nine-patch buttons and panels, Cinzel display font), `UIAssets` loader, reusable components in `scripts/ui/components/` (`UIButton`, `MenuBackground`, `SectionHeading`, `GoldDisplay`, `AvatarFrame`, `CharacterStatusPanel`, `CharacterShowcase`), redesigned title screen, character selection, specialization selection, party overview, settings and Tutorial Complete screen. Tests: `tests/ui/menu_ui_test.tscn` (104 checks, run windowed). `scripts/tools/extract_ui_assets.py` regenerates the processed art from `assets/ui/general/`.
Open: all generated UI art is unverified (release blockers); the grey disabled button and glow hover button, corner pieces and wide panels are not extracted; the Bianca image is a figure plus a bust with cut edges (faded in code); gameplay screens (map, combat, rest, merchant, rewards) keep the previous flat styling and could adopt the ornate panels later; the fade-in and drift animations are skipped when combat effects quality is Off.

## Done in milestone 6 (combat battlefield redesign)
Enemies left, party right, header with turn/phase/intent, centred VFX, overlapping hand with hover/touch selection, energy dock and End Turn. Code: `scripts/ui/combat/` (`CombatBattlefield`, `CombatUnitView` + enemy/character views, `CombatHand`, `CombatAnimationController`), `scripts/combat/combat_presentation.gd`, data `data/combat/combat_presentation.json`, art notes `docs/COMBAT_ASSET_INVENTORY.md`. Tests: `tests/combat/combat_presentation_test.tscn` (154 checks, run windowed). Presentation never changes or delays combat rules.
Open: generated art is unverified (release blockers; the release gate does not yet read `assets/combat_manifest.json`); stale unused `knight_generic_swing.png`; generic knight keeps small checker specks; info holders are flat gold-bordered boxes, not ornate frames; device performance untested.


## Done in milestone 7 (core combat and run progression)
Arcana (Arcane Flow) and Tanking (Bulwark Stance) passives, balance pass 1 (`docs/BALANCE.md`, simulation `tests/combat/balance_simulation.gd`), rest-site card removal, elite encounters (2 examples), treasure rooms with a minimal relic foundation (3 relics), save reliability (room state, reward phase, backup, delete save), Final-Fantasy style battlefield backdrop. Tests: `tests/progression/run_milestone7_tests.gd` (78 logic checks, headless), `tests/progression/milestone7_flow_test.tscn` (42 flow checks through the real screens), `tests/combat/balance_simulation.gd` (25 checks).
Open / limitations:
- Combat is a checkpoint, not a mid-fight save: quitting inside a fight restarts it from the room entry.
- Merchant purchases persist (limited stock stays sold out) but the merchant UI itself was not given a dedicated test beyond logic.
- Relics: only three effect types; no relic UI on the map or party screen yet (they are listed in the treasure choice only).
- Elite art reuses the knight and captain sprites with a gold tint (no new artwork). Elite and treasure icons reuse the star and chest of the Milestone 5 sheet (not release-cleared).
- The demo route has no illustrated map layout and the Royal Castle tutorial contains no elite or treasure rooms.
- Balance is a first pass; a greedy simulation does not use Taunt or combo play.
- Physical device testing is still pending.


## Done in milestone 8 (Enchanted Forest, map markers, polish)
Second act: 21-node Enchanted Forest map with towns, 11 events in two pools, 2 treasures, 8 normal encounters, 3 elites and the Forest Serpent boss; Poison status; castle-to-forest act transition; multi-map saves; medallion map markers and dotted routes on both maps; combat polish (shadows, breathing, lunges, recoils, Chiara's legs, compact potion buttons, ornate intent icons).
Tests: `tests/progression/run_forest_tests.gd` (116 logic checks), `tests/progression/forest_flow_test.tscn` (71 flow checks through the real screens), simulation extended to the forest (33 checks).
Open / limitations:
- All forest art is unverified generated art (release blockers). The release gate still does not read `assets/forest_manifest.json` or `assets/combat_manifest.json`.
- Forest sprites keep small checkerboard remnants (swipe arcs, a few specks); block uses the idle picture; no death art; the forest battle backdrop is a crop of the map picture.
- Only one poison sprite exists: it is used for poison attacks, application and ticks (smaller). No poison projectile.
- Map scrolling is not implemented because the forest map fits all supported landscape sizes whole.
- Start node faces are a little large for the smaller forest medallion.
- Combat is still a checkpoint save (a reload restarts the current fight, including the boss).
- Relics still have no dedicated screen; the run-end screen lists them.
- Balance of the forest is a first pass based on the greedy simulation; real runs arrive wounded.
- `tests/vfx_gallery_test.tscn` is timing sensitive: it fails intermittently when the machine renders slowly (about 220 ms per frame in the failing runs) and passes otherwise.
- Physical device testing is still pending.

## Milestone 8 follow-up (QA feedback round)
Forest battles use `assets/environments/1_forest/forest_battle_background.png`; monsters are sized by a height factor relative to a standing human (wolf 0.6, boar 0.66, spider 0.58, bear 0.95, drake 0.85, troll 1.12; elites and the boss larger). Spider and drake sprites re-extracted (two-tone checker detection + dark-square peeling). The Forest is now a 47-room, 11-stage act on a 3.4-screen chart that scrolls over the picture (mouse wheel, drag, touch; it opens on the party). New content for the longer act: 8 encounters, the Elder Drake elite, 2 towns, 2 treasures. Status counters (icon + remaining stacks) float over every unit with a tint and pop on change; turn banners, screen shake on heavy hits, popping damage numbers. Event, treasure and town choices are ornate choice cards with emblems (`scripts/ui/components/choice_card.gd`).
The full roadmap to a Slay the Spire 2 quality game is in `TODO_ROADMAP.txt` (project root).

## QA round after Milestone 8
- Battlefield: each sprite hugs its picture and stands on the floor of its slot (no floating animals); 22 px between units; a smaller (88%), slightly raised and half-slot-shifted back row for 4-6 enemies; enemies keep a clear distance from the party; intent badges and status chips are drawn above every sprite; life bars are at most 168 px wide.
- The party shows remaining Block as a silver shield chip over the sprite (enemies show it next to their life bar).
- Elites and bosses open with a full-screen cinematic (darkened scene, coloured glow, the foe's portrait, kicker line, ornate title, story text; click to skip; skipped when effects are Off) instead of the small blue box.
- Epic cards: a new rarity (violet) with 2 cards per playable specialization (`data/cards/epic_cards.json`, `epic_pool` in the specializations). They are offered only by a map's final fight: the Forest Serpent and the Castle's Throne Hall Guards give a choice of 3 epic cards. Normal rewards never offer them.
- Open: 6-enemy fights are still crowded at 1280x720 (two staggered rows). (Epic cards have their own art since 2026-11-22.)

## Status rework and the Crystal Hollow demo (ComfyUI)
- Burn / Poison / Bleed now follow distinct rules (see COMBAT_SYSTEM.md): Burn 3 per tick, at most 4 turns; Poison = stacks, unlimited, -1 per tick; Bleed (new) = extra HP loss on every attack that costs HP, consumed by hits, never fades. Each has its own icon and colour on the status chips and on enemy intents.
- Crystal Hollow demo (main menu: "Crystal Cave"): 12 rooms on a map picture, battle background, 5 monsters, a boss and the Bleed icon, all generated locally with ComfyUI (`scripts/tools/comfy_generate.py`, FLUX.1 schnell GGUF + BiRefNet cut-outs; prompts and seeds in `assets/generated/demo/generation_log.json`). Test: `tests/progression/demo_area_test.tscn`.
- Open: generated monsters have a single pose (attacks and hits use motion and flashes only); demo events reuse the forest event pool; ComfyUI needs about 2 minutes per image on this laptop and crashed once on a 1536x864 image (sizes are now 1152x648 max); drive C: is nearly full.

## Combat animation and sprite pass
- All combat poses re-cut with BiRefNet (clean edges, no checker leftovers); see COMBAT_ASSET_INVENTORY.md.
- Sprite shader (`resources/shaders/combat_sprite.gdshader`): hit flash, backdrop rim light and ambient colour (`lighting` in combat_presentation.json), grey when fallen, ember dissolve on death. Outline layer (`combat_outline.gdshader`): pulsing gold outline on valid targets (replaces the rectangle), white on hover, blue on block, accent on spells.
- Motion profiles per creature (`motion_profiles` / `motion` in combat_presentation.json): stand, caster, beast (pounce arc), heavy (slow wind-up, screen shake on impact), hover (bob with shrinking shadow), slither (rocking). Attacks: wind-up squash, lunge with afterimages, impact, recover. Hits: hit-stop, white flash, knockback lean and shake. Units step in at the start of a battle; badly hurt units pant.
- Poses keep the idle pixel scale and stand on the floor (wide attack poses no longer shrink or float). Non-targets darken instead of turning see-through.
- Test: `tests/combat/combat_animation_test.tscn` (81 checks over castle, forest, serpent, Crystal Hollow and wyrm fights).
- Still open: the generated demo monsters have a single picture each (motion only); no frame-by-frame animation yet.


## Damage types, Frost and equipment
- Done: damage types with weaknesses and resistances for every enemy, initiative order, Chill and Frozen, Chiara's Frost specialization (12 cards, 2 epics, passive, generated art, effects and cut-ins), equipment (chest and weapons; 14 items), loot from fights and chests, the equipment screen, saves.
- Done: the Crystal Wyrm stands on the floor. Enemy shadows are soft ellipses at the feet, plus a per-creature `sink` in combat_presentation.json.
- Tests: `tests/combat/run_elements_tests.gd` (94 checks), `tests/progression/equipment_frost_test.tscn` (windowed QA with screenshots in `screenshots/equipment_frost/`). The balance simulation now includes Frost.
- Open:
  - Helmet, amulet, gauntlets, belt, ring and boot items (the slots exist).
  - Merchants do not sell equipment yet.
  - Cards do not preview modified damage on hover.
  - The Frost cut-ins are generated approximations of Chiara.


## Act III: the Sunlit Coast
- **Done:**
  - The map (39 rooms), 8 enemies including 3 elites and the Sandstorm Elemental boss, and 16 encounters.
  - Water and earth damage types, plus Soaked, Sandblind and Quicksand.
  - 6 equipment items (with status immunity); shops that sell equipment.
  - 6 events, 3 chests and 4 towns.
  - Attack effects (water splash, sand blast, boulder, wave), the map, the battle background, all monster sprites and the status icons. All generated in the local ComfyUI.
- **Tests:** `tests/progression/run_beach_tests.gd` (headless) and `tests/progression/beach_flow_test.tscn` (windowed, screenshots in `screenshots/beach/`). The coast is also in the balance simulation.
- **Open:**
  - The coast map is split into sea rooms (middle column, fought aboard the ship) and shore rooms. Each has its own monsters. The Shark Knight was added for the sea.
  - The shore has three regular monsters: crab, rock spider and the Sand Scorpion. The scorpion is in Shell Beach, Salt Flats and Windswept Dunes.
  - Coast monsters have one picture each; their motion and effects carry the animation.
  - The party has no water or earth cards yet. Lightning and wind, the types the coast fears, belong to specializations that are not built yet.


## Terrains on every map
- **Done:**
  - Castle (courtyard and hall), forest (mountain, deep wood and falls), Crystal Hollow (chasm, grotto and ruins) and coast (sea and shore).
  - Each terrain has its own battle backdrop and monsters. Two new forest monsters: the Cliff Harpy and the Will-o'-Wisp.
  - Every backdrop's floor is measured. Wide screens crop sky instead of floor. A footing test checks every unit at three screen sizes.
  - The Shark Knight and Sand Scorpion now face the party.
  - Crystal Hollow rooms no longer show castle pictures.
- **Open:**
  - The mountain has no elite of its own besides the Alpha Wolf. The deep wood's only elite is the Broodmother.
  - The new forest monsters have one picture each.


## Ashveil and the new maps
- **Done:**
  - Bianca's Ashveil (replaces Duelist): the Oiled status, 12 cards and 2 epics, the Slick Tricks passive, card art, cut-ins, effects, an ignition effect on Fire hits, and her own pose set.
  - Illustrated castle and forest maps, with castle rooms placed on their buildings.
- **Open:**
- Ashveil Bianca uses the owner-provided pose sheet. The sheet's map-reading and pouch poses could become event or town portraits.
  - The simulation's greedy policy does not plan Oil-then-Fire turns, so the real combo may play stronger in human hands.


## Combat UI fixes and the balance pass
- **Done:**
  - Ashveil Bianca is exactly Bianca with a charcoal cloak.
  - The enemy hover panel no longer sticks and has smaller text that explains statuses. Status chips have tooltips.
  - Every card's text fits, or shows on hover.
  - Potions ask who drinks them, with a clear highlight.
  - The reward screen always fits. The pile viewer covers the battle.
  - The ship and every other backdrop stand units 7% inside the floor (bottom-anchored zoom).
  - A full-run simulation and a balance pass across specializations; see BALANCE.md.
- **Open:**
  - Gold piles up (300-600 at the end of a run): shops need more to buy (card removal, cards, upgrades).
  - Tanking with Arcana is the hardest pairing (43% for the bot).

## Every card shows an effect
- Every effect of every playable card (106 card effects) now has a specific visual; `tests/combat/run_card_vfx_audit.gd` enforces it. Details: COMBAT_SYSTEM.md, "Every card shows an effect".
- Ashveil: visible oil and smoke (cut-out sprites, normal blending), a thrown flask, a smoke veil for single Block, a smoke cloud for party Block, own slash, thrust and caltrops sprites.
- Draw, energy and heal visuals per specialization.
- Fixed: effects were drawn under front-row unit sprites, so effects inside a silhouette (energy, draw, heals) were hidden. The effect layers now use `z_index` 10.
- Played cards rise to the gap between party and enemies instead of covering the caster or target.
- New art in `assets/generated/vfx/` is not release-cleared (see ASSET_LICENSES.md).

## Party hover panel, town and merchant art
- Hovering (or tapping) Chiara or Bianca in combat shows her statuses explained, like enemies.
- Towns and merchants: every town (`data/towns`) and shop (`data/shops`) names an illustration in `"art"` (catalog ids `town_*`, `merchant_*`, files in `assets/generated/towns/`).
  - Town screen: the town's picture fills the left half (`FramedArt`) and is the backdrop of the town and its services.
  - Merchant screen: the merchant stands at the left beside the stock; a merchant outside a town (castle) also uses it as the backdrop.
  - Without the file, both screens fall back to their previous layout.
  - Generated with `python scripts/tools/comfy_generate.py --group towns`. ComfyUI on this laptop (6 GB VRAM) crashed in dynamic VRAM with the GGUF model; it runs stably when started with `--disable-dynamic-vram --lowvram --reserve-vram 0.8`.

## Equipment screen redesign
- Drawn item sockets with rarity glow and gems, engraved empty-slot glyphs, a lit stage for the character, bonus chips, a socket-grid stash with filters, and an item card that compares with what is worn.
- Drag and drop: equip on a slot, on the character or on her tab; unequip onto the stash; move rings between ring slots. Tap / click still does everything.
- Details: CHARACTER_SYSTEM.md, "Equipment".

## Arcana + Holy combo: Aether
- New combo mechanic **Aether**: Arcana's extra cards and Energy become Aether, which Holy's hymns read or release. It is a counter on `CombatManager`, with effect keys `per_aether` and `spend_aether`.
- 8 new cards (4 Arcana, 4 Holy) with generated art. Ley Siphon is in Arcana's starting deck and Hymn of Dawn in Holy's.
- UI: a violet Aether counter beside Energy, and the word Aether in violet on cards. Lightfall has its own pillar of light, and releasing Aether plays a light burst.
- Balance: full-run simulation, every pairing 48-82%, average 66%. Arcana + Holy is now the strongest Arcana pairing, and Holy is no longer the best partner for everyone (BALANCE.md).
- Tests:
  - `tests/specializations/run_aether_tests.gd` (headless, 32 checks).
  - `tests/ui/aether_ui_test.tscn` (windowed, 8 checks).
- Open: the greedy simulation bot does not plan the "build Aether, then spend it" order, so the combo is likely somewhat stronger in human hands.

## Deck viewer and portrait
- **Map:** a "Deck (N)" button beside Equipment opens `DeckViewer` (`scripts/ui/components/deck_viewer.gd`), a full-screen overlay listing the party's cards.
  - Tabs show the whole party or one princess. Copies are grouped (× N), and upgraded copies are shown apart.
  - Tap a card to see it large with its details and upgrade.
  - Close with the button, a tap outside, or Escape.
  - `DeckViewer.group_deck` is shared with the Party Overview screen.
- **Chiara's face crop** (`face_chiara_cutout`) is recentred and tighter (346, 44, 176x176). It is used on the selection screen, card medallions and chips.
- **Ley Siphon** is lowered to 5 damage (8 upgraded): it beat Arcane Bolt outright.
- **Test:** `tests/ui/deck_viewer_test.tscn` (windowed, 11 checks).

## Twin combos: Wind, Venom and reactions
- **New specializations:** Chiara's Wind (Gusts, Momentum, spreading) and Bianca's Venom (Poison, Catalyst, Blight), which replaces Vanguard. Each has 10 starting cards, 10 rewards and 2 epics, all with generated art.
- **Every Chiara x Bianca pairing has a combo:**
  - 16 entries in `data/combat/twin_combos.json`, five of them signature combos.
  - 8 twin reactions in `data/combat/reactions.json`.
  - 9 cross-combo cards added to the Tanking, Holy, Ashveil and Fire pools.
- **Engine additions:**
  - Token cards (`create_card`, `PartyDeck.add_tokens`) and Momentum (`cards_played_this_turn`, `per_card_played`).
  - The Blight execute status, plus `spread_status`, `multiply_status`, `from_target_status` and `bonus_if_any_status`.
  - Reactions (`Reactions`, `CombatManager._react`) and new passive trigger keys (`cards_played`, `target_already_had`).
- **UI:**
  - Reaction pop-ups and effects, a Momentum counter, and Gust cards in the hand.
  - Combo guide lines and a pair banner on the selection screen.
- **Balance:** full-run simulation for all 16 pairings, 43-80% wins, average 64% (BALANCE.md). Both simulations share `tests/combat/sim_policy.gd`.
- **Tests:**
  - `tests/specializations/run_twin_combo_tests.gd` (headless).
  - `tests/ui/twin_combo_ui_test.tscn` (windowed).
- **Open:**
  - Tanking pairings are the weakest in the bot's hands (43-67%).
  - Wind has no pose set of its own (Chiara uses her default poses). Venom Bianca reuses the Ashveil pose set (`character_variants.bianca.venom`).
  - The bot never plans a "build Poison, then detonate" turn.

- Card-pool expansion balance (2026-11-22): average 74% over 16 pairings (50-87%); Fire + Holy and Wind + Holy sit on the 85% cap at 150 runs, Arcana + Venom is the low end at 50%. BALANCE.md, "Card-pool expansion".

- Frostpeak (done 2026-11-22): standalone mountain adventure from the main menu. 51-room climbing map with a scrolling mountain picture and an altitude gauge, 11 new monsters, the White Dragon, 4 villages and outposts, Frostbitten, 2 armours and 26 ComfyUI pictures. Tests: `tests/progression/run_mountain_tests.gd`. Open: Holy pairings are the weakest on the climb (48-63%).

- Persistent RPG milestone (2026-11-22): castle hub, world map with 5 regions (Royal Castle, Crystal Cave, Enchanted Forest, Sunlit Coast, Frostpeak) and 9 missions (3 with the
  new clear-targets objective on generated maps), expedition lifecycle with results and discoveries,
  card collection and Deck Workshop, permanent upgrades and equipment refinement, Apothecary with brews
  and potion belt, Training Hall (hybrid specializations), Enchanter (4 fusion recipes), Sister Bond (5
  levels, 3 bond relics), world flags and region threat, save v3 with migration of old runs, Quick Play
  slot. Tests: `tests/campaign/campaign_logic_test.tscn` (headless), `tests/campaign/castle_flow_test.tscn`
  (windowed). Runner: `tests/run_all_tests.sh`. Design: `docs/PERSISTENT_RPG_DESIGN.md`.
  Open: branching upgrades, region-threat difficulty, campaign balance simulation, equipment
  sell/dismantle, NPC missions, portrait phones.
