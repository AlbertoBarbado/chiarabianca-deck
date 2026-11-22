"""Extracts battlefield pose sprites and attack cut-ins from the combat art sheets.

Usage (project root):  python scripts/tools/extract_combat_sprites.py [--preview DIR]

Sources (originals are never modified):
  assets/characters/chiara/basic.jpg   6 poses on a dark textured background
  assets/characters/bianca/basic.jpg   8 poses on a light background
  assets/enemies/tutorial/knight_generic.jpg, knight_captain.jpg   labelled pose sheets on grey
  assets/characters/*/{fire,arcane,holy,tanking}.jpg   effect-heavy attack sheets: NOT cut out
      (the effects are painted into the background); stored as opaque cut-in crops per tier.
Pose sprites: the background is flood-filled from the cell border and made transparent (see
extract_ui_assets.cut_checker); a cell is a generous box around one pose, below its caption.
Output: <source folder>/processed/<name>.png and assets/combat_manifest.json.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from PIL import Image  # noqa: E402
from extract_ui_assets import cut_checker, drop_specks, trim  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CH = os.path.join(ROOT, "assets", "characters")
EN = os.path.join(ROOT, "assets", "enemies", "tutorial")

# name -> (box in source pixels). Grids: Chiara 3x2 cells of 352x496; Bianca 3x3 of 320x364.
CHIARA = {
    "idle": (0, 0, 352, 496), "attack": (322, 30, 760, 496), "block": (722, 20, 1057, 496),
    "hit": (0, 500, 352, 992), "cast": (340, 510, 648, 992), "charge": (680, 500, 1057, 992),
}
BIANCA = {
    "idle": (0, 0, 320, 380), "attack": (290, 20, 640, 380), "attack2": (630, 20, 960, 380),
    "guard": (0, 390, 320, 745), "strike": (630, 400, 960, 745),
    "idle_side": (0, 750, 320, 1093), "block": (300, 750, 640, 1093), "down": (630, 790, 960, 1093),
}
# Knight sheets (re-supplied on a light checkerboard, like Chiara's and Bianca's art): poses are cut out
# with the same flood fill. The generic knight sheet has no swing pose, so it attacks with "prep".
KNIGHT_GENERIC = {
    "idle": (40, 25, 250, 375), "prep": (335, 25, 575, 375), "hit": (50, 410, 300, 750),
    "block": (355, 430, 730, 750), "crit_block": (370, 800, 700, 1093),
}
KNIGHT_CAPTAIN = {
    "idle": (50, 45, 260, 380), "prep": (300, 45, 575, 380), "swing": (595, 45, 960, 380),
    "hit": (50, 420, 320, 750), "block": (355, 430, 850, 750), "crit_block": (370, 800, 960, 1093),
}

# Opaque attack cut-ins (tier artwork): name -> box.
CUTINS = {
    ("bianca", "holy"): {"t1": (0, 0, 480, 372), "t2": (480, 0, 960, 372), "t3_summon": (0, 372, 480, 745), "t3_release": (480, 372, 960, 745), "t4": (0, 745, 960, 1093)},
    ("bianca", "tanking"): {"t1": (0, 0, 480, 372), "t2": (480, 0, 960, 372), "t3_summon": (0, 372, 480, 745), "t3_release": (480, 372, 960, 745), "t4": (0, 745, 960, 1093)},
    ("chiara", "fire"): {"t1": (322, 30, 760, 496), "t2": (722, 20, 1057, 496), "t3": (0, 500, 352, 992), "t4": (340, 420, 1057, 992)},
    ("chiara", "arcane"): {"t1": (322, 30, 760, 496), "t2": (722, 20, 1057, 496), "t3": (0, 500, 352, 992), "t4": (340, 420, 1057, 992)},
}

# (flood lo, flood hi, tolerance) per sheet.
BG = {"chiara_basic": (6, 95, 14), "bianca_basic": (205, 255, 10), "knight": (150, 255, 8), "knight_captain": (96, 160, 7)}


def pose(sheet_path, bg_key, box, speck=3000):
    img = Image.open(sheet_path).convert("RGB").crop(box)
    lo, hi, tol = BG[bg_key]
    loose = (lambda p: p[2] - p[0] < 45 and min(p) > 185) if bg_key != "knight_captain" else None
    if bg_key == "chiara_basic":
        return trim(drop_specks(_cut_protecting_blue(img, lo, hi, tol, keep=[[(x - box[0], y - box[1]) for x, y in poly] for poly in KEEP_POLYGONS.get(box, [])]), speck))
    cut = cut_checker(img, lo, hi, tol, loose=loose)
    return trim(drop_specks(cut, speck))


# Hand-traced leg outlines (sheet pixels) for poses whose black leggings are indistinguishable from the
# dark sheet background: everything inside is kept as it is in the original art.
KEEP_POLYGONS = {
    (0, 0, 352, 496): [
        [(179, 345), (209, 350), (208, 395), (206, 430), (215, 460), (224, 480), (221, 488), (203, 487), (195, 470), (192, 437), (185, 405), (179, 375)],
        [(157, 388), (179, 380), (183, 405), (186, 435), (180, 455), (174, 462), (161, 460), (159, 430)],
    ],
}


def _cut_protecting_blue(img, lo, hi, tol, grow=2, keep=()):
    """Chiara's dark sheet background is near black like her boots and leggings, so a plain flood fill
    erased her legs. Bluish dark pixels (the outline and tint of the leggings) and gold trim are marked
    as never background, and that mark is grown by a couple of pixels to close tiny gaps in the outline,
    so the flood fill cannot leak into the legs. The output keeps the original colours."""
    w, h = img.size
    ip = img.load()
    protect = [[False] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            r, g, b = ip[x, y]
            if (b - g >= 4 and b >= r + 2 and b > 26) or (r - b >= 40 and r > 90):
                protect[y][x] = True
    if keep:
        from PIL import ImageDraw
        keep_mask = Image.new("L", (w, h), 0)
        for poly in keep:
            ImageDraw.Draw(keep_mask).polygon(poly, fill=255)
        kp = keep_mask.load()
        for y in range(h):
            for x in range(w):
                if kp[x, y]:
                    protect[y][x] = True
    grown = [row[:] for row in protect]
    for y in range(h):
        for x in range(w):
            if protect[y][x]:
                for dy in range(-grow, grow + 1):
                    for dx in range(-grow, grow + 1):
                        if 0 <= x + dx < w and 0 <= y + dy < h:
                            grown[y + dy][x + dx] = True
    probe = img.copy()
    pp = probe.load()
    for y in range(h):
        for x in range(w):
            if grown[y][x]:
                pp[x, y] = (200, 200, 255)
    mask = cut_checker(probe, lo, hi, tol).load()
    out = Image.new("RGBA", (w, h))
    op = out.load()
    for y in range(h):
        for x in range(w):
            alpha = mask[x, y][3]
            if alpha:
                op[x, y] = ip[x, y] + (alpha,)
    # Peel leftover neutral dark texture from the silhouette edge (the grown protection keeps a few
    # background blobs next to the cape); never touches protected (bluish / gold) pixels.
    for _ in range(5):
        remove = []
        for y in range(h):
            for x in range(w):
                if op[x, y][3] == 0 or protect[y][x]:
                    continue
                r, g, b = ip[x, y]
                if max(r, g, b) < 85 and abs(r - g) <= 12 and abs(g - b) <= 12:
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        nx, ny = x + dx, y + dy
                        if nx < 0 or ny < 0 or nx >= w or ny >= h or op[nx, ny][3] == 0:
                            remove.append((x, y))
                            break
        for x, y in remove:
            op[x, y] = (0, 0, 0, 0)
    return out


def clear_neutral_dark(img, region):
    """Makes neutral dark pixels (the sheet background texture) transparent inside region (x0, y0, x1, y1)."""
    px = img.load()
    for y in range(max(0, region[1]), min(img.size[1], region[3])):
        for x in range(max(0, region[0]), min(img.size[0], region[2])):
            r, g, b, a = px[x, y]
            if a and max(r, g, b) < 85 and abs(r - g) <= 14 and abs(g - b) <= 14:
                px[x, y] = (0, 0, 0, 0)


def main():
    preview = sys.argv[sys.argv.index("--preview") + 1] if "--preview" in sys.argv else None
    manifest = []

    def save(img, folder, name, source, box):
        out_dir = os.path.join(folder, "processed")
        os.makedirs(out_dir, exist_ok=True)
        img.save(os.path.join(out_dir, name + ".png"))
        rel = os.path.relpath(os.path.join(out_dir, name + ".png"), ROOT).replace("\\", "/")
        manifest.append({"id": name, "path": "res://" + rel, "source": source, "box": list(box), "size": list(img.size)})
        print("%-34s %4dx%-4d" % (rel, img.size[0], img.size[1]))

    for name, box in CHIARA.items():
        sprite = pose(os.path.join(CH, "chiara", "basic.jpg"), "chiara_basic", box)
        if name == "idle":  # background enclosed between the cape and the skirt
            clear_neutral_dark(sprite, (40, 240, 72, 290))
            clear_neutral_dark(sprite, (244, 280, 274, 330))
        if name == "cast":  # background enclosed between the cape and the raised hand: clear neutral dark pixels
            clear_neutral_dark(sprite, (225, 40, sprite.size[0], 220))
        save(sprite, os.path.join(CH, "chiara"), name, "basic.jpg", box)
    for name, box in BIANCA.items():
        save(pose(os.path.join(CH, "bianca", "basic.jpg"), "bianca_basic", box), os.path.join(CH, "bianca"), name, "basic.jpg", box)
    for sheet, boxes in (("knight_generic", KNIGHT_GENERIC), ("knight_captain", KNIGHT_CAPTAIN)):
        for name, box in boxes.items():
            save(pose(os.path.join(EN, sheet + ".jpg"), "knight_captain" if sheet == "knight_captain" else "knight", box, 1500 if sheet == "knight_captain" else 6000), EN, "%s_%s" % (sheet, name), sheet + ".jpg", box)
    for (character, spec), crops in CUTINS.items():
        source = os.path.join(CH, character, spec + ".jpg")
        image = Image.open(source).convert("RGB")
        for tier, box in crops.items():
            save(image.crop(box), os.path.join(CH, character), "%s_%s" % (spec, tier), spec + ".jpg", box)
    with open(os.path.join(ROOT, "assets", "combat_manifest.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(manifest, f, indent=2)
    if preview:
        os.makedirs(preview, exist_ok=True)
        for bg_name, color in (("dark", (30, 34, 70)),):
            sheet = Image.new("RGB", (2000, 1800), color)
            x = y = row_h = 0
            for entry in manifest:
                if "_t" in entry["id"] and entry["id"].split("_")[0] in ("holy", "tanking", "fire", "arcane"):
                    continue
                spr = Image.open(os.path.join(ROOT, entry["path"].replace("res://", ""))).convert("RGBA")
                spr = spr.resize((spr.width // 2, spr.height // 2))
                if x + spr.width > 2000:
                    x, y, row_h = 0, y + row_h + 6, 0
                sheet.paste(spr, (x, y), spr)
                x += spr.width + 6
                row_h = max(row_h, spr.height)
            sheet.crop((0, 0, 2000, min(1800, y + row_h + 6))).save(os.path.join(preview, "combat_%s.png" % bg_name))


if __name__ == "__main__":
    main()
