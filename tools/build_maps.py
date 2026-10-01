"""Builds the bundled map JSON for MultiNav Study 2 from OpenStreetMap.

    python3 tools/build_maps.py            # writes MultiNavStudy2/Maps/*.json
    python3 tools/build_maps.py --preview  # also writes docs/map_previews/*.png

Two kinds of map come out, both in the MultiNav TactileMapDocument format
with coordinates in millimetres on screen:

* Level 1, one per route: a schematic of the walk. Street order, turn
  direction and the side each cross street joins come from OSM; the
  streets are squared to the screen and spaced so every intersection is
  finger-sized. Origin top-left, y down.
* Level 2, one per intersection on a route: the junction at its true
  angles with roads, sidewalks, crosswalks, islands and the walking path.
  Origin at the junction centre, y down.

Physical sizes are fixed in millimetres so the maps feel the same on
every phone; the app only scales down if a screen is smaller than the
reference area below.
"""

import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import osm_model as om  # noqa: E402
import route_spec as spec  # noqa: E402

REPO = os.path.dirname(HERE)
MAPS_DIR = os.path.join(REPO, "MultiNavStudy2", "Maps")
PREVIEW_DIR = os.path.join(REPO, "docs", "map_previews")

# Reference drawing area in mm (a 6.1 inch iPhone below the navigation bar).
REF_W = 60.0
REF_H = 116.0
MARGIN = 1.0

# Level 1 sizes, mm. Must match the app's style constants.
L1_ROAD_HALF = 2.0
L1_SQUARE_HALF = 3.0
L1_DOT_R = 3.0
L1_RING_R = 4.0
L1_BOX_W, L1_BOX_H = 9.0, 6.0
L1_BOX_GAP = 2.0
MIN_GAP_JUNCTIONS = 10.0
MIN_GAP_ENDPOINT = 8.0
STUB = 8.0
EXTENSION = 4.0
MAX_STRETCH = 2.6           # most one axis may be stretched against the other

# Level 2 sizes, mm.
L2_ROAD_HALF = 6.0
L2_SIDEWALK_OFFSET = 13.1    # road half 6 + crosswalk 2.8 + kerb gap 1 + sidewalk half 2 + 1.3
L2_CENTER_R = 6.0
L2_MIN_CROSS_T = 7.0       # nearer than this a crosswalk would lie on the other road
L2_ISLAND_HALF_LEN = 2.2
L2_ISLAND_W = 3.0
# Roundabout close-up, mm.
RB_RING_R = 10.0
RB_ROAD_HALF = 3.5
RB_SIDEWALK_OFFSET = 6.7     # leg road half 3.5 + gap 1.2 + sidewalk half 2
RB_SIDEWALK_R = 16.7         # ring outer edge 13.5 + gap 1.2 + sidewalk half 2
RB_CROSSWALK_T = 19.5        # set back from the ring, as a real crossing is
RB_SPLITTER_FROM, RB_SPLITTER_TO = 13.5, 23.0
RB_SPLITTER_W = 2.0

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


def scale(v, s):
    return (v[0] * s, v[1] * s)


def rnd(p):
    return [round(p[0], ONE_DECIMAL), round(p[1], ONE_DECIMAL)]


def snap(angle):
    """Squares a screen angle: 90 degree steps when close, else 45."""
    a = angle % 360.0
    m90 = round(a / 90.0) * 90.0
    if abs(om.angle_diff(a, m90)) <= 30.0:
        return m90 % 360.0
    return (round(a / 45.0) * 45.0) % 360.0


def screen_angle(true_bearing, up):
    return (true_bearing - up) % 360.0


def join_names(names):
    names = list(names)
    if len(names) == 1:
        return names[0]
    if len(names) == 2:
        return "%s and %s" % (names[0], names[1])
    return ", ".join(names[:-1]) + " and " + names[-1]


def spoken_list(names):
    """"A, and B" or "A, B, and C": the comma gives the voice a pause."""
    names = list(names)
    if len(names) == 1:
        return names[0]
    return ", ".join(names[:-1]) + ", and " + names[-1]


def ordinal_legs(count):
    return "%d-way" % count


# ================================================================ junction models

AREAS = {key: om.Area(value["osm"], value["origin"]) for key, value in spec.AREAS.items()}


class Arm:
    def __init__(self, name, bearing, divided=False, oneway=False, crossing=None):
        self.name = name
        self.bearing = bearing % 360.0
        self.divided = divided
        self.oneway = oneway
        self.crossing = crossing

    def __repr__(self):
        return "%s@%.0f" % (self.name, self.bearing)


