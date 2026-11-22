"""Extracts UI elements from the generated JPG sheets in assets/ui/general/ (originals untouched).

Usage (project root):  python scripts/tools/extract_ui_assets.py [--preview DIR]

The JPGs have a fake "transparency" checkerboard painted into their pixels, so none of them has real
alpha. Method per element: crop a generous box around it, flood-fill the neutral checker tones inward
from the box border (so neutral pixels *inside* an element are kept), make the filled area transparent
and soften the cut edge by one pixel. Particle sprites use brightness-over-floor alpha (glow style).
Output (runtime copies):
  assets/ui/buttons  assets/ui/panels  assets/ui/icons  assets/ui/effects  assets/ui/processed
A manifest.json next to the outputs records the source file and box of every element.
"""
import json
import os
import sys
from collections import deque
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
GEN = os.path.join(ROOT, "assets", "ui", "general")
OUT = os.path.join(ROOT, "assets", "ui")

BUTTONS = "Menu _buttons.jpg"
PANELS = "Decorative _panels_and _frames.jpg"
ICONS = "UI_icons.jpg"
LOGO = "Game_logo.jpg"
FX = "main_menu_atmospheric_effects.jpg"

# (source, group, name, box) boxes are generous crops around one element.
BOXES = [
    (BUTTONS, "buttons", "button_ornate", (55, 50, 670, 245)),
    (BUTTONS, "buttons", "button_small_square", (935, 65, 1105, 235)),
    (BUTTONS, "buttons", "button_plain", (55, 285, 670, 475)),
    (PANELS, "panels", "panel_rect_ornate", (825, 65, 1310, 260)),
    (PANELS, "panels", "panel_banner", (75, 505, 670, 645)),
    (PANELS, "panels", "frame_circle", (730, 295, 1065, 630)),
    (PANELS, "panels", "frame_portrait", (1095, 350, 1315, 615)),
    (PANELS, "panels", "divider", (545, 650, 1315, 720)),
    (LOGO, "processed", "logo", (80, 140, 1335, 700)),
]
ICON_NAMES = [
    "heart", "shield", "combat", "gold",
    "potion", "flame", "star", "rune",
    "silhouette", "chest", "settings", "sound",
    "music", "back", "check", "close",
]


def is_checker(p, lo, hi, tol=8):
    r, g, b = p
    return abs(r - g) <= tol and abs(g - b) <= tol and lo <= (r + g + b) // 3 <= hi


def cut_checker(img, lo, hi, tol=8, loose=None, everywhere=False):
    """RGBA image where checker pixels are transparent: those connected to the border, or (everywhere)
    also the ones enclosed by an element, such as the counters of letters."""
    w, h = img.size
    px = img.load()
    bg = bytearray(w * h)
    queue = deque()
    for x in range(w):
        queue.append((x, 0))
        queue.append((x, h - 1))
    for y in range(h):
        queue.append((0, y))
        queue.append((w - 1, y))
    while queue:
        x, y = queue.popleft()
        if x < 0 or y < 0 or x >= w or y >= h or bg[y * w + x]:
            continue
        p = px[x, y]
        if not (is_checker(p, lo, hi, tol) or (loose is not None and loose(p))):
            continue
        bg[y * w + x] = 1
        queue.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))
    if everywhere:
        for y in range(h):
            for x in range(w):
                if is_checker(px[x, y], lo, hi, tol):
                    bg[y * w + x] = 1
    out = Image.new("RGBA", (w, h))
    op = out.load()
    for y in range(h):
        for x in range(w):
            if bg[y * w + x]:
                continue
            edge = False
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and bg[ny * w + nx]:
                    edge = True
                    break
            r, g, b = px[x, y]
            op[x, y] = (r, g, b, 140 if edge else 255)
    return out


def clear_region(rgba, box, pred):
    """Makes matching pixels inside box transparent (enclosed checker squares the flood cannot reach)."""
    px = rgba.load()
    x0, y0, x1, y1 = box
    for y in range(y0, min(y1, rgba.height)):
        for x in range(x0, min(x1, rgba.width)):
            r, g, b, a = px[x, y]
            if a and pred((r, g, b)):
                px[x, y] = (r, g, b, 0)


