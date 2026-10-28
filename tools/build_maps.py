"""Builds the bundled maps for MultiNav Study 2.

    python3 tools/build_maps.py            # writes MultiNavStudy2/Maps/*.json and docs/STUDY.md
    python3 tools/build_maps.py --preview  # also writes docs/map_previews/*.png

Two kinds of map come out, both in the MultiNav TactileMapDocument format
with coordinates in millimetres on screen:

* Route overviews, the training route and the study route: schematic maps
  laid out like the research team's mockups, not to scale. Origin top-left,
  y down.
* Intersection maps: one junction at its true angles from OpenStreetMap,
  turned so the way the participant is walking is up, with roads,
  sidewalks, crosswalks, the median and the walking path through it.
  Origin at the centre of the intersection, y down.

Maps/study.json lists every map in study order with the words spoken on it,
all taken from tools/study_spec.py.

Physical sizes are fixed in millimetres so the maps feel the same on every
phone; the app only scales down if a screen is smaller than the reference
area below.
"""

import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import osm_model as om  # noqa: E402
import study_spec as spec  # noqa: E402

REPO = os.path.dirname(HERE)
MAPS_DIR = os.path.join(REPO, "MultiNavStudy2", "Maps")
PREVIEW_DIR = os.path.join(REPO, "docs", "map_previews")

# Reference drawing area in mm (a 6.1 inch iPhone below the navigation bar).
REF_W = 60.0
REF_H = 116.0
MARGIN = 1.0

# Overview sizes, mm. Must match the app's style constants.
OV_ROAD_HALF = 2.0
OV_SQUARE_HALF = 3.0
OV_DOT_R = 3.0

# Intersection map sizes, mm.
ROAD_HALF = 6.0
SIDEWALK_OFFSET = 13.1     # road half 6 + crosswalk 2.8 + kerb gap 1 + sidewalk half 2 + 1.3
CENTER_R = 5.0
MIN_CROSS_T = 7.0          # nearer than this a crosswalk would lie on the other road
MEDIAN_W = 3.0
MEDIAN_NOSE = 2.0          # how far the median reaches in past the crosswalk's centre
SQUARE_UP_MIN = 2.0        # a crosswalk straighter than this (mm) is left as it is
START_GAP = 16.0           # route drawn before the first crosswalk
END_GAP = 14.0             # and after the last one
ROUTE_INSET = 5.5          # route ends kept this far inside the screen edge

ONE_DECIMAL = 2  # coordinates are written with this many decimals


# ================================================================ helpers

def unit(theta):
    """Screen unit vector for an angle measured clockwise from up (y down)."""
    r = math.radians(theta)
    return (math.sin(r), -math.cos(r))


def cw_normal(theta):
    r = math.radians(theta)
    return (math.cos(r), math.sin(r))


def add(a, b, s=1.0):
    return (a[0] + b[0] * s, a[1] + b[1] * s)


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1])


def scale(v, s):
    return (v[0] * s, v[1] * s)


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1]


def rnd(p):
    return [round(p[0], ONE_DECIMAL), round(p[1], ONE_DECIMAL)]


def screen_angle(true_bearing, up):
    return (true_bearing - up) % 360.0


def join_names(names):
    names = list(names)
    if len(names) == 1:
        return names[0]
    if len(names) == 2:
        return "%s and %s" % (names[0], names[1])
    return ", ".join(names[:-1]) + " and " + names[-1]


def feature(fid, ftype, geometry, name, **extra):
    props = {"name": name}
    custom = {k: str(v) for k, v in extra.pop("custom", {}).items() if v is not None}
    props.update(extra)
    if custom:
        props["custom"] = custom
    return {"id": fid, "type": ftype, "geometry": geometry, "properties": props}


def point_geom(p):
    return {"type": "Point", "coordinates": rnd(p)}


def line_geom(points):
    return {"type": "LineString", "coordinates": [rnd(p) for p in points]}


def document(name, features, origin):
    return {
        "type": "FeatureCollection",
        "version": "1.0",
        "metadata": {"name": name, "scale": "1 unit = 1 mm on screen", "coordinate_unit": "arbitrary",
                     "coordinate_origin": origin, "author": "tools/build_maps.py"},
        "bounds": {"width": REF_W, "height": REF_H},
        "features": features,
    }


def check_spoken(text, where):
    """No dashes or arrows in anything the app speaks: VoiceOver reads them out."""
    for bad in ("—", "–", "→", "←"):
        if bad in text:
            raise SystemExit("%s: dash or arrow in spoken text: %s" % (where, text))
    return text


# ================================================================ overviews

def label_spot(anchor, lines, avoid=4.2, reach=5.0):
    """A clear spot beside `anchor` for a number label, away from every line."""
    for dx, dy in ((1, -1), (-1, -1), (1, 1), (-1, 1), (0, -1.3), (1.3, 0), (-1.3, 0)):
        p = (anchor[0] + dx * reach, anchor[1] + dy * reach)
        if all(om_dist_to_polyline(p, pts) >= avoid for pts in lines) and \
                MARGIN + 2 < p[0] < REF_W - MARGIN - 2 and MARGIN + 2 < p[1] < REF_H - MARGIN - 2:
            return p
    return (anchor[0] + reach, anchor[1] - reach)


def seg_distance(p, a, b):
    d = sub(b, a)
    ls = dot(d, d)
    t = 0.0 if ls == 0 else max(0.0, min(1.0, dot(sub(p, a), d) / ls))
    return om.dist(p, add(a, d, t))


