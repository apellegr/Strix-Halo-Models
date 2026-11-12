#!/usr/bin/env python3
"""Build a small synthetic vision test set with known answers: OUT_DIR/*.png + cases.json.
usage: make_vision_set.py OUT_DIR
Needs Pillow + DejaVu fonts (set FONT_DIR to override). localai has no Pillow: generate elsewhere, copy OUT_DIR over."""
import json, os, random, sys
from PIL import Image, ImageDraw, ImageFont
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
FONT_DIR = os.environ.get("FONT_DIR", "/usr/share/fonts/truetype/dejavu")  # needs DejaVu Sans (fonts-dejavu-core)
F, FB = f"{FONT_DIR}/DejaVuSans.ttf", f"{FONT_DIR}/DejaVuSans-Bold.ttf"
def font(sz, b=False): return ImageFont.truetype(FB if b else F, sz)
cases = []

# 1 receipt OCR
im = Image.new("RGB", (520, 640), "white"); d = ImageDraw.Draw(im)
lines = [("H-E-B #417  AUSTIN TX", True), ("11/09/2026  14:32", False), ("", False),
         ("MILK 2% GAL            3.48", False), ("BANANAS 2.1 LB         1.26", False), ("CHICKEN THIGHS        11.92", False),
         ("SOURDOUGH LOAF         4.99", False), ("BIRTHDAY CANDLES       2.50", False), ("COFFEE BEANS 12OZ     14.99", False),
         ("", False), ("SUBTOTAL              39.14", False), ("TAX                    3.03", False), ("TOTAL                $42.17", True)]
y = 30
for t, b in lines: d.text((30, y), t, fill="black", font=font(24, b)); y += 42
im.save(f"{out}/receipt.png")
cases.append({"img": "receipt.png", "q": "What is the TOTAL on this receipt, and which store is it from? Answer in one short line.", "expect": [["42.17"], ["h-e-b", "heb"]]})

# 2 counting
im = Image.new("RGB", (640, 480), "white"); d = ImageDraw.Draw(im); rnd = random.Random(7)
pts = [(90, 100), (300, 80), (520, 120), (160, 300), (380, 260), (560, 380), (250, 410)]
for x, yy in pts: d.ellipse((x-35, yy-35, x+35, yy+35), fill=rnd.choice(["#d33", "#36c", "#2a2", "#e90"]))
im.save(f"{out}/count.png")
cases.append({"img": "count.png", "q": "How many circles are in this image? Answer with just the number.", "expect": [["7", "seven"]]})

# 3 bar chart
im = Image.new("RGB", (640, 440), "white"); d = ImageDraw.Draw(im)
vals = {"Mon": 12, "Tue": 18, "Wed": 9, "Thu": 27, "Fri": 15}
d.text((180, 15), "Steps (thousands) per day", fill="black", font=font(22, True))
for i, (k, v) in enumerate(vals.items()):
    x = 70 + i * 110; d.rectangle((x, 380 - v * 11, x + 70, 380), fill="#4a7bd0")
    d.text((x + 12, 390), k, fill="black", font=font(20)); d.text((x + 20, 380 - v * 11 - 28), str(v), fill="black", font=font(18))
d.line((50, 380, 620, 380), fill="black", width=2)
im.save(f"{out}/chart.png")
cases.append({"img": "chart.png", "q": "Which day has the highest value in this chart, and what is that value?", "expect": [["thu"], ["27"]]})

# 4 sign
im = Image.new("RGB", (560, 360), "#c22"); d = ImageDraw.Draw(im)
d.rectangle((15, 15, 545, 345), outline="white", width=8)
d.text((95, 60), "NO PARKING", fill="white", font=font(60, True))
d.text((105, 160), "8 AM - 6 PM", fill="white", font=font(48, True))
d.text((85, 250), "MON - FRI  TOW AWAY ZONE", fill="white", font=font(28))
im.save(f"{out}/sign.png")
cases.append({"img": "sign.png", "q": "Can I park here on Saturday at noon according to this sign? Answer yes or no, then one sentence why.", "expect": [["yes"]]})

# 5 schedule table
im = Image.new("RGB", (700, 330), "white"); d = ImageDraw.Draw(im)
rows = [("Day", "Activity", "Time"), ("Tue", "Piano - Mia", "4:15 PM"), ("Wed", "Swim - Leo", "5:30 PM"),
        ("Sat", "Soccer - Mia", "9:45 AM"), ("Sun", "Grandma lunch", "12:30 PM")]
for r, row in enumerate(rows):
    for c, cell in enumerate(row):
        x0, y0 = 20 + c * 220, 20 + r * 58; d.rectangle((x0, y0, x0 + 220, y0 + 58), outline="black", width=2)
        d.text((x0 + 12, y0 + 15), cell, fill="black", font=font(24, r == 0))
im.save(f"{out}/schedule.png")
cases.append({"img": "schedule.png", "q": "From this schedule: what time is Mia's soccer, and on which day?", "expect": [["9:45"], ["sat"]]})

# 6 quadrants
im = Image.new("RGB", (200, 200)); d = ImageDraw.Draw(im)
for (x, y), col in zip([(0, 0), (100, 0), (0, 100), (100, 100)], ["red", "blue", "green", "yellow"]):
    d.rectangle((x, y, x + 99, y + 99), fill=col)
im.save(f"{out}/quadrants.png")
cases.append({"img": "quadrants.png", "q": "Name the color of each quadrant: top-left, top-right, bottom-left, bottom-right.", "expect": [["red"], ["blue"], ["green"], ["yellow"]]})

json.dump(cases, open(f"{out}/cases.json", "w"), indent=1); print(len(cases), "cases")