def drop_specks(rgba, min_area=400):
    """Removes small disconnected blobs (the registration crosses drawn around frames in the sheet)."""
    w, h = rgba.size
    px = rgba.load()
    seen = bytearray(w * h)
    for sy in range(h):
        for sx in range(w):
            if seen[sy * w + sx] or px[sx, sy][3] == 0:
                continue
            comp = []
            queue = deque([(sx, sy)])
            seen[sy * w + sx] = 1
            while queue:
                x, y = queue.popleft()
                comp.append((x, y))
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx] and px[nx, ny][3] > 0:
                        seen[ny * w + nx] = 1
                        queue.append((nx, ny))
            if len(comp) < min_area:
                for x, y in comp:
                    px[x, y] = (0, 0, 0, 0)
    return rgba


def trim(img, pad=2):
    box = img.getchannel("A").point(lambda v: 255 if v > 20 else 0).getbbox()
    if box is None:
        return img
    l, t, r, b = box
    return img.crop((max(0, l - pad), max(0, t - pad), min(img.width, r + pad), min(img.height, b + pad)))


def glow_sprite(img, floor=70):
    """Particle sprite: alpha from brightness above the checker floor, colour kept saturated."""
    w, h = img.size
    px = img.load()
    out = Image.new("RGBA", (w, h))
    op = out.load()
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            m = max(r, g, b)
            if m <= floor:
                continue
            a = (m - floor) / (255.0 - floor)
            op[x, y] = (min(255, int((r - floor * 0.5) / max(a, 0.05))), min(255, int((g - floor * 0.5) / max(a, 0.05))), min(255, int((b - floor * 0.5) / max(a, 0.05))), int(a * 255))
    return out


def save(img, group, name, manifest, source, box):
    folder = os.path.join(OUT, group)
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, name + ".png")
    img.save(path)
    manifest.append({"id": name, "group": group, "path": "res://assets/ui/%s/%s.png" % (group, name), "source": source, "box": list(box), "size": list(img.size)})
    print("%-22s %-10s %4dx%-4d" % (name, group, img.size[0], img.size[1]))


def extract_fx(manifest):
    """One sprite per particle family: the first connected bright blob in each atlas row band."""
    img = Image.open(os.path.join(GEN, FX)).convert("RGB")
    bands = {"fx_gold_dust": (20, 120), "fx_sparkle": (150, 245), "fx_blue_orb": (275, 365), "fx_ember": (400, 500), "fx_swirl": (520, 610), "fx_glitter": (640, 745)}
    for name, (y0, y1) in bands.items():
        band = img.crop((0, y0, 1376, y1))
        w, h = band.size
        px = band.load()
        cols = [0] * w
        for x in range(w):
            for y in range(h):
                if max(px[x, y]) > 110:
                    cols[x] += 1
        # first cluster of bright columns
        xs = [x for x in range(w) if cols[x] > 0]
        if not xs:
            continue
        start = xs[0]
        end = start
        for x in xs:
            if x - end > 14:
                break
            end = x
        cell = band.crop((max(0, start - 14), 0, min(w, end + 14), h))
        sprite = trim(glow_sprite(cell), pad=3)
        save(sprite, "effects", name, manifest, FX, (max(0, start - 14), y0, min(w, end + 14), y1))