def om_dist_to_polyline(p, pts):
    best = float("inf")
    for a, b in zip(pts, pts[1:]):
        d = sub(b, a)
        ls = dot(d, d)
        t = 0.0 if ls == 0 else max(0.0, min(1.0, dot(sub(p, a), d) / ls))
        best = min(best, om.dist(p, add(a, d, t)))
    return best


def build_overview(ov):
    """A schematic route map from the legs in study_spec."""
    pos = ov["start"]["at"]
    route = [pos]
    runs = []          # (street, points) for the streets under the route
    stubs = []         # (name, centre, end, direction)
    nodes = []         # (number, position, text)
    for leg in ov["legs"]:
        nxt = add(pos, unit(leg["dir"]), leg["len"])
        if runs and runs[-1][0] == leg["street"] and abs(om.angle_diff(runs[-1][2], leg["dir"])) < 1:
            runs[-1][1].append(nxt)
        else:
            runs.append([leg["street"], [pos, nxt], leg["dir"]])
        pos = nxt
        route.append(pos)
        node = leg["node"]
        if node["kind"] == "intersection":
            for d, length, name in node["stubs"]:
                stubs.append((name, pos, add(pos, unit(d), length), d))
            nodes.append((node["number"], pos, check_spoken(node["text"], ov["id"])))

    features = []
    for n, (street, pts, _) in enumerate(runs):
        features.append(feature("street_%d" % n, "corridor", line_geom(pts), street))
    # Opposite stubs of one street through a node become one line.
    used = set()
    n = 0
    for i, (name, centre, end, d) in enumerate(stubs):
        if i in used:
            continue
        partner = next((k for k, s in enumerate(stubs) if k != i and k not in used and s[0] == name
                        and s[1] == centre and abs(om.angle_diff(s[3], d + 180)) < 1), None)
        if partner is not None:
            used.update({i, partner})
            pts = [stubs[partner][2], centre, end]
        else:
            used.add(i)
            pts = [centre, end]
        features.append(feature("cross_%d" % n, "corridor", line_geom(pts), name))
        n += 1
    for number, p, text in nodes:
        features.append(feature("node_%d" % number, "intersection", point_geom(p), "Intersection %d" % number,
                                custom={"cue": text, "number": number}))
    features.append(feature("route", "route", line_geom(route), ov["title"], custom={
        "start_text": check_spoken(ov["start"]["text"], ov["id"]),
        "end_text": check_spoken(ov["end"]["text"], ov["id"])}))

    # Labels printed on the map for the researcher and sighted viewers, as in
    # the mockups: intersection numbers, the two ends, street names.
    lines = [pts for _, pts, _ in runs] + [[s[1], s[2]] for s in stubs]
    for number, p, _ in nodes:
        features.append(feature("label_%d" % number, "label", point_geom(label_spot(p, lines)), str(number),
                                custom={"size_mm": 3.6, "weight": "bold"}))
    for which, p in (("start", route[0]), ("end", route[-1])):
        text, side = ov[which]["label"], ov[which]["label_side"]
        width = 1.9 * len(text)
        offset = {"right": (4.5 + width / 2, 0.0), "left": (-4.5 - width / 2, 0.0),
                  "above": (0.0, -5.5), "below": (0.0, 5.5)}[side]
        features.append(feature("label_%s" % which, "label", point_geom(add(p, offset)), text,
                                custom={"size_mm": 3.2, "weight": "bold"}))
    # Street names, written along the route as in the mockup, or beside a street.
    for k, (text, x, y, angle) in enumerate(ov["labels"]):
        features.append(feature("label_street_%d" % k, "label", point_geom((x, y)), text,
                                custom={"size_mm": 2.6, "weight": "bold", "angle": angle}))

    xs = [p[0] for _, pts, _ in runs for p in pts] + [s[2][0] for s in stubs]
    ys = [p[1] for _, pts, _ in runs for p in pts] + [s[2][1] for s in stubs]
    if min(xs) - OV_DOT_R < MARGIN or max(xs) + OV_DOT_R > REF_W - MARGIN \
            or min(ys) - OV_DOT_R < MARGIN or max(ys) + OV_DOT_R > REF_H - MARGIN:
        raise SystemExit("%s does not fit the reference area" % ov["id"])
    return document(ov["title"], features, "top-left")


# ================================================================ junctions

AREA = om.Area(spec.AREA["osm"], spec.AREA["origin"])


class Arm:
    def __init__(self, name, bearing):
        self.name = name
        self.bearing = bearing % 360.0
        self.crossing = None   # "zebra", "unmarked" or None
        self.median = False

    def __repr__(self):
        return "%s@%.0f" % (self.name, self.bearing)


