"""Extracts the Enchanted Forest enemy poses and the poison effect sprite.

Usage (project root):  python scripts/tools/extract_forest_sprites.py

Sources (originals are never modified):
  assets/enemies/1_forest/{wolf,boar,bear,spider,drake,troll,boss_serpent}.jpg
      labelled 3x2 pose sheets on a baked grey checkerboard:
      Still (Idle) | Attack Prep | Attack Swipe  /  Taking Hit | Blocking | Stagger
  assets/effects/sprites/poison/poison_attack.jpg   one poison burst on a baked white checkerboard
Each pose cell (below its caption) is flood-filled from the border to remove the checkerboard
(see extract_ui_assets.cut_checker); nothing is repainted.
Output: assets/enemies/1_forest/processed/<enemy>_<pose>.png, assets/effects/sprites/poison/poison_burst.png
and assets/forest_manifest.json.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from PIL import Image  # noqa: E402
from extract_ui_assets import cut_checker, drop_specks, trim  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FOREST = os.path.join(ROOT, "assets", "enemies", "1_forest")
POISON = os.path.join(ROOT, "assets", "effects", "sprites", "poison")
ENEMIES = ["wolf", "boar", "bear", "spider", "drake", "troll", "boss_serpent"]
POSES = [["idle", "prep", "swing"], ["hit", "block", "stagger"]]
CAPTION = 46      # caption strip at the top of each cell
CHECKER = (62, 150, 9)   # dark grey / mid grey squares (lo, hi, tolerance)
WIDE_CHECKER = (48, 170, 17)
# Sheets whose art has neutral greys like the board (wolf fur, spider highlights, drake belly): narrow flood fill.
NARROW = ("wolf", "spider", "drake")


def clear_enclosed_checker(img, min_each=25):
    """Checker squares enclosed by the art (between legs, inside swipe arcs and shield glows) are not
    reached by the border flood fill. Pixels in the two exact checker tones that form a blob of at
    least 60 pixels are made transparent; smaller neutral areas (fur, highlights) are kept."""
    w, h = img.size
    px = img.load()

    def tone(p):
        """0 = not a checker tone, 1 = dark square, 2 = light square."""
        r, g, b, a = p
        if a == 0 or abs(r - g) > 10 or abs(g - b) > 10:
            return 0
        v = (r + g + b) // 3
        return 1 if 62 <= v <= 100 else (2 if 108 <= v <= 150 else 0)

    seen = bytearray(w * h)
    for y0 in range(h):
        for x0 in range(w):
            if seen[y0 * w + x0] or not tone(px[x0, y0]):
                continue
            stack = [(x0, y0)]
            seen[y0 * w + x0] = 1
            blob = []
            counts = [0, 0, 0]
            while stack:
                x, y = stack.pop()
                blob.append((x, y))
                counts[tone(px[x, y])] += 1
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx] and tone(px[nx, ny]):
                        seen[ny * w + nx] = 1
                        stack.append((nx, ny))
            # A real checker patch has BOTH tones side by side; fur, scales and highlights have one.
            if counts[1] >= min_each and counts[2] >= min_each:
                for x, y in blob:
                    px[x, y] = (0, 0, 0, 0)


def peel_dark_squares(img, lo=50, hi=100, tol=7):
    """Shadowed dark checker squares that touch the cut-out edge survive a narrow flood fill. They are
    removed by continuing the fill from the transparent area through neutral dark-grey pixels only
    (the art next to them is black, coloured, or lighter grey, so it is not touched)."""
    from collections import deque
    w, h = img.size
    px = img.load()

    def dark_square(p):
        r, g, b, a = p
        return a > 0 and abs(r - g) <= tol and abs(g - b) <= tol and lo <= (r + g + b) // 3 <= hi

    queue = deque()
    for y in range(h):
        for x in range(w):
            if px[x, y][3] == 0:
                queue.append((x, y))
    while queue:
        x, y = queue.popleft()
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < w and 0 <= ny < h and dark_square(px[nx, ny]):
                px[nx, ny] = (0, 0, 0, 0)
                queue.append((nx, ny))


def restore_enclosed_highlights(crop, cut):
    """The spider's glossy highlights are neutral grey like the checkerboard, so the flood fill leaks
    into them and leaves see-through holes in the body. Regions that are enclosed by the dark body
    (after a small closing) are restored from the original art unless they look like checkerboard:
    two-tone (dark and light squares) or a plain dark-grey square."""
    import numpy as np
    from scipy import ndimage
    rgb = np.asarray(crop).astype(int)
    out = np.array(cut)
    lum = rgb.mean(axis=2)
    spread = rgb.max(axis=2) - rgb.min(axis=2)
    ink = ndimage.binary_closing((lum < 62) | (spread > 24), structure=np.ones((7, 7)), iterations=2)
    labels, count = ndimage.label(~ink)
    border = set(np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]])).tolist())
    for k in range(1, count + 1):
        if k in border:
            continue
        mask = labels == k
        values = lum[mask]
        dark = ((values >= 66) & (values <= 102)).mean()
        light = ((values >= 108) & (values <= 150)).mean()
        neutral = (spread[mask] <= 12).mean()
        checker = neutral > 0.8 and ((dark > 0.2 and light > 0.2 and mask.sum() > 150) or (dark > 0.7))
        if not checker:
            out[mask, :3] = rgb[mask]
            out[mask, 3] = 255
    return Image.fromarray(out.astype("uint8"), "RGBA").copy()


def main():
    manifest = []
    out_dir = os.path.join(FOREST, "processed")
    os.makedirs(out_dir, exist_ok=True)
    for enemy in ENEMIES:
        sheet = Image.open(os.path.join(FOREST, enemy + ".jpg")).convert("RGB")
        w, h = sheet.size
        cell_w, cell_h = w // 3, h // 2
        for row in range(2):
            for col in range(3):
                box = (col * cell_w, row * cell_h + CAPTION, (col + 1) * cell_w, (row + 1) * cell_h)
                # Soft shadows and glows tint the checkerboard next to the art; every sheet but the wolf
                # (grey fur, same tones as the board) tolerates a wider flood fill.
                cut = cut_checker(sheet.crop(box), *(CHECKER if enemy in NARROW else WIDE_CHECKER))
                if enemy != "wolf":  # the wolf's grey fur has the same tones as the checkerboard
                    clear_enclosed_checker(cut)
                if enemy == "drake":
                    peel_dark_squares(cut)
                if enemy == "spider":
                    cut = cut_checker(sheet.crop(box), *CHECKER)  # no enclosed clearing: it eats the highlights
                    peel_dark_squares(cut, 52, 104, 9)
                    cut = restore_enclosed_highlights(sheet.crop(box), cut)
                sprite = trim(drop_specks(cut, 2500))
                name = "%s_%s" % (enemy, POSES[row][col])
                if name == "boss_serpent_idle":  # a shaded checker patch between the tree and the neck
                    px = sprite.load()
                    for y in range(88, min(150, sprite.size[1])):
                        for x in range(96, min(150, sprite.size[0])):
                            r, g, b, alpha = px[x, y]
                            if alpha and abs(r - g) <= 13 and abs(g - b) <= 13 and 45 <= (r + g + b) // 3 <= 175:
                                px[x, y] = (0, 0, 0, 0)
                sprite.save(os.path.join(out_dir, name + ".png"))
                manifest.append({"id": name, "path": "res://assets/enemies/1_forest/processed/%s.png" % name, "source": enemy + ".jpg", "box": list(box), "size": list(sprite.size)})
                print("%-28s %4dx%-4d" % (name, sprite.size[0], sprite.size[1]))
    burst = Image.open(os.path.join(POISON, "poison_attack.jpg")).convert("RGB")
    cut = cut_checker(burst, 200, 255, 8, loose=lambda p: min(p) > 198 and max(p) - min(p) < 14)
    sprite = trim(drop_specks(cut, 300))
    sprite.save(os.path.join(POISON, "poison_burst.png"))
    manifest.append({"id": "poison_burst", "path": "res://assets/effects/sprites/poison/poison_burst.png", "source": "poison_attack.jpg", "box": [0, 0, burst.size[0], burst.size[1]], "size": list(sprite.size)})
    print("poison_burst %dx%d" % sprite.size)
    with open(os.path.join(ROOT, "assets", "forest_manifest.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump({"_comment": "Generated by scripts/tools/extract_forest_sprites.py. All sources are owner-supplied generated art: NOT release-cleared.", "assets": manifest}, f, indent=1)


if __name__ == "__main__":
    main()
