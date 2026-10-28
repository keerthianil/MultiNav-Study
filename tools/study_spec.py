"""The study: every map, and every word the app speaks on it.

This file follows the research team's two documents, "MultiNav Overview and
App Requirements" and "MultiNav Intersection Descriptions" (10/28), and
their answers to our questions. Spoken text is copied from the team's
wording; change it here, run `python3 tools/build_maps.py --preview`, and
proofread docs/STUDY.md.

The study, in order:
  Training      a made-up route overview and intersection (Pear Street and
                Apple Street), then the route overview of the real route
  Practice      intersection 0, Fore Street and Pearl Street
  Trial 1       intersections 1 to 5, from Dock Fore to Gorham's Corner,
                with every information item on
  Customization the participant picks the information items for Trial 2
  Trial 2       the same five intersections in reverse, back toward the
                Maine Center, with the chosen items

Each intersection has an announcement, spoken when its map opens, and up to
six information items, one per category below, which the participant plays
and steps through. In Trial 2 the researcher can switch each category off.
"""

# The six information items, in the order they are read. The key is used in
# the logs and the app's settings; the title is shown to the researcher.
CATEGORIES = [
    ("geometry", "Intersection geometry"),
    ("direction", "Traffic direction"),
    ("control", "Traffic control"),
    ("signals", "Pedestrian signals"),
    ("crosswalks", "Crosswalks"),
    ("domes", "Truncated domes and curb cuts"),
]

PHASES = {
    "training": "Training",
    "practice": "Practice",
    "trial1": "Trial 1",
    "trial2": "Trial 2",
}

AREA = {"osm": "osm/old_port_area.json", "origin": (43.6560, -70.2540)}

# What the route ends say on an intersection map (from the training mockup).
START_TEXT = "You are here"
END_TEXT = "End of intersection route"


def items(*texts):
    """The six information items, in category order."""
    assert len(texts) == len(CATEGORIES)
    return [{"category": key, "text": text} for (key, _), text in zip(CATEGORIES, texts)]


# ================================================================ overviews
#
# Schematic maps, not to scale, laid out like the team's mockups. Each walk is
# a list of legs from the start: a screen direction (degrees clockwise from
# up) and a length in mm, ending at a node. Nodes are intersections (a red
# square with a spoken cue), plain corners, or the end. Stubs are the streets
# the walk does not follow, each with a direction and a name.

TRAINING_OVERVIEW = {
    "id": "training_overview",
    "title": "Training route overview",
    "subtitle": "Home to Nick's Bakery",
    "description": ("Your route to Nick's Bakery is approximately 0.5 miles away, primarily travelling "
                    "Northeast. There are 3 intersections along the route, with 2 turns and 4 total "
                    "street crossings."),
    "start": {"at": (16.0, 104.0), "text": "Start of route: You are here, at Home.", "label": "Start of Route",
              "label_side": "right"},
    "legs": [
        {"dir": 0, "len": 28.0, "street": "Pear Street", "node": {
            "kind": "intersection", "number": 1,
            "text": "Intersection 1: 4-way intersection of Pear Street and Apple Street.",
            "stubs": [(270, 12.0, "Apple Street"), (90, 12.0, "Apple Street")]}},
        {"dir": 0, "len": 36.0, "street": "Pear Street", "node": {
            "kind": "intersection", "number": 2,
            "text": "Intersection 2: 3-way intersection of Pear Street and Orange Road.",
            "stubs": [(0, 12.0, "Pear Street")]}},
        {"dir": 90, "len": 30.0, "street": "Orange Road", "node": {
            "kind": "intersection", "number": 3,
            "text": "Intersection 3: 4-way intersection of Orange Road and Banana Lane.",
            "stubs": [(90, 10.0, "Orange Road"), (180, 12.0, "Banana Lane")]}},
        {"dir": 0, "len": 30.0, "street": "Banana Lane", "node": {"kind": "end"}},
    ],
    "end": {"text": "End of route: Your destination, Nick's Bakery.", "label": "End of Route",
            "label_side": "left"},
    # Street names printed on the map, as in the mockup: on the route itself,
    # and Apple Street beside its right arm. (text, x, y, angle)
    "labels": [("Pear St.", 16.0, 58.0, -90), ("Orange Rd.", 31.0, 40.0, 0), ("Banana Ln.", 46.0, 25.0, -90),
               ("Apple St.", 40.0, 76.0, 0)],
}

