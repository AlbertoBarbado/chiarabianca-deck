"""Generates the art of the "Crystal Hollow" demo area with the local ComfyUI server.

Usage (project root, ComfyUI at http://127.0.0.1:8188; add --group frost|items|demo to limit a run):
    python scripts/tools/comfy_generate.py            # generate everything that is missing
    python scripts/tools/comfy_generate.py --force    # regenerate everything
    python scripts/tools/comfy_generate.py --only map_crystal_hollow

Model: FLUX.1 [schnell] (Apache 2.0) as GGUF Q3_K_S through the ComfyUI-GGUF custom node, with the
CLIP-L and T5-XXL (GGUF Q3_K_M) text encoders and the FLUX VAE. 4 sampling steps, CFG 1.
Sprites are generated on a plain background and cut out with BiRefNet (ComfyUI RemoveBackground),
so they come out as transparent PNGs. Every file is listed with its prompt and seed in
assets/generated/demo/generation_log.json so it can be regenerated exactly.
"""
import json
import os
import sys
import time
import urllib.request
import uuid

SERVER = "http://127.0.0.1:8188"  # ComfyUI listens on IPv4 only; "localhost" may resolve to ::1 first
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "generated", "demo")
MODEL = {"unet": "flux1-schnell-Q3_K_S.gguf", "clip_l": "clip_l.safetensors",
         "t5": "t5-v1_1-xxl-encoder-Q3_K_M.gguf", "vae": "ae.safetensors"}

STYLE = ("high quality hand-painted fantasy illustration, anime JRPG art style, rich colours, "
         "soft cinematic lighting, detailed")
SPRITE = ("full body, single creature, whole body visible from head to feet, side view facing right, "
          "standing on nothing, isolated on a plain flat light grey background, no ground, no shadow, "
          "no text, centered, game character sprite, " + STYLE)

# id -> (prompt, width, height, seed, cutout[, folder under assets/generated (default "demo")])
CARD = ("fantasy trading card illustration, " + STYLE + ", dramatic composition, no text, no border, no frame")
VFX = ("single magic spell effect, glowing, isolated on a pure black background, centered, no characters, "
       "no text, game visual effect sprite, high contrast, " + STYLE)
ICON = ("single game inventory item icon, centered, isolated on a plain flat light grey background, no text, "
        "no hands, no character, ornate fantasy design, " + STYLE)
TOWN = ("fantasy settlement scene, no text, no letters, no signature, no watermark, blank wooden signs, background art for a JRPG, " + STYLE)
MERCHANT = ("no signature, no watermark, blank signs, medium shot, the merchant at the left third of the image looking at the viewer with a welcoming gesture, "
            "their shop around them, no text, no letters, JRPG shop scene, " + STYLE)
GLYPH = ("simple elegant silhouette icon, solid flat white shape with fine engraved line details, centered, on a pure "
         "black background, no text, no border, no frame, no shading, symmetrical, game UI glyph")