class Junction:
    """One intersection: its arms and what the team describes at each."""

    def __init__(self, key):
        self.key = key
        if key == "training":
            conf = spec.TRAINING_JUNCTION
            arms = [Arm(name, b) for name, b in conf["arms"]]
        else:
            conf = spec.JUNCTIONS[key]
            arms = [Arm(g["name"], g["bearing"]) for g in om.merged_arms(AREA, conf["nodes"])]
        self.conf = conf
        self.arms = sorted(arms, key=lambda a: a.bearing)
        for ref, name in conf.get("rename", {}).items():
            self.arm(ref).name = name
        for ref, kind in conf.get("crosswalks", {}).items():
            self.arm(ref).crossing = kind
        for ref in conf.get("median", []):
            self.arm(ref).median = True
        self.straight = [self.arm(ref) for ref in conf.get("straight", [])]
        self.skew = [(self.arm(ref), side, mm) for ref, side, mm in conf.get("skew", [])]

    def arm(self, ref):
        name, _, b = ref.partition("@")
        candidates = [a for a in self.arms if a.name == name]
        if not candidates:
            raise KeyError("%s has no arm named %s (arms: %s)" % (self.key, name, self.arms))
        if not b:
            return candidates[0]
        found = min(candidates, key=lambda a: abs(om.angle_diff(a.bearing, float(b))))
        if abs(om.angle_diff(found.bearing, float(b))) > 25:
            raise KeyError("%s: %s is %.0f degrees, not near %s" % (self.key, name, found.bearing, b))
        return found


def resolve_side(arm, compass_word):
    """'cw' or 'ccw' for the side of an arm named by a compass word."""
    target = {name: i * 45.0 for i, name in enumerate(om.COMPASS)}[compass_word]
    d = om.angle_diff(target, arm.bearing)
    if abs(abs(d) - 90) > 50:
        raise ValueError("%s side %s is not beside the street" % (arm, compass_word))
    return "cw" if d > 0 else "ccw"


# Centre of the visible area in the map's own coordinates. A map is first laid
# out round the junction centre; when the walk would run off the screen the
# visible area moves to centre on the walk instead (see frame_for).
FRAME = [0.0, 0.0]


def arm_limit(theta, inset):
    """Distance along an arm before it leaves the visible area."""
    return line_limit((0.0, 0.0), theta, inset)


def line_limit(origin, theta, inset):
    """Distance from `origin` along `theta` before leaving the visible area."""
    u = unit(theta)
    limits = []
    for axis, half in ((0, REF_W / 2 - inset), (1, REF_H / 2 - inset)):
        if abs(u[axis]) < 1e-6:
            continue
        bound = FRAME[axis] + (half if u[axis] > 0 else -half)
        limits.append((bound - origin[axis]) / u[axis])
    return max(0.0, min(limits))


def frame_for(route_points):
    """Where to centre the visible area so the whole walk fits on screen.

    The junction stays the centre when the walk fits round it; otherwise the
    walk is centred, keeping the junction well inside the screen."""
    hw, hh = REF_W / 2 - ROUTE_INSET, REF_H / 2 - ROUTE_INSET
    if all(abs(p[0]) <= hw and abs(p[1]) <= hh for p in route_points):
        return [0.0, 0.0]
    xs = [p[0] for p in route_points]
    ys = [p[1] for p in route_points]
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    lim_x, lim_y = REF_W / 2 - 12.0, REF_H / 2 - 16.0
    return [max(-lim_x, min(lim_x, cx)), max(-lim_y, min(lim_y, cy))]


def shift_features(features, offset):
    """Moves every coordinate so the visible area's centre becomes (0, 0)."""
    def move(c):
        if isinstance(c[0], (int, float)):
            return [round(c[0] - offset[0], ONE_DECIMAL), round(c[1] - offset[1], ONE_DECIMAL)]
        return [move(x) for x in c]
    for f in features:
        f["geometry"]["coordinates"] = move(f["geometry"]["coordinates"])
    return features


def corner(theta_a, theta_b, d):
    """The sidewalk corner between two arms, clockwise from a to b.

    A corner under 180 degrees is one point where the two sidewalks meet,
    t along each arm from the centre. A flat or reflex side has no corner:
    the sidewalk runs straight past, bending round the back when wider.
    """
    alpha = (theta_b - theta_a) % 360.0
    if alpha < 179.0:
        r = d / math.sin(math.radians(alpha / 2))
        t = d / math.tan(math.radians(alpha / 2))
        return {"kind": "point", "points": [scale(unit(theta_a + alpha / 2), r)], "t": t}
    start = theta_a + 90
    sweep = alpha - 180
    if sweep < 1:
        return {"kind": "flat", "points": [scale(unit(start), d)], "t": 0.0}
    steps = max(1, int(sweep / 10))
    return {"kind": "flat", "points": [scale(unit(start + sweep * i / steps), d) for i in range(steps + 1)],
            "t": 0.0}


