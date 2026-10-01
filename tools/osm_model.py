"""Reads the OpenStreetMap extracts and describes each junction on a route.

A junction is described by its arms (the streets leaving it, with a true
compass bearing), the crossings recorded on each arm, and how traffic is
controlled there. Everything here is plain data read from OSM; the study
choices that sit on top of it live in route_spec.py.
"""

import collections
import json
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))

M_PER_DEG_LAT = 111_132.0
ROAD_TYPES = {
    "motorway", "trunk", "primary", "secondary", "tertiary", "unclassified",
    "residential", "living_street", "motorway_link", "trunk_link",
    "primary_link", "secondary_link", "tertiary_link",
}


class Area:
    """One OSM extract with a local metric projection around `origin`."""

    def __init__(self, path, origin):
        self.origin = origin
        self.m_per_deg_lon = 111_320.0 * math.cos(math.radians(origin[0]))
        self.nodes, self.ways = _load(os.path.join(HERE, path))
        self.node_ways = collections.defaultdict(list)
        for way in self.ways.values():
            for node_id in way["nodes"]:
                self.node_ways[node_id].append(way)

    def xy(self, lat, lon):
        return ((lon - self.origin[1]) * self.m_per_deg_lon,
                (lat - self.origin[0]) * M_PER_DEG_LAT)

    def node_xy(self, node_id):
        node = self.nodes[node_id]
        return self.xy(node["lat"], node["lon"])

    def way_xy(self, way):
        return [self.node_xy(n) for n in way["nodes"] if n in self.nodes]


def _load(path):
    with open(path) as handle:
        data = json.load(handle)
    nodes, ways = {}, {}
    for element in data["elements"]:
        if element["type"] == "node":
            node = nodes.setdefault(element["id"], {
                "id": element["id"], "lat": element["lat"], "lon": element["lon"], "tags": {}})
            node["tags"].update(element.get("tags", {}))
        elif element["type"] == "way":
            way = ways.setdefault(element["id"], {
                "id": element["id"], "nodes": element["nodes"], "tags": {}})
            way["tags"].update(element.get("tags", {}))
    return nodes, ways


# ---------------------------------------------------------------- geometry

