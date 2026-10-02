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
    for f in _features(doc, "island"):
        _line(draw, [P(p) for p in f["geometry"]["coordinates"]], GREEN, float(f["properties"]["custom"]["width_mm"]))
    for f in _features(doc, "route"):
        _line(draw, [P(p) for p in f["geometry"]["coordinates"]], CYAN, 3.5)
    roads = [(f["geometry"]["coordinates"], float(f["properties"]["custom"]["width_mm"]))
             for f in _features(doc, "corridor")]
    rings = [(float(f["properties"]["custom"]["radius_mm"]), float(f["properties"]["custom"]["width_mm"]))
             for f in _features(doc, "roundabout")]

    def on_roadway(p):
        if any(abs(math.hypot(*p) - r) <= w / 2 for r, w in rings):
            return True
        return any(_polyline_distance(p, pts) <= w / 2 for pts, w in roads)

    pink = []
    for f in _features(doc, "crosswalk"):
        a, b = f["geometry"]["coordinates"][0], f["geometry"]["coordinates"][-1]
        s, e = paint_span(a, b, on_roadway)
        for x, y in stripe_segments(s, e):
            draw.line([P(x), P(y)], fill=WHITE, width=int(STRIPE_WIDTH * PX_PER_MM))
        ends = f["properties"].get("custom", {}).get("endpoints", "both")
        for p, keep in ((a, ends in ("both", "start")), (b, ends in ("both", "end"))):
            if keep and all(math.hypot(p[0] - q[0], p[1] - q[1]) >= 2.0 for q in pink):
                pink.append(p)
    pink = [P(p) for p in pink]
    turns = []
    for f in _features(doc, "route"):
        turns = route_turns([P(p) for p in f["geometry"]["coordinates"]], pink)
    for p in pink:
        if all(math.hypot(p[0] - q[0], p[1] - q[1]) >= 3.0 * PX_PER_MM for q in turns):
            _dot(draw, p, 5.0, PINK)
    for b in turns:
        _dot(draw, b, 6.0, ORANGE)
    for f in _features(doc, "route"):
        pts = [P(p) for p in f["geometry"]["coordinates"]]
        _dot(draw, pts[0], 6.0, YELLOW)
        _dot(draw, pts[-1], 6.0, YELLOW)
    img.save(path)


# Crosswalk stripes, mm. Must match the app's crosswalk style.
STRIPE_LENGTH = 1.0   # along the crossing
STRIPE_WIDTH = 2.8    # across it, parallel to traffic
STRIPE_COUNT = 3      # at most
STRIPE_MIN_GAP = 1.0  # shorter spans drop bars rather than close the gaps


def paint_span(a, b, on_roadway, samples=60):
    """The part of a crossing that lies over the roadway, where stripes are painted."""
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


def _polyline_distance(p, pts):
    best = float("inf")
    for a, b in zip(pts, pts[1:]):
        dx, dy = b[0] - a[0], b[1] - a[1]
        ls = dx * dx + dy * dy
        t = 0.0 if ls == 0 else max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / ls))
        best = min(best, math.hypot(p[0] - a[0] - dx * t, p[1] - a[1] - dy * t))
    return best


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