class Geometry:
    """Corners, crosswalk ends and sidewalk lines for one junction, turned so
    `up` is at the top of the screen.

    Crosswalks run corner to corner, so a walk along a sidewalk meets the
    crosswalk end exactly where the sidewalk turns the corner. A crosswalk the
    team describes as straight has both ends equally far out; one described
    as angled has one end moved further out along its arm.
    """

    def __init__(self, j, up):
        self.j = j
        self.up = up
        self.arms = sorted(j.arms, key=lambda a: screen_angle(a.bearing, up))
        self.theta = {id(a): screen_angle(a.bearing, up) for a in self.arms}
        self.d = SIDEWALK_OFFSET
        n = len(self.arms)
        # Corner k lies between arm k and arm k+1, clockwise.
        self.corners = [corner(self.theta[id(self.arms[k])], self.theta[id(self.arms[(k + 1) % n])], self.d)
                        for k in range(n)]
        self.end_t = {}
        for k, arm in enumerate(self.arms):
            before, after = self.corners[(k - 1) % n], self.corners[k]
            t_ccw = before["t"] if before["kind"] == "point" and before["t"] >= MIN_CROSS_T else None
            t_cw = after["t"] if after["kind"] == "point" and after["t"] >= MIN_CROSS_T else None
            if t_ccw is None and t_cw is None:
                t_ccw = t_cw = MIN_CROSS_T
            self.end_t[(id(arm), "ccw")] = t_ccw if t_ccw is not None else t_cw
            self.end_t[(id(arm), "cw")] = t_cw if t_cw is not None else t_ccw
        for arm in j.straight:
            a, b = self.end_t[(id(arm), "ccw")], self.end_t[(id(arm), "cw")]
            if abs(a - b) >= SQUARE_UP_MIN:
                self.end_t[(id(arm), "ccw")] = self.end_t[(id(arm), "cw")] = max(a, b)
        for arm, side, mm in j.skew:
            self.end_t[(id(arm), side)] += mm

    def index(self, arm):
        return next(i for i, a in enumerate(self.arms) if a is arm)

    def side_point(self, arm, side, t):
        th = self.theta[id(arm)]
        n = cw_normal(th) if side == "cw" else scale(cw_normal(th), -1)
        return add(scale(unit(th), t), n, self.d)

    def cross_t(self, arm, side):
        return self.end_t[(id(arm), side)]

    def cross_end(self, arm, side):
        return self.side_point(arm, side, self.cross_t(arm, side))

    def axis_t(self, arm):
        """How far out the crosswalk meets the arm's centre line."""
        a, b = self.cross_end(arm, "ccw"), self.cross_end(arm, "cw")
        u = unit(self.theta[id(arm)])
        ca = a[0] * u[1] - a[1] * u[0]
        cb = b[0] * u[1] - b[1] * u[0]
        s = ca / (ca - cb) if abs(ca - cb) > 1e-9 else 0.5
        p = (a[0] + (b[0] - a[0]) * s, a[1] + (b[1] - a[1]) * s)
        return dot(p, u)

    def far(self, arm, inset, side=None):
        if side is None:
            return arm_limit(self.theta[id(arm)], inset)
        th = self.theta[id(arm)]
        n = cw_normal(th) if side == "cw" else scale(cw_normal(th), -1)
        return line_limit(scale(n, self.d), th, inset)


def sidewalk_feature(index, points, street):
    return feature("sidewalk_%d" % index, "sidewalk", line_geom(points), "Sidewalk along %s" % street)


def crosswalk_features(fid, a, b, arm_name, marking, uses_median, mid=None, normal=None):
    """One crosswalk, or two halves either side of a median."""
    name = "Crosswalk across %s" % arm_name
    common = {"marking": marking}
    if not uses_median:
        return [feature(fid, "crosswalk", line_geom([a, b]), name, custom=dict(common, endpoints="both"))]
    gap = MEDIAN_W / 2 + 0.3
    return [
        feature(fid + "_a", "crosswalk", line_geom([a, add(mid, normal, -gap)]), name,
                custom=dict(common, endpoints="start")),
        feature(fid + "_b", "crosswalk", line_geom([add(mid, normal, gap), b]), name,
                custom=dict(common, endpoints="end")),
    ]


def stop_heading(stop, j):
    """Compass direction drawn at the top: the way the participant walks in,
    or for a walk that starts at the corner, the way they first cross."""
    if stop.get("heading") != "first_crossing":
        return (j.arm(stop["in"][0]).bearing + 180.0) % 360.0
    # Any orientation lists the arms in the same circular order, so the
    # walk can be worked out before the map is turned.
    _, crossed, via = walking_path(Geometry(j, 0.0), stop, with_via=True)
    first = crossed[0]
    return (first.bearing + (90.0 if via == "cw" else -90.0)) % 360.0


def build_intersection(stop):
    j = Junction(stop["junction"])
    up = stop_heading(stop, j)
    geo = Geometry(j, up)
    FRAME[:] = [0.0, 0.0]
    FRAME[:] = frame_for(walking_path(geo, stop, capped=False)[0])
    features = []

    # Roads, running off the edge of the screen.
    for k, arm in enumerate(geo.arms):
        th = geo.theta[id(arm)]
        features.append(feature("road_%d" % k, "corridor", line_geom([(0.0, 0.0), scale(unit(th), geo.far(arm, 0) + 12)]),
                                arm.name, custom={"width_mm": ROAD_HALF * 2}))
    features.append(feature("center", "center", point_geom((0, 0)), "Center", custom={"radius_mm": CENTER_R}))

    # Medians along divided arms, from just inside the crosswalk outwards.
    for k, arm in enumerate(geo.arms):
        if not arm.median:
            continue
        th = geo.theta[id(arm)]
        t0 = (geo.axis_t(arm) if arm.crossing else geo.cross_t(arm, "cw")) - MEDIAN_NOSE
        features.append(feature("median_%d" % k, "median",
                                line_geom([scale(unit(th), t0), scale(unit(th), geo.far(arm, 0) + 12)]),
                                "Median", custom={"width_mm": MEDIAN_W}))

    # Sidewalks: each corner split into the two streets it runs along.
    sw = 0
    n = len(geo.arms)
    for k, c in enumerate(geo.corners):
        a, b = geo.arms[k], geo.arms[(k + 1) % n]
        far_a = geo.side_point(a, "cw", geo.far(a, 2.0, "cw"))
        far_b = geo.side_point(b, "ccw", geo.far(b, 2.0, "ccw"))
        pts = c["points"]
        if c["kind"] == "point":
            first, second = [far_a, pts[0]], [pts[0], far_b]
        else:
            mid = len(pts) // 2
            first, second = [far_a] + pts[:mid + 1], pts[mid:] + [far_b]
        features.append(sidewalk_feature(sw, first, a.name))
        features.append(sidewalk_feature(sw + 1, second, b.name))
        sw += 2

    # Crosswalks.
    for k, arm in enumerate(geo.arms):
        if not arm.crossing:
            continue
        a, b = geo.cross_end(arm, "ccw"), geo.cross_end(arm, "cw")
        th = geo.theta[id(arm)]
        mid = scale(unit(th), geo.axis_t(arm))
        features += crosswalk_features("crosswalk_%d" % k, a, b, arm.name, arm.crossing, arm.median,
                                       mid, cw_normal(th))

    path, crossed = walking_path(geo, stop)
    for arm in crossed:
        if not arm.crossing:
            raise SystemExit("%s crosses %s, which has no crosswalk in the spec" % (stop["id"], arm))
    features.append(feature("route", "route", line_geom(path), "Route", custom={
        "start_text": spec.START_TEXT, "end_text": spec.END_TEXT}))
    shift_features(features, FRAME)
    tidy(features)
    place_dots(features, stop["id"])
    doc = document(stop["subtitle"], features, "center")
    FRAME[:] = [0.0, 0.0]
    facts = {
        "heading": up,
        "arms": [(arm.name, om.compass8(arm.bearing), arm.crossing, arm.median) for arm in j.arms],
        "crossed": [arm.name for arm in crossed],
    }
    return doc, facts


