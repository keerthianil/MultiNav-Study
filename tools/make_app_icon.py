"""Draws the app icon in its three appearances, 1024 px each.

    python3 tools/make_app_icon.py

The icon is a piece of the app's own overview map: two streets meeting at a
red intersection, the cyan route turning there toward a yellow destination,
and vibration ripples round the yellow start dot where a finger rests.

Writes AppIcon.png (light), AppIcon-Dark.png and AppIcon-Tinted.png into the
asset catalog. All three are opaque, as App Store Connect requires.
"""

import os

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(HERE, "..", "MultiNavStudy2", "Assets.xcassets", "AppIcon.appiconset")

SIZE = 1024
SUPERSAMPLE = 4
S = SIZE * SUPERSAMPLE

STYLES = {
    "AppIcon.png": {
        "background": ((12, 82, 178), (3, 36, 92)),
        "street": (226, 238, 252),
        "route": (40, 196, 232),
        "route_edge": (8, 120, 170),
        "intersection": (214, 32, 45),
        "dot": (255, 214, 0),
        "outline": (255, 255, 255),
        "ripple": (255, 255, 255),
    },
    "AppIcon-Dark.png": {
        "background": ((14, 32, 64), (4, 10, 24)),
        "street": (196, 212, 234),
        "route": (40, 196, 232),
        "route_edge": (10, 96, 140),
        "intersection": (226, 52, 62),
        "dot": (255, 214, 0),
        "outline": (236, 242, 250),
        "ripple": (236, 242, 250),
    },
    # Grey levels only; the system tints this one with the user's colour.
    "AppIcon-Tinted.png": {
        "background": ((0, 0, 0), (0, 0, 0)),
        "street": (120, 120, 120),
        "route": (255, 255, 255),
        "route_edge": (60, 60, 60),
        "intersection": (190, 190, 190),
        "dot": (255, 255, 255),
        "outline": (0, 0, 0),
        "ripple": (255, 255, 255),
    },
}


def px(v):
    return int(v * SUPERSAMPLE)


def gradient(top, bottom):
    image = Image.new("RGB", (S, S))
    draw = ImageDraw.Draw(image)
    for y in range(S):
        t = y / (S - 1)
        draw.line([(0, y), (S, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return image


def line(draw, points, width, color):
    draw.line([(px(x), px(y)) for x, y in points], fill=color, width=px(width), joint="curve")
    r = px(width) / 2
    for x, y in (points[0], points[-1]):
        draw.ellipse([px(x) - r, px(y) - r, px(x) + r, px(y) + r], fill=color)


def dot(draw, center, radius, fill, outline, border):
    x, y = center
    draw.ellipse([px(x - radius), px(y - radius), px(x + radius), px(y + radius)], fill=outline)
    r = radius - border
    draw.ellipse([px(x - r), px(y - r), px(x + r), px(y + r)], fill=fill)


def square(draw, center, half, fill, outline, border):
    x, y = center
    draw.rounded_rectangle([px(x - half), px(y - half), px(x + half), px(y + half)], radius=px(10), fill=outline)
    h = half - border
    draw.rounded_rectangle([px(x - h), px(y - h), px(x + h), px(y + h)], radius=px(5), fill=fill)


def ripples(draw, center, radii, width, color, span=52):
    x, y = center
    for r in radii:
        for middle in (0, 180):
            draw.arc([px(x - r), px(y - r), px(x + r), px(y + r)],
                     start=middle - span, end=middle + span, fill=color, width=px(width))


def render(style):
    image = gradient(*style["background"])
    draw = ImageDraw.Draw(image)
    x, turn_y, side_y, start_y, end_x = 372, 330, 588, 812, 752

    line(draw, [(x, 120), (x, 920)], 116, style["street"])
    line(draw, [(120, turn_y), (904, turn_y)], 116, style["street"])
    line(draw, [(170, side_y), (x, side_y)], 116, style["street"])

    route = [(x, start_y), (x, turn_y), (end_x, turn_y)]
    line(draw, route, 78, style["route_edge"])
    line(draw, route, 62, style["route"])

    square(draw, (x, turn_y), 76, style["intersection"], style["outline"], 14)
    square(draw, (x, side_y), 58, style["intersection"], style["outline"], 12)
    dot(draw, (end_x, turn_y), 72, style["dot"], style["outline"], 14)
    dot(draw, (x, start_y), 58, style["dot"], style["outline"], 12)
    ripples(draw, (x, start_y), [110, 160], 22, style["ripple"])

    return image.resize((SIZE, SIZE), Image.LANCZOS)


if __name__ == "__main__":
    for name, style in STYLES.items():
        path = os.path.normpath(os.path.join(OUT_DIR, name))
        render(style).convert("RGB").save(path)
        print("wrote", path)