class Junction:
    def __init__(self, key):
        self.key = key
        conf = spec.JUNCTIONS[key]
        self.conf = conf
        self.area = AREAS[conf["area"]]
        self.control = conf.get("control")
        self.is_roundabout = "roundabout_way" in conf
        if self.is_roundabout:
            self._build_roundabout(conf["roundabout_way"])
        else:
            self.center = om.junction_center(self.area, conf["nodes"])
            self._build_arms()

    # ---- standard junction
    def _build_arms(self):
        conf = self.conf
        if "arms" in conf:
            arms = [Arm(a["name"], a["bearing"], a.get("divided", False)) for a in conf["arms"]]
        else:
            arms = []
            for group in om.merged_arms(self.area, conf["nodes"]):
                oneway = all(p["oneway"] in ("yes", "-1") for p in group["parts"]) and not group["divided"]
                arms.append(Arm(group["name"], group["bearing"], group["divided"], oneway))
        for extra in conf.get("extra_arms", []):
            arms.append(Arm(extra["name"], extra["bearing"]))
        self.arms = sorted(arms, key=lambda a: a.bearing)
        crossings = assigned_crossings(self)
        for arm in self.arms:
            arm.crossing = om.crossing_for_arm(self.area, self.center, arm.bearing, crossings)
            arm.island = crossing_island(self, arm)
        for ref in conf.get("no_crossing", []):
            self.arm(ref).crossing = None
        for ref in conf.get("assume_crossing", []):
            arm = self.arm(ref)
            if arm.crossing is None:
                arm.crossing = {"signal": bool(conf.get("assume_signal")), "marked": False, "unmarked": False,
                                "button": False, "no_sound": False, "raised": False, "assumed": True}

    # ---- roundabout
    def _build_roundabout(self, way_id):
        area = self.area
        ring = area.ways[way_id]
        points = [area.node_xy(n) for n in ring["nodes"]]
        self.center = (sum(p[0] for p in points) / len(points), sum(p[1] for p in points) / len(points))
        ring_nodes = set(ring["nodes"])
        legs = {}
        for way in area.ways.values():
            if way["id"] == way_id or not ring_nodes.intersection(way["nodes"]):
                continue
            name = way["tags"].get("name")
            if not name:
                continue
            pts = area.way_xy(way)
            far = max(pts, key=lambda p: om.dist(p, self.center))
            b = om.bearing(self.center, far)
            for key, leg in legs.items():
                if leg["name"] == name and abs(om.angle_diff(leg["bearing"], b)) < 40:
                    leg["bearings"].append(b)
                    leg["bearing"] = om.mean_bearing(leg["bearings"])
                    break
            else:
                legs[len(legs)] = {"name": name, "bearing": b, "bearings": [b]}
        self.arms = sorted([Arm(l["name"], l["bearing"], divided=True) for l in legs.values()],
                           key=lambda a: a.bearing)
        # Crossings and splitter islands, per leg.
        crossings = []
        islands = []
        for way in area.ways.values():
            tags = way["tags"]
            if tags.get("footway") not in ("crossing", "traffic_island"):
                continue
            pts = area.way_xy(way)
            mid = (sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts))
            if om.dist(mid, self.center) > 45:
                continue
            (islands if tags.get("footway") == "traffic_island" else crossings).append((mid, tags))
        for arm in self.arms:
            arm.crossing = om.crossing_for_arm(area, self.center, arm.bearing, crossings, half_angle=35)
            arm.island = any(abs(om.angle_diff(om.bearing(self.center, p), arm.bearing)) < 20 for p, _ in islands)

    def arm(self, ref):
        name, _, b = ref.partition("@")
        candidates = [a for a in self.arms if a.name == name]
        if not candidates:
            raise KeyError("%s has no arm named %s (arms: %s)" % (self.key, name, self.arms))
        if not b:
            return candidates[0]
        return min(candidates, key=lambda a: abs(om.angle_diff(a.bearing, float(b))))

    def title(self, first=None):
        names = []
        if first:
            names.append(first)
        for arm in self.arms:
            if arm.name not in names and not arm.name.startswith("Access road"):
                names.append(arm.name)
        return names


def assigned_crossings(junction):
    """Crossings nearer this junction than any other junction on a route."""
    area = junction.area
    others = [om.junction_center(area, c["nodes"]) for k, c in spec.JUNCTIONS.items()
              if c["area"] == junction.conf["area"] and "nodes" in c and k != junction.key]
    result = []
    for point, tags in om.crossing_points(area, junction.center, radius=21.0):
        mine = om.dist(point, junction.center)
        if all(mine <= om.dist(point, o) for o in others):
            result.append((point, tags))
    return result


def crossing_island(junction, arm):
    """True if OSM records a refuge island on this arm's crossing."""
    area = junction.area
    for way in area.ways.values():
        if way["tags"].get("footway") != "traffic_island":
            continue
        pts = area.way_xy(way)
        mid = (sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts))
        d = om.dist(mid, junction.center)
        if 4 < d < 26 and abs(om.angle_diff(om.bearing(junction.center, mid), arm.bearing)) < 25:
            return True
    return False


JUNCTION_CACHE = {}


def junction(key):
    if key not in JUNCTION_CACHE:
        JUNCTION_CACHE[key] = Junction(key)
    return JUNCTION_CACHE[key]


# ================================================================ spoken text

def control_sentence(j):
    c = j.control
    if c == "signals":
        return "Traffic signals."
    if c == "all_way_stop":
        return "All-way stop."
    if c == "side_stop":
        others = [n for n in j.title() if n != j.conf["stop_street"]]
        return "Stop sign for %s only. %s traffic does not stop." % (j.conf["stop_street"], others[0])
    if c == "none":
        return "No traffic signals or stop signs."
    if c == "roundabout":
        return "Traffic moves counterclockwise and yields when entering. No signals."
    return ""


def crosswalk_name(arm, half=None, roundabout=False):
    x = arm.crossing or {}
    street = arm.name
    if roundabout and x.get("raised"):
        text = "Raised crosswalk across %s" % street
    elif x.get("signal"):
        text = "Crosswalk with signal across %s" % street
        if x.get("button"):
            text += ", push button"
        if x.get("no_sound"):
            text += ", no audible signal"
    elif x.get("marked"):
        text = "Marked crosswalk across %s" % street
    elif x.get("unmarked"):
        text = "Unmarked crossing across %s" % street
    else:
        text = "Crosswalk across %s" % street
    if arm.oneway:
        text += ", one-way street"
    if half == "outbound":
        text += ", exit lane" if roundabout else ", lanes leaving the intersection"
    elif half == "inbound":
        text += ", entry lane" if roundabout else ", lanes entering the intersection"
    return text


def side_name(arm, side):
    """Compass side of the street for an arm and a 'cw'/'ccw' side."""
    b = arm.bearing + (90 if side == "cw" else -90)
    return om.compass8(b)


