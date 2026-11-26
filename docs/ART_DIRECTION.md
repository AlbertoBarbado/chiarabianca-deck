# Art Direction — Voidfarer Chronicles

**Celestial Royal Fantasy · Anime JRPG · Painterly Environments · Ornate Handcrafted UI**

Visual anchor: the Royal Castle UI concept (castle at dusk on a waterfall cliff, ivory parchment
plaques with gold frames and navy diamond medallions, a violet "Set Out" seal). Every new screen and
asset should look like it belongs next to it. The concept itself is a reference only: it has baked
text and UI, so it is never shipped as an asset.

---

## 1. Visual identity
- The sisters' world is royal and celestial: dusk skies, starlight, gold filigree, enamel and vellum.
- Environments are illustrated places with depth and a focal point, never blurred wallpaper.
- The UI is crafted objects lying on top of the world: plaques, seals, frames, ribbons.
- Decoration frames the content; it never competes with it. Text sits on calm, flat areas.

## 2. Palette (`UITheme`)
| Role | Name | Hex |
|---|---|---|
| Base dark | Midnight navy | `0a1230` (`NAVY_DEEP`) |
| Base | Royal blue | `14224a` / `22377a` |
| Accent | Deep violet | `3a1f6e` (`VIOLET`) |
| Accent | Antique gold | `d4a64a` / `8a6a26` |
| Text on dark | Warm ivory | `f4efe0` |
| Text on parchment | Ink brown | `3b2a1a` (`INK`) |
| Secondary text | Muted lavender | `b8b0d6` (`LAVENDER`) |
| Bond, sisters | Soft pink | `ff9fb8` |
| Magic, essence | Azure | `9fc8ff` / `5aa0ff` |
| Fire | Amber | `ffa040` |
| Nature, ready | Emerald | `4f9d6a` |
| Danger, errors | Crimson | `b23a48` |

Color carries meaning: gold = interactive and valuable, violet = the main action, pink = bond,
azure = magic, crimson = danger. Do not saturate everything.

## 3. Typography
- Display and headings: **Cinzel** (SIL OFL, `resources/fonts/Cinzel.ttf`), weights 650-800.
- Body: the engine's default sans serif for now (very legible at small sizes).
- Planned: a book serif for body text on parchment (e.g. Cormorant Garamond or EB Garamond, both OFL,
  Google Fonts). Not added yet: adding a font file needs your approval to download it.
- Never bake text into images. Minimum on-screen body size 16 px at 720p.

## 4. Materials
| Material | Use | Asset |
|---|---|---|
| Ivory parchment + gold frame | navigation plaques, information panels, rewards | `ui_kit/plaque_parchment*` |
| Midnight navy enamel + gold frame | dark panels over busy art, dialogs, headers | `ui_kit/panel_navy*` |
| Violet enamel + gold | the single primary action of a screen ("Set Out") | `ui_kit/button_violet*` |
| Navy diamond medallion | service and node icons | `ui/frame_diamond` |
| Gold filigree | corners, dividers, title crest | `ui/orn_*` |
| Crystal, leather, wood, engraved metal | future: apothecary shelves, armory racks, card frames | backlog |

One screen uses at most two panel materials plus the action seal.

## 5. Lighting
Warm key light from the castle windows and dusk sky, cool rim light from the stars. UI assets are lit
from the top-left with soft highlights; no hard drop shadows baked into assets (the engine adds them).

## 6. Icons
Painted, three-dimensional objects with soft highlights (not flat vectors), front view, centred,
transparent background. Service icons sit inside the navy diamond medallion (`frame_diamond`), so
the frame is shared and the icon art stays separate. Resource icons (gold, essence, bond) stand alone.

## 7. Backgrounds
16:9, painterly, layered foreground / midground / background, one focal point placed away from the
main UI column, calm lower half (or a vignette) where the UI sits. Each screen family gets its own
background (castle hub, war table, workshop interiors...). No people, text, logos or UI.

## 8. Panels and buttons
- Nine-patch textures (`StyleBoxTexture`) composed by `scripts/tools/compose_ui_kit.py` from a generated
  material texture plus generated gold corner ornaments; corners never stretch.
- Panel family: parchment (main, info, selected, locked), navy (main, small, warning), reward.
- Buttons: violet primary, navy secondary, back, danger (crimson tint), disabled (desaturated),
  selected (gold rim). Hover brightens, pressed darkens and shifts, focus adds an azure ring.

## 9. Card frames, portraits, combat
- Cards keep the existing frame system (`CardView`); next pass: parchment text box and owner seals.
- Portraits: existing art is the source of truth (Chiara: auburn-blonde hair, light grey eyes, mage;
  Bianca: black hair, brown eyes, paladin). Never regenerate them for UI work.
- Combat VFX: existing atlas; glows in the element colours above, short and readable.

