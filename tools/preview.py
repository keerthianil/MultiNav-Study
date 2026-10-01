"""Draws a generated map JSON to PNG at true size on a 460 ppi screen.

Used by `build_maps.py --preview` to check a layout before it reaches the
app. Colours and widths follow the app's map style.
"""

import math

from PIL import Image, ImageDraw

PX_PER_MM = 460 / 25.4
PAD_MM = 3.0

BLUE = (0x02, 0x3E, 0x8A)
RED = (0xC1, 0x12, 0x1F)
CYAN = (0x48, 0xCA, 0xE4)
PURPLE = (0x7B, 0x2C, 0xBF)
YELLOW = (255, 214, 0)
GRAY = (0x9E, 0x9E, 0x9E)
GREEN = (0x52, 0xB7, 0x88)
PINK = (255, 45, 85)
ORANGE = (255, 140, 0)
WHITE = (255, 255, 255)


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


def render_level1(doc, path):
    img, draw = _canvas(doc)
    P = _mapper(doc)
    for f in _features(doc, "corridor"):
        _line(draw, [P(p) for p in f["geometry"]["coordinates"]], BLUE, 4.0)
    for f in _features(doc, "route"):
        _line(draw, [P(p) for p in f["geometry"]["coordinates"]], CYAN, 3.5)
    for f in _features(doc, "intersection"):
        x, y = P(f["geometry"]["coordinates"])
        if f["properties"]["custom"]["kind"] == "roundabout":
            r = 4.0 * PX_PER_MM
            draw.ellipse([x - r, y - r, x + r, y + r], outline=RED, width=int(1.8 * PX_PER_MM))
        else:
            h = 3.0 * PX_PER_MM
            draw.rectangle([x - h, y - h, x + h, y + h], fill=RED, outline=WHITE, width=int(0.5 * PX_PER_MM))
    for f in _features(doc, "landmark"):
        c = f["properties"]["custom"]
        ax, ay = P(f["geometry"]["coordinates"])
        nx, ny = float(c["offset_x"]), float(c["offset_y"])
        extent = abs(nx) * 4.5 + abs(ny) * 3.0
        dist = (2.0 + 2.0 + extent) * PX_PER_MM
        cx, cy = ax + nx * dist, ay + ny * dist
        hw, hh = 4.5 * PX_PER_MM, 3.0 * PX_PER_MM
        draw.rounded_rectangle([cx - hw, cy - hh, cx + hw, cy + hh], radius=int(1.2 * PX_PER_MM),
                               fill=PURPLE, outline=WHITE, width=int(0.5 * PX_PER_MM))
        draw.text((cx - hw + 8, cy - 8), c["tag"], fill=WHITE)
    for f in _features(doc, "route"):
        pts = f["geometry"]["coordinates"]
        for p in (pts[0], pts[-1]):
            _dot(draw, P(p), 6.0, YELLOW)
    img.save(path)


def render_level2(doc, path):
    img, draw = _canvas(doc)
    P = _mapper(doc)
    for f in _features(doc, "sidewalk"):
        _line(draw, [P(p) for p in f["geometry"]["coordinates"]], GRAY, 4.0)
    for f in _features(doc, "corridor"):
        _line(draw, [P(p) for p in f["geometry"]["coordinates"]], BLUE, float(f["properties"]["custom"]["width_mm"]))
    for f in _features(doc, "roundabout"):
        c = f["properties"]["custom"]
        r, w = float(c["radius_mm"]) * PX_PER_MM, float(c["width_mm"]) * PX_PER_MM
        x, y = P((0, 0))
        draw.ellipse([x - r - w / 2, y - r - w / 2, x + r + w / 2, y + r + w / 2], fill=BLUE)
    for f in _features(doc, "central_island"):
        r = float(f["properties"]["custom"]["radius_mm"]) * PX_PER_MM
        x, y = P((0, 0))
        draw.ellipse([x - r, y - r, x + r, y + r], fill=GREEN)
    for f in _features(doc, "median") + _features(doc, "island"):
        _line(draw, [P(p) for p in f["geometry"]["coordinates"]], GREEN, float(f["properties"]["custom"]["width_mm"]))
    for f in _features(doc, "route"):
        _line(draw, [P(p) for p in f["geometry"]["coordinates"]], CYAN, 3.5)
    pink = []
    for f in _features(doc, "crosswalk"):
        a, b = [P(p) for p in f["geometry"]["coordinates"]]
        length = math.hypot(b[0] - a[0], b[1] - a[1])
        ux, uy = (b[0] - a[0]) / length, (b[1] - a[1]) / length
        dash = 1.0 * PX_PER_MM
        gap = max((length - 3 * dash) / 4, 0)
        off = gap
        for _ in range(3):
            s = (a[0] + ux * off, a[1] + uy * off)
            e = (a[0] + ux * (off + dash), a[1] + uy * (off + dash))
            draw.line([s, e], fill=WHITE, width=int(2.8 * PX_PER_MM))
            off += dash + gap
        ends = f["properties"].get("custom", {}).get("endpoints", "both")
        for p, keep in ((a, ends in ("both", "start")), (b, ends in ("both", "end"))):
            if keep and all(math.hypot(p[0] - q[0], p[1] - q[1]) > 2.0 * PX_PER_MM for q in pink):
                pink.append(p)
    turns = []
    for f in _features(doc, "route"):
        turns = route_turns([P(p) for p in f["geometry"]["coordinates"]], pink)
    for p in pink:
        if all(math.hypot(p[0] - q[0], p[1] - q[1]) > 3.0 * PX_PER_MM for q in turns):
            _dot(draw, p, 5.0, PINK)
    for b in turns:
        _dot(draw, b, 6.0, ORANGE)
    for f in _features(doc, "route"):
        pts = [P(p) for p in f["geometry"]["coordinates"]]
        _dot(draw, pts[0], 6.0, YELLOW)
        _dot(draw, pts[-1], 6.0, YELLOW)
    img.save(path)


def route_turns(pts, crosswalk_ends, threshold=40.0):
    """Turn dots: bends over the threshold, at least 4 mm apart."""
    turns = []
    for i in range(1, len(pts) - 1):
        a, b, c = pts[i - 1], pts[i], pts[i + 1]
        h1 = math.atan2(b[1] - a[1], b[0] - a[0])
        h2 = math.atan2(c[1] - b[1], c[0] - b[0])
        turn = abs((math.degrees(h2 - h1) + 180) % 360 - 180)
        if turn <= threshold:
            continue
        if any(math.hypot(b[0] - q[0], b[1] - q[1]) < 4.0 * PX_PER_MM for q in turns):
            continue
        turns.append(b)
    return turns