ROUTE_OVERVIEW = {
    "id": "route_overview",
    "title": "Route overview",
    "subtitle": "Dock Fore to Gorham's Corner",
    "description": ("Your route to Gorham's Corner is approximately 0.5 miles away, primarily travelling "
                    "Southwest. There are 5 intersections along the route, with 7 turns and 6 total "
                    "street crossings."),
    "start": {"at": (42.0, 106.0), "text": "Start of route: You are here, at Dock Fore, 336 Fore Street.",
              "label": "Start of Route", "label_side": "left"},
    # Drawn with southwest at the top, the way the walk goes.
    "legs": [
        {"dir": 0, "len": 12.0, "street": "Fore Street", "node": {
            "kind": "intersection", "number": 1,
            "text": "Intersection 1: 4-way intersection of Fore Street and Silver Street.",
            "stubs": [(270, 9.0, "Silver Street"), (90, 9.0, "Silver Street")]}},
        {"dir": 0, "len": 20.5, "street": "Fore Street", "node": {
            "kind": "intersection", "number": 2,
            "text": "Intersection 2: 4-way intersection of Fore Street, Moulton Street, and Exchange Street.",
            "stubs": [(0, 9.0, "Fore Street"), (90, 9.0, "Exchange Street")]}},
        {"dir": 270, "len": 24.5, "street": "Moulton Street", "node": {"kind": "corner"}},
        {"dir": 0, "len": 26.5, "street": "Commercial Street", "node": {
            "kind": "intersection", "number": 3,
            "text": "Intersection 3: 4-way intersection of Commercial Street and Union Street.",
            "stubs": [(0, 9.0, "Commercial Street"), (270, 9.0, "Union Wharf")]}},
        {"dir": 90, "len": 24.5, "street": "Union Street", "node": {
            "kind": "intersection", "number": 4,
            "text": "Intersection 4: 4-way intersection of Union Street and Fore Street.",
            "stubs": [(90, 9.0, "Union Street"), (180, 9.0, "Fore Street")]}},
        {"dir": 0, "len": 24.0, "street": "Fore Street", "node": {
            "kind": "intersection", "number": 5,
            "text": "Intersection 5: 5-way intersection of Fore Street, Center Street, and York Street.",
            "stubs": [(270, 9.0, "Center Street"), (90, 9.0, "Center Street"), (0, 9.0, "Pleasant Street")]}},
        {"dir": 315, "len": 21.0, "street": "York Street", "node": {"kind": "end"}},
    ],
    "end": {"text": "End of route: Your destination, Gorham's Corner.", "label": "End of Route",
            "label_side": "above"},
    "labels": [],
}


# ================================================================ intersections
#
# Junctions are read from OpenStreetMap (arms at their true angles). The team
# checked each intersection on site, so what the maps draw about the route's
# crossings (zebra or unmarked, straight or angled, the median) follows their
# descriptions. The other legs follow aerial photos (Maine GeoLibrary 2017,
# Vantor 2025) and OSM; docs/STUDY.md lists each one for the team to check.
#
# Arms are named "Street@bearing", the arm's compass direction leaving the
# junction; the nearest arm of that street is used.
#
# crosswalks   per arm: "zebra" or "unmarked"; arms not listed have none
# skew         (arm, side, mm): moves that end of the crosswalk further out
#              along the arm, for a crosswalk the team describes as angled
# straight     arms whose crosswalk is squared up (both ends equally far out)
# median       arms divided by a median; their crosswalk is split around it
# rename       arms whose OSM name differs from the street as it is signed
#              and as the team names it