## 10. Screen identities (plan)
| Screen | Identity |
|---|---|
| Castle hub | dusk terrace, parchment plaques, violet seal (done in this milestone) |
| War table | painted world map on a wooden war table, wax-seal mission markers |
| Deck Workshop / Collection | library interior, vellum pages, bookshelf light |
| Armory | stone hall, weapon racks, engraved metal panels |
| Apothecary | herb shelves, glass and crystal materials |
| Enchanter | night tower, crystal and starlight materials |
| Events, rewards | illustrated vignettes with parchment choice cards |
| Combat | existing battle backdrops; parchment/navy HUD pieces |

## 11. Asset generation rules (summary; details in `COMFYUI_ASSET_PIPELINE.md`)
- Every prompt names the style ("hand-painted anime fantasy", "painted fantasy JRPG style").
- Every prompt includes "no text, no letters" and, for cut-outs, "isolated on a plain flat light grey
  background".
- Sizes: backgrounds 1536x864 (16:9), icons 512x512 / 384x384, textures 512x512, ornaments wide.
- Transparent assets are cut out with BiRefNet and trimmed automatically.
- Names: `bg_<screen>`, `icon_svc_<service>`, `icon_res_<resource>`, `icon_ui_<action>`, `tex_<material>`,
  `orn_<ornament>`, `frame_<shape>`; composed kit pieces in `assets/generated/ui_kit/`.
- Every generated file is logged with prompt and seed (`generation_log.json`) and listed in
  `docs/ASSET_LICENSES.md`.

## 12. Implementation status (stages, 2026-11-22)
| Stage | Status |
|---|---|
| A — foundation | done: palette, kit (`UIKit`, `compose_ui_kit.py`), theme buttons and panels on the kit, shared header and resource ribbon (`CastleUI`), catalog-registered art |
| B — main menu + castle hub | done: twilight castle menu (logo, sisters, enamel menu panel; Quick Play submenu for classic runs and shortcuts), hub with parchment plaques and medallions |
| C — war table | done: painted atlas (`bg_world_map`) with landmark medallions, golden trails and a region panel with art, threat and parchment mission cards. Expedition route maps keep their existing art; node icons generated, wiring pending |
| D — card screens | done: Deck Workshop (portrait tabs, drag and drop, hover preview, deck summary), Collection (larger cards, badges), shared card-pile modal (`CardPileModal`) for draw / discard / exhaust |
| D2 — expedition preparation | done: "Prepare Your Expedition" in three columns: parchment mission brief (region painting, seal, objective, danger, threat, reward icons), sister cards with figures and compact shortcuts, potion belt as gold sockets, heirloom and bond relic icons, violet "Begin Expedition" in the loadout column |
| E — combat | pending: HUD pieces and card frame family (backlog) |
| F — services and rooms | partly: each service has its own room background (data `background`), panels on the kit; dedicated layouts for Armory / Apothecary / Enchanter / Sisters, events, merchants, rest and rewards pending |
| G — polish | pending |

Motion rules: illustrated scene backgrounds never drift (only the old soft menu painting did); ambient
particles stay subtle and follow the effects-quality setting; trails on the atlas flow only at "full".

## 13. Menu buttons and labels (OrnateButton, ribbons)
- **OrnateButton** (`scripts/ui/components/ornate_button.gd`): pointed enamel bar, double gold rim, soft top
  gloss, a gold filigree end cap on each tip (`orn_endcap`, turned outward), and an optional painted icon in
  a round gold socket (`frame_socket`) on the left end. Violet = primary (`btn_primary`), navy = secondary
  (`btn_secondary`). Keyboard focus lights the gold rim instead of drawing a box.
- Used for the main menu, the castle hub footer and Set Out, and every castle screen's back button. The
  theme's PrimaryButton uses the same pointed violet shape everywhere (Prepare, Take Card, ...); small and
  utility buttons keep the rectangular navy frame.
- Menus float over the scene on a soft dark glow; no boxy panel behind them.
- **Ribbons** (`ribbon_navy`, `ribbon_violet`): swallowtail banners for names on the world map (the
  selected region turns violet).
- Small buttons (around 160 px wide) drop the icon: text reads better than a cramped socket.

## 14. Chips, dropdowns and plates (2026-11-23)
- **Pointed buttons** are for actions. Their reserved end-cap margin matches the drawn cap (kit
  `content_margin` 54 at texture scale), so labels never touch the filigree.
- **Choice chips** (tabs, filters, sister pickers, specialization choice) use the rectangular navy
  enamel, lit gold when selected (`CastleUI.chip_style`).
- **Dropdowns** (OptionButton) use the rectangular navy frame with room for the arrow (`UITheme._style_dropdown`).
- **Castle services** sit on a soft dark content plate over the room painting (`ContentPlate`), so
  text never lies on bare art.
- **Status cards** (act transition, run end) use the navy enamel kit panel; the rest room shows each
  sister's full figure.
- **Relics** everywhere share one hover text (`RelicIcon.tooltip_for`: name, rarity, effect); relic
  choices in chests and events show the relic's own art.
- QA: `tests/ui/ui_tour_test.tscn -- <dir>` opens every screen once and saves a picture of each.

