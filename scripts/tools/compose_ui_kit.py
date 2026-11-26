"""Composes the nine-patch UI kit (panels, plaques, buttons) from generated materials and ornaments.

Inputs (assets/generated/ui, from castle_ui_prompts.json): tex_parchment, tex_navy_enamel,
tex_violet_enamel, orn_corner. Output: assets/generated/ui_kit/<piece>.png and kit.json with the
nine-patch margins (texture_margin) and content margins Godot should use (UIKit reads kit.json).

Composing instead of generating whole panels keeps every border straight, every corner identical and
the margins exact, so StyleBoxTexture can stretch the middle without ever stretching an ornament.
    python scripts/tools/compose_ui_kit.py
"""
import json
import os

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageOps

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "assets", "generated", "ui")
OUT = os.path.join(ROOT, "assets", "generated", "ui_kit")

GOLD = (212, 166, 74, 255)
GOLD_DARK = (122, 90, 30, 255)
GOLD_LIGHT = (250, 222, 150, 255)


def load(name):
    return Image.open(os.path.join(SRC, name + ".png")).convert("RGBA")


def corner_top_left(corner):
    """Rotates the ornament so most of it sits in the top-left quadrant (the L opens to bottom-right)."""
    best, best_mass = corner, -1
    for angle in (0, 90, 180, 270):
        img = corner.rotate(angle, expand=True)
        alpha = img.getchannel("A")
        w, h = img.size
        mass = sum(alpha.crop((0, 0, w // 2, h // 2)).histogram()[i] * i for i in range(256))
        if mass > best_mass:
            best, best_mass = img, mass
    return best


def fill(texture, size, brightness=1.0, alpha=255):
    tile = texture.resize((max(size[0], size[1]),) * 2, Image.LANCZOS) if min(texture.size) < max(size) else texture
    base = Image.new("RGBA", size)
    for x in range(0, size[0], tile.width):
        for y in range(0, size[1], tile.height):
            base.paste(tile, (x, y))
    if brightness != 1.0:
        base = ImageEnhance.Brightness(base).enhance(brightness)
    base.putalpha(alpha)
    return base


def chamfer_mask(size, cut, radius=0):
    """Rectangle with cut (chamfered) corners."""
    w, h = size
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).polygon([(cut, 0), (w - cut, 0), (w, cut), (w, h - cut), (w - cut, h), (cut, h), (0, h - cut), (0, cut)], fill=255)
    return mask


def inner_shade(img, mask, strength=90, blur=18):
    """Darkens the edges a little so the panel reads as a raised, framed surface."""
    edge = ImageOps.invert(mask).filter(ImageFilter.GaussianBlur(blur))
    shade = Image.new("RGBA", img.size, (0, 0, 0, 0))
    shade.putalpha(edge.point(lambda v: min(strength, v)))
    return Image.alpha_composite(img, shade)


def border(img, cut, inset, colors, widths):
    draw = ImageDraw.Draw(img)
    w, h = img.size
    offset = inset
    for color, width in zip(colors, widths):
        c = cut + offset * 0.4
        points = [(c, offset), (w - c, offset), (w - offset, c), (w - offset, h - c), (w - c, h - offset), (c, h - offset), (offset, h - c), (offset, c), (c, offset)]
        draw.line(points, fill=color, width=width, joint="curve")
        offset += width
    return img


def corners(img, corner, size, pad):
    tl = corner_top_left(corner)
    tl = tl.resize((size, int(size * tl.height / tl.width)), Image.LANCZOS)
    w, h = img.size
    img.alpha_composite(tl, (pad, pad))
    img.alpha_composite(ImageOps.mirror(tl), (w - tl.width - pad, pad))
    img.alpha_composite(ImageOps.flip(tl), (pad, h - tl.height - pad))
    img.alpha_composite(ImageOps.flip(ImageOps.mirror(tl)), (w - tl.width - pad, h - tl.height - pad))
    return img


def piece(texture, size, cut, corner, corner_size, brightness=1.0, alpha=255, rim=(GOLD_DARK, GOLD, GOLD_LIGHT), rim_widths=(3, 3, 1), shade=90):
    mask = chamfer_mask(size, cut)
    img = fill(texture, size, brightness, 255)
    img = inner_shade(img, mask, shade)
    img.putalpha(mask.point(lambda v: v * alpha // 255))
    img = border(img, cut, 1, rim, rim_widths)
    if corner is not None:
        img = corners(img, corner, corner_size, 2)
    return img


def pointed(texture, size, endcap, gloss=0.22, rim=(GOLD_DARK, GOLD, GOLD_LIGHT), rim_widths=(6, 5, 2), brightness=1.0):
    """A JRPG menu button: an enamel bar with pointed ends, a double gold rim, a soft top gloss and a
    gold filigree end cap on each point (docs/ART_DIRECTION.md §8)."""
    w, h = size
    p = int(h * 0.42)
    poly = [(p, 0), (w - p, 0), (w - 1, h // 2), (w - p, h - 1), (p, h - 1), (0, h // 2)]
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).polygon(poly, fill=255)
    img = fill(texture, size, brightness, 255)
    # Gloss: lighter top half fading down, darker bottom edge.
    shade = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(shade)
    for y in range(h):
        t = y / h
        if t < 0.5:
            draw.line([(0, y), (w, y)], fill=(255, 255, 255, int(255 * gloss * (1 - t * 2))))
        else:
            draw.line([(0, y), (w, y)], fill=(0, 0, 0, int(255 * 0.28 * (t - 0.5) * 2)))
    img = Image.alpha_composite(img, shade)
    img.putalpha(mask)
    draw = ImageDraw.Draw(img)
    inset = 0
    for color, width in zip(rim, rim_widths):
        q = [(p + inset * 0.4, inset), (w - p - inset * 0.4, inset), (w - 1 - inset, h // 2), (w - p - inset * 0.4, h - 1 - inset), (p + inset * 0.4, h - 1 - inset), (inset, h // 2)]
        draw.line(q + [q[0]], fill=color, width=width, joint="curve")
        inset += width
    # A thin inner gold line, the "illuminated border".
    i2 = inset + 7
    q = [(p + i2 * 0.4, i2), (w - p - i2 * 0.4, i2), (w - 1 - i2, h // 2), (w - p - i2 * 0.4, h - 1 - i2), (p + i2 * 0.4, h - 1 - i2), (i2, h // 2)]
    draw.line(q + [q[0]], fill=(214, 172, 90, 150), width=2, joint="curve")
    if endcap is not None:
        # orn_endcap (seed 22001) is an upright fleur-de-lis: turned to point outward along each tip.
        cap = endcap.rotate(90, expand=True)
        cap_h = int(h * 0.56)
        cap = cap.resize((int(cap.width * cap_h / cap.height), cap_h), Image.LANCZOS)
        img.alpha_composite(cap, (4, (h - cap_h) // 2))
        right = ImageOps.mirror(cap)
        img.alpha_composite(right, (w - right.width - 4, (h - cap_h) // 2))
    return img, p


def ribbon(texture, size, brightness=1.0):
    """A swallowtail banner (notched ends) for labels such as map region names."""
    w, h = size
    n = int(h * 0.38)
    poly = [(0, 0), (w - 1, 0), (w - 1 - n, h // 2), (w - 1, h - 1), (0, h - 1), (n, h // 2)]
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).polygon(poly, fill=255)
    img = fill(texture, size, brightness, 255)
    img.putalpha(mask)
    draw = ImageDraw.Draw(img)
    draw.line(poly + [poly[0]], fill=GOLD, width=4, joint="curve")
    draw.line([(n + 10, 7), (w - n - 10, 7)], fill=(232, 196, 112, 170), width=2)
    draw.line([(n + 10, h - 8), (w - n - 10, h - 8)], fill=(232, 196, 112, 170), width=2)
    return img, n


def save(img, name, kit, margin, content):
    os.makedirs(OUT, exist_ok=True)
    img.save(os.path.join(OUT, name + ".png"))
    kit[name] = {"texture_margin": margin, "content_margin": content, "size": list(img.size)}


def main():
    parchment, navy, violet = load("tex_parchment"), load("tex_navy_enamel"), load("tex_violet_enamel")
    # Deep violet, not electric purple (docs/ART_DIRECTION.md palette).
    violet = ImageEnhance.Brightness(ImageEnhance.Color(violet).enhance(0.62)).enhance(0.72)
    corner = load("orn_corner")
    # The generator drew a whole symmetric frame for orn_corner (seed 20301); its top-left quarter is
    # the corner flourish we need (the other quarters are mirror images of it).
    corner = corner.crop((0, 0, int(corner.width * 0.43), int(corner.height * 0.41)))
    kit = {"_comment": "Generated by scripts/tools/compose_ui_kit.py. texture_margin / content_margin are [left, top, right, bottom] in texture pixels."}
    # Parchment plaques (navigation cards, information panels).
    plaque = piece(parchment, (480, 192), 18, corner, 58)
    save(plaque, "plaque_parchment", kit, [60, 60, 60, 60], [26, 18, 26, 18])
    hover = ImageEnhance.Brightness(piece(parchment, (480, 192), 18, corner, 58, rim=(GOLD, GOLD_LIGHT, (255, 246, 214, 255)), rim_widths=(3, 3, 2))).enhance(1.02)
    save(hover, "plaque_parchment_hover", kit, [60, 60, 60, 60], [26, 18, 26, 18])
    pressed = ImageEnhance.Brightness(plaque).enhance(0.86)
    save(pressed, "plaque_parchment_pressed", kit, [60, 60, 60, 60], [26, 18, 26, 18])
    locked = ImageEnhance.Brightness(ImageEnhance.Color(plaque).enhance(0.35)).enhance(0.5)
    save(locked, "plaque_locked", kit, [60, 60, 60, 60], [26, 18, 26, 18])
    # Navy enamel panels (dark panels over art, dialogs, the status ribbon).
    save(piece(navy, (480, 240), 16, corner, 50, alpha=236, shade=70), "panel_navy", kit, [52, 52, 52, 52], [24, 18, 24, 18])
    save(piece(navy, (320, 120), 10, corner, 30, alpha=230, rim_widths=(2, 2, 1), shade=60), "panel_navy_small", kit, [34, 34, 34, 34], [16, 10, 16, 10])
    # Buttons: violet primary, navy secondary; states by tone.
    for name, texture in (("button_violet", violet), ("button_navy", navy)):
        base = piece(texture, (360, 104), 22, corner, 34, rim_widths=(3, 3, 1), shade=60)
        save(base, name, kit, [40, 36, 40, 36], [16, 8, 16, 8])
        save(ImageEnhance.Brightness(piece(texture, (360, 104), 22, corner, 34, rim=(GOLD, GOLD_LIGHT, (255, 246, 214, 255)), rim_widths=(3, 3, 2), shade=50)).enhance(1.18), name + "_hover", kit, [40, 36, 40, 36], [16, 8, 16, 8])
        save(ImageEnhance.Brightness(base).enhance(0.78), name + "_pressed", kit, [40, 36, 40, 36], [16, 10, 16, 6])
        save(ImageEnhance.Brightness(ImageEnhance.Color(base).enhance(0.1)).enhance(0.6), name + "_disabled", kit, [40, 36, 40, 36], [16, 8, 16, 8])
    # Pointed JRPG buttons (menu and primary actions) and ribbon banners, when the end cap exists.
    endcap_path = os.path.join(SRC, "orn_endcap.png")
    endcap = Image.open(endcap_path).convert("RGBA") if os.path.exists(endcap_path) else None
    for name, texture in (("btn_primary", violet), ("btn_secondary", navy)):
        size = (760, 150)
        base, p = pointed(texture, size, endcap)
        margin = [p + 58, 44, p + 58, 44]
        content = [54, 8, 54, 8]  # clears the pointed tip and its end-cap ornament (texture margin 121 x 0.5)
        save(base, name, kit, margin, content)
        hover, _ = pointed(texture, size, endcap, gloss=0.3, rim=(GOLD, GOLD_LIGHT, (255, 246, 214, 255)), brightness=1.18)
        save(hover, name + "_hover", kit, margin, content)
        save(ImageEnhance.Brightness(base).enhance(0.8), name + "_pressed", kit, margin, [content[0], content[1] + 2, content[2], content[3] - 2])
        save(ImageEnhance.Brightness(ImageEnhance.Color(base).enhance(0.12)).enhance(0.55), name + "_disabled", kit, margin, content)
    for name, texture, bright in (("ribbon_navy", navy, 1.0), ("ribbon_violet", violet, 1.0)):
        img, n = ribbon(texture, (520, 84), bright)
        save(img, name, kit, [n + 18, 24, n + 18, 24], [n // 2 + 22, 4, n // 2 + 22, 4])
    with open(os.path.join(OUT, "kit.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(kit, f, indent=1)
    print("composed", len(kit) - 1, "pieces")


if __name__ == "__main__":
    main()
