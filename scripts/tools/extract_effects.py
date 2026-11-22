"""Extracts individual combat-effect sprites (transparent PNG) from the two source atlases.

Usage (from the project root):  python scripts/tools/extract_effects.py [--preview DIR]

Source atlases (never modified):
  assets/effects/sources/combat_effects_atlas_01.png   near-black background, labels above sprites
  assets/effects/sources/combat_effects_atlas_02.png   dark blue textured background, labels below
Output: assets/effects/sprites/<element>/<name>.png and assets/effects/sprites/manifest.json

Method: each sprite is searched only inside a hand-defined box that excludes titles, label text
and ornament lines. The background is modelled (black for atlas 1, bilinear from the four box
corners for atlas 2) and removed:
  glow  : alpha = brightest channel above the background, colour = that excess / alpha. Composited
          with normal or additive blending it reproduces the original glow without a dark box.
  solid : alpha from colour distance to the background, colour recovered with the matting
          equation, for opaque shapes (rock, smoke, vines).
The result is cropped to the visible content plus padding. Sprites whose content touches the
search box border are flagged ("touches_box_edge") because a neighbour may have clipped them.
"""
import json
import os
import sys
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "assets", "effects", "sources")
OUT = os.path.join(ROOT, "assets", "effects", "sprites")
ATLAS = {"a1": "combat_effects_atlas_01.png", "a2": "combat_effects_atlas_02.png"}

# Search boxes. a1: 6 columns (x), 5 rows (y) with the label above each sprite.
# Column boundaries are not fixed: they are searched near these expected x positions for the emptiest
# vertical strip between neighbouring sprites (see find_splits).
A1_EDGES = [279, 558, 836, 1115, 1394]
A1_Y = [(38, 196), (232, 392), (424, 580), (610, 764), (795, 941)]
# a2: label below each sprite; title and "-2" artefact live in the top band.
A2_EDGES = [300, 570, 830, 1100, 1385]
SPLIT_WINDOW = 55
# Atlas 1 draws a small gold diamond under each label; its lower tip reaches the first rows of the
# search box. Rows of this height at the sprite's column centre are erased (A1_DIAMOND_X = centres).
A1_DIAMOND_X = [130, 433, 726, 1001, 1273, 1552]
A1_DIAMOND_ROWS = 7
A2_Y = [(46, 185), (206, 366), (386, 539), (566, 720), (752, 897)]

