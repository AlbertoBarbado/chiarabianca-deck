"""Cuts a character pose sheet (a grid of poses on a plain background) into separate transparent
sprites with the local ComfyUI server (BiRefNet background removal), trims them and scales every pose
by ONE common factor so the idle pose matches a target height (the poses keep their relative sizes).

Usage (project root, ComfyUI at http://127.0.0.1:8188):
    python scripts/tools/cut_pose_sheet.py ashveil
"""
import io
import json
import os
import sys
import time
import urllib.request
import uuid

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import comfy_generate as gen  # noqa: E402

from PIL import Image  # noqa: E402

SHEETS = {
    # Owner-provided sheet: 3 x 3 grid, centre cell empty. (column, row) per combat state.
    "ashveil": {
        "sheet": "assets/characters/bianca/ashveil_bianca.jpg",
        "out": "assets/characters/bianca/ashveil",
        "grid": (3, 3),
        "cells": {"idle": (0, 0), "attack": (1, 0), "block": (2, 0), "cast": (2, 1), "hit": (0, 2), "down": (2, 2),
                  "map": (0, 1), "pouch": (1, 2)},
        "target_idle_height": 357,
        "inset": 6,  # pixels trimmed from every cell edge (the sheet's faint grid lines)
    },
}


def _upload(image: Image.Image, name: str) -> str:
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    boundary = uuid.uuid4().hex
    body = (("--%s\r\nContent-Disposition: form-data; name=\"image\"; filename=\"%s\"\r\nContent-Type: image/png\r\n\r\n" % (boundary, name)).encode()
            + buffer.getvalue() + ("\r\n--%s\r\nContent-Disposition: form-data; name=\"overwrite\"\r\n\r\ntrue\r\n--%s--\r\n" % (boundary, boundary)).encode())
    request = urllib.request.Request(gen.SERVER + "/upload/image", data=body, headers={"Content-Type": "multipart/form-data; boundary=" + boundary})
    with urllib.request.urlopen(request, timeout=120) as response:
        return json.loads(response.read())["name"]


def _cutout(image: Image.Image, tag: str) -> Image.Image:
    name = _upload(image.convert("RGB"), "voidfarer_cut_%s.png" % tag)
    workflow = {
        "1": {"class_type": "LoadImage", "inputs": {"image": name}},
        "2": {"class_type": "LoadBackgroundRemovalModel", "inputs": {"bg_removal_name": "birefnet.safetensors"}},
        "3": {"class_type": "RemoveBackground", "inputs": {"bg_removal_model": ["2", 0], "image": ["1", 0]}},
        "4": {"class_type": "InvertMask", "inputs": {"mask": ["3", 0]}},
        "5": {"class_type": "JoinImageWithAlpha", "inputs": {"image": ["1", 0], "alpha": ["4", 0]}},
        "6": {"class_type": "SaveImage", "inputs": {"images": ["5", 0], "filename_prefix": "voidfarer_cut_" + tag}},
    }
    prompt_id = gen._post("/prompt", {"prompt": workflow, "client_id": str(uuid.uuid4())})["prompt_id"]
    started = time.time()
    while True:
        history = json.loads(gen._get("/history/" + prompt_id))
        if prompt_id in history:
            entry = history[prompt_id]
            if entry.get("status", {}).get("status_str") == "error":
                raise RuntimeError("%s failed: %s" % (tag, json.dumps(entry["status"])[:500]))
            out = entry["outputs"]["6"]["images"][0]
            break
        if time.time() - started > 600:
            raise RuntimeError(tag + " timed out")
        time.sleep(1)
    data = gen._get("/view?filename=%s&subfolder=%s&type=%s" % (out["filename"], out["subfolder"], out["type"]))
    return Image.open(io.BytesIO(data)).convert("RGBA")


def _trim(image: Image.Image, pad: int = 4) -> Image.Image:
    box = image.getchannel("A").point(lambda v: 255 if v > 24 else 0).getbbox()
    if not box:
        return image
    return image.crop((max(0, box[0] - pad), max(0, box[1] - pad), min(image.width, box[2] + pad), min(image.height, box[3] + pad)))


def cut(sheet_id: str) -> None:
    spec = SHEETS[sheet_id]
    sheet = Image.open(os.path.join(gen.ROOT, spec["sheet"])).convert("RGB")
    cols, rows = spec["grid"]
    cell_w, cell_h = sheet.width / cols, sheet.height / rows
    inset = spec["inset"]
    sprites = {}
    for state, (col, row) in spec["cells"].items():
        box = (round(col * cell_w) + inset, round(row * cell_h) + inset, round((col + 1) * cell_w) - inset, round((row + 1) * cell_h) - inset)
        sprites[state] = _trim(_cutout(sheet.crop(box), "%s_%s" % (sheet_id, state)))
        print("cut ", state, sprites[state].size)
    factor = spec["target_idle_height"] / sprites["idle"].height
    out_dir = os.path.join(gen.ROOT, spec["out"])
    os.makedirs(out_dir, exist_ok=True)
    for state, sprite in sprites.items():
        size = (max(1, round(sprite.width * factor)), max(1, round(sprite.height * factor)))
        sprite.resize(size, Image.LANCZOS).save(os.path.join(out_dir, state + ".png"))
        print("ok  ", state, size)


if __name__ == "__main__":
    cut(sys.argv[1])
