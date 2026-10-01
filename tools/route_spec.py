"""Study choices layered on top of OpenStreetMap.

Everything a researcher might want to change lives here: which junctions
each route passes, which side of each street the walk uses, the spoken
names of the endpoints, and notes from the team's "MultiNav Walking Routes"
map that OSM does not record (such as all-way stops).

Sides are compass words ("northwest") for the side of the street the
traveller walks on. Arms are named "Street@bearing" where the bearing is
the arm's true compass direction leaving the junction; the nearest arm of
that street is used, so the bearing only needs to be roughly right.

Run `python3 tools/build_maps.py` after editing to regenerate the maps.
"""

AREAS = {
    "usm": {"osm": "osm/usm_area.json", "origin": (43.6617, -70.2770)},
    "oldport": {"osm": "osm/old_port_area.json", "origin": (43.6577, -70.2512)},
}

# Control wording spoken in the intersection view.
#   signals       traffic signals
#   all_way_stop  stop signs on every approach
#   side_stop     stop sign on one street only (street given in "stop_street")
#   none          no signals or stop signs (only where the team confirmed it)
#   roundabout    yield on entry
# Junctions with no entry say nothing about control rather than guess.
# "control_source" records where the control came from when it was not OSM;
# "team map" means a pin on the team's "MultiNav Walking Routes" map.
JUNCTIONS = {
    # USM and Forest Avenue area
    "bedford_deering": {"area": "usm", "nodes": [6583000830], "control": "none", "control_source": "team map"},
    "roundabout": {"area": "usm", "roundabout_way": 945152554, "control": "roundabout",
                   "name": "Deering Avenue, Falmouth Street and Brighton Avenue"},
    "falmouth_oakdale": {"area": "usm", "nodes": [101446870], "control": "none", "control_source": "team map"},
    "falmouth_durham": {"area": "usm", "nodes": [101677584]},
    "forest_falmouth": {"area": "usm", "nodes": [4565006585, 101466464, 4565006582], "control": "signals"},
    "forest_belmeade": {"area": "usm", "nodes": [101499368, 101499370],
                        "no_crossing": ["Forest Avenue@309", "Forest Avenue@131"]},
    "forest_fenwick": {"area": "usm", "nodes": [101566833]},
    "forest_bank": {"area": "usm", "nodes": [13335583073]},
    "forest_bedford": {"area": "usm", "nodes": [101685149, 101684845], "control": "signals"},
    "bedford_durham": {"area": "usm", "nodes": [101697079],
                       "assume_crossing": ["Durham Street@309"]},

    # Old Port, Fore Street
    "fore_franklin": {"area": "oldport", "nodes": [101533393, 101533503], "control": "signals"},
    "fore_india": {"area": "oldport", "nodes": [101610409], "control": "all_way_stop", "control_source": "team map"},
    "fore_hancock": {"area": "oldport", "nodes": [101610416], "control": "all_way_stop", "control_source": "team map"},
    "fore_mountfort": {"area": "oldport", "nodes": [101454292]},
    "fore_munjoy": {"area": "oldport", "nodes": [11124475008, 101571032],
                    "extra_arms": [{"name": "Access road to 58 Fore Street", "bearing": 152}]},
    "fore_custom_house": {"area": "oldport", "nodes": [101610372]},
    "fore_pearl": {"area": "oldport", "nodes": [101610366], "control": "signals"},
    "fore_silver": {"area": "oldport", "nodes": [101432200, 101610334],
                    "control": "side_stop", "stop_street": "Silver Street", "control_source": "team map and OSM"},
    "fore_market": {"area": "oldport", "nodes": [101610358],
                    "arms": [{"name": "Fore Street", "bearing": 52, "divided": True},
                             {"name": "Market Street", "bearing": 141},
                             {"name": "Fore Street", "bearing": 248},
                             {"name": "Market Street", "bearing": 317}]},
    "fore_moulton": {"area": "oldport", "nodes": [101610336]},
    "fore_exchange": {"area": "oldport", "nodes": [101396310], "control": "none", "control_source": "team map"},
    "fore_union": {"area": "oldport", "nodes": [101592984], "control": "signals", "control_source": "team map and OSM",
                   "assume_crossing": ["Fore Street@61", "Union Street@144", "Fore Street@243", "Union Street@329"],
                   "assume_signal": True},
    "fore_cross": {"area": "oldport", "nodes": [101380827], "control": "all_way_stop", "control_source": "team map",
                   "assume_crossing": ["Fore Street@63", "Cross Street@152", "Fore Street@237", "Cross Street@333"]},
    "fore_cotton": {"area": "oldport", "nodes": [101610344],
                    "assume_crossing": ["Cotton Street@320"]},
    "fore_center": {"area": "oldport", "nodes": [101412002], "control": "signals"},
    "center_spring": {"area": "oldport", "nodes": [101477063], "control": "signals"},
}