# (atlas, col, row, folder, name, mode, display name in the atlas)
SPRITES = [
    ("a1", 0, 0, "fire", "fire_bolt", "glow", "Fire Bolt"),
    ("a1", 1, 0, "fire", "flame_wave", "glow", "Flame Wave"),
    ("a1", 2, 0, "fire", "inferno", "glow", "Inferno"),
    ("a1", 3, 0, "fire", "burning_aura", "glow", "Burning Aura"),
    ("a1", 4, 0, "fire", "ember_blast", "glow", "Ember Blast"),
    ("a1", 5, 0, "fire", "fire_shield", "glow", "Fire Shield"),
    ("a1", 4, 4, "fire", "meteor", "glow", "Meteor"),
    ("a1", 5, 4, "fire", "meteor_shower", "glow", "Meteor Shower"),
    ("a2", 0, 0, "fire", "fireball", "glow", "Fireball"),
    ("a2", 1, 0, "fire", "flame_explosion", "glow", "Flame Explosion"),
    ("a2", 4, 0, "fire", "burn_apply", "glow", "Burn Effect"),
    ("a2", 5, 0, "fire", "burn_tick", "glow", "Burn Tick"),
    ("a1", 0, 1, "holy", "holy_strike", "glow", "Holy Strike"),
    ("a1", 1, 1, "holy", "divine_light", "glow", "Divine Light"),
    ("a1", 2, 1, "holy", "healing_light", "glow", "Healing Light"),
    ("a1", 3, 1, "holy", "blessing", "glow", "Blessing"),
    ("a1", 4, 1, "holy", "radiant_shield", "glow", "Radiant Shield"),
    ("a1", 5, 1, "holy", "judgment", "glow", "Judgment"),
    ("a2", 0, 1, "holy", "radiant_strike", "glow", "Radiant Strike"),
    ("a2", 1, 1, "holy", "blessed_shield", "glow", "Blessed Shield"),
    ("a2", 2, 1, "holy", "healing", "glow", "Healing"),
    ("a2", 3, 1, "holy", "divine_judgment", "glow", "Divine Judgment"),
    ("a2", 4, 1, "holy", "sanctified_ward", "glow", "Sanctified Ward"),
    ("a2", 5, 1, "holy", "party_heal", "glow", "Party Heal"),
    ("a1", 0, 2, "arcane", "arcane_bolt", "glow", "Arcane Bolt"),
    ("a1", 1, 2, "arcane", "arcane_explosion", "glow", "Arcane Explosion"),
    ("a1", 2, 2, "arcane", "mana_surge", "glow", "Mana Surge"),
    ("a1", 3, 2, "arcane", "magic_barrier", "glow", "Magic Barrier"),
    ("a1", 4, 2, "arcane", "control", "glow", "Control"),
    ("a1", 5, 2, "arcane", "time_warp", "glow", "Time Warp"),
    ("a1", 3, 4, "arcane", "chain_lightning", "glow", "Chain Lightning"),
    ("a2", 0, 2, "arcane", "arcane_bolt_runic", "glow", "Arcane Bolt"),
    ("a2", 1, 2, "arcane", "mana_surge_pillar", "glow", "Mana Surge"),
    ("a2", 2, 2, "arcane", "arcane_blast", "glow", "Arcane Blast"),
    ("a2", 3, 2, "arcane", "arcane_nova", "glow", "Arcane Nova"),
    ("a2", 4, 2, "arcane", "arcane_curse", "glow", "Arcane Curse"),
    ("a2", 5, 2, "arcane", "mana_shield", "glow", "Mana Shield"),
    ("a1", 0, 3, "earth", "earth_spike", "solid", "Earth Spike"),
    ("a1", 1, 3, "earth", "stone_skin", "solid", "Stone Skin"),
    ("a1", 2, 3, "earth", "ground_slam", "solid", "Ground Slam"),
    ("a2", 0, 3, "earth", "earth_shatter", "solid", "Earth Shatter"),
    ("a2", 1, 3, "earth", "stone_wall", "solid", "Stone Wall"),
    ("a2", 3, 3, "ice", "ice_shards", "glow", "Ice Shards"),
    ("a2", 4, 3, "wind", "wind_slash", "glow", "Wind Slash"),
    ("a2", 5, 3, "wind", "wind_gust", "glow", "Wind Gust"),
    ("a1", 3, 3, "nature", "natures_embrace", "glow", "Nature's Embrace"),
    ("a1", 4, 3, "nature", "regrowth", "glow", "Regrowth"),
    ("a1", 5, 3, "nature", "fortify", "glow", "Fortify"),
    ("a1", 2, 4, "nature", "poison_cloud", "solid", "Poison Cloud"),
    ("a2", 2, 3, "nature", "entangling_vines", "solid", "Entangling Vines"),
    ("a2", 2, 4, "nature", "poison_skull", "solid", "Poison"),
    ("a1", 0, 4, "utility", "taunt", "glow", "Taunt"),
    ("a1", 1, 4, "utility", "smoke_screen", "solid", "Smoke Screen"),
    ("a2", 0, 4, "utility", "haste", "glow", "Haste"),
    ("a2", 1, 4, "utility", "invisibility", "glow", "Invisibility"),
    ("a2", 3, 4, "utility", "shadow_strike", "glow", "Shadow Strike"),
    ("a2", 4, 4, "utility", "barrier", "glow", "Barrier"),
    ("a2", 5, 4, "utility", "taunt_alert", "glow", "Taunt"),
]

