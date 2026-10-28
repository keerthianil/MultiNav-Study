"""Draws a generated map JSON to PNG at true size on a 460 ppi screen.

Used by `build_maps.py --preview` to check a layout before it reaches the
app. Colours and widths follow the app's map style.
"""

import math

from PIL import Image, ImageDraw, ImageFont

PX_PER_MM = 460 / 25.4
PAD_MM = 3.0

BLUE = (0x02, 0x3E, 0x8A)
RED = (0xC1, 0x12, 0x1F)
CYAN = (0x48, 0xCA, 0xE4)
YELLOW = (255, 214, 0)
GRAY = (0x9E, 0x9E, 0x9E)
GREEN = (0x52, 0xB7, 0x88)
PINK = (255, 45, 85)
ORANGE = (255, 140, 0)
WHITE = (255, 255, 255)
BLACK = (0, 0, 0)


def _canvas(doc):
    w = doc["bounds"]["width"] + 2 * PAD_MM
    h = doc["bounds"]["height"] + 2 * PAD_MM
    img = Image.new("RGB", (int(w * PX_PER_MM), int(h * PX_PER_MM)), WHITE)
    return img, ImageDraw.Draw(img)


def _mapper(doc):
    center = doc["metadata"].get("coordinate_origin") == "center"
    ox = PAD_MM + (doc["bounds"]["width"] / 2 if center else 0)
    oy = PAD_MM + (doc["bounds"]["height"] / 2 if center else 0)
    return lambda p: ((p[0] + ox) * PX_PER_MM, (p[1] + oy) * PX_PER_MM)


def _line(draw, pts, color, width_mm):
    w = max(1, int(width_mm * PX_PER_MM))
    draw.line(pts, fill=color, width=w, joint="curve")
    r = w / 2
    for x, y in (pts[0], pts[-1]):
        draw.ellipse([x - r, y - r, x + r, y + r], fill=color)


def _dot(draw, p, diameter_mm, color, border=WHITE):
    r = diameter_mm * PX_PER_MM / 2
    draw.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=color, outline=border,
                 width=max(1, int(0.4 * PX_PER_MM)))


def _features(doc, kind):
    return [f for f in doc["features"] if f["type"] == kind]


def _font(size_mm, bold=True):
    size = max(8, int(size_mm * PX_PER_MM))
    for name in ("/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "",
                 "/System/Library/Fonts/Helvetica.ttc"):
        if not name:
            continue
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def _label(img, text, at, size_mm, angle):
    font = _font(size_mm)
    box = font.getbbox(text)
    w, h = box[2] - box[0] + 8, box[3] - box[1] + 8
    tile = Image.new("RGBA", (w, h), (255, 255, 255, 0))
    ImageDraw.Draw(tile).text((4 - box[0], 4 - box[1]), text, fill=BLACK, font=font)
    if angle:
        tile = tile.rotate(-angle, expand=True)
    img.paste(tile, (int(at[0] - tile.width / 2), int(at[1] - tile.height / 2)), tile)


def render_overview(doc, path):
    img, draw = _canvas(doc)
    P = _mapper(doc)
    for f in _features(doc, "corridor"):
        _line(draw, [P(p) for p in f["geometry"]["coordinates"]], BLUE, 4.0)
    for f in _features(doc, "route"):
        _line(draw, [P(p) for p in f["geometry"]["coordinates"]], CYAN, 3.5)
    for f in _features(doc, "intersection"):
        x, y = P(f["geometry"]["coordinates"])
        h = 3.0 * PX_PER_MM
        draw.rectangle([x - h, y - h, x + h, y + h], fill=RED, outline=WHITE, width=int(0.5 * PX_PER_MM))
    for f in _features(doc, "route"):
        pts = f["geometry"]["coordinates"]
        _dot(draw, P(pts[0]), 6.0, YELLOW)
        _dot(draw, P(pts[-1]), 6.0, YELLOW)
    for f in _features(doc, "label"):
        c = f["properties"].get("custom", {})
        _label(img, f["properties"]["name"], P(f["geometry"]["coordinates"]), float(c.get("size_mm", 3)),
               float(c.get("angle", 0)))
    img.save(path)