def resolve_side(arm, compass_word):
    target = {name: i * 45.0 for i, name in enumerate(om.COMPASS)}[compass_word]
    d = om.angle_diff(target, arm.bearing)
    if abs(abs(d) - 90) > 50:
        raise ValueError("%s side %s is not beside the street" % (arm, compass_word))
    return "cw" if d > 0 else "ccw"


# ================================================================ Level 1

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


def level2_file(route, key):
    return "%s_l2_%s" % (route["id"], key)


def build_level1(route):
    area = AREAS[route["area"]]
    up = route["up"]
    dep = route["departure"]
    dest = route["destination"]
    stops = route["stops"]
    juncs = [junction(s["junction"]) for s in stops]

    # Sequence of points: departure, junctions, destination (the destination
    # may sit just before the last junction, as on the Center Street walk).
    seq = [{"kind": "dep", "xy": area.xy(*dep["latlon"])}]
    for s, j in zip(stops, juncs):
        if s.get("destination_before_junction"):
            seq.append({"kind": "dest", "xy": area.xy(*dest["latlon"]), "street": s["street_before"]})
        seq.append({"kind": "junction", "xy": j.center, "stop": s, "j": j, "street": s["street_before"]})
    if not stops[-1].get("destination_before_junction"):
        seq.append({"kind": "dest", "xy": area.xy(*dest["latlon"]), "street": route["street_after"]})
    for i in range(1, len(seq)):
        seq[i]["street"] = seq[i].get("street") or seq[i - 1].get("street")

    # Street runs get one squared direction each.
    runs = []
    for i in range(1, len(seq)):
        street = seq[i]["street"]
        if runs and runs[-1]["street"] == street:
            runs[-1]["end"] = i
        else:
            runs.append({"street": street, "start": i - 1, "end": i})
    for run in runs:
        b = om.bearing(seq[run["start"]]["xy"], seq[run["end"]]["xy"])
        run["dir"] = snap(screen_angle(b, up))
    seg_dir = {}
    for run in runs:
        for i in range(run["start"], run["end"]):
            seg_dir[i] = run["dir"]

    def choose_stubs(i):
        """Squared direction for every arm the walk does not use."""
        j, s = seq[i]["j"], seq[i]["stop"]
        taken = set()
        if i > 0:
            taken.add((seg_dir[i - 1] + 180) % 360)
        if i < len(seq) - 1:
            taken.add(seg_dir[i])
        used_arms = set()
        if s.get("in"):
            used_arms.add(id(j.arm(s["in"][0])))
        if s.get("out"):
            used_arms.add(id(j.arm(s["out"][0])))
        stubs = []
        for arm in j.arms:
            if id(arm) in used_arms:
                continue
            want = snap(screen_angle(arm.bearing, up))
            options = sorted({(want + d) % 360 for d in (0, 45, -45, 90, -90, 135, -135)},
                             key=lambda o: abs(om.angle_diff(o, screen_angle(arm.bearing, up))))
            chosen = next(o for o in options if all(abs(om.angle_diff(o, t)) >= 44 for t in taken))
            taken.add(chosen)
            stubs.append((arm, chosen))
        return stubs

    stub_dirs = {i: choose_stubs(i) for i, item in enumerate(seq) if item["kind"] == "junction"}

    def box_normal(which):
        ep = dep if which == "dep" else dest
        if not ep.get("tag"):
            return None
        i = 0 if which == "dep" else next(k for k, it in enumerate(seq) if it["kind"] == "dest")
        travel = seg_dir[0] if which == "dep" else seg_dir[i - 1]
        return travel + (90 if ep["side"] == "right" else -90)

    def room_for_box(i, n):
        """Gap an endpoint i needs from junction n so its landmark box clears n's stubs."""
        which = seq[i]["kind"]
        if which not in ("dep", "dest") or seq[n]["kind"] != "junction":
            return 0.0
        normal = box_normal(which)
        if normal is None or not any(abs(om.angle_diff(d, normal)) < 50 for _, d in stub_dirs[n]):
            return 0.0
        along = unit(normal + 90)
        extent = abs(along[0]) * L1_BOX_W / 2 + abs(along[1]) * L1_BOX_H / 2
        return extent + L1_ROAD_HALF + 3.0

    def layout(kx, ky=None):
        ky = kx if ky is None else ky
        pos = [(0.0, 0.0)]
        for i in range(len(seq) - 1):
            u = unit(seg_dir[i])
            k = abs(u[0]) * kx + abs(u[1]) * ky
            real = om.dist(seq[i]["xy"], seq[i + 1]["xy"])
            kinds = {seq[i]["kind"], seq[i + 1]["kind"]}
            if kinds == {"junction"}:
                minimum = MIN_GAP_JUNCTIONS
            else:
                minimum = max(MIN_GAP_ENDPOINT, room_for_box(i, i + 1), room_for_box(i + 1, i))
            gap = max(real * k, minimum)
            pos.append(add(pos[-1], unit(seg_dir[i]), gap))
        return pos

    def geometry(pos):
        g = {"lines": [], "squares": [], "rings": [], "dots": [], "boxes": [], "stubs": []}
        route_index = [i for i in range(len(seq))
                       if not (i == len(seq) - 1 and seq[i]["kind"] == "junction")]
        g["route"] = [pos[i] for i in route_index]
        # Street runs, with extensions past the endpoints.
        for run in runs:
            pts = [pos[i] for i in range(run["start"], run["end"] + 1)]
            if run["start"] == 0:
                pts.insert(0, add(pts[0], unit(run["dir"]), -EXTENSION))
            if run["end"] == len(seq) - 1 and seq[-1]["kind"] == "dest":
                pts.append(add(pts[-1], unit(run["dir"]), EXTENSION))
            g["lines"].append((run["street"], pts))
        # Junction stubs for every arm the walk does not use.
        for i, item in enumerate(seq):
            if item["kind"] != "junction":
                continue
            j, s = item["j"], item["stop"]
            stubs = stub_dirs[i]
            for arm, d in stubs:
                g["stubs"].append((arm.name, pos[i], add(pos[i], unit(d), STUB), d, i))
            if j.is_roundabout:
                g["rings"].append(pos[i])
            else:
                g["squares"].append(pos[i])
        # Endpoint dots and landmark boxes.
        for idx in (0, len(g["route"]) - 1):
            g["dots"].append(g["route"][idx])
        for which, ep, ref in (("dep", dep, 0), ("dest", dest, None)):
            if not ep.get("tag"):
                continue
            i = 0 if which == "dep" else next(k for k, it in enumerate(seq) if it["kind"] == "dest")
            travel = seg_dir[0] if which == "dep" else seg_dir[i - 1]
            normal = cw_normal(travel) if ep["side"] == "right" else scale(cw_normal(travel), -1)
            extent = abs(normal[0]) * L1_BOX_W / 2 + abs(normal[1]) * L1_BOX_H / 2
            center = add(pos[i], normal, L1_ROAD_HALF + L1_BOX_GAP + extent)
            g["boxes"].append((which, ep, pos[i], normal, center))
        return g

    def bbox(g):
        xs, ys = [], []

        def take(p, r):
            xs.extend([p[0] - r, p[0] + r])
            ys.extend([p[1] - r, p[1] + r])
        for _, pts in g["lines"]:
            for p in pts:
                take(p, L1_ROAD_HALF)
        for _, a, b, _, _ in g["stubs"]:
            take(a, L1_ROAD_HALF)
            take(b, L1_ROAD_HALF)
        for p in g["squares"]:
            take(p, L1_SQUARE_HALF)
        for p in g["rings"]:
            take(p, L1_RING_R + 0.5)
        for p in g["dots"]:
            take(p, L1_DOT_R)
        for _, _, _, _, c in g["boxes"]:
            xs.extend([c[0] - L1_BOX_W / 2, c[0] + L1_BOX_W / 2])
            ys.extend([c[1] - L1_BOX_H / 2, c[1] + L1_BOX_H / 2])
        return min(xs), min(ys), max(xs), max(ys)

    def fits(kx, ky):
        x0, y0, x1, y1 = bbox(geometry(layout(kx, ky)))
        return x1 - x0 <= REF_W - 2 * MARGIN and y1 - y0 <= REF_H - 2 * MARGIN

    def largest(test, lo, hi):
        for _ in range(60):
            mid = (lo + hi) / 2
            lo, hi = (mid, hi) if test(mid) else (lo, mid)
        return lo

    # Largest even scale (mm per metre) that fits the reference area, then
    # stretch whichever axis still has room, by up to MAX_STRETCH, as the
    # earlier schematic maps stretched their height to fill a tall screen.
    # Each step backs off a hair so the next search does not start on the edge.
    k = largest(lambda v: fits(v, v), 0.0, 1.0) * 0.999
    ky = largest(lambda v: fits(k, v), k, k * MAX_STRETCH) * 0.999
    kx = largest(lambda v: fits(v, ky), k, min(k * MAX_STRETCH, ky * MAX_STRETCH)) * 0.999
    pos = layout(kx, ky)
    g = geometry(pos)
    x0, y0, x1, y1 = bbox(g)
    if x1 - x0 > REF_W - 2 * MARGIN + 0.01 or y1 - y0 > REF_H - 2 * MARGIN + 0.01:
        raise SystemExit("%s does not fit the reference area even at minimum spacing" % route["id"])
    shift = ((REF_W - (x1 - x0)) / 2 - x0, (REF_H - (y1 - y0)) / 2 - y0)

    def T(p):
        return add(p, shift)

    features = []
    for n, (street, pts) in enumerate(g["lines"]):
        features.append(feature("street_%d" % n, "corridor", line_geom([T(p) for p in pts]), street))
    # Opposite stubs of one street through a junction become one line.
    by_junction = {}
    for name, a, b, d, i in g["stubs"]:
        by_junction.setdefault(i, []).append((name, a, b, d))
    n = 0
    for i, stubs in sorted(by_junction.items()):
        used = set()
        for x, (name, a, b, d) in enumerate(stubs):
            if x in used:
                continue
            partner = next((y for y, s in enumerate(stubs) if y != x and y not in used and s[0] == name
                            and abs(om.angle_diff(s[3], d + 180)) < 1), None)
            if partner is not None:
                used.update({x, partner})
                pts = [stubs[partner][2], a, b]
            else:
                used.add(x)
                pts = [a, b]
            features.append(feature("cross_%d" % n, "corridor", line_geom([T(p) for p in pts]), name))
            n += 1

    waypoint_ids = []
    for i, item in enumerate(seq):
        if item["kind"] != "junction":
            continue
        j, s = item["j"], item["stop"]
        fid = "j_%s" % j.key
        waypoint_ids.append(fid)
        route_street = s["street_before"]
        names = j.title(first=route_street)
        if j.is_roundabout:
            announcement = "Roundabout of %s" % spoken_list(names)
            kind = "roundabout"
        else:
            announcement = "%s intersection of %s" % (ordinal_legs(len(j.arms)), spoken_list(names))
            kind = "junction"
        features.append(feature(fid, "intersection", point_geom(T(pos[i])), join_names(names), custom={
            "kind": kind, "legs": len(j.arms), "detail": level2_file(route, j.key),
            "announcement": announcement}))

    for which, ep, anchor, normal, center in g["boxes"]:
        direction = ep["side"]
        features.append(feature("landmark_%s" % which, "landmark", point_geom(T(anchor)), ep["name"],
                                side=direction, custom={
                                    "tag": ep["tag"],
                                    "announcement": "%s on your %s" % (ep["name"], direction),
                                    "offset_x": round(normal[0], 3), "offset_y": round(normal[1], 3)}))

    features.append(feature("route", "route", line_geom([T(p) for p in g["route"]]), route["title"], custom={
        "departure": dep["spoken"], "destination": dest["spoken"],
        "waypoints": ",".join(waypoint_ids)}))

    doc = {
        "type": "FeatureCollection",
        "version": "1.0",
        "metadata": {"name": "Route %d: %s" % (route["number"], route["title"]),
                     "scale": "1 unit = 1 mm on screen", "coordinate_unit": "arbitrary",
                     "coordinate_origin": "top-left", "author": "tools/build_maps.py"},
        "bounds": {"width": REF_W, "height": REF_H},
        "features": features,
    }
    return doc, {"k_mm_per_m": (kx, ky), "seq": seq}