def walking_path(geo, stop, with_via=False, capped=True):
    """The walk through the junction: corner to corner across each arm."""
    j = geo.j
    n = len(geo.arms)
    in_arm = j.arm(stop["in"][0])
    in_side = resolve_side(in_arm, stop["in"][1])
    start_corner = geo.index(in_arm) if in_side == "cw" else (geo.index(in_arm) - 1) % n
    out_arm = j.arm(stop["out"][0])
    out_side = resolve_side(out_arm, stop["out"][1])
    target = geo.index(out_arm) if out_side == "cw" else (geo.index(out_arm) - 1) % n

    cw_steps = (target - start_corner) % n
    ccw_steps = (start_corner - target) % n
    via = stop.get("via") or ("cw" if cw_steps <= ccw_steps else "ccw")

    start_gap = stop.get("start_gap", START_GAP)
    start_t = geo.cross_t(in_arm, in_side) + start_gap
    if capped:
        start_t = max(geo.cross_t(in_arm, in_side), min(start_t, geo.far(in_arm, ROUTE_INSET, in_side)))
    points = [geo.side_point(in_arm, in_side, start_t), geo.cross_end(in_arm, in_side)]
    current = in_arm
    crossed = []
    c = start_corner
    for _ in range(cw_steps if via == "cw" else ccw_steps):
        nxt = geo.arms[(c + 1) % n] if via == "cw" else geo.arms[c]
        crossed.append(nxt)
        near, far_side = ("ccw", "cw") if via == "cw" else ("cw", "ccw")
        if current is not nxt:
            points += ordered_corner(geo, c, current)
            points.append(geo.cross_end(nxt, near))
        points.append(geo.cross_end(nxt, far_side))
        current = nxt
        c = (c + 1) % n if via == "cw" else (c - 1) % n
    if current is not out_arm:
        points += ordered_corner(geo, c, current)
        points.append(geo.cross_end(out_arm, out_side))
    end_t = geo.cross_t(out_arm, out_side) + stop.get("end_gap", END_GAP)
    if capped:
        end_t = max(geo.cross_t(out_arm, out_side), min(end_t, geo.far(out_arm, ROUTE_INSET, out_side)))
    points.append(geo.side_point(out_arm, out_side, end_t))
    if with_via:
        return dedupe(points), crossed, via
    return dedupe(points), crossed


def ordered_corner(geo, c, coming_from):
    """Corner points ordered from the side of `coming_from`."""
    pts = list(geo.corners[c]["points"])
    return pts if coming_from is geo.arms[c] else pts[::-1]


def dedupe(points):
    out = []
    for p in points:
        if out and om.dist(out[-1], p) < 1.5 and len(out) > 1:
            # A step shorter than 1.5 mm is a jog, not a turn: keep the later point.
            out[-1] = p
            continue
        if out and om.dist(out[-1], p) < 0.05:
            continue
        out.append(p)
    # Drop points that sit on a straight line between their neighbours.
    cleaned = [out[0]]
    for i in range(1, len(out) - 1):
        a, b, c = cleaned[-1], out[i], out[i + 1]
        cross = (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0])
        if abs(cross) > 0.02:
            cleaned.append(b)
    cleaned.append(out[-1])
    return cleaned


# ================================================================ dots

# Dot sizes, mm, as the app draws them.
TURN_R = 3.0
END_R = 3.0
PINK_R = 2.5
DOT_CLEARANCE = 1.0        # free space kept between any two dots
TURN_THRESHOLD = 40.0      # path bends sharper than this get an orange turn dot


def route_bends(points):
    out = []
    for i in range(1, len(points) - 1):
        a, b, c = points[i - 1], points[i], points[i + 1]
        h1 = math.degrees(math.atan2(b[1] - a[1], b[0] - a[0]))
        h2 = math.degrees(math.atan2(c[1] - b[1], c[0] - b[0]))
        if abs(om.angle_diff(h2, h1)) > TURN_THRESHOLD:
            out.append(b)
    return out


def line_length(pts):
    return sum(om.dist(a, b) for a, b in zip(pts, pts[1:]))