ASSETS = {
    "map_crystal_hollow": (
        "wide landscape top-down illustrated fantasy adventure map of a vast underground crystal cavern, winding cave "
        "tunnels and chambers, glowing blue and violet crystal clusters, an underground lake, a mushroom "
        "grove, ancient ruins, lava fissure at the top, painted on aged parchment, ornate border, no text, "
        "no labels, no letters, " + STYLE, 1152, 648, 1101, False),
    "battle_crystal_hollow": (
        # The battlefield stands its units on a line about halfway down the screen, so the floor must
        # already be there: a huge flat stone floor filling the whole lower half, horizon at mid-height.
        "wide eye-level view of a vast underground crystal cavern for a 2D JRPG battle scene, a huge flat "
        "open floor of cracked stone tiles filling the entire lower half of the image, the floor starts at "
        "the middle of the image and stretches from the left edge to the right edge, empty arena, "
        "glowing blue and violet crystal formations on the far walls, soft mist, distant glowing waterfall, "
        "no characters, no creatures, no text, " + STYLE, 1152, 648, 1112, False),
    "monster_crystal_golem": (
        "a hulking crystal golem made of blue quartz and dark stone, glowing core in its chest, " + SPRITE,
        768, 768, 1201, True),
    "monster_cave_bat": (
        "a giant fanged cave bat with leathery violet wings spread wide, sharp claws, red eyes, " + SPRITE,
        768, 768, 1202, True),
    "monster_fungal_shambler": (
        "a shambling mushroom creature with a big spotted purple cap, glowing green spores, root legs, " + SPRITE,
        768, 768, 1203, True),
    "monster_shadow_wraith": (
        "a floating hooded shadow wraith with tattered black robes and glowing violet eyes, spectral claws, " + SPRITE,
        768, 768, 1204, True),
    "boss_crystal_wyrm": (
        "a colossal terrifying dragon wyrm, dark obsidian black scales, huge jagged glowing violet crystal "
        "spikes erupting along its spine and horns, rearing up ready to strike, enormous gaping fanged maw "
        "with rows of sharp crystal teeth, glowing furious magenta eyes, clawed forelegs, thick armoured "
        "serpent body, dark fantasy final boss monster, menacing and intimidating, dramatic rim light, "
        + SPRITE, 896, 640, 1311, True),
    "icon_bleed": (
        "a single game icon of a bright red blood drop with a small slash wound, ornate gold rim, "
        "centered, isolated on a plain flat light grey background, no text, " + STYLE, 512, 512, 1401, True),

    # --- Frost specialization (Chiara) ----------------------------------------------------------
    "card_frost_bolt": ("a jagged spear of glowing blue ice flying through the air leaving frost mist, " + CARD, 768, 448, 2101, False, "frost"),
    "card_frost_ward": ("a shimmering wall of translucent blue ice crystals forming a protective barrier, snowflakes, " + CARD, 768, 448, 2102, False, "frost"),
    "card_frost_chill": ("swirling freezing wind full of snowflakes and frost runes wrapping around a target, blue glow, " + CARD, 768, 448, 2103, False, "frost"),
    "card_frost_blizzard": ("a violent magical blizzard with ice shards raining down on a dark battlefield, " + CARD, 768, 448, 2104, False, "frost"),
    "card_frost_nova": ("an expanding ring explosion of ice and frost shards from the ground, bright cyan light, " + CARD, 768, 448, 2105, False, "frost"),
    "card_frost_shatter": ("a frozen ice statue shattering into hundreds of glittering crystal fragments, " + CARD, 768, 448, 2106, False, "frost"),
    "card_frost_glacier": ("a colossal glacier spike erupting from the ground, towering ice, cold blue light, " + CARD, 768, 448, 2107, False, "frost"),
    "card_frost_heart": ("a glowing crystalline heart made of ice floating in the air above a frozen altar, snowflakes, cold blue light, epic, absolutely no letters or symbols, " + CARD, 768, 448, 2118, False, "frost"),
    "card_frost_avalanche": ("a magical avalanche of ice and snow crashing down a mountain, epic scale, " + CARD, 768, 448, 2109, False, "frost"),
    "cutin_frost_t2": ("anime mage princess with long wavy light copper-blonde hair (not red), pale grey eyes, deep blue and ivory royal mage robes with gold trim, casting a spear of ice from her hand, frost particles, dynamic pose, " + STYLE, 768, 576, 2211, False, "frost"),
    "cutin_frost_t3": ("anime mage princess with long wavy light copper-blonde hair (not red), pale grey eyes, deep blue and ivory royal mage robes with gold trim, summoning a swirling blizzard, glowing blue magic circle, " + STYLE, 768, 576, 2212, False, "frost"),
    "cutin_frost_t4": ("anime mage princess with long wavy light copper-blonde hair (not red), pale grey eyes, deep blue and ivory royal mage robes with gold trim, raising both arms as a giant glacier erupts behind her, epic ice magic, " + STYLE, 896, 512, 2213, False, "frost"),
    "vfx_ice_spear": ("a long horizontal spear of glowing blue ice pointing right with a frost trail, " + VFX, 768, 384, 2301, False, "frost"),
    "vfx_frost_nova": ("a circular burst explosion of ice shards and frost, top-down ring, " + VFX, 640, 640, 2302, False, "frost"),
    "vfx_ice_prison": ("a block of ice crystal encasing nothing, frozen crystal shell with sharp spikes, " + VFX, 640, 640, 2303, False, "frost"),
    "icon_chill": ("a single snowflake game icon, glowing pale blue ice crystal, ornate silver rim, " + ICON, 512, 512, 2401, True, "frost"),
    # --- Ashveil specialization (Bianca): oil, powder, smoke and traps -----------------------------
    "card_ash_slash": ("a dark steel longsword slashing through a cloud of grey ash and drifting embers, black and ember orange, " + CARD, 768, 448, 5101, False, "ashveil"),
    "card_ash_smoke": ("a thick billowing cloud of charcoal grey smoke with a shadowy hooded knight silhouette vanishing inside it, embers, " + CARD, 768, 448, 5102, False, "ashveil"),
    "card_ash_flask": ("a glass flask of thick black oil shattering in mid-air, glossy dark oil splashing outward, amber highlights, " + CARD, 768, 448, 5103, False, "ashveil"),
    "card_ash_caltrops": ("dozens of spiky iron caltrops scattered on a stone floor in a slick of black oil, glinting, " + CARD, 768, 448, 5104, False, "ashveil"),
    "card_ash_powder": ("a black powder keg exploding in a huge blast of orange fire and black smoke, sparks flying, " + CARD, 768, 448, 5105, False, "ashveil"),
    "card_ash_ignite": ("a sword blade striking sparks onto a pool of black oil that bursts into roaring orange flames, " + CARD, 768, 448, 5106, False, "ashveil"),
    "card_ash_shadow": ("a dagger thrust out of deep purple-black shadows, the blade trailing dark smoke, glowing ember eyes in the dark, " + CARD, 768, 448, 5107, False, "ashveil"),
    "card_ash_inferno": ("a battlefield drowned in black oil erupting into a towering sea of fire and falling ash, epic scale, " + CARD, 768, 448, 5108, False, "ashveil"),
    "card_ash_veil": ("a swirling dome of grey ash and smoke shielding two figures, embers drifting, mysterious dusk light, " + CARD, 768, 448, 5109, False, "ashveil"),
    "cutin_ash_t2": ("anime knight princess with long black hair and brown eyes, wearing dark charcoal plate armour with ember-orange trim and a hooded smoky grey cloak, "
                     "belts with oil flasks, throwing a flask of black oil, dynamic pose, smoke and embers, " + STYLE, 768, 576, 5211, False, "ashveil"),
    "cutin_ash_t3": ("anime knight princess with long black hair and brown eyes, wearing dark charcoal plate armour with ember-orange trim and a hooded smoky grey cloak, "
                     "lunging with a sword out of a cloud of black smoke, embers, dynamic pose, " + STYLE, 768, 576, 5212, False, "ashveil"),
    "cutin_ash_t4": ("anime knight princess with long black hair and brown eyes, wearing dark charcoal plate armour with ember-orange trim and a hooded smoky grey cloak, "
                     "standing before a towering wall of fire and falling ash, sword raised, epic, " + STYLE, 896, 512, 5213, False, "ashveil"),
    "vfx_oil_splash": ("a big splash of thick glossy black oil with dark droplets and amber highlights, " + VFX, 640, 640, 5301, False, "ashveil"),
    "vfx_smoke_burst": ("a billowing burst of thick grey and charcoal smoke with a few orange embers, " + VFX, 640, 640, 5302, False, "ashveil"),
    "vfx_powder_blast": ("a violent black powder explosion, orange fireball core with black smoke and flying sparks, " + VFX, 640, 640, 5303, False, "ashveil"),
    "vfx_oil_ignite": ("a pool of oil igniting into a tall roaring column of orange and red flame with black smoke, " + VFX, 640, 640, 5304, False, "ashveil"),
    "vfx_caltrops": ("a scattered spray of small spiky iron caltrops and sparks flying outward, " + VFX, 640, 640, 5305, False, "ashveil"),
    "icon_oiled": ("a single game icon of a glossy black oil droplet with an amber highlight and a tiny flame reflection, ornate bronze rim, " + ICON, 512, 512, 5401, True, "ashveil"),
    "icon_ashveil": ("a single game emblem icon of a dark sword crossed with a smoking flask, wreathed in grey smoke and embers, ornate dark iron rim, " + ICON, 512, 512, 5402, True, "ashveil"),
    # --- Card-play effects (every card shows something). Dark effects (oil, smoke) are cut out and
    # drawn with normal blending: additive blending makes black oil and grey smoke invisible.
    "vfx_oil_splash_cut": ("a big splash of thick glossy pitch-black oil with flying black droplets and amber highlights, "
                           "isolated on a plain flat white background, centered, no text, game visual effect sprite, " + STYLE, 640, 640, 5501, True, "vfx"),
    "vfx_smoke_cloud_cut": ("a dense billowing cloud of dark charcoal grey smoke puffs with a few small orange embers, "
                            "isolated on a plain flat white background, centered, no text, game visual effect sprite, " + STYLE, 640, 640, 5502, True, "vfx"),
    "vfx_smoke_veil_cut": ("a swirling ring of grey smoke and drifting ash wrapping around an empty space, soft wispy edges, "
                           "isolated on a plain flat white background, centered, no text, game visual effect sprite, " + STYLE, 640, 640, 5503, True, "vfx"),
    "vfx_flask_cut": ("a small round glass flask full of black oil with a cork, spinning in the air, a few oil drops, "
                      "isolated on a plain flat white background, centered, no text, game visual effect sprite, " + STYLE, 512, 512, 5504, True, "vfx"),
    "vfx_caltrops_cut": ("a scattered spray of shiny spiky iron caltrops flying outward with small sparks and oil drops, "
                         "isolated on a plain flat white background, centered, no text, game visual effect sprite, " + STYLE, 640, 640, 5505, True, "vfx"),
    "vfx_ash_slash": ("a wide curved sword slash arc trail made of glowing orange embers and sparks with grey ash flakes, motion streak, " + VFX, 768, 512, 5511, False, "vfx"),
    "vfx_shadow_stab": ("a straight horizontal dagger thrust streak of glowing violet shadow energy pointing right with purple sparks, " + VFX, 768, 384, 5512, False, "vfx"),
    "vfx_card_draw": ("three glowing ethereal magic cards fanning out in the air with sparkling light trails, " + VFX, 640, 640, 5513, False, "vfx"),
    "vfx_energy_burst": ("a radiant glowing energy crystal bursting with light rays and sparkles, " + VFX, 640, 640, 5514, False, "vfx"),
    # --- Map pictures for the castle and the forest (same illustrated style as the coast and cave) ----
    "map_royal_castle": ("wide landscape top-down illustrated fantasy adventure map of a royal castle and its grounds seen from above, "
                         "a royal keep and bedchambers at the bottom centre, guest houses and a guard barracks on the left, a sandy "
                         "training yard with practice dummies on the right, a large courtyard with a round fountain in the middle, "
                         "market stalls and an armory on the far right, a library tower left of centre, a grand throne hall at the "
                         "top centre, the main castle gate with a drawbridge and moat at the top, stone walls and towers around, "
                         "gardens and blue roofs, painted on aged parchment, ornate border, absolutely no text, no labels, no letters, "
                         + STYLE, 1152, 648, 6101, False, "maps"),
    "map_enchanted_forest": ("wide landscape top-down illustrated fantasy adventure map of an enchanted forest, the left third is rocky "
                             "grey mountains with snow and pine trees and winding mountain paths, the middle third is a dense misty forest "
                             "of colossal ancient trees with glowing mushrooms, the right third is a river with waterfalls, cliffs and "
                             "green meadows, a dark serpent lair at the top centre, painted on aged parchment, ornate border, absolutely no "
                             "text, no labels, no letters, " + STYLE, 1152, 648, 6111, False, "maps"),
    # --- Equipment (chest armour and weapons) -----------------------------------------------------
    "item_padded_gambeson": ("a quilted padded cloth gambeson armor jacket, beige and brown, " + ICON, 512, 512, 2501, True, "items"),
    "item_chainmail_hauberk": ("a steel chainmail hauberk armor shirt, " + ICON, 512, 512, 2502, True, "items"),
    "item_flameward_cuirass": ("a red and gold steel breastplate cuirass engraved with flame patterns, glowing ember runes, " + ICON, 512, 512, 2503, True, "items"),
    "item_frostbound_mail": ("a pale blue steel chest armor covered in frost and ice crystals, " + ICON, 512, 512, 2504, True, "items"),
    "item_shadowveil_robe": ("a dark purple and black hooded mage robe with silver moon embroidery, " + ICON, 512, 512, 2505, True, "items"),
    "item_stormweave_coat": ("a long blue leather coat with crackling lightning embroidery, " + ICON, 512, 512, 2506, True, "items"),
    "item_venomguard_jerkin": ("a green leather jerkin armor with herbal charms and leaf patterns, " + ICON, 512, 512, 2507, True, "items"),
    "item_apprentice_staff": ("a simple wooden mage staff with a small blue crystal at the top, vertical, " + ICON, 512, 512, 2601, True, "items"),
    "item_ember_staff": ("a mage staff of dark wood with a burning red fire crystal at the top, vertical, " + ICON, 512, 512, 2602, True, "items"),
    "item_rimeglass_staff": ("a mage staff made of clear blue ice glass with a frozen crystal top, vertical, " + ICON, 512, 512, 2603, True, "items"),
    "item_starlit_rod": ("an ornate silver mage rod topped with a glowing violet star crystal, vertical, " + ICON, 512, 512, 2604, True, "items"),
    "item_steel_longsword": ("a plain steel longsword with leather grip, vertical, point up, " + ICON, 512, 512, 2701, True, "items"),
    "item_dawnsteel_blade": ("a holy golden-white longsword glowing with radiant light, vertical, point up, " + ICON, 512, 512, 2702, True, "items"),
    "item_runed_warblade": ("a heavy broad sword with glowing blue runes along the blade, vertical, point up, " + ICON, 512, 512, 2703, True, "items"),
    # --- Act III: the Sunlit Coast (beach) -------------------------------------------------------
    "map_sunlit_coast": ("wide landscape top-down illustrated fantasy adventure map of a sunny coastal land, a thin strip of turquoise sea only "
                         "along the left edge, the rest is land: golden beaches, rocky coves, tide pools, palm groves, a small fishing village "
                         "with piers, a broken shipwreck on the shore, sandstone ruins, rolling dunes, and a dark swirling sandstorm at the top, "
                         "painted on aged parchment, ornate border, absolutely no text, no writing, no labels, no letters, no title, " + STYLE, 1152, 648, 3111, False, "beach"),
    "battle_beach": ("wide eye-level view of a sunny fantasy beach for a 2D JRPG battle scene, evenly lit, soft daylight, no shadows on the sand, a huge flat "
                     "open floor of smooth golden sand filling the entire lower half of the image, the sand starts at the middle of the image and stretches "
                     "from the left edge to the right edge, turquoise sea and gentle waves on the horizon, sea cliffs and palm trees at "
                     "the far sides, empty arena, no characters, no creatures, no text, " + STYLE, 1152, 648, 3112, False, "beach"),
    "monster_giant_crab": ("a giant armoured red and orange crab with huge serrated pincers raised, barnacles on its shell, " + SPRITE, 768, 768, 3201, True, "beach"),
    "monster_dire_albatross": ("a huge menacing dire albatross seabird with enormous wings spread wide, hooked beak, storm-grey feathers, flying, " + SPRITE, 768, 768, 3202, True, "beach"),
    "monster_triton_soldier": ("a triton soldier, a fish-man warrior with blue-green scales, fins, shell and coral armour, holding a trident, standing, " + SPRITE, 768, 768, 3203, True, "beach"),
    "monster_rock_spider": ("a giant spider made of grey and brown rock and stone plates, glowing amber eyes, eight stone legs, " + SPRITE, 768, 768, 3204, True, "beach"),
    "monster_sand_giant": ("a hulking giant golem made entirely of rough grainy golden desert sand, cracked crumbling sand texture, sand streaming and pouring "
                           "from its shoulders and fists, glowing amber eyes, rocks embedded in its body, standing, monster, " + SPRITE, 768, 768, 3215, True, "beach"),
    "monster_rock_giant": ("a colossal giant made of craggy dark boulders and stone, moss and cracks, glowing orange core, massive arms, standing, " + SPRITE, 768, 768, 3206, True, "beach"),
    "monster_sea_snake": ("a huge teal and blue sea serpent with fins and spines, coiled body rising up, open fanged jaws, wet glistening scales, " + SPRITE, 768, 768, 3207, True, "beach"),
    "boss_sandstorm_elemental": ("a colossal living sandstorm monster, a towering whirling tornado of golden sand and dust with a monstrous face, two glowing orange eyes "
                                 "and a gaping mouth, huge arms made of swirling sand with claws, rocks orbiting it, terrifying elemental final boss, "
                                 "no people, no humans, no figures, " + SPRITE, 896, 640, 3311, True, "beach"),
    "vfx_water_splash": ("a big explosive splash of sea water with droplets and foam, " + VFX, 640, 640, 3401, False, "beach"),
    "vfx_sand_blast": ("a violent blast of swirling sand and dust, " + VFX, 640, 640, 3402, False, "beach"),
    "vfx_rock_hurl": ("a single large boulder rock flying with dust trail, " + VFX, 640, 640, 3403, False, "beach"),
    "vfx_tidal_wave": ("a curling ocean wave crashing, foam and spray, side view, " + VFX, 768, 512, 3404, False, "beach"),
    "icon_soaked": ("a single game icon of three blue water droplets, glossy, ornate silver rim, " + ICON, 512, 512, 3501, True, "beach"),
    "icon_sandblind": ("a single game icon of a closed eye covered by swirling golden sand, ornate bronze rim, " + ICON, 512, 512, 3502, True, "beach"),
    "icon_quicksand": ("a single game icon of a sinking sand whirlpool vortex, golden brown, ornate bronze rim, " + ICON, 512, 512, 3503, True, "beach"),
    # Sea rooms of the coast (middle column of the map): fights aboard a ship, plus the Shark Knight.
    "battle_ship_deck": ("wide eye-level view across the deck of a large wooden fantasy sailing ship on the open sea for a 2D JRPG battle scene, "
                         "evenly lit, bright sunny daylight, a huge flat open floor of wooden deck planks filling the entire lower half of the image, "
                         "the planks start at the middle of the image and stretch from the left edge to the right edge, wooden railings, "
                         "a mast with furled sails and ropes at the far sides, turquoise open sea and blue sky on the horizon behind the railing, "
                         "empty deck, no characters, no creatures, no text, " + STYLE, 1152, 648, 3121, False, "beach"),
    "monster_shark_knight": ("a fearsome shark knight, a muscular shark-headed humanoid warrior with grey-blue shark skin, gaping jaws full of "
                             "jagged teeth, a dorsal fin on its back, wearing barnacle-crusted steel and coral plate armour, holding a large "
                             "serrated sword and a round shell shield, standing, monster, " + SPRITE, 768, 768, 3221, True, "beach"),
    "monster_sand_scorpion": ("a giant desert sand scorpion with a sandy gold and rust-orange segmented carapace, two huge pincers raised, "
                              "a tall curled tail with a glowing green venom stinger, side view, monster, " + SPRITE, 768, 768, 3232, True, "beach"),
    # Enemies stand on the LEFT and must face RIGHT (toward the party). FLUX ignores the direction in the prompt, so check each new sprite: monster_shark_knight.png and monster_sand_scorpion.png were mirrored after generation (regenerating them needs the same mirror).
    # --- Terrain battle backdrops and monsters for the castle, forest and Crystal Hollow --------------
    # FLUX does not place the horizon reliably (a retry of the chasm put the ledge at 68%). Backdrops whose
    # floor starts too low get a bottom-anchored zoom in combat_presentation.json "floors" instead.
    # Every backdrop needs open, level floor from about 45% of the height down: the battlefield's
    # feet line sits 59-62% down the picture (16:9 to ultrawide), so units always stand on ground.
    "battle_castle_yard": ("wide eye-level view of a sunny royal castle training courtyard for a 2D JRPG battle scene, evenly lit, soft daylight, "
                           "a huge flat open floor of large pale stone flagstones filling the entire lower 60 percent of the image, the floor starts "
                           "just above the middle of the image and stretches from the left edge to the right edge, tall castle walls with blue "
                           "banners and towers in the background, wooden practice dummies and weapon racks at the far sides, empty arena, "
                           "no characters, no people, no text, " + STYLE, 1152, 648, 4101, False, "terrain"),
    "battle_forest_mountain": ("wide eye-level view of a high mountain pass for a 2D JRPG battle scene, evenly lit, cool morning light, a huge flat "
                               "open floor of packed earth, gravel and flat grey rock filling the entire lower 60 percent of the image, the ground "
                               "starts just above the middle of the image and stretches from the left edge to the right edge, tall pine trees and "
                               "rocky cliffs at the far sides, snowy mountain peaks and mist in the background, empty arena, no characters, "
                               "no creatures, no text, " + STYLE, 1152, 648, 4111, False, "terrain"),
    "battle_forest_deepwood": ("wide eye-level view inside a misty ancient forest of colossal trees for a 2D JRPG battle scene, evenly lit, soft "
                               "green-gold light rays, a huge flat open floor of soft moss and leaf litter filling the entire lower 60 percent of "
                               "the image, the floor starts just above the middle of the image and stretches from the left edge to the right edge, "
                               "gigantic gnarled tree trunks and roots with spider webs at the far sides, glowing mushrooms, mist between the "
                               "trunks in the background, empty arena, no characters, no creatures, no text, " + STYLE, 1152, 648, 4121, False, "terrain"),
    "battle_crystal_chasm": ("wide eye-level view of a broad flat stone ledge inside a huge underground cavern for a 2D JRPG battle scene, evenly lit, "
                             "a huge flat open floor of smooth dark stone filling the entire lower 60 percent of the image, the floor starts just "
                             "above the middle of the image and stretches from the left edge to the right edge, beyond the ledge a deep chasm "
                             "with a glowing blue underground lake far below, stalactites and roosting bats on the distant cave ceiling, blue "
                             "crystals, empty arena, no characters, no creatures, no text, " + STYLE, 1152, 648, 4131, False, "terrain"),
    "battle_crystal_ruins": ("wide eye-level view of ancient carved stone temple ruins inside a crystal cave for a 2D JRPG battle scene, evenly lit, "
                             "a huge flat open floor of worn carved stone tiles filling the entire lower 60 percent of the image, the floor starts "
                             "just above the middle of the image and stretches from the left edge to the right edge, broken pillars, a stone "
                             "archway and a tall dark obelisk in the background, purple and violet crystals growing from the walls, empty arena, "
                             "no characters, no creatures, no text, " + STYLE, 1152, 648, 4141, False, "terrain"),
    "monster_cliff_harpy": ("a fierce cliff harpy, a monstrous bird-woman with grey-brown feathered wings spread wide, hawk talons for feet, "
                            "wild feathered hair, savage face, flying, side view, monster, " + SPRITE, 768, 768, 4201, True, "terrain"),
    "monster_will_o_wisp": ("a will-o'-the-wisp forest spirit, a floating ghostly blue-green flame with a faint eerie face, glowing wisps and "
                            "sparks trailing around it, translucent, monster, " + SPRITE, 768, 768, 4211, True, "terrain"),
    "item_coral_mail": ("a chest armour made of pink and orange coral plates and seashells, " + ICON, 512, 512, 2511, True, "items"),
    "item_sandstone_cuirass": ("a sandstone carved breastplate armour, desert tan with engraved sun symbols, " + ICON, 512, 512, 2512, True, "items"),
    "item_kelpwoven_coat": ("a long coat woven from dark green kelp and seaweed with pearl buttons, " + ICON, 512, 512, 2513, True, "items"),
    "item_dunewalker_wraps": ("a folded desert nomad cloth vest with a sand-coloured scarf and brass goggles lying on top, the garment laid flat, "
                              "no person, no face, no body, " + ICON, 512, 512, 2524, True, "items"),
    # Towns (data/towns) and merchants (data/shops): wide scenes used as the room backdrop and as the
    # framed illustration at the top of the town / shop screen.
    **{key: (prompt + ", wide establishing shot, " + TOWN, 1152, 648, seed, False, "towns") for key, prompt, seed in [
        ("town_brookside_camp", "a small woodcutters' camp beside a clear forest brook, a campfire, log benches, stacked firewood, "
         "canvas tents and a woodpile, tall sunlit trees, early evening", 6101),
        ("town_elderwood_village", "a hidden fantasy village built among the enormous roots of a giant ancient tree, wooden houses "
         "with round doors and glowing lantern windows, rope bridges, market stalls with herbs below, warm golden light", 6102),
        ("town_last_trader_outpost", "a lonely fortified wooden trading post at the edge of a dark misty forest, palisade wall, "
         "crates and barrels, a single lantern, ominous serpent-shaped mountains in the distance, dusk", 6113),
        ("town_lantern_post", "a forest crossroads with a tall wooden lantern post and a rangers' shelter, a signpost, a small "
         "campfire, supply crates, blue twilight with fireflies", 6104),
        ("town_charcoal_camp", "a charcoal burners' camp in a forest clearing, earthen kilns smoking, piles of logs, embers "
         "glowing orange, smoke curling between dark pine trees", 6105),
        ("town_fishers_hamlet", "a floating village of fishing boats lashed together on a calm turquoise sea, fishing nets drying "
         "on the masts, plank walkways between the boats, lanterns, a sunny coast in the distance", 6106),
        ("town_tide_camp", "a ring of wooden rafts tied around an old anchored shipwreck hulk on the sea, a glowing brazier "
         "on the deck, ropes and barrels, sunset over the waves", 6107),
        ("town_dune_village", "a desert village among golden sand dunes beside the sea, striped cloth awnings over market "
         "stalls, adobe houses, camels resting in the shade, palm trees, bright sun", 6118),
        ("town_last_camp", "a last shelter camp on a windswept rocky shore, a tattered tent and a lone trader's cart, a dark "
         "storm with lightning gathering over the sea, dramatic clouds", 6109),
    ]},
    **{key: (prompt + ", " + MERCHANT, 1152, 648, seed, False, "towns") for key, prompt, seed in [
        ("merchant_castle_potions", "a kindly elderly royal quartermaster in a blue and gold livery behind a polished counter of "
         "potion bottles in a castle storeroom, shelves of jars, stone walls, plain blue banners without symbols", 6211),
        ("merchant_forest_peddler", "a cheerful travelling peddler woman with a wide hat unpacking colourful wares on a big tree "
         "stump in a sunny forest clearing, a heavy backpack, hanging pots and charms", 6202),
        ("merchant_forest_village_market", "a friendly elf herbalist at a wooden market stall under the roots of a giant tree, "
         "bundles of dried herbs, glowing tonic bottles, baskets, warm lantern light", 6203),
        ("merchant_forest_last_trader", "a grizzled one-eyed trader in a fur cloak behind a crude plank counter inside a dim "
         "fortified outpost, weapons and potions on the wall, a single lantern", 6204),
        ("merchant_beach_fish_market", "a jolly bearded fisherman merchant at a stall on a boat deck, baskets of fish, sea-salt "
         "tonic bottles without labels, coral armour pieces hanging, nets and seagulls, sunny sea", 6215),
        ("merchant_beach_dune_bazaar", "a desert bazaar merchant woman in flowing robes and a veil under a striped awning, rugs, "
         "brass lamps, potions and travel gear, sand dunes behind, bright sun", 6216),
        ("merchant_beach_last_merchant", "a grim hooded trader beside a cart under a tattered tent on a stormy shore, a lantern, "
         "potions and old weapons, dark storm clouds and lightning over the sea", 6207),
    ]},
    # Empty-slot glyphs for the equipment screen: a white emblem on black; slot_glyphs() below turns
    # brightness into alpha so the game can draw them as faint engravings.
    **{"slot_" + key: ("a single " + what + " emblem, " + GLYPH, 512, 512, seed, False, "ui") for key, what, seed in [
        ("helmet", "knight helmet seen from the front", 6301), ("amulet", "pendant amulet on a chain", 6302),
        ("chest", "breastplate armour", 6303), ("gauntlets", "armoured gauntlet glove", 6304),
        ("weapon", "sword pointing up", 6305), ("ring", "ring with a gem", 6306),
        ("belt", "leather belt with a buckle", 6307), ("boots", "pair of boots", 6308),
    ]},
    # Aether: Arcana (Chiara) conjures surplus magic, Holy (Bianca) turns it into light. Violet arcane
    # motes and golden holy light are the shared palette of the combo.
    **{key: (prompt + ", " + CARD, 768, 448, seed, False, "aether") for key, prompt, seed in [
        ("card_arcana_siphon", "a violet arcane bolt piercing a shadow wraith while ribbons of glowing blue ley energy flow back "
         "into a floating crystal orb held in an outstretched hand, blank glowing pages, no writing", 6421),
        ("card_arcana_echo", "concentric rings of glowing violet light rippling outward like echoes from a single bright point, "
         "floating blank cards of light spiralling upward, starry dark background, no star symbol, no hexagram", 6422),
        ("card_arcana_weave", "glowing blue and violet leylines weaving across a night landscape into a radiant knot of arcane "
         "energy, threads of light, epic and mystical", 6403),
        ("card_arcana_aetherlance", "a long lance of crackling violet and white aether light streaking through the air, "
         "shimmering motes trailing behind it, dark sky", 6404),
        ("card_holy_hymn", "a single knight's longsword held point up toward a golden sunrise, seen from behind a gauntleted "
         "hand, beams of holy light and floating violet motes of magic gathering around the one blade, cathedral silhouette", 6425),
        ("card_holy_lightfall", "a colossal pillar of golden holy light crashing down from the clouds onto a dark monster, "
         "violet arcane sparks swirling into the beam, dramatic", 6406),
        ("card_holy_cascade", "waves of radiant golden light cascading across a battlefield from a glowing shield, sparkles of "
         "violet magic, sweeping motion", 6407),
        ("card_holy_wellspring", "a glowing sacred spring of golden light rising from a marble fountain, violet arcane motes "
         "dissolving into warm healing light, serene", 6408),
    ]},
    "icon_aether": ("a single game icon of a glowing violet four-pointed star made of arcane light with a small golden halo, "
                    "ornate silver rim, " + ICON, 512, 512, 6411, True, "aether"),
    "vfx_aether_release": ("a radiant burst of golden holy light with violet arcane motes spiralling into it, starburst rays, "
                           + VFX, 640, 640, 6412, False, "aether"),
    # Wind (Chiara): pale jade and silver gales, swirling leaves, airy blue sky.
    **{key: (prompt + ", swirling jade green and silver wind currents, " + CARD, 768, 448, seed, False, "wind") for key, prompt, seed in [
        ("card_wind_bolt", "a sharp crescent blade of compressed wind shooting forward through a mountain sky", 6501),
        ("card_wind_ward", "a spinning shield of wind and drifting leaves forming a protective dome", 6502),
        ("card_wind_flurry", "two small glowing whirlwinds spinning out of an open palm, leaves caught in them", 6503),
        ("card_wind_gust", "a single small sharp gust of wind slicing the air, motion streaks", 6504),
        ("card_wind_razor", "thin razor-like slivers of wind cutting falling leaves in half", 6505),
        ("card_wind_blades", "three curved crescent-shaped blades made of wind spinning in a ring, like scythe-shaped gusts, no crosses, no swords", 6526),
        ("card_wind_updraft", "a powerful updraft lifting leaves and a fluttering cloak toward the clouds", 6507),
        ("card_wind_cyclone", "a towering cyclone tearing across a grassy plain, debris spinning", 6508),
        ("card_wind_scatter", "a gust of wind scattering a cloud of glowing motes outward in every direction", 6509),
        ("card_wind_slipstream", "a sleek ribbon of wind streaming past at great speed, trailing light", 6510),
        ("card_wind_barrier", "a wall of curving wind currents deflecting arrows in mid-air", 6511),
        ("card_wind_galeforce", "a colossal gale blasting across a cliffside, trees bending, epic scale", 6512),
        ("card_wind_eye", "the calm glowing eye of a vast storm seen from above, spiral clouds", 6513),
        ("card_wind_whisper", "soft whispering wind carrying glowing pages and feathers through the air", 6514),
        ("card_wind_hurricane", "a monstrous hurricane of jade wind and lightning swallowing the horizon, epic", 6515),
        ("card_wind_dancer", "a graceful silhouette of a mage dancing on the wind high above the clouds, ribbons of air", 6516),
    ]},
    # Venom (Bianca): a plague knight - toxic green, sickly violet, black iron.
    **{key: (prompt + ", toxic green and sickly violet palette, dark fantasy, " + CARD, 768, 448, seed, False, "venom") for key, prompt, seed in [
        ("card_venom_strike", "a dark iron sword blade dripping glowing green venom mid-swing", 6601),
        ("card_venom_guard", "a black iron shield coated in hissing green toxin, fumes rising", 6602),
        ("card_venom_envenom", "a gauntleted hand tipping a plain unlabelled round glass vial so glowing green venom drips onto a dark blade, no text, no label", 6623),
        ("card_venom_cut", "a small curved dagger leaving a glowing green poisoned cut in the air", 6604),
        ("card_venom_cloud", "a rolling cloud of thick green poison gas spreading across a battlefield", 6605),
        ("card_venom_corrode", "a smooth unadorned steel helmet melting and pitting under dripping glowing green acid, holes eaten through the metal, no symbols, no text", 6646),
        ("card_venom_veil", "a knight silhouette hidden behind a veil of green miasma fumes", 6607),
        ("card_venom_catalyst", "an alchemical flask with violet and green liquids reacting violently, bubbling over", 6608),
        ("card_venom_mark", "a glowing violet sigil of decay branded on dark stone, withered roots around it", 6609),
        ("card_venom_distill", "plain unlabelled glass alembic and coiled tubes dripping glowing green venom, violet arcane sparks, no text, no labels", 6630),
        ("card_venom_reaping", "a spectral scythe of green mist reaping withered grass, ominous", 6611),
        ("card_venom_bloom", "a giant poisonous flower blooming and releasing glowing green spores", 6612),
        ("card_venom_septic", "a jagged serrated blade striking, green venom splashing from the wound", 6613),
        ("card_venom_pestilence", "a plague storm of green miasma and swarming dark motes over a ruined field, epic", 6614),
        ("card_venom_ledger", "a closed ancient black leather tome bound with iron, a skull clasp glowing green, candles, no text", 6635),
    ]},
    # Cross-combo cards added to the other specializations' pools.
    **{key: (prompt + ", " + CARD, 768, 448, seed, False, "combos") for key, prompt, seed in [
        ("card_tanking_runic", "a heavy knight's tower shield engraved with glowing violet runes, arcane light", 6701),
        ("card_tanking_momentum", "an armoured knight charging forward behind a plain round steel shield with no emblem, wind streaks and dust trailing", 6712),
        ("card_tanking_brand", "a shield bash slamming into a burning foe, embers bursting", 6703),
        ("card_holy_sunfire", "a golden holy sword wreathed in sacred flame striking down", 6704),
        ("card_holy_psalm", "golden feathers and wind swirling around a praying knight, holy light", 6705),
        ("card_ash_hexpowder", "black powder bursting into violet arcane flames, sparks and smoke", 6706),
        ("card_fire_flashpoint", "two quick bursts of fire flashing from a mage's fingertips", 6707),
        ("card_fire_wildfire", "a wildfire racing across dry grassland at dusk, sweeping flames", 6708),
        ("card_fire_volley", "a volley of three small fiery embers shooting through the night air, glowing trails", 6709),
    ]},
    "icon_wind": ("a single game emblem icon of a jade green swirling gust of wind with a silver feather, ornate silver rim, " + ICON, 512, 512, 6801, True, "wind"),
    "icon_venom": ("a single game emblem icon of a dark sword dripping green venom over a violet skull motif, ornate black iron rim, " + ICON, 512, 512, 6802, True, "venom"),
    "icon_blight": ("a single game icon of a withered black skull wreathed in sickly violet mist, ornate bronze rim, " + ICON, 512, 512, 6803, True, "venom"),
    "icon_momentum": ("a single game icon of three curved jade wind arrows spinning in a circle, ornate silver rim, " + ICON, 512, 512, 6804, True, "wind"),
    "vfx_combustion": ("a violent explosion of green poison gas igniting into orange fire, toxic fireball, " + VFX, 640, 640, 6901, False, "combos"),
    "vfx_miasma": ("a wide ring of glowing green poison mist blown outward by wind, " + VFX, 640, 640, 6902, False, "combos"),
    "vfx_blight": ("a ghostly violet skull of mist rising and dissolving, deathly glow, " + VFX, 640, 640, 6903, False, "combos"),
    "item_tidecaller_staff": ("a mage staff of driftwood topped with a glowing blue-white pearl and a seashell, vertical, " + ICON, 512, 512, 2611, True, "items"),
    "item_coralsteel_sabre": ("a curved sabre with a blade of blue-green coral steel and a pearl pommel, vertical, point up, " + ICON, 512, 512, 2711, True, "items"),
    # Gear for every slot (data/items/equipment.json): stats plus specialization effects.
    "item_iron_sallet": ("a plain steel sallet helmet with a short visor, " + ICON, 512, 512, 7001, True, "gear"),
    "item_seers_circlet": ("a thin silver circlet headband, a delicate round diadem ring for the forehead with one glowing violet gem at the front, seen from the front at a slight angle, " + ICON, 512, 512, 7202, True, "gear"),
    "item_ember_crown": ("a dark iron crown with glowing red ember crystals and small flickering flames on its points, " + ICON, 512, 512, 7003, True, "gear"),
    "item_rimefrost_hood": ("a pale blue fur-lined mage hood frosted with ice crystals, laid flat, empty, " + ICON, 512, 512, 7004, True, "gear"),
    "item_galeplume_helm": ("a light silver open-faced helmet with two jade feather wings on its sides, a full helmet shape, swirling air around it, " + ICON, 512, 512, 7205, True, "gear"),
    "item_bastion_greathelm": ("a massive steel great helm with a reinforced visor and a tall crest, heavy plate, " + ICON, 512, 512, 7006, True, "gear"),
    "item_plague_mask": ("a dark leather plague doctor beak mask with green glass eyepieces, wisps of sickly green mist, " + ICON, 512, 512, 7007, True, "gear"),
    "item_smokeveil_hood": ("a charcoal grey hooded cowl with a smoky veil drifting from it, laid flat, empty, " + ICON, 512, 512, 7008, True, "gear"),
    "item_amber_amulet": ("a warm amber gemstone amulet on a bronze chain, " + ICON, 512, 512, 7009, True, "gear"),
    "item_hourglass_amulet": ("a golden hourglass pendant with glowing blue sand, on a fine chain, " + ICON, 512, 512, 7010, True, "gear"),
    "item_ley_pendant": ("a silver pendant holding a swirling violet aether orb, faint arcane runes orbiting it, " + ICON, 512, 512, 7011, True, "gear"),
    "item_sunlit_reliquary": ("a small golden reliquary locket radiating warm sunlight, a sun emblem engraved on it, " + ICON, 512, 512, 7012, True, "gear"),
    "item_catalyst_locket": ("a dark iron locket with a cracked glass vial of glowing green and violet liquid inside, " + ICON, 512, 512, 7013, True, "gear"),
    "item_leather_bracers": ("a pair of brown leather bracers with buckles, " + ICON, 512, 512, 7014, True, "gear"),
    "item_spellweaver_gloves": ("a pair of elegant blue silk mage gloves embroidered with glowing silver runes, " + ICON, 512, 512, 7015, True, "gear"),
    "item_storm_grips": ("a pair of light jade leather gloves with small whirlwinds curling around the fingers, " + ICON, 512, 512, 7016, True, "gear"),
    "item_shieldbearer_gauntlets": ("a pair of heavy steel plate gauntlets with small round shield plates on the backs, " + ICON, 512, 512, 7017, True, "gear"),
    "item_cinderfist_gauntlets": ("a pair of soot-blackened iron gauntlets with glowing orange cracks and drips of burning oil, " + ICON, 512, 512, 7018, True, "gear"),
    "item_sturdy_belt": ("a thick brown leather belt with an iron buckle, coiled, " + ICON, 512, 512, 7019, True, "gear"),
    "item_alchemists_bandolier": ("a leather bandolier holding small colourful potion vials, coiled, " + ICON, 512, 512, 7020, True, "gear"),
    "item_kindling_sash": ("a crimson silk sash with golden flame embroidery, the ends smouldering with tiny embers, " + ICON, 512, 512, 7021, True, "gear"),
    "item_powder_belt": ("a black leather belt with powder horns, oil flasks and small fuse pouches, " + ICON, 512, 512, 7022, True, "gear"),
    "item_pilgrims_girdle": ("a coiled white braided rope belt with a plain round golden sun-disc buckle and golden tassels at the ends, simple and clean, nothing hanging from the buckle, " + ICON, 512, 512, 7341, True, "gear"),
    "item_copper_ring": ("a simple polished copper ring, " + ICON, 512, 512, 7024, True, "gear"),
    "item_twinbond_ring": ("two intertwined rings, one silver with a blue gem and one gold with a red gem, joined together, " + ICON, 512, 512, 7025, True, "gear"),
    "item_victors_signet": ("a heavy gold signet ring with a laurel wreath crest, " + ICON, 512, 512, 7026, True, "gear"),
    "item_arcanist_ring": ("a silver ring set with a violet crystal that glows with arcane light, " + ICON, 512, 512, 7027, True, "gear"),
    "item_cinderheart_ring": ("a black iron ring set with a glowing ember-red gemstone, heat shimmer around it, " + ICON, 512, 512, 7028, True, "gear"),
    "item_frostbite_band": ("a single finger ring with a band of pale blue ice crystal and a small frozen gem, frost on the band, seen at an angle so the ring hole is visible, " + ICON, 512, 512, 7219, True, "gear"),
    "item_tempest_ring": ("a single jade finger ring with a round gem in which a tiny storm cloud swirls, seen at an angle so the ring band and hole are visible, " + ICON, 512, 512, 7230, True, "gear"),
    "item_venomfang_ring": ("a dark silver ring shaped like a snake with green venom-dripping fangs, " + ICON, 512, 512, 7031, True, "gear"),
    "item_traveling_boots": ("a pair of sturdy brown leather travel boots, " + ICON, 512, 512, 7032, True, "gear"),
    "item_glacier_greaves": ("a pair of pale blue armoured boots of ice crystal, frost mist at their soles, " + ICON, 512, 512, 7033, True, "gear"),
    "item_windstep_boots": ("a pair of light green boots with small feathered wings at the ankles and swirling air, " + ICON, 512, 512, 7034, True, "gear"),
    "item_rampart_sabatons": ("a pair of heavy steel plate armoured boots (sabatons) standing side by side, thick riveted plates over the feet and shins, knight footwear, " + ICON, 512, 512, 7235, True, "gear"),
    "item_dawnwalker_sabatons": ("a pair of white and gold armoured boots glowing with soft holy light, " + ICON, 512, 512, 7036, True, "gear"),
    "item_plaguewalker_boots": ("a pair of dark leather boots with green toxic mist seeping from them, " + ICON, 512, 512, 7037, True, "gear"),
    "item_gale_staff": ("a slender pale wood mage staff topped with a jade crystal wrapped in swirling wind, vertical, " + ICON, 512, 512, 7038, True, "gear"),
    "item_venom_kris": ("a wavy-bladed kris dagger dripping glowing green venom, vertical, point up, " + ICON, 512, 512, 7039, True, "gear"),
    # Relics (data/items/relics.json).
    "relic_guardian_locket": ("an ornate silver heart-shaped locket split into two halves on a fine chain, small blue gem, " + ICON, 512, 512, 8001, True, "relics"),
    "relic_scholars_satchel": ("a worn brown leather scholar's satchel with rolled scrolls and a quill sticking out, " + ICON, 512, 512, 8002, True, "relics"),
    "relic_healers_pendant": ("a pale green jade pendant shaped like a leaf with a soft healing glow, on a cord, " + ICON, 512, 512, 8003, True, "relics"),
    "relic_sundial_shard": ("a cracked shard of a golden sun disc with engraved sun rays and a small bronze shadow pin standing on it, warm glow, plain smooth surface, " + ICON, 512, 512, 8204, True, "relics"),
    "relic_thorn_pouch": ("a small dark leather pouch spilling black iron thorn caltrops, " + ICON, 512, 512, 8005, True, "relics"),
    "relic_royal_pear": ("a single golden pear with a small leaf and a tiny royal crown mark on its skin, " + ICON, 512, 512, 8006, True, "relics"),
    "relic_whispering_bell": ("a small silver hand bell with engraved leaf patterns and a blue ribbon, " + ICON, 512, 512, 8007, True, "relics"),
    "relic_raven_horn": ("a black curved drinking horn with raven feathers and silver bands, " + ICON, 512, 512, 8008, True, "relics"),
    "relic_sisters_locket": ("an oval gold locket open showing two tiny painted silhouettes of two young women with long hair facing each other, one in blue and one in red, " + ICON, 512, 512, 8109, True, "relics"),
    "relic_chime_of_echoes": ("a set of three crystal wind chimes on a silver bar glowing with violet light, " + ICON, 512, 512, 8010, True, "relics"),
    "relic_ley_crystal": ("a floating violet crystal shard with swirling arcane mist and tiny runes around it, " + ICON, 512, 512, 8011, True, "relics"),
    "relic_mercury_bell": ("a small bell made of shimmering liquid silver mercury with golden light, " + ICON, 512, 512, 8012, True, "relics"),
    "relic_war_drum": ("a small round war drum with red painted skin, brass studs and two drumsticks, " + ICON, 512, 512, 8013, True, "relics"),
    "relic_tidal_mirror": ("a round hand mirror with a frame of seashells and a surface rippling like water, " + ICON, 512, 512, 8014, True, "relics"),
    "relic_alchemists_stone": ("a glowing red philosopher's stone gem set in a small iron alchemical cage, " + ICON, 512, 512, 8015, True, "relics"),
    "relic_twin_comet": ("two small glowing comets, one blue and one red, spiralling around each other in a tiny night sky orb, " + ICON, 512, 512, 8016, True, "relics"),
    "relic_phoenix_feather": ("a single long phoenix feather of red, orange and gold with glowing ember tips, " + ICON, 512, 512, 8017, True, "relics"),
    "relic_storm_crown": ("a jagged silver crown crackling with blue lightning sparks, " + ICON, 512, 512, 8018, True, "relics"),
    "relic_dragon_heart": ("a crystallized dragon heart, a deep red gem shaped like a heart with molten veins, " + ICON, 512, 512, 8019, True, "relics"),
    "relic_runic_crown": ("a heavy dark stone crown with glowing golden geometric rune lines, abstract carved patterns only, no letters, no writing, " + ICON, 512, 512, 8120, True, "relics"),
    "relic_eclipse_orb": ("a black orb with a blazing golden eclipse ring of light around it, " + ICON, 512, 512, 8021, True, "relics"),
    "relic_crimson_chalice": ("an ornate golden chalice filled with glowing crimson liquid, " + ICON, 512, 512, 8022, True, "relics"),
    "relic_twin_halo": ("two glowing golden halo rings interlocked like two linked rings, radiant white light, floating, no frame, " + ICON, 512, 512, 8123, True, "relics"),
}