def main():
    preview = sys.argv[sys.argv.index("--preview") + 1] if "--preview" in sys.argv else None
    manifest = []
    for source, group, name, box in BOXES:
        img = Image.open(os.path.join(GEN, source)).convert("RGB").crop(box)
        cut = cut_checker(img, 15, 125, everywhere=(name == "logo"))
        if group in ("buttons", "panels") and name != "divider":
            cut = drop_specks(cut, 3000)  # keeps only the frame itself; the sheet's corner crosses are smaller
        sprite = trim(cut)
        save(sprite, group, name, manifest, source, box)
    sheet = Image.open(os.path.join(GEN, ICONS)).convert("RGB")
    for i, name in enumerate(ICON_NAMES):
        cx, cy = (i % 4) * 256, (i // 4) * 256
        cell = sheet.crop((cx, cy, cx + 256, cy + 256))
        save(trim(cut_checker(cell, 10, 125, everywhere=True)), "icons", "icon_" + name, manifest, ICONS, (cx, cy, cx + 256, cy + 256))
    extract_fx(manifest)
    chiara = Image.open(os.path.join(GEN, "chiara.jpg")).convert("RGB")
    chiara_rgba = cut_checker(chiara, 150, 255, 6, loose=lambda p: p[2] - p[0] < 45 and min(p) > 185)
    # The magic ring behind her hand is a tinted overlay on the checker: drop its pale, low-saturation tiles.
    clear_region(chiara_rgba, (60, 20, 400, 300), lambda p: min(p) > 150 and max(p) - min(p) < 85)
    clear_region(chiara_rgba, (40, 0, 420, 300), lambda p: p[2] > p[0] + 18 and min(p) > 110)  # light-blue glow tiles and ring
    clear_region(chiara_rgba, (40, 0, 420, 300), lambda p: min(p) > 150 and max(p) - min(p) < 30)  # pale neutral tiles
    clear_region(chiara_rgba, (316, 0, 352, 125), lambda p: min(p) > 120 and max(p) - min(p) < 70)  # leftover glow sliver
    clear_region(chiara_rgba, (100, 300, 232, 430), lambda p: min(p) > 150 and max(p) - min(p) < 30)  # tiles between hair strands
    chiara_trimmed = trim(chiara_rgba)
    # Light-grey checker squares left beside her head and between the hair strands at her elbow
    # (boxes in trimmed-image pixels; hair and shadows are darker or coloured, so they stay).
    for box in ((316, 0, 356, 140), (160, 285, 205, 350)):
        clear_region(chiara_trimmed, box, lambda p: min(p) > 160 and max(p) - min(p) < 30)
    save(chiara_trimmed, "processed", "chiara_cutout", manifest, "chiara.jpg", (0, 0) + chiara.size)
    bianca = Image.open(os.path.join(GEN, "bianca.jpg")).convert("RGB")
    # The current bianca.jpg is a single full-body figure on a light checkerboard (same as chiara.jpg).
    bianca_rgba = cut_checker(bianca, 150, 255, 6, loose=lambda p: p[2] - p[0] < 45 and min(p) > 185)
    clear_region(bianca_rgba, (130, 60, 335, 430), lambda p: min(p) > 190 and max(p) - min(p) < 14)  # tiles between the left hair strands only (armor is also near-white)
    clear_region(bianca_rgba, (300, 60, 450, 230), lambda p: min(p) > 165 and max(p) - min(p) < 22)  # tiles beside the left hair
    clear_region(bianca_rgba, (535, 120, 625, 235), lambda p: min(p) > 165 and max(p) - min(p) < 22)  # tiles beside the right hair
    print("bianca trim box:", bianca_rgba.getchannel("A").point(lambda v: 255 if v > 20 else 0).getbbox())
    save(trim(bianca_rgba), "processed", "bianca_cutout", manifest, "bianca.jpg", (0, 0) + bianca.size)
    with open(os.path.join(OUT, "manifest.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(manifest, f, indent=2)
    if preview:
        os.makedirs(preview, exist_ok=True)
        for bg_name, color in (("dark", (18, 22, 48)), ("light", (205, 205, 210))):
            sheet_img = Image.new("RGB", (1800, 1500), color)
            x = y = row_h = 0
            for entry in manifest:
                spr = Image.open(os.path.join(ROOT, entry["path"].replace("res://", "")))
                if entry["group"] == "processed" and "cutout" in entry["id"]:
                    spr = spr.resize((spr.width // 3, spr.height // 3))
                if x + spr.width > 1800:
                    x, y, row_h = 0, y + row_h + 8, 0
                sheet_img.paste(spr, (x, y), spr)
                x += spr.width + 8
                row_h = max(row_h, spr.height)
            sheet_img.crop((0, 0, 1800, min(1500, y + row_h + 8))).save(os.path.join(preview, "ui_%s.png" % bg_name))
        for name in ("chiara_cutout", "bianca_cutout"):
            spr = Image.open(os.path.join(OUT, "processed", name + ".png"))
            sheet_img = Image.new("RGB", spr.size, (24, 28, 70))
            sheet_img.paste(spr, (0, 0), spr)
            sheet_img.save(os.path.join(preview, name + "_preview.png"))


if __name__ == "__main__":
    main()