def render_intersection(doc, path):
    img, draw = _canvas(doc)
    P = _mapper(doc)
    for f in _features(doc, "sidewalk"):
        _line(draw, [P(p) for p in f["geometry"]["coordinates"]], GRAY, 4.0)
    for f in _features(doc, "corridor"):
        _line(draw, [P(p) for p in f["geometry"]["coordinates"]], BLUE, float(f["properties"]["custom"]["width_mm"]))
    for f in _features(doc, "median"):
        _line(draw, [P(p) for p in f["geometry"]["coordinates"]], GREEN, float(f["properties"]["custom"]["width_mm"]))
    for f in _features(doc, "route"):
        _line(draw, [P(p) for p in f["geometry"]["coordinates"]], BLUE, 4.6)
        _line(draw, [P(p) for p in f["geometry"]["coordinates"]], CYAN, 4.0)
    roads = [(f["geometry"]["coordinates"], float(f["properties"]["custom"]["width_mm"]))
             for f in _features(doc, "corridor")]

    def on_roadway(p):
        return any(_polyline_distance(p, pts) <= w / 2 for pts, w in roads)

    for f in _features(doc, "crosswalk"):
        a, b = f["geometry"]["coordinates"][0], f["geometry"]["coordinates"][-1]
        s, e = paint_span(a, b, on_roadway)
        if f["properties"].get("custom", {}).get("marking") == "unmarked":
            for x, y in edge_lines(s, e):
                draw.line([P(x), P(y)], fill=WHITE, width=max(1, int(EDGE_WIDTH * PX_PER_MM)))
        else:
            for x, y in stripe_segments(s, e):
                draw.line([P(x), P(y)], fill=WHITE, width=int(STRIPE_WIDTH * PX_PER_MM))
    for f in _features(doc, "crosswalk_end"):
        _dot(draw, P(f["geometry"]["coordinates"]), 5.0, PINK)
    for f in _features(doc, "turn"):
        _dot(draw, P(f["geometry"]["coordinates"]), 6.0, ORANGE)
    for f in _features(doc, "center"):
        if f["properties"].get("custom", {}).get("mark") == "no":
            continue
        x, y = P(f["geometry"]["coordinates"])
        r = 1.0 * PX_PER_MM
        draw.ellipse([x - r, y - r, x + r, y + r], outline=WHITE, width=max(1, int(0.4 * PX_PER_MM)))
    for f in _features(doc, "route"):
        pts = [P(p) for p in f["geometry"]["coordinates"]]
        _dot(draw, pts[0], 6.0, YELLOW)
        _dot(draw, pts[-1], 6.0, YELLOW)
    img.save(path)


# Crosswalk markings, mm. Must match the app's crosswalk style.
STRIPE_LENGTH = 1.0   # along the crossing
STRIPE_WIDTH = 2.8    # across it, parallel to traffic
STRIPE_COUNT = 3      # at most
STRIPE_MIN_GAP = 1.0  # shorter spans drop bars rather than close the gaps
EDGE_WIDTH = 0.35     # the two thin lines along an unmarked crossing
EDGE_OFFSET = 1.4     # each line's distance from the crossing's centre line


def paint_span(a, b, on_roadway, samples=60):
    """The part of a crossing that lies over the roadway, where it is painted."""
    inside = [i / samples for i in range(samples + 1)
              if on_roadway((a[0] + (b[0] - a[0]) * i / samples, a[1] + (b[1] - a[1]) * i / samples))]
    if inside and inside[-1] > inside[0]:
        f, l = inside[0], inside[-1]
        return (a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f), (a[0] + (b[0] - a[0]) * l, a[1] + (b[1] - a[1]) * l)
    return a, b


def stripe_segments(a, b):
    """Zebra bars as the app draws them: the span cut into equal cells, one bar
    centred in each, with fewer cells on a short span so bars never touch."""
    length = math.hypot(b[0] - a[0], b[1] - a[1])
    if length <= 0:
        return []
    ux, uy = (b[0] - a[0]) / length, (b[1] - a[1]) / length
    count = min(STRIPE_COUNT, max(1, int(length // (STRIPE_LENGTH + STRIPE_MIN_GAP))))
    cell = length / count
    out = []
    for i in range(count):
        off = cell * (i + 0.5) - STRIPE_LENGTH / 2
        out.append(((a[0] + ux * off, a[1] + uy * off),
                    (a[0] + ux * (off + STRIPE_LENGTH), a[1] + uy * (off + STRIPE_LENGTH))))
    return out


def edge_lines(a, b):
    """An unmarked crossing: two thin dashed lines along its edges."""
    length = math.hypot(b[0] - a[0], b[1] - a[1])
    if length <= 0:
        return []
    ux, uy = (b[0] - a[0]) / length, (b[1] - a[1]) / length
    nx, ny = -uy, ux
    out = []
    dash, gap = 1.2, 0.9
    for side in (-1, 1):
        ox, oy = nx * EDGE_OFFSET * side, ny * EDGE_OFFSET * side
        s = 0.0
        while s < length:
            e = min(length, s + dash)
            out.append(((a[0] + ux * s + ox, a[1] + uy * s + oy), (a[0] + ux * e + ox, a[1] + uy * e + oy)))
            s = e + gap
    return out


def _polyline_distance(p, pts):
    best = float("inf")
    for a, b in zip(pts, pts[1:]):
        dx, dy = b[0] - a[0], b[1] - a[1]
        ls = dx * dx + dy * dy
        t = 0.0 if ls == 0 else max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / ls))
        best = min(best, math.hypot(p[0] - a[0] - dx * t, p[1] - a[1] - dy * t))
    return best