# Card-pool expansion and own art for every older card (scripts/tools/card_expansion_prompts.json):
# group "cards", one colour palette per specialization so each pool reads as a set.
CARD_PALETTES = {
    "fire": "blazing orange, crimson and gold palette",
    "frost": "icy cyan, pale blue and silver palette",
    "arcana": "deep violet, indigo and starlight palette",
    "wind": "swirling jade green and silver wind currents",
    "holy": "radiant gold and warm white light palette",
    "tanking": "polished steel, navy and bronze palette",
    "venom": "toxic green and sickly violet palette, dark fantasy",
    "ashveil": "charcoal smoke, black oil and ember orange palette",
}
_expansion = os.path.join(os.path.dirname(os.path.abspath(__file__)), "card_expansion_prompts.json")
if os.path.exists(_expansion):
    for _key, _entry in json.load(open(_expansion, encoding="utf-8")).items():
        if _key not in ASSETS:
            ASSETS[_key] = (_entry["prompt"] + ", " + CARD_PALETTES.get(_entry["specialization"], "") + ", " + CARD,
                            768, 448, _entry["seed"], False, "cards")

# Frostpeak (the mountain adventure, scripts/tools/mountain_prompts.json): group "mountain"; each entry
# carries its prompt, size, seed, cut-out flag and output folder (STYLE is added here).
_mountain = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mountain_prompts.json")
if os.path.exists(_mountain):
    for _key, _entry in json.load(open(_mountain, encoding="utf-8")).items():
        if _key.startswith("_"):
            continue
        if _key not in ASSETS:
            _extra = (", isolated on a plain flat light grey background, no ground, no shadow, single creature, whole body visible, "
                      "no text, centered, game character sprite") if _entry["kind"] == "sprite" else ""
            ASSETS[_key] = (_entry["prompt"] + _extra + ", " + STYLE, _entry["width"], _entry["height"], _entry["seed"], _entry["cutout"], _entry["folder"])