def visible(p, margin=0.0):
    return abs(p[0]) <= REF_W / 2 + margin and abs(p[1]) <= REF_H / 2 + margin


def tidy(features):
    """Drops sidewalks, crosswalks and medians too short to feel or wholly
    off screen, which happen where a corner falls past the edge."""
    kept = []
    for f in features:
        if f["type"] in ("sidewalk", "crosswalk", "median"):
            pts = f["geometry"]["coordinates"]
            if line_length(pts) < 1.5:
                continue
            steps = max(2, int(line_length(pts) / 0.5))
            inside = [p for a, b in zip(pts, pts[1:]) for p in
                      ((a[0] + (b[0] - a[0]) * i / steps, a[1] + (b[1] - a[1]) * i / steps) for i in range(steps + 1))
                      if visible(p, -1.0)]
            if len(inside) < 4:
                continue
        kept.append(f)
    features[:] = kept
    return features


def place_dots(features, where):
    """Turn dots and crosswalk end dots, placed so no two dots touch.

    The route's ends win over turns, and turns over crosswalk ends, as on
    the earlier maps where a turn and a crosswalk end at one corner show the
    turn. Crosswalk ends that would touch become one dot."""
    route = next(f for f in features if f["type"] == "route")["geometry"]["coordinates"]
    ends = [(route[0], END_R), (route[-1], END_R)]
    placed = list(ends)

    def clear(p, r):
        return all(om.dist(p, q) >= r + qr + DOT_CLEARANCE for q, qr in placed)

    def on_screen(p, r):
        return abs(p[0]) <= REF_W / 2 - r - 0.5 and abs(p[1]) <= REF_H / 2 - r - 0.5

    for p, r in ends:
        if not on_screen(p, r):
            raise SystemExit("%s: route end at %s is cut by the screen edge" % (where, rnd(p)))

    turns = []
    for p in route_bends(route):
        if clear(p, TURN_R) and on_screen(p, TURN_R):
            turns.append(p)
            placed.append((p, TURN_R))
    pinks = []
    for f in features:
        if f["type"] != "crosswalk":
            continue
        pts = f["geometry"]["coordinates"]
        which = f["properties"]["custom"].get("endpoints", "both")
        for p, keep in ((pts[0], which in ("both", "start")), (pts[-1], which in ("both", "end"))):
            if not keep:
                continue
            # A crosswalk end at a turn or a route end is shown by that dot, and
            # one at the screen edge, away from the walk, is left out.
            if any(om.dist(p, q) < qr + PINK_R + DOT_CLEARANCE for q, qr in placed) or not on_screen(p, PINK_R):
                continue
            pinks.append(p)
            placed.append((p, PINK_R))
    # The small ring marking the centre is left off where a crosswalk runs over it.
    for f in features:
        if f["type"] == "center":
            c = f["geometry"]["coordinates"]
            crosswalks = [g["geometry"]["coordinates"] for g in features if g["type"] == "crosswalk"]
            if any(seg_distance(c, cw[0], cw[-1]) < 3.0 for cw in crosswalks):
                f["properties"].setdefault("custom", {})["mark"] = "no"
    for k, p in enumerate(turns):
        features.append(feature("turn_%d" % k, "turn", point_geom(p), "Turn"))
    for k, p in enumerate(pinks):
        features.append(feature("crosswalk_end_%d" % k, "crosswalk_end", point_geom(p), "Crosswalk end"))
    for i, (p, r) in enumerate(placed):
        for q, qr in placed[i + 1:]:
            if om.dist(p, q) < r + qr + DOT_CLEARANCE - 0.01:
                raise SystemExit("%s: dots at %s and %s overlap" % (where, rnd(p), rnd(q)))
    return features


# ================================================================ the offset intersection

