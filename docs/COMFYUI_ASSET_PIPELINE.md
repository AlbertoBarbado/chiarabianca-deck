# ComfyUI Asset Pipeline

How Voidfarer Chronicles art is generated locally and brought into the game, reproducibly.

## 1. Setup in use
- ComfyUI (desktop install) at `http://127.0.0.1:8188`, started with `--lowvram --reserve-vram 0.8`.
- Model: **FLUX.1 [schnell]** GGUF Q3_K_S (Apache 2.0) through ComfyUI-GGUF; text encoders CLIP-L and
  T5-XXL GGUF; FLUX VAE. 4 steps, euler / simple, CFG 1.
- Background removal: **BiRefNet** (MIT) through ComfyUI's RemoveBackground node.
- Driver script: `scripts/tools/comfy_generate.py` (reads prompt tables, queues the workflow, cuts out,
  trims, logs). Prompt tables: the script itself, `card_expansion_prompts.json`,
  `mountain_prompts.json`, `castle_ui_prompts.json`.

```
python scripts/tools/comfy_generate.py --group ui           # everything missing in a group
python scripts/tools/comfy_generate.py --only bg_castle_hub --force
python scripts/tools/compose_ui_kit.py                      # builds nine-patch panels/buttons
```

## 2. Workflows
| Need | Workflow |
|---|---|
| Background, texture | text-to-image, no cut-out |
| Icon, ornament, sprite | text-to-image on a light grey background, then BiRefNet cut-out + trim |
| Nine-patch panel / button | generate the material texture and the corner ornament separately, compose with PIL (`compose_ui_kit.py`) so corners never stretch and margins are exact |
| Variation of an approved asset | image-to-image from the approved file at denoise 0.35-0.55, same prompt, new seed |
| Style consistency | reuse the prompt fragments below verbatim; change only the subject |
| Character consistency | do not generate the sisters from text. Use the approved figures (`assets/characters`, `art_catalog.json`) as image-to-image input at low denoise (0.3-0.45) or with an IP-Adapter / Redux reference when available; describe hair and eye colours explicitly |

## 3. Prompt templates
Background:
```
breathtaking hand-painted anime fantasy environment illustration, <scene>, layered depth, painterly
texture, soft cinematic light, celestial royal fantasy JRPG background art, empty space in the
<area> for interface, no people, no characters, no text, no letters, no logo, no user interface
```
Icon (cut-out):
```
game UI icon, <object>, painted fantasy JRPG style, soft highlights, front view, centered,
isolated on a plain flat light grey background, no text
```
Ornament (cut-out):
```
a single ornate antique gold <ornament>, polished metal, front view, flat, isolated on a plain flat
light grey background, no text, game UI decoration
```
Material texture:
```
flat seamless texture of <material>, soft even lighting, no text, no border, no frame, top-down,
uniform, game UI material texture
```

## 4. Negative prompts
FLUX schnell runs at CFG 1 and ignores negative prompts, so exclusions live in the positive prompt
("no text, no letters, no logo, no people"). For SDXL / CFG > 1 workflows use:
```
text, letters, words, watermark, signature, logo, UI, interface, buttons, frame, border (for
backgrounds), blurry, lowres, jpeg artifacts, extra limbs, deformed hands, photo, 3d render,
flat vector, clipart, oversaturated
```

## 5. Sizes and transparency
| Asset | Size | Aspect | Transparent |
|---|---|---|---|
| Screen background | 1536x864 (upscale 2x for 4K if needed) | 16:9 | no |
| Service / node icon | 512x512 | 1:1 | yes |
| Resource / small UI icon | 384x384 | 1:1 | yes |
| Material texture | 512x512 | 1:1 | no |
| Divider | 1024x192 | wide | yes |
| Crest / title ornament | 768x320 | wide | yes |
| Corner ornament | 512x512 | 1:1 | yes |

## 6. Quality checks before integration
1. No text, letters or watermark anywhere (zoom in on signs and edges).
2. Cut-out clean: no grey halo, no holes; trimmed to content.
3. Style matches the anchor (painted, warm gold, navy/violet).
4. Readability: put the asset behind/inside real UI at 1280x720 and 844x390.
5. Characters: hair, eyes and outfit match the approved figures.
Rejected files go to the scratchpad `rejected/`; reroll with a new seed and record it in the prompt
table's `_note`.

## 7. Export and integration
1. Files land in `assets/generated/<folder>/` with `generation_log.json` (prompt, seed, model, date).
2. Godot imports them (run the editor or `godot --headless --import`).
3. Register ids in `data/art/art_catalog.json` (backgrounds, icons) — screens reference catalog ids,
   never file paths.
4. Add the batch to `docs/ASSET_LICENSES.md` (not release-cleared until reviewed).