def _workflow(prompt, width, height, seed, cutout, prefix):
    wf = {
        "1": {"class_type": "UnetLoaderGGUF", "inputs": {"unet_name": MODEL["unet"]}},
        "2": {"class_type": "DualCLIPLoaderGGUF", "inputs": {"clip_name1": MODEL["clip_l"], "clip_name2": MODEL["t5"], "type": "flux"}},
        "3": {"class_type": "VAELoader", "inputs": {"vae_name": MODEL["vae"]}},
        "4": {"class_type": "CLIPTextEncode", "inputs": {"text": prompt, "clip": ["2", 0]}},
        "5": {"class_type": "CLIPTextEncode", "inputs": {"text": "", "clip": ["2", 0]}},
        "6": {"class_type": "EmptySD3LatentImage", "inputs": {"width": width, "height": height, "batch_size": 1}},
        "7": {"class_type": "KSampler", "inputs": {"model": ["1", 0], "seed": seed, "steps": 4, "cfg": 1.0,
                                                   "sampler_name": "euler", "scheduler": "simple", "positive": ["4", 0],
                                                   "negative": ["5", 0], "latent_image": ["6", 0], "denoise": 1.0}},
        "8": {"class_type": "VAEDecode", "inputs": {"samples": ["7", 0], "vae": ["3", 0]}},
    }
    if cutout:
        wf["9"] = {"class_type": "LoadBackgroundRemovalModel", "inputs": {"bg_removal_name": "birefnet.safetensors"}}
        wf["10"] = {"class_type": "RemoveBackground", "inputs": {"bg_removal_model": ["9", 0], "image": ["8", 0]}}
        wf["11"] = {"class_type": "InvertMask", "inputs": {"mask": ["10", 0]}}
        wf["12"] = {"class_type": "JoinImageWithAlpha", "inputs": {"image": ["8", 0], "alpha": ["11", 0]}}
        wf["13"] = {"class_type": "SaveImage", "inputs": {"images": ["12", 0], "filename_prefix": prefix}}
    else:
        wf["13"] = {"class_type": "SaveImage", "inputs": {"images": ["8", 0], "filename_prefix": prefix}}
    return wf


