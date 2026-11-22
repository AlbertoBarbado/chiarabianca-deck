"""Gives the Hall Captain's idle pose the sword he holds in his other poses: the sword is cut from
his block pose, turned to hang point-down from his right fist and drawn behind the figure, so his
gauntlet covers the grip. Usage: python captain_sword.py <project root> <out preview> [--write]"""
import math
import sys
from PIL import Image, ImageDraw

root, preview = sys.argv[1], sys.argv[2]
write = "--write" in sys.argv
rec = root + "/assets/enemies/tutorial/recut/"
block = Image.open(rec + "knight_captain_block.png").convert("RGBA")
idle_path = rec + "knight_captain_idle.png"
idle = Image.open(idle_path).convert("RGBA")

# Sword axis in the block pose: pommel/hilt end and blade tip (pixels).
hilt = (124.0, 134.0)
tip = (6.0, 266.0)
pommel = (128.0, 126.0)
half_width = 13.0


def dist_to_segment(p, a, b):
    ax, ay = a; bx, by = b; px, py = p
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    cx, cy = ax + t * dx, ay + t * dy
    return math.hypot(px - cx, py - cy)


mask = Image.new("L", block.size, 0)
mp = mask.load()
for y in range(block.height):
    for x in range(block.width):
        if dist_to_segment((x, y), pommel, tip) <= half_width and x < 150:
            mp[x, y] = 255
sword = Image.new("RGBA", block.size, (0, 0, 0, 0))
sword.paste(block, (0, 0), mask)
sword = sword.crop(sword.getbbox())
bx0, by0 = block.size  # recompute hilt inside the crop
box = Image.new("RGBA", block.size, (0, 0, 0, 0)); box.paste(block, (0, 0), mask)
l, t, r, b = box.getbbox()
hilt_c = (hilt[0] - l, hilt[1] - t)

# Current blade angle from vertical (tip below-left of the hilt) and the target angle.
cur = math.degrees(math.atan2(-(tip[0] - hilt[0]), tip[1] - hilt[1]))  # positive = leaning left
target = 22.0
rot = target - cur  # PIL rotates counter-clockwise for positive angles
big = Image.new("RGBA", (sword.width * 3, sword.height * 3), (0, 0, 0, 0))
off = (sword.width, sword.height)
big.paste(sword, off)
centre = (hilt_c[0] + off[0], hilt_c[1] + off[1])
rotated = big.rotate(-rot, resample=Image.BICUBIC, center=centre)

fist = (30, 170)  # the captain's right fist in the idle pose
pad_left = 70
canvas = Image.new("RGBA", (idle.width + pad_left, idle.height), (0, 0, 0, 0))
canvas.alpha_composite(rotated, (int(fist[0] + pad_left - centre[0]), int(fist[1] - centre[1])))
canvas.alpha_composite(idle, (pad_left, 0))
canvas = canvas.crop(canvas.getbbox())
if canvas.height != idle.height:  # never change the pose height
    canvas = canvas.resize((round(canvas.width * idle.height / canvas.height), idle.height), Image.LANCZOS)

bg = Image.new("RGBA", canvas.size, (40, 45, 60, 255))
bg.alpha_composite(canvas)
bg.resize((canvas.width * 2, canvas.height * 2)).save(preview)
print("size", canvas.size, "rotation", round(rot, 1))
if write:  # a new file: the original idle pose is kept
    out = rec + "knight_captain_idle_sword.png"
    canvas.save(out)
    print("written", out)