# Minimum brightness above the background that counts as sprite (suppresses background texture).
KNEE = {("a1", "glow"): 22, ("a1", "solid"): 34, ("a2", "glow"): 26, ("a2", "solid"): 36}
# Content extent: rows/columns whose summed alpha is above this count as part of the sprite
# (single stray pixels of background noise do not stretch the crop).
PROJECTION_MIN = 1.2
PAD = 12
# Atlas rectangles (x0, y0, x1, y1) erased before cropping: baked-in text that is not part of a sprite.
MASKS = {
    "burn_tick": [(1512, 40, 1582, 90)],  # the "-2" damage number drawn above the flame
    "arcane_bolt_runic": [(0, 534, 300, 560)],  # top of its caption, which sits closer than the others
}


def find_splits(img, atlas, row):
    """x boundaries between the six columns of one atlas row: the emptiest strip near each edge."""
    ys = (A1_Y if atlas == "a1" else A2_Y)[row]
    knee = 40
    px = img.load()
    width = img.size[0]
    cols = []
    for x in range(width):
        cols.append(sum(1 for y in range(ys[0], ys[1], 2) if max(px[x, y]) > knee + (0 if atlas == "a1" else 25)))
    edges = A1_EDGES if atlas == "a1" else A2_EDGES
    splits = [0]
    for e in edges:
        lo, hi = e - SPLIT_WINDOW, e + SPLIT_WINDOW
        window = [(sum(cols[max(0, x - 3):x + 4]), abs(x - e), x) for x in range(lo, hi)]
        splits.append(min(window)[2])
    splits.append(width)
    return splits


_SPLIT_CACHE = {}


def search_box(atlas, col, row, img=None):
    ys = (A1_Y if atlas == "a1" else A2_Y)[row]
    key = (atlas, row)
    if key not in _SPLIT_CACHE:
        _SPLIT_CACHE[key] = find_splits(img, atlas, row)
    splits = _SPLIT_CACHE[key]
    return splits[col], ys[0], splits[col + 1], ys[1]