LAW_SCHOOL = {
    "name": "University of Maine School of Law",
    "spoken": "Maine Law, 300 Fore Street",
    "tag": "LAW",
    "latlon": (43.6577030, -70.2512262),
}
USM = {
    "name": "University of Southern Maine",
    "spoken": "U S M, Bedford Street",
    "tag": "USM",
    "latlon": (43.6617204, -70.2761214),
}
FOREST_415 = {
    "name": "415 Forest Avenue",
    "spoken": "415 Forest Avenue",
    "tag": "415",
    "latlon": (43.6653503, -70.2751519),
}

# `up` is the compass bearing drawn at the top of the screen. Portland's
# downtown grid runs northeast and northwest, so turning the map by a
# multiple of 45 degrees squares the streets to the screen while keeping
# the walk moving up it.
ROUTES = [
    {
        "id": "route1",
        "number": 1,
        "title": "USM to 415 Forest Avenue",
        "summary": "Bedford Street, Deering Avenue, the roundabout, Falmouth Street, Forest Avenue",
        "area": "usm",
        "up": 45,
        "departure": dict(USM, side="right"),
        "destination": dict(FOREST_415, side="right"),
        "stops": [
            {"junction": "bedford_deering", "street_before": "Bedford Street",
             "in": ("Bedford Street@56", "northwest"), "out": ("Deering Avenue@322", "southwest")},
            {"junction": "roundabout", "street_before": "Deering Avenue",
             "in": ("Deering Avenue@138", "southwest"), "out": ("Falmouth Street@51", "northwest")},
            {"junction": "falmouth_oakdale", "street_before": "Falmouth Street",
             "in": ("Falmouth Street@225", "northwest"), "out": ("Falmouth Street@45", "northwest")},
            {"junction": "falmouth_durham", "street_before": "Falmouth Street",
             "in": ("Falmouth Street@225", "northwest"), "out": ("Falmouth Street@45", "northwest")},
            {"junction": "forest_falmouth", "street_before": "Falmouth Street",
             "in": ("Falmouth Street@231", "northwest"), "out": ("Forest Avenue@306", "northeast")},
            {"junction": "forest_belmeade", "street_before": "Forest Avenue",
             "in": ("Forest Avenue@131", "northeast"), "out": ("Forest Avenue@309", "northeast"),
             "ends_here": True},
        ],
        "street_after": "Forest Avenue",
    },
    {
        "id": "route2",
        "number": 2,
        "title": "300 Fore Street to 58 Fore Street",
        "summary": "Fore Street across Franklin Street, India Street and Hancock Street",
        "area": "oldport",
        "up": 45,
        "departure": dict(LAW_SCHOOL, side="right"),
        "destination": {"name": "58 Fore Street", "spoken": "58 Fore Street", "tag": "58",
                        "latlon": (43.6618483, -70.2456857), "side": "left"},
        "stops": [
            {"junction": "fore_franklin", "street_before": "Fore Street",
             "in": ("Fore Street@209", "southeast"), "out": ("Fore Street@40", "southeast")},
            {"junction": "fore_india", "street_before": "Fore Street",
             "in": ("Fore Street@249", "southeast"), "out": ("Fore Street@61", "southeast")},
            {"junction": "fore_hancock", "street_before": "Fore Street",
             "in": ("Fore Street@210", "southeast"), "out": ("Fore Street@22", "southeast")},
            {"junction": "fore_mountfort", "street_before": "Fore Street",
             "in": ("Fore Street@208", "southeast"), "out": ("Fore Street@42", "southeast")},
            {"junction": "fore_munjoy", "street_before": "Fore Street",
             "in": ("Fore Street@256", "southeast"), "out": ("Access road to 58 Fore Street@152", "northeast")},
        ],
        "street_after": "Access road to 58 Fore Street",
    },
    {
        "id": "route3",
        "number": 3,
        "title": "300 Fore Street to Center and Spring Streets",
        "summary": "Fore Street to Center Street, ending at Spring Street",
        "area": "oldport",
        "up": 225,
        "departure": dict(LAW_SCHOOL, side="left"),
        "destination": {"name": "Center Street and Spring Street", "spoken": "corner of Center Street and Spring Street",
                        "tag": None, "latlon": (43.6556658, -70.2581223), "side": None},
        "stops": [
            {"junction": "fore_custom_house", "street_before": "Fore Street",
             "in": ("Fore Street@23", "southeast"), "out": ("Fore Street@210", "southeast")},
            {"junction": "fore_pearl", "street_before": "Fore Street",
             "in": ("Fore Street@31", "southeast"), "out": ("Fore Street@223", "northwest"), "via": "ccw"},
            {"junction": "fore_silver", "street_before": "Fore Street",
             "in": ("Fore Street@47", "northwest"), "out": ("Fore Street@242", "northwest")},
            {"junction": "fore_market", "street_before": "Fore Street",
             "in": ("Fore Street@52", "northwest"), "out": ("Fore Street@248", "northwest")},
            {"junction": "fore_moulton", "street_before": "Fore Street",
             "in": ("Fore Street@69", "northwest"), "out": ("Fore Street@246", "northwest")},
            {"junction": "fore_exchange", "street_before": "Fore Street",
             "in": ("Fore Street@68", "northwest"), "out": ("Fore Street@236", "northwest")},
            {"junction": "fore_union", "street_before": "Fore Street",
             "in": ("Fore Street@61", "northwest"), "out": ("Fore Street@243", "northwest")},
            {"junction": "fore_cross", "street_before": "Fore Street",
             "in": ("Fore Street@63", "northwest"), "out": ("Fore Street@237", "northwest")},
            {"junction": "fore_cotton", "street_before": "Fore Street",
             "in": ("Fore Street@57", "northwest"), "out": ("Fore Street@235", "northwest")},
            {"junction": "fore_center", "street_before": "Fore Street",
             "in": ("Fore Street@55", "northwest"), "out": ("Center Street@320", "northeast")},
            {"junction": "center_spring", "street_before": "Center Street",
             "in": ("Center Street@139", "northeast"), "out": None, "ends_here": True,
             "destination_before_junction": True},
        ],
        "street_after": None,
    },
    {
        "id": "route4",
        "number": 4,
        "title": "415 Forest Avenue to USM",
        "summary": "Forest Avenue, then Bedford Street",
        "area": "usm",
        "up": 135,
        "departure": dict(FOREST_415, side="left"),
        "destination": dict(USM, side="right"),
        "stops": [
            {"junction": "forest_belmeade", "street_before": "Forest Avenue",
             "in": ("Forest Avenue@309", "northeast"), "out": ("Forest Avenue@131", "northeast"),
             "starts_here": True},
            {"junction": "forest_falmouth", "street_before": "Forest Avenue",
             "in": ("Forest Avenue@306", "northeast"), "out": ("Forest Avenue@131", "northeast")},
            {"junction": "forest_fenwick", "street_before": "Forest Avenue",
             "in": ("Forest Avenue@308", "northeast"), "out": ("Forest Avenue@131", "northeast")},
            {"junction": "forest_bank", "street_before": "Forest Avenue",
             "in": ("Forest Avenue@311", "northeast"), "out": ("Forest Avenue@131", "northeast")},
            {"junction": "forest_bedford", "street_before": "Forest Avenue",
             "in": ("Forest Avenue@313", "northeast"), "out": ("Bedford Street@236", "northwest")},
            {"junction": "bedford_durham", "street_before": "Bedford Street",
             "in": ("Bedford Street@56", "northwest"), "out": ("Bedford Street@236", "northwest")},
        ],
        "street_after": "Bedford Street",
    },
]