def _post(path, payload):
    request = urllib.request.Request(SERVER + path, data=json.dumps(payload).encode(), headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=300) as response:
        return json.loads(response.read())


def _get(path):
    with urllib.request.urlopen(SERVER + path, timeout=300) as response:
        return response.read()


def generate(asset_id, force=False):
    prompt, width, height, seed, cutout = ASSETS[asset_id][:5]
    folder = ASSETS[asset_id][5] if len(ASSETS[asset_id]) > 5 else "demo"
    out_dir = os.path.join(ROOT, "assets", "generated", folder)
    target = os.path.join(out_dir, asset_id + ".png")
    if os.path.exists(target) and not force:
        print("skip", asset_id)
        return
    queued = _post("/prompt", {"prompt": _workflow(prompt, width, height, seed, cutout, "voidfarer_" + asset_id), "client_id": str(uuid.uuid4())})
    prompt_id = queued["prompt_id"]
    started = time.time()
    while True:
        history = json.loads(_get("/history/" + prompt_id))
        if prompt_id in history:
            entry = history[prompt_id]
            if entry.get("status", {}).get("status_str") == "error":
                raise RuntimeError("%s failed: %s" % (asset_id, json.dumps(entry["status"])[:600]))
            images = entry["outputs"]["13"]["images"]
            break
        if time.time() - started > 1800:
            raise RuntimeError(asset_id + " timed out")
        time.sleep(2)
    image = images[0]
    data = _get("/view?filename=%s&subfolder=%s&type=%s" % (image["filename"], image["subfolder"], image["type"]))
    os.makedirs(out_dir, exist_ok=True)
    with open(target, "wb") as f:
        f.write(data)
    if cutout:
        _trim(target)
    if asset_id.startswith("slot_"):
        _glyph_alpha(target)
    _log(asset_id, prompt, width, height, seed, cutout, time.time() - started, out_dir, folder)
    print("ok  ", asset_id, "%.0fs" % (time.time() - started))


