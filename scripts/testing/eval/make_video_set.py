#!/usr/bin/env python3
"""Build a small synthetic VIDEO test set with known answers: OUT_DIR/*.mp4 + cases.json.
Each clip needs temporal understanding (order, direction, before/after), not just one frame.
usage: make_video_set.py OUT_DIR
Needs Pillow, DejaVu fonts (FONT_DIR to override) and ffmpeg on PATH."""
import json, os, subprocess, sys, tempfile
from PIL import Image, ImageDraw, ImageFont

out = sys.argv[1]; os.makedirs(out, exist_ok=True)
FONT_DIR = os.environ.get("FONT_DIR", "/usr/share/fonts/truetype/dejavu")
def font(sz, b=False): return ImageFont.truetype(f"{FONT_DIR}/DejaVuSans{'-Bold' if b else ''}.ttf", sz)
W, H, FPS = 640, 360, 8

def encode(name, frames):
    with tempfile.TemporaryDirectory() as td:
        for i, im in enumerate(frames): im.save(f"{td}/f{i:04d}.png")
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-framerate", str(FPS), "-i", f"{td}/f%04d.png",
                        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "23", f"{out}/{name}"], check=True)

def hold(im, seconds): return [im.copy() for _ in range(int(seconds * FPS))]
cases = []

# 1 direction of motion
frames = []
for i in range(5 * FPS):
    im = Image.new("RGB", (W, H), "#dfe8df"); d = ImageDraw.Draw(im)
    x = 60 + (W - 120) * i / (5 * FPS - 1); d.ellipse((x - 30, 150, x + 30, 210), fill="#d22")
    frames.append(im)
encode("direction.mp4", frames)
cases.append({"video": "direction.mp4", "q": "In which direction does the red ball move: left to right, or right to left? Answer briefly.",
              "expect": [["left to right"]], "reject": ["right to left"]})

# 2 order of numbers shown
frames = []
for n in ["3", "8", "1"]:
    im = Image.new("RGB", (W, H), "white"); ImageDraw.Draw(im).text((270, 70), n, fill="black", font=font(200, True))
    frames += hold(im, 2)
encode("sequence.mp4", frames)
cases.append({"video": "sequence.mp4", "q": "This video shows several digits one after another. List them in the order they appear.",
              "expect": [["3, 8, 1", "3,8,1", "3 8 1", "3 → 8 → 1", "3, then 8, then 1", "381", "3 -> 8 -> 1"]]})

# 3 doorstep: a package appears on the porch partway through, a person arrives then leaves
def porch(person=False, package=False):
    im = Image.new("RGB", (W, H), "#9cc3e6"); d = ImageDraw.Draw(im)
    d.rectangle((0, 260, W, H), fill="#b0a089"); d.rectangle((260, 60, 380, 260), fill="#7a4b2a")  # floor + door
    d.ellipse((355, 160, 365, 170), fill="#e8c34a")
    if person:
        d.ellipse((120, 90, 170, 140), fill="#f0c9a0"); d.rectangle((115, 140, 175, 250), fill="#2b5fab")
        d.text((95, 255), "COURIER", fill="black", font=font(18, True))
    if package: d.rectangle((420, 215, 500, 260), fill="#c8995a", outline="black", width=3); d.text((428, 228), "BOX", fill="black", font=font(16, True))
    return im
frames = hold(porch(), 2) + hold(porch(person=True), 2) + hold(porch(person=True, package=True), 2) + hold(porch(package=True), 2)
encode("porch.mp4", frames)
cases.append({"video": "porch.mp4", "q": "This is a front-door camera clip. Describe what happens, in order, in one or two sentences. Is anything left on the porch at the end?",
              "expect": [["package", "box", "parcel", "delivery", "delivered"], ["courier", "person", "someone", "delivery"]]})

# 4 traffic light: which color is shown last
frames = []
for col in ["#2c2", "#eb2", "#d22"]:
    im = Image.new("RGB", (W, H), "#333"); d = ImageDraw.Draw(im); d.rectangle((270, 40, 370, 320), fill="#111")
    for k, c in enumerate(["#d22", "#eb2", "#2c2"]):
        d.ellipse((290, 55 + k * 88, 350, 115 + k * 88), fill=c if c == col else "#3a3a3a")
    frames += hold(im, 2)
encode("light.mp4", frames)
cases.append({"video": "light.mp4", "q": "Watch the traffic light. Which color is it at the very end of the clip, and which color was it at the start?",
              "expect": [["red"], ["green"]]})

json.dump(cases, open(f"{out}/cases.json", "w"), indent=1); print(len(cases), "video cases")