JUNCTIONS = {
    # The southwest leg is split by the tip of the Boothby Square island; its
    # crossings are paving stones, not paint.
    "pearl": {
        "nodes": [101610366],
        "crosswalks": {"Fore Street@31": "zebra", "Pearl Street@129": "zebra",
                       "Fore Street@223": "unmarked", "Pearl Street@310": "zebra"},
        "median": ["Fore Street@223"],
        "straight": ["Pearl Street@129"],
    },
    # Boothby Square: Fore Street runs either side of the island, Silver Street
    # crosses it on setts, and no crossing is painted.
    "silver": {
        "nodes": [101432200, 101610334],
        "crosswalks": {"Fore Street@47": "unmarked", "Silver Street@138": "unmarked",
                       "Fore Street@242": "unmarked", "Silver Street@318": "unmarked"},
        "median": ["Fore Street@47", "Fore Street@242"],
        "straight": ["Silver Street@318"],
    },
    # Zebras on all four legs; the turn lane on Commercial Street is flush,
    # with no refuge.
    "commercial_union": {
        "nodes": [101503250],
        "crosswalks": {"Commercial Street@47": "zebra", "Union Wharf@144": "zebra",
                       "Commercial Street@225": "zebra", "Union Street@325": "zebra"},
        "straight": ["Union Street@325"],
    },
    # The Fore Street crossing on the route runs at about 20 degrees.
    "union_fore": {
        "nodes": [101592984],
        "crosswalks": {"Fore Street@61": "zebra", "Union Street@144": "zebra",
                       "Fore Street@243": "zebra", "Union Street@329": "zebra"},
        "skew": [("Fore Street@243", "cw", 9.0)],
    },
    # Five zebras round the junction since the 2023 changes (OSM has three).
    # OSM names the first stretch of the south leg Fore Street; it is signed
    # and spoken of as York Street, as in the team's descriptions.
    "gorhams_corner": {
        "nodes": [101412002],
        "rename": {"Fore Street@191": "York Street"},
        "crosswalks": {"Fore Street@55": "zebra", "Center Street@141": "zebra", "York Street@191": "zebra",
                       "Pleasant Street@237": "zebra", "Center Street@320": "zebra"},
        "straight": ["Fore Street@55", "York Street@191", "Pleasant Street@237"],
    },
}

# The offset intersection: Exchange Street meets Fore Street 16 m southwest
# of where Moulton Street leaves it, on the other side. The crosswalk on the
# route runs between the two corners at about 25 degrees; Moulton Street's
# mouth is crossed on a brick band, not paint.
OFFSET_JUNCTIONS = {
    "exchange_moulton": {
        "main": "Fore Street",
        "near": {"node": 101396310, "arm": "Exchange Street"},   # northwest side
        "far": {"node": 101610336, "arm": "Moulton Street"},     # southeast side
        "offset_mm": 33.0,
        "crosswalks": ["diagonal", "near_arm", "near_main", "far_arm"],
        "markings": {"far_arm": "unmarked"},
    },
}

# The made-up training intersection, as drawn in the team's mockup.
TRAINING_JUNCTION = {
    "arms": [("Pear Street", 0.0), ("Apple Street", 90.0), ("Pear Street", 180.0), ("Apple Street", 270.0)],
    "crosswalks": {"Pear Street@0": "zebra", "Apple Street@90": "zebra",
                   "Pear Street@180": "zebra", "Apple Street@270": "zebra"},
}


# ================================================================ stops
#
# in / out  the arm walked in along and out along, with the side of the
#           street; "via" picks the way round when both are the same length
# up        the map is turned so the way the participant walks in is up;
#           "heading": "first_crossing" faces the first crossing instead,
#           for the return, which starts at Gorham's Corner
# path      the offset intersection: "near_to_far" crosses from the Exchange
#           Street side to the Moulton Street side, "far_to_near" back

