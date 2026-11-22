"""Redraws a small character cutout at a higher resolution with the local ComfyUI server, keeping
its look: the cutout is enlarged (Lanczos) on a light grey canvas, then FLUX image-to-image at a low
denoise adds real detail at the new size (sharp edges and lines instead of blurry pixels), and
BiRefNet cuts it out again. No upscaler model is needed.

Usage (project root, ComfyUI at http://127.0.0.1:8188):
    python scripts/tools/comfy_upscale.py bianca_paladin
    python scripts/tools/comfy_upscale.py bianca_ashveil --denoise 0.2 --seed 9

Output goes to assets/generated/figures/<id>.png; prompts, seeds and denoise are logged in
assets/generated/figures/generation_log.json. Sources are never changed.
"""
import json
import os
import sys
import time
import uuid

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import comfy_generate as gen  # noqa: E402
import comfy_restyle as restyle  # noqa: E402  (upload + img2img workflow)

from PIL import Image  # noqa: E402

FOLDER = "figures"
JOBS = {
    # Holy / Tanking (the base paladin look): the figure of the character screens.
    "bianca_paladin": {
        "source": "assets/ui/processed/bianca_cutout.png",
        "height": 1216,
        "prompt": "anime knight princess with long black hair and brown eyes, silver plate armour with gold trim and a red cape, "
                  "full body, crisp clean line art, sharp details, isolated on a plain flat light grey background, " + gen.STYLE,
    },
    # Ashveil and Venom: the hooded rogue-knight look (cut from the owner-provided Ashveil sheet).
    "bianca_ashveil": {
        "source": "assets/characters/bianca/ashveil/idle.png",
        "height": 1280,
        "prompt": "anime rogue knight princess with long black hair, dark hood with red trim, charcoal cloak, leather straps and "
                  "a travel backpack, a short sword, full body, crisp clean line art, sharp details, isolated on a plain flat "
                  "light grey background, " + gen.STYLE,
    },
}
DEFAULT_DENOISE = 0.25
PAD = 0.06  # grey margin around the figure (fraction of the canvas)


def upscale(job_id: str, seed: int, denoise: float) -> None:
    job = JOBS[job_id]
    source = Image.open(os.path.join(gen.ROOT, job["source"])).convert("RGBA")
    box = source.getbbox()
    source = source.crop(box)
    height = job["height"]
    width = round(source.width * height / source.height)
    # Canvas sides are multiples of 64 (the latent grid), with a margin all around.
    canvas_h = ((round(height * (1 + 2 * PAD)) + 63) // 64) * 64
    canvas_w = ((round(width + height * 2 * PAD) + 63) // 64) * 64
    big = source.resize((width, height), Image.LANCZOS)
    canvas = Image.new("RGBA", (canvas_w, canvas_h), (214, 214, 214, 255))
    canvas.alpha_composite(big, ((canvas_w - width) // 2, (canvas_h - height) // 2))
    name = restyle._upload(canvas.convert("RGB"), "voidfarer_upscale_%s_src.png" % job_id)
    started = time.time()
    queued = gen._post("/prompt", {"prompt": restyle._workflow(name, job["prompt"], seed, denoise, "voidfarer_upscale_" + job_id), "client_id": str(uuid.uuid4())})
    prompt_id = queued["prompt_id"]
    while True:
        history = json.loads(gen._get("/history/" + prompt_id))
        if prompt_id in history:
            entry = history[prompt_id]
            if entry.get("status", {}).get("status_str") == "error":
                raise RuntimeError("%s failed: %s" % (job_id, json.dumps(entry["status"])[:600]))
            image = entry["outputs"]["13"]["images"][0]
            break
        if time.time() - started > 3600:
            raise RuntimeError("timed out")
        time.sleep(3)
    data = gen._get("/view?filename=%s&subfolder=%s&type=%s" % (image["filename"], image["subfolder"], image["type"]))
    out_dir = os.path.join(gen.ROOT, "assets", "generated", FOLDER)
    os.makedirs(out_dir, exist_ok=True)
    target = os.path.join(out_dir, job_id + ".png")
    with open(target, "wb") as f:
        f.write(data)
    gen._trim(target)
    gen._log(job_id, job["prompt"] + " [img2img upscale of res://%s to %d px tall, denoise %.2f]" % (job["source"], height, denoise),
             canvas_w, canvas_h, seed, True, time.time() - started, out_dir, FOLDER)
    print("ok  ", job_id, Image.open(target).size, "%.0fs" % (time.time() - started))


if __name__ == "__main__":
    denoise = float(sys.argv[sys.argv.index("--denoise") + 1]) if "--denoise" in sys.argv else DEFAULT_DENOISE
    seed = int(sys.argv[sys.argv.index("--seed") + 1]) if "--seed" in sys.argv else 9301
    for job_id in sys.argv[1:]:
        if job_id in JOBS:
            upscale(job_id, seed, denoise)