# ================================================================ Level 2

def arm_limit(theta, inset):
    """Distance along an arm before it leaves the reference area."""
    s, c = unit(theta)
    hw, hh = REF_W / 2 - inset, REF_H / 2 - inset
    limits = []
    if abs(s) > 1e-6:
        limits.append(hw / abs(s))
    if abs(c) > 1e-6:
        limits.append(hh / abs(c))
    return min(limits)


def side_limit(theta, side, offset, inset):
    """Distance along an arm's sidewalk line before it leaves the reference area."""
    u = unit(theta)
    n = cw_normal(theta) if side == "cw" else scale(cw_normal(theta), -1)
    hw, hh = REF_W / 2 - inset, REF_H / 2 - inset
    limits = []
    for axis, half in ((0, hw), (1, hh)):
        if abs(u[axis]) < 1e-6:
            continue
        bound = half if u[axis] > 0 else -half
        limits.append((bound - offset * n[axis]) / u[axis])
    return min(limits)


class Level2Geometry:
    """Corners, crosswalk ends and sidewalk lines for one junction.

    Crosswalks run corner to corner, so a walk along a sidewalk meets the
    crosswalk end exactly where the sidewalk turns the corner, and a
    straight walk past a square junction has no bends at all.
    """

    def __init__(self, j, up):
        self.j = j
        self.up = up
        self.rb = j.is_roundabout
        self.arms = sorted(j.arms, key=lambda a: screen_angle(a.bearing, up))
        self.theta = {id(a): screen_angle(a.bearing, up) for a in self.arms}
        self.d = RB_SIDEWALK_OFFSET if self.rb else L2_SIDEWALK_OFFSET
        n = len(self.arms)
        self.corners = []  # corner k lies between arm k and arm k+1 (clockwise)
        for k in range(n):
            a, b = self.arms[k], self.arms[(k + 1) % n]
            alpha = (self.theta[id(b)] - self.theta[id(a)]) % 360.0
            if n == 1:
                alpha = 360.0
            self.corners.append(self._corner(a, b, alpha))
        self.end_t = {}
        for k, arm in enumerate(self.arms):
            if self.rb:
                self.end_t[(id(arm), "ccw")] = RB_CROSSWALK_T
                self.end_t[(id(arm), "cw")] = RB_CROSSWALK_T
                continue
            before, after = self.corners[(k - 1) % n], self.corners[k]
            t_ccw = before["t_b"] if before["kind"] == "point" and before["t_b"] >= L2_MIN_CROSS_T else None
            t_cw = after["t_a"] if after["kind"] == "point" and after["t_a"] >= L2_MIN_CROSS_T else None
            if t_ccw is None and t_cw is None:
                t_ccw = t_cw = L2_MIN_CROSS_T
            self.end_t[(id(arm), "ccw")] = t_ccw if t_ccw is not None else t_cw
            self.end_t[(id(arm), "cw")] = t_cw if t_cw is not None else t_ccw

    def _corner(self, a, b, alpha):
        ta = self.theta[id(a)]
        d = self.d
        if self.rb:
            half = math.degrees(math.asin(d / RB_SIDEWALK_R))
            if alpha > 2 * half + 1:
                start = ta + half
                sweep = alpha - 2 * half
                steps = max(2, int(sweep / 8))
                arc = [scale(unit(start + sweep * i / steps), RB_SIDEWALK_R) for i in range(steps + 1)]
                t_edge = math.sqrt(RB_SIDEWALK_R ** 2 - d ** 2)
                return {"kind": "arc", "points": arc, "t_a": t_edge, "t_b": t_edge}
        if alpha < 179.0:
            r = d / math.sin(math.radians(alpha / 2))
            p = scale(unit(ta + alpha / 2), r)
            t = d / math.tan(math.radians(alpha / 2))
            return {"kind": "point", "points": [p], "t_a": t, "t_b": t}
        # Flat or reflex side: the sidewalk runs straight past the junction,
        # bending round the back of it when the side is wider than 180 degrees.
        start = ta + 90
        sweep = alpha - 180
        if sweep < 1:
            return {"kind": "flat", "points": [scale(unit(start), d)], "t_a": 0.0, "t_b": 0.0}
        steps = max(1, int(sweep / 10))
        arc = [scale(unit(start + sweep * i / steps), d) for i in range(steps + 1)]
        return {"kind": "flat", "points": arc, "t_a": 0.0, "t_b": 0.0}

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

    def axis_crossing(self, arm):
        """Where the crosswalk meets the arm's centre line."""
        a, b = self.cross_end(arm, "ccw"), self.cross_end(arm, "cw")
        u = unit(self.theta[id(arm)])
        ca = a[0] * u[1] - a[1] * u[0]
        cb = b[0] * u[1] - b[1] * u[0]
        s = ca / (ca - cb) if abs(ca - cb) > 1e-9 else 0.5
        return (a[0] + (b[0] - a[0]) * s, a[1] + (b[1] - a[1]) * s)

    def far(self, arm, inset, side=None):
        if side is None:
            return arm_limit(self.theta[id(arm)], inset)
        return side_limit(self.theta[id(arm)], side, self.d, inset)