def _glyph_alpha(path):
    """White-on-black emblem -> white shape whose alpha is the brightness, trimmed and centred."""
    from PIL import Image, ImageOps
    grey = ImageOps.autocontrast(Image.open(path).convert("L"), cutoff=1)
    grey = grey.point(lambda v: 0 if v < 40 else min(255, int((v - 40) * 1.35)))
    image = Image.new("RGBA", grey.size, (255, 255, 255, 0))
    image.putalpha(grey)
    image.save(path)
    _trim(path, pad=8)


def _trim(path, pad=4):
    """Crops a cut-out sprite to its visible pixels (plus a small margin) so the game can stand it on the ground."""
    from PIL import Image
    image = Image.open(path).convert("RGBA")
    box = image.getchannel("A").point(lambda v: 255 if v > 24 else 0).getbbox()
    if box:
        box = (max(0, box[0] - pad), max(0, box[1] - pad), min(image.width, box[2] + pad), min(image.height, box[3] + pad))
        image.crop(box).save(path)


def _log(asset_id, prompt, width, height, seed, cutout, seconds, out_dir=OUT, folder="demo"):
    path = os.path.join(out_dir, "generation_log.json")
    log = json.load(open(path, encoding="utf-8")) if os.path.exists(path) else {"_comment": "Generated locally with ComfyUI. Model: FLUX.1 [schnell] (Apache 2.0, black-forest-labs) GGUF Q3_K_S by city96; text encoders CLIP-L + T5-XXL GGUF; background removal BiRefNet (MIT). 4 steps, euler/simple, CFG 1.", "assets": {}}
    log["assets"][asset_id] = {"file": "res://assets/generated/%s/%s.png" % (folder, asset_id), "prompt": prompt, "width": width, "height": height,
                               "seed": seed, "steps": 4, "cutout": cutout, "model": MODEL, "seconds": round(seconds, 1),
                               "date": time.strftime("%Y-%m-%d")}
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(log, f, indent=1)


if __name__ == "__main__":
    force = "--force" in sys.argv
    only = sys.argv[sys.argv.index("--only") + 1] if "--only" in sys.argv else None
    group = sys.argv[sys.argv.index("--group") + 1] if "--group" in sys.argv else None
    for key in ASSETS:
        in_group = group is None or (ASSETS[key][5] if len(ASSETS[key]) > 5 else "demo") == group
        if (only is None or key == only) and in_group:
            generate(key, force)
