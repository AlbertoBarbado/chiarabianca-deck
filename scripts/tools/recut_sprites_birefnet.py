"""Re-cuts every combat pose from its original sheet with BiRefNet (local ComfyUI), replacing the old
colour flood fill that left checkerboard fragments around slashes, shields and dust, and ate dark
leggings or fur that matched the sheet background.

Usage (project root, ComfyUI running at http://127.0.0.1:8188 with models/background_removal/birefnet.safetensors):
    python scripts/tools/recut_sprites_birefnet.py              # every pose
    python scripts/tools/recut_sprites_birefnet.py wolf chiara  # only sheets whose key contains these words

Pose boxes come from extract_forest_sprites.py / extract_combat_sprites.py (same cells as before).
Output: <sheet folder>/recut/<name>.png (the old processed/ files are kept for comparison) and
assets/recut_manifest.json. Originals are never modified.

Clean-up after the mask: tiny detached islands (debris, leftover squares) are dropped, and edge
pixels are pulled toward the colour of their solid neighbours so no grey checker fringe remains.
"""
import io
import json
import os
import sys
import time
import urllib.request
import uuid

sys.path.insert(0, os.path.dirname(__file__))
import numpy as np  # noqa: E402
from PIL import Image, ImageFilter  # noqa: E402
from scipy import ndimage  # noqa: E402

import extract_combat_sprites as combat  # noqa: E402
import extract_forest_sprites as forest  # noqa: E402

SERVER = "http://127.0.0.1:8188"
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def jobs():
    """(key, sheet path, box, output folder, name) for every pose used in combat."""
    out = []
    for enemy in forest.ENEMIES:
        sheet = os.path.join(forest.FOREST, enemy + ".jpg")
        w, h = Image.open(sheet).size
        cw, chh = w // 3, h // 2
        for row in range(2):
            for col in range(3):
                box = (col * cw, row * chh + forest.CAPTION, (col + 1) * cw, (row + 1) * chh)
                out.append((enemy, sheet, box, os.path.join(forest.FOREST, "recut"), "%s_%s" % (enemy, forest.POSES[row][col])))
    for key, sheet_name, boxes in (("knight_generic", "knight_generic.jpg", combat.KNIGHT_GENERIC),
                                   ("knight_captain", "knight_captain.jpg", combat.KNIGHT_CAPTAIN)):
        for pose, box in boxes.items():
            out.append((key, os.path.join(combat.EN, sheet_name), box, os.path.join(combat.EN, "recut"), "%s_%s" % (key, pose)))
    for key, boxes in (("chiara", combat.CHIARA), ("bianca", combat.BIANCA)):
        for pose, box in boxes.items():
            out.append((key, os.path.join(combat.CH, key, "basic.jpg"), box, os.path.join(combat.CH, key, "recut"), pose))
    return out


def _upload(image):
    buffer = io.BytesIO()
    image.save(buffer, "PNG")
    boundary = uuid.uuid4().hex
    name = "voidfarer_recut_%s.png" % uuid.uuid4().hex[:10]
    body = (("--%s\r\nContent-Disposition: form-data; name=\"image\"; filename=\"%s\"\r\nContent-Type: image/png\r\n\r\n" % (boundary, name)).encode()
            + buffer.getvalue() + ("\r\n--%s\r\nContent-Disposition: form-data; name=\"overwrite\"\r\n\r\ntrue\r\n--%s--\r\n" % (boundary, boundary)).encode())
    request = urllib.request.Request(SERVER + "/upload/image", data=body, headers={"Content-Type": "multipart/form-data; boundary=" + boundary})
    with urllib.request.urlopen(request, timeout=120) as response:
        return json.loads(response.read())["name"]