def build_level2(route, stop, previous_stop, next_stop):
    j = junction(stop["junction"])
    up = route["up"]
    geo = Level2Geometry(j, up)
    features = []
    route_street = stop["street_before"]
    names = j.title(first=route_street)
    title = j.conf.get("name") or join_names(names)

    # Intro line spoken when the view opens.
    if j.is_roundabout:
        intro = "Roundabout view. %s. %d streets meet at a one-lane roundabout. %s" % (
            title, len(j.arms), control_sentence(j))
    else:
        intro = "Intersection view. %s. %s intersection. %s" % (
            title, ordinal_legs(len(j.arms)), control_sentence(j))
    features.append(feature("info", "info", point_geom((0, 0)), intro.strip(), custom={
        "title": title, "kind": "roundabout" if j.is_roundabout else "junction",
        "legs": len(j.arms), "spoken_title": spoken_list(names)}))

    road_half = RB_ROAD_HALF if j.is_roundabout else L2_ROAD_HALF
    # Roads.
    for k, arm in enumerate(geo.arms):
        th = geo.theta[id(arm)]
        start = scale(unit(th), RB_RING_R) if j.is_roundabout else (0.0, 0.0)
        end = scale(unit(th), geo.far(arm, 0) + 12)
        name = arm.name + (", one way" if arm.oneway else "")
        features.append(feature("road_%d" % k, "corridor", line_geom([start, end]), name,
                                custom={"width_mm": road_half * 2, "divided": "yes" if arm.divided else None}))
        if arm.divided and not j.is_roundabout:
            t0 = math.hypot(*geo.axis_crossing(arm)) + (L2_ISLAND_HALF_LEN + 1.5 if arm.island else 3.5)
            features.append(feature("median_%d" % k, "median",
                                    line_geom([scale(unit(th), t0), scale(unit(th), geo.far(arm, 0) + 12)]),
                                    "Median of %s" % arm.name, custom={"width_mm": 2.0}))
    if j.is_roundabout:
        features.append(feature("ring", "roundabout", point_geom((0, 0)),
                                "Roundabout. Traffic moves counterclockwise",
                                custom={"radius_mm": RB_RING_R, "width_mm": RB_ROAD_HALF * 2}))
        features.append(feature("central_island", "central_island", point_geom((0, 0)),
                                "Center island. Not a walkway",
                                custom={"radius_mm": RB_RING_R - RB_ROAD_HALF}))
        for k, arm in enumerate(geo.arms):
            if not arm.island:
                continue
            th = geo.theta[id(arm)]
            features.append(feature("splitter_%d" % k, "island",
                                    line_geom([scale(unit(th), RB_SPLITTER_FROM), scale(unit(th), RB_SPLITTER_TO)]),
                                    "Splitter island on %s. Pedestrian refuge between the entry and exit lanes" % arm.name,
                                    custom={"width_mm": RB_SPLITTER_W}))
    else:
        features.append(feature("center", "center", point_geom((0, 0)), "Center",
                                custom={"radius_mm": L2_CENTER_R}))

    # Sidewalks: each corner split into the two streets it runs along.
    sw = 0
    for k, corner in enumerate(geo.corners):
        a = geo.arms[k]
        b = geo.arms[(k + 1) % len(geo.arms)]
        far_a = geo.side_point(a, "cw", geo.far(a, 2.0, "cw"))
        far_b = geo.side_point(b, "ccw", geo.far(b, 2.0, "ccw"))
        pts = corner["points"]
        if j.is_roundabout and corner["kind"] == "arc":
            edge_a = geo.side_point(a, "cw", corner["t_a"])
            edge_b = geo.side_point(b, "ccw", corner["t_b"])
            features.append(feature("sidewalk_%d" % sw, "sidewalk", line_geom([far_a, edge_a]),
                                    "Sidewalk on the %s side of %s" % (side_name(a, "cw"), a.name)))
            features.append(feature("sidewalk_%d" % (sw + 1), "sidewalk", line_geom(pts),
                                    "Sidewalk around the roundabout"))
            features.append(feature("sidewalk_%d" % (sw + 2), "sidewalk", line_geom([edge_b, far_b]),
                                    "Sidewalk on the %s side of %s" % (side_name(b, "ccw"), b.name)))
            sw += 3
            continue
        if corner["kind"] == "point":
            first, second = [far_a, pts[0]], [pts[0], far_b]
        else:
            mid = len(pts) // 2
            first, second = [far_a] + pts[:mid + 1], pts[mid:] + [far_b]
        features.append(feature("sidewalk_%d" % sw, "sidewalk", line_geom(first),
                                "Sidewalk on the %s side of %s" % (side_name(a, "cw"), a.name)))
        features.append(feature("sidewalk_%d" % (sw + 1), "sidewalk", line_geom(second),
                                "Sidewalk on the %s side of %s" % (side_name(b, "ccw"), b.name)))
        sw += 2

    # Crosswalks and refuge islands.
    for k, arm in enumerate(geo.arms):
        if not arm.crossing:
            continue
        ccw_end = geo.cross_end(arm, "ccw")
        cw_end = geo.cross_end(arm, "cw")
        th = geo.theta[id(arm)]
        mid = geo.axis_crossing(arm)
        split = arm.island
        common = {"assumed": "yes" if arm.crossing.get("assumed") else None}
        if split:
            gap = (RB_SPLITTER_W / 2 + 0.6) if j.is_roundabout else L2_ISLAND_W / 2 + 0.3
            n = cw_normal(th)
            features.append(feature("crosswalk_%d_in" % k, "crosswalk", line_geom([ccw_end, add(mid, n, -gap)]),
                                    crosswalk_name(arm, "inbound", j.is_roundabout),
                                    custom=dict(common, endpoints="start")))
            features.append(feature("crosswalk_%d_out" % k, "crosswalk", line_geom([add(mid, n, gap), cw_end]),
                                    crosswalk_name(arm, "outbound", j.is_roundabout),
                                    custom=dict(common, endpoints="end")))
            if not j.is_roundabout:
                u = unit(th)
                features.append(feature("refuge_%d" % k, "island",
                                        line_geom([add(mid, u, -L2_ISLAND_HALF_LEN), add(mid, u, L2_ISLAND_HALF_LEN)]),
                                        "Pedestrian refuge island in the middle of %s" % arm.name,
                                        custom={"width_mm": L2_ISLAND_W}))
        else:
            features.append(feature("crosswalk_%d" % k, "crosswalk", line_geom([ccw_end, cw_end]),
                                    crosswalk_name(arm, None, j.is_roundabout),
                                    custom=dict(common, endpoints="both")))

    # Walking path through the junction.
    path, crossed = walking_path(geo, stop)
    first_is_route_start = bool(stop.get("starts_here"))
    last_is_route_end = bool(stop.get("ends_here"))
    pair = spoken_list(names)
    departure = ("Your location, %s" % route["departure"]["spoken"]) if first_is_route_start \
        else "Your location at the intersection of %s" % pair
    if last_is_route_end:
        destination = "Destination, %s. Double tap to return to map overview." % route["destination"]["spoken"]
    else:
        destination = "End of route. Double tap to return to map overview."
    features.append(feature("route", "route", line_geom(path), "Route", custom={
        "departure": departure, "destination": destination}))

    doc = {
        "type": "FeatureCollection",
        "version": "1.0",
        "metadata": {"name": title, "scale": "1 unit = 1 mm on screen", "coordinate_unit": "arbitrary",
                     "coordinate_origin": "center", "author": "tools/build_maps.py"},
        "bounds": {"width": REF_W, "height": REF_H},
        "features": features,
    }
    summary = {
        "title": title,
        "legs": len(j.arms),
        "roundabout": j.is_roundabout,
        "control": control_sentence(j) or "Not recorded",
        "control_source": control_source(j),
        "arms": [(arm.name, om.compass8(arm.bearing), crosswalk_name(arm, None, j.is_roundabout) if arm.crossing else None,
                  bool(arm.crossing and arm.crossing.get("assumed")), bool(arm.island)) for arm in j.arms],
        "crossed": [crosswalk_name(arm, None, j.is_roundabout) if arm.crossing else "%s (no crosswalk in OSM)" % arm.name
                    for arm in crossed],
    }
    return doc, summary