STOPS = [
    {
        "id": "training_intersection", "phase": "training", "log_id": "Training intersection",
        "title": "Training intersection", "subtitle": "Pear Street and Apple Street",
        "junction": "training",
        "in": ("Pear Street@180", "east"), "out": ("Pear Street@0", "east"),
        "announcement": ("You are at the 4-way intersection of Pear Street and Apple Street. Your route "
                         "crosses Apple Street, then continues along Pear Street."),
        "items": items(
            "This is a four-way, plus-shaped intersection.",
            "Both Pear Street and Apple Street have two-way traffic.",
            "The intersection is controlled by stop signs in all directions.",
            "There are no pedestrian signals at this intersection.",
            "Your route crossing uses a straight zebra crosswalk.",
            "The truncated domes are not aligned with the direction of the crosswalk when crossing Apple Street.",
        ),
    },
    {
        "id": "intersection_0", "phase": "practice", "log_id": "Intersection 0",
        "title": "Intersection 0, practice", "subtitle": "Fore Street and Pearl Street",
        "junction": "pearl",
        "in": ("Fore Street@31", "southeast"), "out": ("Fore Street@223", "southeast"),
        "announcement": ("You are at the 4-way intersection of Fore Street and Pearl Street. Your route "
                         "crosses Pearl Street, then continues along Fore Street."),
        "items": items(
            "This is a four-way, plus-shaped intersection.",
            "Both Fore Street and Pearl Street have two-way traffic.",
            "The intersection is controlled by a traffic signal. Right turns are permitted during the walking cycle.",
            "The pedestrian signal operates automatically on a timed cycle without a push button.",
            "Your route crossing uses a straight zebra crosswalk.",
            "There are no curb cuts or truncated domes when crossing Pearl Street.",
        ),
    },
    {
        "id": "intersection_1", "phase": "trial1", "log_id": "Intersection 1",
        "title": "Intersection 1", "subtitle": "Fore Street and Silver Street",
        "junction": "silver",
        "in": ("Fore Street@47", "southeast"), "out": ("Fore Street@242", "northwest"), "via": "ccw",
        "announcement": ("You are at the 4-way intersection of Fore Street and Silver Street. Your route first "
                         "crosses Fore Street and then turns left to cross Silver Street, then continues along "
                         "the other side of Fore Street."),
        "items": items(
            "This is a four-way, plus-shaped intersection with a median.",
            "Fore Street has two-way traffic, while Silver Street has one-way traffic moving through the intersection.",
            "Silver Street traffic is controlled by a stop sign.",
            "There are no pedestrian signals at this intersection.",
            "The Fore Street crossing is unmarked and divided into two stages by a median. The Silver Street "
            "crossing is unmarked.",
            "There are curb cuts with no truncated domes when crossing either street.",
        ),
    },
    {
        "id": "intersection_2", "phase": "trial1", "log_id": "Intersection 2",
        "title": "Intersection 2", "subtitle": "Fore Street, Moulton Street and Exchange Street",
        "junction": "exchange_moulton",
        "path": "near_to_far",
        "announcement": ("You are at the 4-way intersection of Fore Street, Moulton Street, and Exchange Street. "
                         "Your route crosses Fore Street, then continues left along Moulton Street."),
        "items": items(
            "This is a 4-way, offset intersection.",
            "Fore Street has two-way traffic. Moulton Street has one-way traffic moving away from the "
            "intersection. Exchange Street has one-way traffic moving toward the intersection.",
            "Exchange Street traffic is controlled by a stop sign.",
            "There are no pedestrian signals at this intersection.",
            "Your crossing uses a zebra crosswalk that angles slightly to the left.",
            "The truncated domes are not aligned with the direction of the crosswalk when crossing Fore Street.",
        ),
    },
    {
        "id": "intersection_3", "phase": "trial1", "log_id": "Intersection 3",
        "title": "Intersection 3", "subtitle": "Commercial Street and Union Street",
        "junction": "commercial_union",
        "in": ("Commercial Street@47", "northwest"), "out": ("Union Street@325", "southwest"),
        "announcement": ("You are at the 4-way intersection of Commercial Street and Union Street. Your route "
                         "crosses Union Street, then continues right along Union Street."),
        "items": items(
            "This is a four-way, plus-shaped intersection.",
            "Both Commercial Street and Union Street have two-way traffic.",
            "The intersection is controlled by a traffic signal.",
            "The intersection has APS, located on a pole about 6 feet back from the intersection.",
            "Your crossing uses a straight zebra crosswalk.",
            "The truncated domes are aligned with the direction of the crosswalk when crossing Union Street.",
        ),
    },
    {
        "id": "intersection_4", "phase": "trial1", "log_id": "Intersection 4",
        "title": "Intersection 4", "subtitle": "Union Street and Fore Street",
        "junction": "union_fore",
        "in": ("Union Street@144", "southwest"), "out": ("Fore Street@243", "northwest"),
        "announcement": ("You are at the 4-way intersection of Union Street and Fore Street. Your route crosses "
                         "Fore Street, then continues left along the other side of Fore Street."),
        "items": items(
            "This is a four-way, plus-shaped intersection.",
            "Both Union Street and Fore Street have two-way traffic.",
            "The intersection is controlled by a traffic signal. It has an exclusive pedestrian crossing phase "
            "where all vehicle traffic is stopped.",
            "The pedestrian signal is activated by a push button, located on a pole at the corner of the "
            "intersection.",
            "Your crossing uses a zebra crosswalk that angles slightly to the left.",
            "The truncated dome is aligned with the crosswalk when approaching the Fore Street crossing. The "
            "truncated dome at the end of the crossing is misaligned.",
        ),
    },
    {
        "id": "intersection_5", "phase": "trial1", "log_id": "Intersection 5",
        "title": "Intersection 5", "subtitle": "Fore Street, Center Street and York Street",
        "junction": "gorhams_corner",
        "in": ("Fore Street@55", "northwest"), "out": ("York Street@191", "east"), "end_gap": 6.0,
        "announcement": ("You are at the 5-way intersection of Fore Street, Center Street, and York Street. Your "
                         "route first crosses Fore Street, then turns right to cross Center Street, and continues "
                         "along York Street to your destination."),
        "items": items(
            "This intersection has 5 legs, with York Street intersecting Fore Street and Center Street at a "
            "45-degree angle.",
            "All streets have two-way traffic.",
            "The intersection is controlled by a traffic signal.",
            "The pedestrian signals are activated by push buttons, located on poles directly at each street corner.",
            "The Fore Street crossing uses a straight zebra crosswalk. The Center Street crossing uses a zebra "
            "crosswalk that angles slightly to the left.",
            "The truncated domes at both route crossings are not aligned with the direction of the crosswalks.",
        ),
    },
    # ------------------------------------------------------------ return route
    {
        "id": "return_5", "phase": "trial2", "log_id": "Reversed intersection 5",
        "title": "Reversed intersection 5", "subtitle": "Center Street, Fore Street and York Street",
        "junction": "gorhams_corner", "heading": "first_crossing", "start_gap": 6.0,
        "in": ("York Street@191", "east"), "out": ("Fore Street@55", "northwest"),
        "announcement": ("You are at the 5-way intersection of Center Street, Fore Street, and York Street. Your "
                         "route first crosses Center Street, then turns left to cross Fore Street, and continues "
                         "along Fore Street."),
        "items": items(
            "This intersection has 5 legs, with York Street intersecting Center Street and Fore Street at a "
            "45-degree angle.",
            "All streets have two-way traffic.",
            "The intersection is controlled by a traffic signal.",
            "The pedestrian signals are activated by push buttons, located on poles directly at each street corner.",
            "The Center Street crossing uses a zebra crosswalk that angles slightly to the left. The Fore Street "
            "crossing uses a straight zebra crosswalk.",
            "The truncated domes at both route crossings are not aligned with the direction of the crosswalks.",
        ),
    },
    {
        "id": "return_4", "phase": "trial2", "log_id": "Reversed intersection 4",
        "title": "Reversed intersection 4", "subtitle": "Fore Street and Union Street",
        "junction": "union_fore",
        "in": ("Fore Street@243", "northwest"), "out": ("Union Street@144", "southwest"),
        "announcement": ("You are at the 4-way intersection of Fore Street and Union Street. Your route crosses "
                         "Fore Street, then continues along Union Street."),
        "items": items(
            "This is a four-way, plus-shaped intersection.",
            "Both Fore Street and Union Street have two-way traffic.",
            "The intersection is controlled by a traffic signal. It has an exclusive pedestrian crossing phase "
            "where all vehicle traffic is stopped.",
            "The pedestrian signal is activated by a push button, located on a pole at the corner of the "
            "intersection.",
            "Your crossing uses a zebra crosswalk that angles slightly to the left.",
            "The truncated dome is misaligned with the crosswalk when approaching the Fore Street crossing. The "
            "truncated dome at the end of the crossing is aligned.",
        ),
    },
    {
        "id": "return_3", "phase": "trial2", "log_id": "Reversed intersection 3",
        "title": "Reversed intersection 3", "subtitle": "Union Street and Commercial Street",
        "junction": "commercial_union",
        "in": ("Union Street@325", "southwest"), "out": ("Commercial Street@47", "northwest"),
        "announcement": ("You are at the 4-way intersection of Union Street and Commercial Street. Your route "
                         "crosses Union Street, then continues along Commercial Street."),
        "items": items(
            "This is a four-way, plus-shaped intersection.",
            "Both Union Street and Commercial Street have two-way traffic.",
            "The intersection is controlled by a traffic signal.",
            "The intersection has APS, located on a pole about 6 feet back from the intersection.",
            "Your crossing uses a straight zebra crosswalk.",
            "The truncated domes are aligned with the direction of the crosswalk when crossing Union Street.",
        ),
    },
    {
        "id": "return_2", "phase": "trial2", "log_id": "Reversed intersection 2",
        "title": "Reversed intersection 2", "subtitle": "Moulton Street, Fore Street and Exchange Street",
        "junction": "exchange_moulton",
        "path": "far_to_near",
        "announcement": ("You are at the 4-way intersection of Moulton Street, Fore Street, and Exchange Street. "
                         "Your route crosses Fore Street, then continues right along Fore Street."),
        "items": items(
            "This is a 4-way, offset intersection.",
            "Fore Street has two-way traffic. Moulton Street has one-way traffic moving away from the "
            "intersection. Exchange Street has one-way traffic moving toward the intersection.",
            "Exchange Street traffic is controlled by a stop sign.",
            "There are no pedestrian signals at this intersection.",
            "Your crossing uses a zebra crosswalk that angles slightly to the left.",
            "The truncated domes are not aligned with the direction of the crosswalk when crossing Fore Street.",
        ),
    },
    {
        "id": "return_1", "phase": "trial2", "log_id": "Reversed intersection 1",
        "title": "Reversed intersection 1", "subtitle": "Fore Street and Silver Street",
        "junction": "silver",
        "in": ("Fore Street@242", "northwest"), "out": ("Fore Street@47", "southeast"), "via": "cw",
        "announcement": ("You are at the 4-way intersection of Fore Street and Silver Street. Your route first "
                         "crosses Silver Street and then turns right to cross Fore Street."),
        "items": items(
            "This is a four-way, plus-shaped intersection with a median.",
            "Fore Street has two-way traffic, while Silver Street has one-way traffic moving through the intersection.",
            "Silver Street traffic is controlled by a stop sign.",
            "There are no pedestrian signals at this intersection.",
            "The Silver Street crossing is unmarked. The Fore Street crossing is unmarked and divided into two "
            "stages by a median.",
            "There are curb cuts with no truncated domes when crossing either street.",
        ),
    },
]

