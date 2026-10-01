"""Draws the 1024 px app icon: a route up a street with two cross streets."""

import os
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "MultiNavStudy2", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png")

S = 1024
BLUE = (0x02, 0x3E, 0x8A)
CYAN = (0x48, 0xCA, 0xE4)
RED = (0xC1, 0x12, 0x1F)
YELLOW = (255, 214, 0)
WHITE = (255, 255, 255)

img = Image.new("RGB", (S, S), WHITE)
d = ImageDraw.Draw(img)
road = 120
d.line([(512, 40), (512, 984)], fill=BLUE, width=road)
for y in (330, 690):
    d.line([(130, y), (894, y)], fill=BLUE, width=road)
d.line([(512, 860), (512, 330), (800, 330)], fill=CYAN, width=86, joint="curve")
for y in (330, 690):
    h = 92
    d.rectangle([512 - h, y - h, 512 + h, y + h], fill=RED, outline=WHITE, width=16)
for x, y in ((512, 860), (800, 330)):
    r = 78
    d.ellipse([x - r, y - r, x + r, y + r], fill=YELLOW, outline=WHITE, width=14)
img.save(OUT)
print("wrote", os.path.normpath(OUT))
