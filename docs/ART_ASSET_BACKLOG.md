# Art Asset Backlog

Exact prompts and seeds live in the prompt tables (`scripts/tools/castle_ui_prompts.json` for batch 1)
so they can be regenerated with `comfy_generate.py`; this file tracks purpose, size and status.
Style rules: `docs/ART_DIRECTION.md`. Workflow: `docs/COMFYUI_ASSET_PIPELINE.md`.

Status: **gen** = generated and integrated · **todo** = specified, not generated · **rej** = rerolled.

## Batch 1 — Castle Hub (this milestone)
Output folder: `assets/generated/ui/`; composed kit: `assets/generated/ui_kit/`.

| Asset ID | Description | Size | Alpha | Usage | Status |
|---|---|---|---|---|---|
| `bg_castle_hub` | castle at dusk on a waterfall cliff, balcony foreground | 1536x864 | no | castle hub background (catalog `bg_castle_hub`) | gen |
| `tex_parchment` | ivory vellum texture | 512x512 | no | parchment plaques (composed) | gen |
| `tex_navy_enamel` | midnight navy enamel texture | 512x512 | no | dark panels, secondary buttons (composed) | gen |
| `tex_violet_enamel` | violet enamel texture | 512x512 | no | primary action button (composed) | gen |
| `orn_corner` | gold filigree corner with sapphire | 512x512 | yes | panel / button corners (composed, mirrored x4) | gen |
| `orn_divider` | gold horizontal divider with star | 1024x192 | yes | section separators | gen |
| `orn_crest` | gold crown crest with wings | 768x320 | yes | screen title ornament | gen |
| `frame_diamond` | navy diamond medallion with gold rim | 512x512 | yes | frame behind service icons | gen |
| `icon_svc_expeditions` | gold compass rose | 512x512 | yes | Expeditions | gen |
| `icon_svc_library` | fanned cards | 512x512 | yes | Deck Workshop | gen |
| `icon_svc_collection` | treasure chest | 512x512 | yes | Card Collection | gen |
| `icon_svc_armory` | navy shield, fleur-de-lis | 512x512 | yes | Armory | gen |
| `icon_svc_blacksmith` | crossed hammer and tongs | 512x512 | yes | Upgrade Workshop | gen |
| `icon_svc_enchanter` | two crystals merging | 512x512 | yes | Enchanter | gen |
| `icon_svc_apothecary` | amber flask with herbs | 512x512 | yes | Apothecary | gen |
| `icon_svc_training` | sword in laurel wreath | 512x512 | yes | Training Hall | gen |
| `icon_svc_sisters` | twin crescent moons forming a heart | 512x512 | yes | The Sisters | gen |
| `icon_res_gold` | crowned gold coin | 384x384 | yes | treasury | gen |
| `icon_res_essence` | star crystal | 384x384 | yes | Starlight Essence | gen |
| `icon_res_bond` | rose heart gem | 384x384 | yes | Sister Bond | gen |
| `icon_ui_home` | small castle keep | 384x384 | yes | Main Menu | gen |
| `icon_ui_settings` | gold cogwheel | 384x384 | yes | Settings | gen |
| `icon_ui_lock` | gold padlock | 384x384 | yes | locked services | gen |

Composed by `compose_ui_kit.py` (nine-patch, margins written to `ui_kit/kit.json`):
`plaque_parchment`, `plaque_parchment_hover`, `plaque_locked`, `panel_navy`, `panel_navy_small`,
`button_violet` (+ hover/pressed/disabled), `button_navy` (+ states).