# Points for the team to confirm, listed at the top of docs/STUDY.md.
TEAM_NOTES = [
    "The route overview says 6 total street crossings. The five intersection descriptions add up to 7 "
    "(Fore and Silver at 1, Fore at 2, Union at 3, Fore at 4, Fore and Center at 5). Between them the walk "
    "also crosses Market Street (between 1 and 2), Wharf Street (on Moulton Street and on Union Street), and "
    "Cross Street and Cotton Street (between 4 and 5).",
    "Pearl Street: the Fore Street leg toward Silver Street is split by the tip of the Boothby Square island, "
    "crossed on paving stones. The practice map shows it as a median; the description calls the "
    "intersection plus-shaped.",
    "Gorham's Corner: aerial photos from 2025 show five zebra crosswalks, including the two across Pleasant "
    "Street and York Street added in 2023. The maps draw all five. The 2023 changes also set the signals to "
    "flash red as a five-way stop; the descriptions say signal controlled.",
    "Gorham's Corner: city records name the first stretch of the south leg Fore Street; the maps call it "
    "York Street, as the descriptions do.",
    "Commercial Street and Union Street: the leg opposite Union Street is Union Wharf, and the map names it so.",
    "Route overview: intersection 1 is drawn with Silver Street on both sides, like the other four; the "
    "mockup showed no cross street there.",
    "The crosswalks described as angled are drawn at their measured angles: about 24 degrees at Union and "
    "Fore, 26 at Exchange and Moulton, and 28 across Center Street, where York Street meets it at a sharp angle.",
]

# The order the researcher's screen lists the maps in, and the order "Next"
# follows. Overviews and intersections share one list.
ORDER = ["training_overview", "training_intersection", "route_overview", "intersection_0",
         "intersection_1", "intersection_2", "intersection_3", "intersection_4", "intersection_5",
         "return_5", "return_4", "return_3", "return_2", "return_1"]