def build_offset(stop):
    """Exchange Street and Moulton Street meet Fore Street a little apart, on
    opposite sides. Fore Street is drawn straight through both junctions, the
    `near` arm leaves it on one side and the `far` arm further along on the
    other, so the crosswalk between the two corners runs at an angle."""
    conf = spec.OFFSET_JUNCTIONS[stop["junction"]]
    pa = AREA.node_xy(conf["near"]["node"])
    pb = AREA.node_xy(conf["far"]["node"])
    main_b = om.bearing(pa, pb)
    near_arm = next(g for g in om.merged_arms(AREA, [conf["near"]["node"]]) if g["name"] == conf["near"]["arm"])
    far_arm = next(g for g in om.merged_arms(AREA, [conf["far"]["node"]]) if g["name"] == conf["far"]["arm"])
    if stop["path"] == "near_to_far":
        up = (main_b + 180.0) % 360.0
    else:
        up = (far_arm["bearing"] + 180.0) % 360.0
    d = SIDEWALK_OFFSET
    s = conf["offset_mm"]
    th_fwd = screen_angle(main_b, up)                 # from the near junction toward the far one
    th_back = (th_fwd + 180.0) % 360.0
    th_near = screen_angle(near_arm["bearing"], up)
    th_far = screen_angle(far_arm["bearing"], up)
    u = unit(th_fwd)
    A, B = scale(u, -s / 2), scale(u, s / 2)
    n = cw_normal(th_fwd)
    near_sign = 1.0 if dot(n, unit(th_near)) > 0 else -1.0
    n_near = scale(n, near_sign)                       # towards the near arm's side of the main street
    n_far = scale(n_near, -1)
    if dot(n_far, unit(th_far)) <= 0:
        raise SystemExit("%s: the two side streets are on the same side" % stop["id"])

    def corner_at(centre, theta_a, theta_b):
        c = corner(theta_a, theta_b, d)
        return add(centre, c["points"][0]), c["t"]

    # Corners, clockwise. Which of each pair is clockwise depends on the side.
    if near_sign > 0:      # near arm clockwise of forward
        a_fwd, t_a_fwd = corner_at(A, th_fwd, th_near)
        a_back, t_a_back = corner_at(A, th_near, th_back)
        b_back, t_b_back = corner_at(B, th_back, th_far)
        b_fwd, t_b_fwd = corner_at(B, th_far, th_fwd + 360)
    else:
        a_fwd, t_a_fwd = corner_at(A, th_near, th_fwd + 360)
        a_back, t_a_back = corner_at(A, th_back, th_near)
        b_back, t_b_back = corner_at(B, th_far, th_back)
        b_fwd, t_b_fwd = corner_at(B, th_fwd, th_far)

    # The walk: along the main street to the near corner, across on the
    # diagonal, and on along the far side street (or the reverse).
    def walk(capped):
        def reach(origin, theta, gap):
            return add(origin, unit(theta), min(gap, line_limit(origin, theta, ROUTE_INSET)) if capped else gap)
        if stop["path"] == "near_to_far":
            return [reach(a_fwd, th_fwd, stop.get("start_gap", START_GAP)), a_fwd, b_back,
                    reach(b_back, th_far, stop.get("end_gap", END_GAP))]
        return [reach(b_back, th_far, stop.get("start_gap", START_GAP)), b_back, a_fwd,
                reach(a_fwd, th_fwd, stop.get("end_gap", END_GAP))]

    FRAME[:] = [0.0, 0.0]
    FRAME[:] = frame_for(walk(capped=False))

    def along(origin, theta, inset):
        return add(origin, unit(theta), line_limit(origin, theta, inset))

    features = []
    features.append(feature("road_main", "corridor",
                            line_geom([along((0.0, 0.0), th_back, -12), along((0.0, 0.0), th_fwd, -12)]),
                            conf["main"], custom={"width_mm": ROAD_HALF * 2}))
    features.append(feature("road_near", "corridor", line_geom([A, along(A, th_near, -12)]),
                            near_arm["name"], custom={"width_mm": ROAD_HALF * 2}))
    features.append(feature("road_far", "corridor", line_geom([B, along(B, th_far, -12)]),
                            far_arm["name"], custom={"width_mm": ROAD_HALF * 2}))
    features.append(feature("center", "center", point_geom((0, 0)), "Center", custom={"radius_mm": CENTER_R}))

    # Sidewalks. The main street's sidewalk on each side turns the corners of
    # the side street on that side and runs straight past the other junction.
    sidewalks = [
        ([along(scale(n_near, d), th_fwd, 2.0), a_fwd], conf["main"]),
        ([a_fwd, along(a_fwd, th_near, 2.0)], near_arm["name"]),
        ([along(a_back, th_near, 2.0), a_back], near_arm["name"]),
        ([a_back, along(a_back, th_back, 2.0)], conf["main"]),
        ([along(scale(n_far, d), th_back, 2.0), b_back], conf["main"]),
        ([b_back, along(b_back, th_far, 2.0)], far_arm["name"]),
        ([along(b_fwd, th_far, 2.0), b_fwd], far_arm["name"]),
        ([b_fwd, along(b_fwd, th_fwd, 2.0)], conf["main"]),
    ]
    for k, (pts, street) in enumerate(sidewalks):
        features.append(sidewalk_feature(k, pts, street))

    # Crosswalks, corner to corner as they are painted: the two across the side
    # streets share their corner with the angled one across the main street.
    marks = conf.get("markings", {})
    cross = {
        "diagonal": (a_fwd, b_back, conf["main"]),
        "near_arm": (a_fwd, a_back, near_arm["name"]),
        "near_main": (a_back, add(a_back, n_far, 2 * d), conf["main"]),
        "far_arm": (b_back, b_fwd, far_arm["name"]),
        "far_main": (b_fwd, add(b_fwd, n_near, 2 * d), conf["main"]),
    }
    for key in conf["crosswalks"]:
        p, q, street = cross[key]
        features += crosswalk_features("crosswalk_%s" % key, p, q, street, marks.get(key, "zebra"), False)

    features.append(feature("route", "route", line_geom(walk(capped=True)), "Route", custom={
        "start_text": spec.START_TEXT, "end_text": spec.END_TEXT}))
    shift_features(features, FRAME)
    FRAME[:] = [0.0, 0.0]
    tidy(features)
    place_dots(features, stop["id"])
    doc = document(stop["subtitle"], features, "center")
    drawn = set(conf["crosswalks"])
    facts = {
        "heading": up,
        "arms": [(conf["main"], om.compass8(main_b), "zebra" if "far_main" in drawn else None, False),
                 (near_arm["name"], om.compass8(near_arm["bearing"]), "zebra" if "near_arm" in drawn else None, False),
                 (conf["main"], om.compass8(main_b + 180), "zebra" if "near_main" in drawn else None, False),
                 (far_arm["name"], om.compass8(far_arm["bearing"]), "zebra" if "far_arm" in drawn else None, False)],
        "crossed": ["%s, on the angled crosswalk between %s and %s" % (conf["main"], near_arm["name"], far_arm["name"])],
    }
    return doc, facts


# ================================================================ output