## Batch 2 — shared kit and the rest of the castle (next)
| Asset ID | Description | Size | Alpha |
|---|---|---|---|
| `icon_ui_back`, `icon_ui_confirm`, `icon_ui_cancel`, `icon_ui_reward`, `icon_ui_mission`, `icon_ui_map` | action icons, same family as batch 1 | 384x384 | yes |
| `icon_node_combat/event/merchant/rest/treasure/elite/boss` | map node icons inside `frame_diamond` | 512x512 | yes |
| `orn_flourish_small`, `orn_seal_glow`, `fx_star_particles`, `tex_overlay_vignette` | small accents and overlays | 256-512 | yes |
| `tex_leather`, `tex_carved_wood`, `tex_crystal`, `tex_engraved_steel` | extra materials | 512x512 | no |
| `panel_warning`, `panel_reward` | crimson-rimmed and gold-ribbon variants (composed) | — | yes |

## Batch 3 — screen backgrounds
| Asset ID | Scene |
|---|---|
| `bg_war_table` | a painted world map spread on an oak war table, candles, brass instruments, top-down three-quarter view, calm centre |
| `bg_library` | castle library interior at night, tall bookshelves, warm lamps, reading desk in the foreground |
| `bg_armory` | stone armory hall, weapon racks and armour stands, banners, cool daylight from high windows |
| `bg_apothecary` | herb shop corner, drying herbs, shelves of coloured bottles, copper alembic |
| `bg_enchanter` | starlit tower observatory, floating crystals, astrolabe, violet light |
| `bg_results` | castle gate courtyard at sunrise, banners |

Prompt template for each: see `COMFYUI_ASSET_PIPELINE.md` §3 (background), subject as above.

## Notes from batch 1
- `orn_corner` (seed 20301) came out as a whole symmetric frame; `compose_ui_kit.py` crops its top-left
  quarter as the corner flourish. A dedicated corner reroll is optional.
- `icon_svc_sisters` reads as two moons with a pale fill; acceptable, reroll candidate for batch 2.
- ComfyUI crashed once (access violation in BiRefNet's deform-conv) on the first cut-out; a server restart
  fixed it. `run_*_art.py` retries, but needs the server back up.

## Batch 2 — main menu, war table, service rooms, shared icons (generated 2026-11-22)
Prompts and seeds: `scripts/tools/castle_ui_prompts.json` (seeds 21001-21308), same folder and catalog.

| Asset ID | Usage | Size | Alpha | Status |
|---|---|---|---|---|
| `bg_main_menu` | main menu (castle right, open sky left for logo and menu) | 1536x864 | no | gen |
| `bg_world_map` | war table atlas (island kingdom; region markers sit on its landmarks via `data/regions` world_position) | 1536x864 | no | gen (cropped: painted signature removed) |
| `bg_library` | Deck Workshop, Collection, war table backdrop | 1536x864 | no | gen |
| `bg_forge` | Upgrade Workshop, Armory | 1536x864 | no | gen |
| `bg_apothecary` | Apothecary | 1536x864 | no | gen |
| `bg_enchanter` | Enchanter | 1536x864 | no | gen |
| `icon_region_castle/crystal/forest/coast/frostpeak` | war table landmark medallions | 512 | yes | gen |
| `icon_ui_continue/new_campaign/quickplay/exit` | main menu buttons | 384 | yes | gen |
| `icon_ui_mission` | mission cards (wax-seal scroll) | 384 | yes | gen |
| `icon_node_combat/elite/boss/treasure/rest/merchant/event/town` | expedition map nodes (Stage C2 / E) | 384 | yes | gen, not wired yet |

## Next batches (stages E-F)
| Asset ID | Usage |
|---|---|
| `card_frame_<type>` (attack, defense, spell, utility, special, twin) | card frame family (frames only, art stays the focal point) |
| `card_cost_orb`, `card_owner_badge`, `card_rarity_gem`, `card_upgrade_star`, `card_select_glow` | card UI parts |
| `bg_event`, `bg_merchant`, `bg_rest`, `bg_rewards` | room screens |
| `hud_hp_frame`, `hud_energy_orb`, `hud_intent_frame` | combat HUD |
| `tab_*`, `scrollbar_*` | composed by `compose_ui_kit.py` from existing materials |