def control_source(j):
    if j.is_roundabout:
        return "OSM"
    conf = j.conf
    if conf.get("control") is None:
        return ""
    return conf.get("control_source", "OSM")


def walking_path(geo, stop):
    j = geo.j
    n = len(geo.arms)
    in_arm = j.arm(stop["in"][0])
    in_side = resolve_side(in_arm, stop["in"][1])
    corner = geo.index(in_arm) if in_side == "cw" else (geo.index(in_arm) - 1) % n

    if stop.get("out"):
        out_arm = j.arm(stop["out"][0])
        out_side = resolve_side(out_arm, stop["out"][1])
        target = geo.index(out_arm) if out_side == "cw" else (geo.index(out_arm) - 1) % n
    else:
        out_arm, out_side = None, None
        target = corner

    cw_steps = (target - corner) % n
    ccw_steps = (corner - target) % n
    via = stop.get("via") or ("cw" if cw_steps <= ccw_steps else "ccw")
    if cw_steps == 0 and ccw_steps == 0:
        via = None

    inset_route = 2.5
    if stop.get("starts_here"):
        start_t = geo.cross_t(in_arm, in_side) + 7.0
    else:
        start_t = geo.far(in_arm, inset_route, in_side)
    points = [geo.side_point(in_arm, in_side, start_t), geo.cross_end(in_arm, in_side)]

    current_arm, current_side = in_arm, in_side
    crossed = []
    c = corner
    if via == "cw":
        for _ in range(cw_steps):
            nxt = geo.arms[(c + 1) % n]
            crossed.append(nxt)
            if current_arm is not nxt:
                points += ordered_corner(geo, c, current_arm)
                points.append(geo.cross_end(nxt, "ccw"))
            points.append(geo.cross_end(nxt, "cw"))
            current_arm, current_side = nxt, "cw"
            c = (c + 1) % n
    elif via == "ccw":
        for _ in range(ccw_steps):
            here = geo.arms[c]
            crossed.append(here)
            if current_arm is not here:
                points += ordered_corner(geo, c, current_arm)
                points.append(geo.cross_end(here, "cw"))
            points.append(geo.cross_end(here, "ccw"))
            current_arm, current_side = here, "ccw"
            c = (c - 1) % n

    if out_arm is not None:
        if current_arm is not out_arm:
            points += ordered_corner(geo, c, current_arm)
            points.append(geo.cross_end(out_arm, out_side))
        end_t = geo.cross_t(out_arm, out_side) + 7.0 if stop.get("ends_here") else geo.far(out_arm, inset_route, out_side)
        points.append(geo.side_point(out_arm, out_side, end_t))
    else:
        # The walk ends at this corner.
        pts = geo.corners[c]["points"]
        points.append(pts[0] if len(pts) == 1 else pts[len(pts) // 2])
    points = dedupe(points)
    if geo.rb:
        crossing_ends = [geo.cross_end(a, s) for a in geo.arms for s in ("cw", "ccw")]
        points = round_bends(points, crossing_ends)
    return points, crossed


def round_bends(points, keep, radius=2.5, threshold=40.0):
    """Rounds sharp bends that are not crosswalk ends, as a curved kerb would."""
    out = [points[0]]
    for i in range(1, len(points) - 1):
        a, b, c = points[i - 1], points[i], points[i + 1]
        h1 = math.degrees(math.atan2(b[1] - a[1], b[0] - a[0]))
        h2 = math.degrees(math.atan2(c[1] - b[1], c[0] - b[0]))
        turn = abs(om.angle_diff(h2, h1))
        if turn <= threshold or any(om.dist(b, k) < 0.3 for k in keep):
            out.append(b)
            continue
        r = min(radius, om.dist(a, b) / 2, om.dist(b, c) / 2)
        p0 = add(b, scale((a[0] - b[0], a[1] - b[1]), r / om.dist(a, b)))
        p2 = add(b, scale((c[0] - b[0], c[1] - b[1]), r / om.dist(b, c)))
        for s in (0.0, 0.25, 0.5, 0.75, 1.0):
            q = (1 - s) ** 2
            out.append((q * p0[0] + 2 * (1 - s) * s * b[0] + s * s * p2[0],
                        q * p0[1] + 2 * (1 - s) * s * b[1] + s * s * p2[1]))
    out.append(points[-1])
    return out


def ordered_corner(geo, c, coming_from):
    """Corner points ordered from the side of `coming_from`."""
    pts = list(geo.corners[c]["points"])
    a = geo.arms[c]
    return pts if coming_from is a else pts[::-1]


def dedupe(points):
    out = []
    for p in points:
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
    manifest = {"routes": []}
    sheets = []
    for route in spec.ROUTES:
        doc, info = build_level1(route)
        l1_name = "%s_overview" % route["id"]
        write_json(l1_name, doc)
        details = []
        summaries = []
        for i, stop in enumerate(route["stops"]):
            prev_stop = route["stops"][i - 1] if i > 0 else None
            next_stop = route["stops"][i + 1] if i + 1 < len(route["stops"]) else None
            l2, summary = build_level2(route, stop, prev_stop, next_stop)
            summaries.append((stop, summary))
            name = level2_file(route, stop["junction"])
            write_json(name, l2)
            details.append(name)
            if preview:
                import preview as pv
                pv.render_level2(l2, os.path.join(PREVIEW_DIR, name + ".png"))
        if preview:
            import preview as pv
            pv.render_level1(doc, os.path.join(PREVIEW_DIR, l1_name + ".png"))
        manifest["routes"].append({
            "id": route["id"], "number": route["number"], "title": route["title"],
            "summary": route["summary"], "overview": l1_name, "details": details,
            "departure": route["departure"]["spoken"], "destination": route["destination"]["spoken"],
        })
        sheets.append((route, summaries))
        print("%s: %d intersections, schematic scale %.3f mm per metre across, %.3f up" % (
            route["id"], len(route["stops"]), info["k_mm_per_m"][0], info["k_mm_per_m"][1]))
    with open(os.path.join(MAPS_DIR, "routes.json"), "w") as handle:
        json.dump(manifest, handle, indent=1)
        handle.write("\n")
    write_route_sheet(sheets)


def write_route_sheet(sheets):
    """docs/ROUTES.md: every intersection, its control, crossings and what the walk crosses."""
    up_names = {45: "northeast", 135: "southeast", 225: "southwest", 315: "northwest", 0: "north"}
    lines = ["# Routes", "",
             "Generated by `tools/build_maps.py` from OpenStreetMap and `tools/route_spec.py`. Do not edit by hand.",
             "",
             "Crosswalks marked *assumed* are not in OpenStreetMap; they were added from the team's notes or",
             "because the junction has no crossing data at all. Please check them on site.", ""]
    for route, summaries in sheets:
        lines += ["## Route %d: %s" % (route["number"], route["title"]), "",
                  "From %s to %s. %s." % (route["departure"]["name"], route["destination"]["name"], route["summary"]),
                  "Drawn with %s at the top of the screen." % up_names.get(route["up"], "%d degrees" % route["up"]), "",
                  "| # | Intersection | Legs | Control | Walk crosses |",
                  "|---|---|---|---|---|"]
        for n, (stop, s) in enumerate(summaries, 1):
            control = s["control"] + (" (%s)" % s["control_source"] if s["control_source"] else "")
            crossed = "; ".join(s["crossed"]) if s["crossed"] else "nothing"
            kind = "roundabout" if s["roundabout"] else ""
            lines.append("| %d | %s %s | %d | %s | %s |" % (n, s["title"], kind, s["legs"], control, crossed))
        lines.append("")
        lines.append("<details><summary>Crosswalks at each intersection</summary>")
        lines.append("")
        for stop, s in summaries:
            lines.append("**%s**" % s["title"])
            lines.append("")
            for name, toward, crossing, assumed, island in s["arms"]:
                if crossing:
                    extra = (" (assumed)" if assumed else "") + (", refuge island" if island else "")
                    lines.append("- %s leg, to the %s: %s%s" % (name, toward, crossing, extra))
                else:
                    lines.append("- %s leg, to the %s: no crosswalk in OSM" % (name, toward))
            lines.append("")
        lines.append("</details>")
        lines.append("")
    with open(os.path.join(REPO, "docs", "ROUTES.md"), "w") as handle:
        handle.write("\n".join(lines))


if __name__ == "__main__":
    build_all(preview="--preview" in sys.argv)