def _mask(image):
    """BiRefNet foreground mask (0..255, same size as `image`)."""
    uploaded = _upload(image)
    workflow = {
        "1": {"class_type": "LoadImage", "inputs": {"image": uploaded}},
        "2": {"class_type": "LoadBackgroundRemovalModel", "inputs": {"bg_removal_name": "birefnet.safetensors"}},
        "3": {"class_type": "RemoveBackground", "inputs": {"bg_removal_model": ["2", 0], "image": ["1", 0]}},
        "4": {"class_type": "InvertMask", "inputs": {"mask": ["3", 0]}},
        "5": {"class_type": "JoinImageWithAlpha", "inputs": {"image": ["1", 0], "alpha": ["4", 0]}},
        "6": {"class_type": "SaveImage", "inputs": {"images": ["5", 0], "filename_prefix": "voidfarer_recut"}},
    }
    request = urllib.request.Request(SERVER + "/prompt", data=json.dumps({"prompt": workflow, "client_id": str(uuid.uuid4())}).encode(), headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=120) as response:
        prompt_id = json.loads(response.read())["prompt_id"]
    started = time.time()
    while True:
        with urllib.request.urlopen(SERVER + "/history/" + prompt_id, timeout=60) as response:
            history = json.loads(response.read())
        if prompt_id in history:
            entry = history[prompt_id]
            if entry.get("status", {}).get("status_str") == "error":
                raise RuntimeError(json.dumps(entry["status"])[:500])
            info = entry["outputs"]["6"]["images"][0]
            break
        if time.time() - started > 600:
            raise RuntimeError("timed out")
        time.sleep(1)
    url = SERVER + "/view?filename=%s&subfolder=%s&type=%s" % (info["filename"], info["subfolder"], info["type"])
    with urllib.request.urlopen(url, timeout=120) as response:
        result = Image.open(io.BytesIO(response.read())).convert("RGBA")
    return np.array(result)[:, :, 3]


def clean(rgb, alpha, min_island=0.02):
    """Drops detached islands smaller than `min_island` of the main body, hardens the matte and
    replaces fringe colours (half-transparent pixels mixed with the old background) by the colour of
    the nearest solid pixel, so the sprite never shows a grey or white halo on dark scenery."""
    alpha = alpha.astype(np.float32)
    solid = alpha > 127
    labels, count = ndimage.label(solid)
    if count > 1:
        sizes = ndimage.sum(solid, labels, range(1, count + 1))
        keep = np.zeros(count + 1, bool)
        keep[1:] = sizes >= sizes.max() * min_island
        body = keep[labels]
        # soft pixels belong to the body only when they touch it
        near = ndimage.binary_dilation(body, iterations=3)
        alpha = np.where(near, alpha, 0.0)
        alpha = np.where(solid & ~body, 0.0, alpha)
    # Matte: steeper ramp (no ghost veils), keep a 1-2 px soft edge.
    alpha = np.clip((alpha - 40.0) * (255.0 / 175.0), 0, 255)
    fully = alpha >= 250
    if fully.any():
        _, (iy, ix) = ndimage.distance_transform_edt(~fully, return_indices=True)
        fringe = (alpha > 0) & ~fully
        rgb = rgb.copy()
        rgb[fringe] = rgb[iy[fringe], ix[fringe]]
    out = np.dstack([rgb, alpha.astype(np.uint8)])
    return Image.fromarray(out.astype(np.uint8), "RGBA")


def trim(image, pad=6):
    box = image.getchannel("A").point(lambda v: 255 if v > 16 else 0).getbbox()
    if not box:
        return image
    return image.crop((max(0, box[0] - pad), max(0, box[1] - pad), min(image.width, box[2] + pad), min(image.height, box[3] + pad)))


def main():
    wanted = [a for a in sys.argv[1:] if not a.startswith("--")]
    manifest = []
    for key, sheet, box, folder, name in jobs():
        if wanted and not any(w in key for w in wanted):
            continue
        crop = Image.open(sheet).convert("RGB").crop(box)
        alpha = _mask(crop)
        sprite = trim(clean(np.array(crop), alpha))
        os.makedirs(folder, exist_ok=True)
        path = os.path.join(folder, name + ".png")
        sprite.save(path)
        rel = os.path.relpath(path, ROOT).replace("\\", "/")
        manifest.append({"id": name, "path": "res://" + rel, "source": os.path.relpath(sheet, ROOT).replace("\\", "/"), "box": list(box), "size": list(sprite.size)})
        print("%-28s %4dx%-4d" % (key + "/" + name, sprite.size[0], sprite.size[1]))
    path = os.path.join(ROOT, "assets", "recut_manifest.json")
    old = json.load(open(path, encoding="utf-8"))["assets"] if os.path.exists(path) else []
    ids = {m["path"] for m in manifest}
    merged = [m for m in old if m["path"] not in ids] + manifest
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump({"_comment": "Generated by scripts/tools/recut_sprites_birefnet.py (BiRefNet, MIT, run locally in ComfyUI). Sources are owner-supplied generated art: NOT release-cleared.", "assets": merged}, f, indent=1)


if __name__ == "__main__":
    main()