def corner_median(img, x0, y0, size=8):
    px = []
    for y in range(y0, y0 + size):
        for x in range(x0, x0 + size):
            px.append(img.getpixel((x, y)))
    return tuple(sorted(p[c] for p in px)[len(px) // 2] for c in range(3))


def background_model(atlas, img, box):
    """Returns f(x, y) -> (r, g, b) background colour inside the box."""
    if atlas == "a1":
        return lambda x, y: (0.0, 0.0, 0.0)
    x0, y0, x1, y1 = box
    tl = corner_median(img, x0, y0)
    tr = corner_median(img, x1 - 8, y0)
    bl = corner_median(img, x0, y1 - 8)
    br = corner_median(img, x1 - 8, y1 - 8)
    w, h = max(1, x1 - x0 - 1), max(1, y1 - y0 - 1)

    def model(x, y):
        u, v = (x - x0) / w, (y - y0) / h
        return tuple((tl[c] * (1 - u) + tr[c] * u) * (1 - v) + (bl[c] * (1 - u) + br[c] * u) * v for c in range(3))
    return model


def extract(atlas, img, col, row, mode, masks=()):
    box = search_box(atlas, col, row, img)
    x0, y0, x1, y1 = box
    if atlas == "a1":
        cx = A1_DIAMOND_X[col]
        masks = list(masks) + [(cx - 12, y0, cx + 12, y0 + A1_DIAMOND_ROWS)]
    bg = background_model(atlas, img, box)
    knee = KNEE[(atlas, mode)]
    w, h = x1 - x0, y1 - y0
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    src = img.load()
    dst = out.load()
    for y in range(h):
        for x in range(w):
            p = src[x0 + x, y0 + y]
            b = bg(x0 + x, y0 + y)
            if mode == "glow":
                ex = [max(0.0, p[c] - b[c]) for c in range(3)]
                m = max(ex)
                if m <= knee:
                    continue
                a = min(1.0, (m - knee) / (255.0 - knee))
                top = m
                col_rgb = [min(255, int(ex[c] / top * 255.0)) for c in range(3)]
                # Brightness lives in alpha; keep colour saturated but never darker than the glow.
                dst[x, y] = (col_rgb[0], col_rgb[1], col_rgb[2], int(a * 255))
            else:
                d = max(abs(p[c] - b[c]) for c in range(3))
                if d <= knee:
                    continue
                a = min(1.0, (d - knee) / 70.0)
                rgb = [max(0, min(255, int((p[c] - b[c] * (1 - a)) / a))) for c in range(3)]
                dst[x, y] = (rgb[0], rgb[1], rgb[2], int(a * 255))
    for mx0, my0, mx1, my1 in masks:
        for y in range(max(0, my0 - y0), min(h, my1 - y0)):
            for x in range(max(0, mx0 - x0), min(w, mx1 - x0)):
                dst[x, y] = (0, 0, 0, 0)
    alpha = out.getchannel("A")
    apx = alpha.load()
    cols = [sum(apx[x, y] for y in range(h)) / 255.0 for x in range(w)]
    rows = [sum(apx[x, y] for x in range(w)) / 255.0 for y in range(h)]
    xs = [x for x in range(w) if cols[x] >= PROJECTION_MIN]
    ys = [y for y in range(h) if rows[y] >= PROJECTION_MIN]
    if not xs or not ys:
        return None, box, False
    left, top, right, bottom = xs[0], ys[0], xs[-1] + 1, ys[-1] + 1
    touches = left <= 1 or top <= 1 or right >= w - 1 or bottom >= h - 1
    left, top = max(0, left - PAD), max(0, top - PAD)
    right, bottom = min(w, right + PAD), min(h, bottom + PAD)
    return out.crop((left, top, right, bottom)), (x0 + left, y0 + top, x0 + right, y0 + bottom), touches


def main() -> None:
    preview_dir = None
    if "--preview" in sys.argv:
        preview_dir = sys.argv[sys.argv.index("--preview") + 1]
        os.makedirs(preview_dir, exist_ok=True)
    atlases = {k: Image.open(os.path.join(SRC, v)).convert("RGB") for k, v in ATLAS.items()}
    manifest = []
    for atlas, col, row, folder, name, mode, label in SPRITES:
        sprite, region, touches = extract(atlas, atlases[atlas], col, row, mode, MASKS.get(name, ()))
        if sprite is None:
            print("EMPTY", name)
            continue
        folder_path = os.path.join(OUT, folder)
        os.makedirs(folder_path, exist_ok=True)
        sprite.save(os.path.join(folder_path, name + ".png"))
        manifest.append({
            "id": name, "folder": folder, "path": "res://assets/effects/sprites/%s/%s.png" % (folder, name),
            "source": ATLAS[atlas], "atlas_label": label, "region": list(region),
            "size": list(sprite.size), "mode": mode, "touches_box_edge": touches,
        })
        print("%-20s %-8s %4dx%-4d %s" % (name, folder, sprite.size[0], sprite.size[1], "TOUCHES EDGE" if touches else ""))
    with open(os.path.join(OUT, "manifest.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(manifest, f, indent=2)
    if preview_dir:
        for bgname, color in (("dark", (24, 28, 48)), ("light", (200, 200, 205))):
            sheet = Image.new("RGB", (1800, 1500), color)
            x = y = rowh = 0
            for entry in manifest:
                spr = Image.open(os.path.join(ROOT, entry["path"].replace("res://", "")))
                if x + spr.width > 1800:
                    x, y, rowh = 0, y + rowh + 8, 0
                sheet.paste(spr, (x, y), spr)
                x += spr.width + 8
                rowh = max(rowh, spr.height)
            sheet.crop((0, 0, 1800, min(1500, y + rowh + 8))).save(os.path.join(preview_dir, "sheet_%s.png" % bgname))


if __name__ == "__main__":
    main()