def dist(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def bearing(a, b):
    """Compass bearing in degrees from a to b (x east, y north)."""
    return (math.degrees(math.atan2(b[0] - a[0], b[1] - a[1])) + 360.0) % 360.0


def angle_diff(a, b):
    """Smallest signed difference a - b in degrees, in (-180, 180]."""
    d = (a - b + 180.0) % 360.0 - 180.0
    return 180.0 if d == -180.0 else d


def mean_bearing(values):
    x = sum(math.sin(math.radians(v)) for v in values)
    y = sum(math.cos(math.radians(v)) for v in values)
    return (math.degrees(math.atan2(x, y)) + 360.0) % 360.0


COMPASS = ["north", "northeast", "east", "southeast",
           "south", "southwest", "west", "northwest"]


def compass8(b):
    return COMPASS[int(((b % 360.0) + 22.5) // 45) % 8]


# ---------------------------------------------------------------- junctions

def junction_center(area, node_ids):
    points = [area.node_xy(n) for n in node_ids]
    return (sum(p[0] for p in points) / len(points), sum(p[1] for p in points) / len(points))


def _walk(area, way, index, step, length):
    points = [area.node_xy(way["nodes"][index])]
    travelled = 0.0
    i = index
    while 0 <= i + step < len(way["nodes"]):
        i += step
        point = area.node_xy(way["nodes"][i])
        travelled += dist(points[-1], point)
        points.append(point)
        if travelled >= length:
            break
    return points


def raw_arms(area, node_ids, reach=30.0):
    """Every road piece leaving the junction, with its local bearing."""
    cluster = set(node_ids)
    center = junction_center(area, node_ids)
    arms = []
    for node_id in cluster:
        for way in area.node_ways[node_id]:
            highway = way["tags"].get("highway")
            if highway not in ROAD_TYPES and highway != "service":
                continue
            for index, n in enumerate(way["nodes"]):
                if n != node_id:
                    continue
                for step in (1, -1):
                    nxt = index + step
                    if not 0 <= nxt < len(way["nodes"]):
                        continue
                    if way["nodes"][nxt] in cluster:
                        continue
                    points = _walk(area, way, index, step, reach)
                    arms.append({
                        "name": way["tags"].get("name"),
                        "highway": highway,
                        "bearing": bearing(center, points[-1]),
                        "way": way["id"],
                        "oneway": way["tags"].get("oneway"),
                        "lanes": way["tags"].get("lanes"),
                    })
    return arms


def merged_arms(area, node_ids, merge_within=40.0):
    """Arms of the same street within `merge_within` degrees become one arm.

    A merged arm made of two one-way carriageways is marked divided.
    """
    groups = []
    for arm in sorted(raw_arms(area, node_ids), key=lambda a: a["bearing"]):
        if arm["highway"] == "service" or not arm["name"]:
            continue
        for group in groups:
            if group["name"] == arm["name"] and abs(angle_diff(group["bearing"], arm["bearing"])) <= merge_within:
                group["parts"].append(arm)
                group["bearing"] = mean_bearing([p["bearing"] for p in group["parts"]])
                break
        else:
            groups.append({"name": arm["name"], "bearing": arm["bearing"], "parts": [arm]})
    for group in groups:
        ways = {p["way"] for p in group["parts"]}
        oneways = [p for p in group["parts"] if p["oneway"] == "yes"]
        group["divided"] = len(ways) >= 2 and len(oneways) >= 2
        group["highway"] = group["parts"][0]["highway"]
    return groups


def crossing_points(area, center, radius=36.0):
    """Crossing nodes and crossing ways near a junction, as (point, tags)."""
    found = []
    for node in area.nodes.values():
        tags = node["tags"]
        if tags.get("highway") == "crossing" or "crossing" in tags:
            point = area.xy(node["lat"], node["lon"])
            if dist(point, center) <= radius:
                found.append((point, tags))
    for way in area.ways.values():
        tags = way["tags"]
        if tags.get("footway") == "crossing":
            points = area.way_xy(way)
            if not points:
                continue
            mid = (sum(p[0] for p in points) / len(points), sum(p[1] for p in points) / len(points))
            if dist(mid, center) <= radius:
                found.append((mid, tags))
    return found


def crossing_for_arm(area, center, arm_bearing, crossings, half_angle=32.0):
    """Summarises the crossing recorded on one arm, or None if OSM has none."""
    hits = []
    for point, tags in crossings:
        d = dist(point, center)
        if d < 3.0:
            continue
        if abs(angle_diff(bearing(center, point), arm_bearing)) <= half_angle:
            hits.append(tags)
    if not hits:
        return None
    kinds = [t.get("crossing") for t in hits if t.get("crossing")]
    markings = [t.get("crossing:markings") for t in hits if t.get("crossing:markings")]
    summary = {
        "signal": any(k == "traffic_signals" for k in kinds) or any(t.get("crossing:signals") == "yes" for t in hits),
        "marked": any(m in ("yes", "zebra", "lines", "surface", "dashes", "ladder") for m in markings)
                  or any(k in ("marked", "zebra") for k in kinds),
        "unmarked": any(k == "unmarked" for k in kinds) or any(m == "no" for m in markings),
        "button": any(t.get("button_operated") == "yes" for t in hits),
        "no_sound": any(t.get("traffic_signals:sound") == "no" for t in hits),
        "raised": any(t.get("traffic_calming") == "table" for t in hits),
    }
    if summary["marked"]:
        summary["unmarked"] = False
    return summary


def has_signals(area, center, radius=26.0):
    for node in area.nodes.values():
        if node["tags"].get("highway") == "traffic_signals" and dist(area.xy(node["lat"], node["lon"]), center) <= radius:
            return True
    return False
