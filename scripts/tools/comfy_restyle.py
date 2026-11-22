"""Restyles existing character pose sprites with the local ComfyUI server (FLUX image-to-image), so a
specialization can have its own look while keeping the character's pose, face and proportions.

Usage (project root, ComfyUI at http://127.0.0.1:8188):
    python scripts/tools/comfy_restyle.py ashveil            # restyle every pose of the set
    python scripts/tools/comfy_restyle.py ashveil --only idle --denoise 0.6 --seed 7

Each source pose is centred on a light grey square, encoded, re-sampled at `denoise` (lower keeps
more of the original), cut out again with BiRefNet, trimmed and scaled back to the source sprite's
height so the game's pose sizes do not change. Prompts, seeds and denoise are logged next to the
output in generation_log.json (same format as comfy_generate.py).
"""
import io
import json
import os
import sys
import time
import urllib.request
import uuid

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import comfy_generate as gen  # noqa: E402  (shares the server, model and helpers)

from PIL import Image  # noqa: E402

CANVAS = 768
## Ashveil Bianca must look exactly like Bianca: only the red cape changes (to a smoky charcoal
## cloak). The armour, gold trim, face and hair keep every original pixel.
CAPE_ONLY = True


def _smooth(edge0: float, edge1: float, x: float) -> float:
    t = max(0.0, min(1.0, (x - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


def ashveil_recolor(image: Image.Image) -> Image.Image:
    """Deterministic first pass for Ashveil: silver plate -> blackened steel, red cape -> smoky grey
    cloak, gold trim -> ember orange. Skin and the black hair are protected. Soft weights, so the
    image-to-image pass only has to blend the shading (FLUX alone kept the old colours)."""
    import colorsys
    from PIL import ImageFilter
    image = image.convert("RGBA")
    px = image.load()
    target = Image.new("RGBA", image.size)
    tpx = target.load()
    mask = Image.new("L", image.size, 0)
    mpx = mask.load()
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            hd = h * 360.0
            # Skin: warm, moderately saturated and bright. Armour highlights are paler (s < 0.2).
            skin = _smooth(6, 12, hd) * (1.0 - _smooth(38, 46, hd)) * _smooth(0.2, 0.28, s) * (1.0 - _smooth(0.62, 0.72, s)) * _smooth(0.5, 0.62, v)
            red_dist = min(hd, 360.0 - hd)
            # The cape is saturated crimson to magenta (hue 295-360 / 0-8, saturation > 0.5). Her pink-toned
            # skin shares that hue but stays at saturation <= 0.45, and the hair is blue-black: both untouched.
            cape_hue = max(_smooth(290, 302, hd), 1.0 - _smooth(6, 12, hd)) if (hd >= 280 or hd <= 12) else 0.0
            cape = cape_hue * _smooth(0.46, 0.58, s) * _smooth(0.08, 0.14, v) * (1.0 - skin)
            gold = _smooth(28, 36, hd) * (1.0 - _smooth(58, 66, hd)) * _smooth(0.3, 0.42, s) * _smooth(0.35, 0.45, v)
            silver = (1.0 - _smooth(0.2, 0.32, s)) * _smooth(0.28, 0.4, v) * (1.0 - skin)
            if CAPE_ONLY:
                gold = 0.0
                silver = 0.0
            weight, colour = max((cape, "cape"), (gold, "gold"), (silver, "silver"))
            if weight <= 0.01:
                continue
            if colour == "cape":
                tr, tg, tb = colorsys.hsv_to_rgb(0.07, 0.12, 0.09 + v * 0.36)
            elif colour == "gold":
                tr, tg, tb = colorsys.hsv_to_rgb(22 / 360.0, min(1.0, s * 1.2), min(1.0, v * 1.05))
            else:
                tr, tg, tb = colorsys.hsv_to_rgb(0.6, 0.12, 0.07 + max(0.0, v - 0.28) * 0.5)
            tpx[x, y] = (round(tr * 255), round(tg * 255), round(tb * 255), a)
            mpx[x, y] = round(weight * 255)
    # A slightly blurred mask removes the speckle a per-pixel colour test leaves on shiny metal.
    target = target.filter(ImageFilter.GaussianBlur(0.6))
    mask = mask.filter(ImageFilter.GaussianBlur(1.2))
    blended = Image.composite(target, image, mask)
    blended.putalpha(image.getchannel("A"))
    return blended


SETS = {
    "ashveil": {
        "source": "assets/characters/bianca/recut",
        "out": "assets/generated/ashveil/bianca",
        "poses": ["idle", "attack", "strike", "block", "guard", "down"],
        "prompt": ("the same anime knight princess with long black hair and brown eyes in the same pose, now wearing dark charcoal "
                   "and blackened steel plate armour with glowing ember-orange trim, a hooded smoky grey cloak instead of the red "
                   "cape, leather belts with small glass oil flasks and powder pouches, a dark steel sword, rogue knight, "
                   "isolated on a plain flat light grey background, full body, " + gen.STYLE),
        # 0 = recolour only. FLUX image-to-image (tried at 0.62, 0.45 and 0.3) changed her face and
        # hair colour before it changed the armour, so the deterministic recolour is the final look.
        "denoise": 0.0,
        "seed": 7101,
        "prepare": ashveil_recolor,
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


def _workflow(image_name: str, prompt: str, seed: int, denoise: float, prefix: str) -> dict:
    return {
        "1": {"class_type": "UnetLoaderGGUF", "inputs": {"unet_name": gen.MODEL["unet"]}},
        "2": {"class_type": "DualCLIPLoaderGGUF", "inputs": {"clip_name1": gen.MODEL["clip_l"], "clip_name2": gen.MODEL["t5"], "type": "flux"}},
        "3": {"class_type": "VAELoader", "inputs": {"vae_name": gen.MODEL["vae"]}},
        "4": {"class_type": "CLIPTextEncode", "inputs": {"text": prompt, "clip": ["2", 0]}},
        "5": {"class_type": "CLIPTextEncode", "inputs": {"text": "", "clip": ["2", 0]}},
        "6": {"class_type": "LoadImage", "inputs": {"image": image_name}},
        "14": {"class_type": "VAEEncode", "inputs": {"pixels": ["6", 0], "vae": ["3", 0]}},
        "7": {"class_type": "KSampler", "inputs": {"model": ["1", 0], "seed": seed, "steps": 4, "cfg": 1.0, "sampler_name": "euler",
                                                   "scheduler": "simple", "positive": ["4", 0], "negative": ["5", 0],
                                                   "latent_image": ["14", 0], "denoise": denoise}},
        "8": {"class_type": "VAEDecode", "inputs": {"samples": ["7", 0], "vae": ["3", 0]}},
        "9": {"class_type": "LoadBackgroundRemovalModel", "inputs": {"bg_removal_name": "birefnet.safetensors"}},
        "10": {"class_type": "RemoveBackground", "inputs": {"bg_removal_model": ["9", 0], "image": ["8", 0]}},
        "11": {"class_type": "InvertMask", "inputs": {"mask": ["10", 0]}},
        "12": {"class_type": "JoinImageWithAlpha", "inputs": {"image": ["8", 0], "alpha": ["11", 0]}},
        "13": {"class_type": "SaveImage", "inputs": {"images": ["12", 0], "filename_prefix": prefix}},
    }


def restyle(set_id: str, pose: str, seed: int, denoise: float) -> None:
    spec = SETS[set_id]
    source = Image.open(os.path.join(gen.ROOT, spec["source"], pose + ".png")).convert("RGBA")
    prepared = spec["prepare"](source) if "prepare" in spec else source
    if denoise <= 0.0:
        out_dir = os.path.join(gen.ROOT, spec["out"])
        os.makedirs(out_dir, exist_ok=True)
        prepared.save(os.path.join(out_dir, pose + ".png"))
        gen._log(pose, "recolour only (%s) of res://%s/%s.png" % (spec["prepare"].__name__, spec["source"], pose), source.width, source.height,
                 0, False, 0.0, out_dir, spec["out"].replace("assets/generated/", ""))
        print("ok  ", set_id, pose, "(recolour)")
        return
    scale =(CANVAS * 0.86) / max(source.width, source.height)
    big = prepared.resize((round(source.width * scale), round(source.height * scale)), Image.LANCZOS)
    canvas = Image.new("RGBA", (CANVAS, CANVAS), (214, 214, 214, 255))
    canvas.alpha_composite(big, ((CANVAS - big.width) // 2, (CANVAS - big.height) // 2))
    name = _upload(canvas.convert("RGB"), "voidfarer_%s_%s_src.png" % (set_id, pose))
    started = time.time()
    queued = gen._post("/prompt", {"prompt": _workflow(name, spec["prompt"], seed, denoise, "voidfarer_%s_%s" % (set_id, pose)), "client_id": str(uuid.uuid4())})
    prompt_id = queued["prompt_id"]
    while True:
        history = json.loads(gen._get("/history/" + prompt_id))
        if prompt_id in history:
            entry = history[prompt_id]
            if entry.get("status", {}).get("status_str") == "error":
                raise RuntimeError("%s/%s failed: %s" % (set_id, pose, json.dumps(entry["status"])[:600]))
            image = entry["outputs"]["13"]["images"][0]
            break
        if time.time() - started > 1800:
            raise RuntimeError("timed out")
        time.sleep(2)
    data = gen._get("/view?filename=%s&subfolder=%s&type=%s" % (image["filename"], image["subfolder"], image["type"]))
    out_dir = os.path.join(gen.ROOT, spec["out"])
    os.makedirs(out_dir, exist_ok=True)
    target = os.path.join(out_dir, pose + ".png")
    with open(target, "wb") as f:
        f.write(data)
    gen._trim(target)
    # Back to the source sprite's height, so the game's pose boxes keep their size.
    result = Image.open(target).convert("RGBA")
    factor = source.height / result.height
    result.resize((max(1, round(result.width * factor)), source.height), Image.LANCZOS).save(target)
    folder = spec["out"].replace("assets/generated/", "")
    gen._log(pose, spec["prompt"] + " [img2img from res://%s/%s.png%s, denoise %.2f]" % (spec["source"], pose, " after " + spec["prepare"].__name__ if "prepare" in spec else "", denoise),
             CANVAS, CANVAS, seed, True, time.time() - started, out_dir, folder)
    print("ok  ", set_id, pose, "%.0fs" % (time.time() - started))


if __name__ == "__main__":
    set_id = sys.argv[1]
    only = sys.argv[sys.argv.index("--only") + 1] if "--only" in sys.argv else None
    denoise = float(sys.argv[sys.argv.index("--denoise") + 1]) if "--denoise" in sys.argv else SETS[set_id]["denoise"]
    seed = int(sys.argv[sys.argv.index("--seed") + 1]) if "--seed" in sys.argv else SETS[set_id]["seed"]
    for pose in SETS[set_id]["poses"]:
        if only is None or pose == only:
            restyle(set_id, pose, seed, denoise)