def write_json(name, doc):
    path = os.path.join(MAPS_DIR, name + ".json")
    with open(path, "w") as handle:
        json.dump(doc, handle, indent=1)
        handle.write("\n")
    return path


def build_all(preview=False):
    os.makedirs(MAPS_DIR, exist_ok=True)
    for old in os.listdir(MAPS_DIR):
        if old.endswith(".json"):
            os.remove(os.path.join(MAPS_DIR, old))
    if preview:
        os.makedirs(PREVIEW_DIR, exist_ok=True)
        for old in os.listdir(PREVIEW_DIR):
            if old.endswith(".png"):
                os.remove(os.path.join(PREVIEW_DIR, old))
        import preview as pv

    by_id = {}
    overviews = {spec.TRAINING_OVERVIEW["id"]: spec.TRAINING_OVERVIEW, spec.ROUTE_OVERVIEW["id"]: spec.ROUTE_OVERVIEW}
    stops = {s["id"]: s for s in spec.STOPS}
    facts = {}
    for map_id in spec.ORDER:
        if map_id in overviews:
            ov = overviews[map_id]
            doc = build_overview(ov)
            entry = {"id": map_id, "kind": "overview", "phase": "training", "log_id": ov["title"],
                     "title": ov["title"], "subtitle": ov["subtitle"], "file": map_id,
                     "announcement": check_spoken(ov["description"], map_id), "items": []}
            if preview:
                pv.render_overview(doc, os.path.join(PREVIEW_DIR, map_id + ".png"))
        else:
            stop = stops[map_id]
            if stop["junction"] in spec.OFFSET_JUNCTIONS:
                doc, facts[map_id] = build_offset(stop)
            else:
                doc, facts[map_id] = build_intersection(stop)
            for item in stop["items"]:
                check_spoken(item["text"], map_id)
            entry = {"id": map_id, "kind": "intersection", "phase": stop["phase"], "log_id": stop["log_id"],
                     "title": stop["title"], "subtitle": stop["subtitle"], "file": map_id,
                     "announcement": check_spoken(stop["announcement"], map_id), "items": stop["items"]}
            if preview:
                pv.render_intersection(doc, os.path.join(PREVIEW_DIR, map_id + ".png"))
        write_json(map_id, doc)
        by_id[map_id] = entry
        print("%-22s %s" % (map_id, entry["subtitle"]))

    study = {
        "categories": [{"key": key, "title": title} for key, title in spec.CATEGORIES],
        "phases": [{"key": key, "title": title} for key, title in spec.PHASES.items()],
        "maps": [by_id[m] for m in spec.ORDER],
    }
    with open(os.path.join(MAPS_DIR, "study.json"), "w") as handle:
        json.dump(study, handle, indent=1)
        handle.write("\n")
    write_study_sheet(study, facts, overviews)


def write_study_sheet(study, facts, overviews):
    """docs/STUDY.md: every map and every word spoken on it, for proofreading."""
    titles = dict((c["key"], c["title"]) for c in study["categories"])
    phases = dict((p["key"], p["title"]) for p in study["phases"])
    lines = ["# Study maps and wording", "",
             "Generated by `tools/build_maps.py` from `tools/study_spec.py`. Do not edit by hand.", "",
             "Everything the app says on each map, in study order. The announcement plays when a map opens;",
             "the information items play with a double tap and are stepped through with three-finger swipes.",
             "In Trial 2 the researcher can switch each item off; the announcement always plays.", "",
             "## Points for the team to confirm", ""]
    lines += ["- %s" % note for note in spec.TEAM_NOTES]
    lines.append("")
    for m in study["maps"]:
        lines += ["## %s: %s" % (m["title"], m["subtitle"]), "",
                  "%s. Map file `%s.json`, logged as \"%s\"." % (phases[m["phase"]], m["file"], m["log_id"]), "",
                  "![%s](map_previews/%s.png)" % (m["title"], m["file"]), ""]
        if m["kind"] == "overview":
            ov = overviews[m["id"]]
            lines += ["**Overview:** %s" % m["announcement"], "",
                      "What each point says when touched:", "",
                      "- Start dot: \"%s\"" % ov["start"]["text"]]
            for leg in ov["legs"]:
                if leg["node"]["kind"] == "intersection":
                    stubs = join_names(sorted({s[2] for s in leg["node"]["stubs"]}))
                    lines.append("- Square %d: \"%s\" Cross streets drawn: %s." % (
                        leg["node"]["number"], leg["node"]["text"], stubs))
            lines += ["- End dot: \"%s\"" % ov["end"]["text"], ""]
        else:
            lines += ["**Announcement:** %s" % m["announcement"], ""]
            for n, item in enumerate(m["items"], 1):
                lines.append("%d. *%s:* %s" % (n, titles[item["category"]], item["text"]))
            f = facts.get(m["id"])
            if f:
                lines += ["", "Drawn with %s at the top. Legs:" % om.compass8(f["heading"]), ""]
                for name, toward, crossing, median in f["arms"]:
                    lines.append("- %s, to the %s: %s%s" % (
                        name, toward, ("%s crosswalk" % crossing) if crossing else "no crosswalk drawn",
                        ", median" if median else ""))
                lines.append("")
                lines.append("The route crosses: %s." % join_names(f["crossed"]))
            lines.append("")
    with open(os.path.join(REPO, "docs", "STUDY.md"), "w") as handle:
        handle.write("\n".join(lines))


if __name__ == "__main__":
    build_all(preview="--preview" in sys.argv)
