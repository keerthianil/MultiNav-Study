# MultiNav Study 2

An iOS research app for blind and low-vision travellers, built at UNAR Labs, Roux Institute, Northeastern
University. Four real walking routes in Portland, Maine, can be explored by touch on a phone: a tactile
overview of the whole route, and a close-up of every intersection on it, each one felt through vibration,
sound and speech, and designed for VoiceOver first.

The maps come from OpenStreetMap and the team's "MultiNav Walking Routes" map, and the app is built on the
**MultiNav** foundational package ([ProjectMultiNav](https://github.com/Hariprasath88/ProjectMultiNav)).

## The four routes

| Route | From | To | Along | Intersections |
|---|---|---|---|---|
| 1 | USM, Bedford Street | 415 Forest Avenue | Bedford St, Deering Ave, the roundabout, Falmouth St, Forest Ave | 6, including a five-leg roundabout |
| 2 | 300 Fore Street (Maine Law) | 58 Fore Street | Fore St across Franklin St, India St and Hancock St | 5 |
| 3 | 300 Fore Street (Maine Law) | Center St and Spring St | Fore St to Center St | 11 |
| 4 | 415 Forest Avenue | USM, Bedford Street | Forest Ave, then Bedford St | 6 |

Route 4 is Route 1 in reverse, by way of Forest Avenue and Bedford Street. Every intersection, its traffic
control, its crosswalks and the streets each walk crosses are listed in [docs/ROUTES.md](docs/ROUTES.md).

## Using the app

The home screen lists Route 1 to Route 4, each with its name in small type underneath, and the data files.
Choosing a route opens its overview.

### Level 1, the route overview

A schematic of the whole walk on one screen. Street order, turn directions and the side each cross street
joins come from OpenStreetMap; streets are squared to the screen and intersections spaced at least 10 mm
apart so each one is finger-sized. The map is turned so the walk goes up the screen: the start is near the
bottom and the destination toward the top.

| Under the finger | Looks like | Vibration | Sound | Speech |
|---|---|---|---|---|
| Start or destination | yellow dot | fast pulse | | "Your location, ... Route to ..." or "Destination, ..." |
| Building at either end | purple box with a tag | fast pulse | | "... on your right" |
| Intersection | red square | slow pulse | ding every 0.4 s | "3-way intersection of Bedford Street, and Deering Avenue" |
| Roundabout | red ring | slow pulse | ding every 0.4 s | "Roundabout of Deering Avenue, Falmouth Street, and Brighton Avenue" |
| Route | cyan line | rhythmic pulse | | "Route to 415 Forest Avenue" on the first leg, then "Route" |
| Street | blue line | steady heavy buzz | | street name |

**Double tap an intersection** to open its close-up.

### Level 2, the intersection close-up

The junction at its true angles from OpenStreetMap, in the same orientation as the overview, with the
roads, sidewalks, crosswalks and islands it really has, and the walking path through it.

| Under the finger | Looks like | Vibration | Sound | Speech |
|---|---|---|---|---|
| Turn | orange dot | tap with each ding | ding every 0.4 s | "Turn" |
| Crosswalk end | pink dot | none | one ding | |
| Centre of the junction | | steady heavy buzz | | "Center" |
| Start or end of the path | yellow dot | fast pulse | | "Your location at the intersection of ..." or "End of route. Double tap to return to map overview." |
| Path over a crosswalk | cyan on stripes | rhythmic pulse | clicks | crosswalk name |
| Path | cyan line | rhythmic pulse | | "Route" |
| Crosswalk | white stripes | road buzz under it | clicks | "Crosswalk with signal across Franklin Street, push button" |
| Refuge, splitter island or median | green | two soft taps, repeating | | "Splitter island on Deering Avenue. Pedestrian refuge between the entry and exit lanes" |
| Sidewalk | grey line | softer steady buzz | | "Sidewalk on the northwest side of Fore Street" |
| Road | blue | steady heavy buzz | | street name, "one way" where it is |

**Double tap anywhere** to return to the overview.

### Gestures

| Gesture | Where | What it does |
|---|---|---|
| Drag one finger | both maps | explore |
| Tap | both maps | a pulse, and the name if it was not just spoken |
| Double tap | overview | open the intersection under the finger |
| Double tap | close-up | back to the overview |
| Three-finger swipe right | both maps | back |
| Two-finger scrub (VoiceOver escape) | both maps | back |
| Two-finger double tap (VoiceOver magic tap) | both maps | repeat the route or intersection summary |

The system edge swipe-back is turned off on map screens, so exploring near the left edge never leaves the
screen. The navigation bar Back button still works for sighted researchers.

## VoiceOver

The map is a VoiceOver direct-touch area that stays silent on touch, so every finger movement reaches the
map rather than VoiceOver. With VoiceOver on, the map's speech is sent as VoiceOver announcements in the
listener's own voice and rate; with it off, the system voice is used. Either way a phrase plays to the end
until the next thing is spoken, which cuts it off, and stops as soon as the map is left (back, or opening an
intersection). When a map opens, VoiceOver focus moves onto it and reads its name ("Map overview. Route 1,
USM to 415 Forest Avenue") and how to use it. Haptics and sounds behave the same either way.

## The roundabout

Route 1 passes the single-lane roundabout where Deering Avenue, Falmouth Street and Brighton Avenue meet. Its
close-up follows the guidance on roundabouts for pedestrians with vision disabilities (NCHRP Report 674,
*Crossing Solutions at Roundabouts and Channelized Turn Lanes for Pedestrians with Vision Disabilities*, and
NCHRP Report 672, *Roundabouts: An Informational Guide*):

* **Pedestrians go around, never across.** The walk follows the sidewalk around the outside of the circle.
  The centre island is drawn and named "Center island. Not a walkway", with no vibration, so it never feels
  like somewhere to walk.
* **Crossings are set back from the circle**, about one car length, as they are on the street, so the
  crosswalk is found by following the sidewalk out along the leg, not at the edge of the circle.
* **Each crossing is two crossings.** Four of the five legs have a splitter island in the middle, drawn
  green with its own two-tap vibration and named as a pedestrian refuge. Each half of the crosswalk is
  named for the lane it crosses, "entry lane" or "exit lane". The exit lane is where drivers, speeding up
  out of the circle, are least likely to yield, so the traveller should know which half they are on.
* **Traffic direction is stated**: the roadway says "Roundabout. Traffic moves counterclockwise", and the
  view opens with "5 streets meet at a one-lane roundabout. Traffic moves counterclockwise and yields when
  entering. No signals." This tells the traveller which way the traffic they hear is moving.
* **Legs keep their true angles**, so the narrow 40 degree gap between Brighton Avenue and the north leg of
  Deering Avenue is felt as narrow.
* **What is underfoot is named**: OpenStreetMap records these crossings as raised tables, so they are
  "raised crosswalks". It also records no detectable warning (tactile paving) on them, which is worth
  confirming on site before a session.

Route 1 crosses two legs here: Deering Avenue, then Falmouth Street, walking round the east side.

## Logs

Logs are saved in the app's Documents folder. They can be shared from **Data Files**, opened in the Files
app under *On My iPhone > MultiNav Study 2*, or copied off over USB in Finder.

| File | Contents |
|---|---|
| `Route1_20260930_153012_touches.csv` | every touch down, move (10 per second) and up: time, trial time, element under the finger, position in points and in mm, screen, VoiceOver on or off |
| `Route1_20260930_153012_events.csv` | session start and end, screens opened, taps, double taps, back gestures, everything spoken, VoiceOver changes, errors |
| `MultiNav_app_log.csv` | across all sessions: app launches, background and foreground, sessions, and every error |

A session starts when a route is opened and ends when the app returns to the route list; visits to
intersection close-ups belong to the same session.

## The MultiNav package

The app depends on [ProjectMultiNav](https://github.com/Hariprasath88/ProjectMultiNav) (product
`TactileMapKit`) as a Swift package from GitHub, pinned in `Package.resolved`. It builds on:

* **TactileMapCore**: every bundled map is a `TactileMapDocument` read with its loader; map elements are its
  `MapElement` and `TactileElementType`, extended with the study's own types (sidewalk, island, roundabout
  and so on); every size goes through `PhysicalDimensions` so a millimetre is a millimetre on every iPhone.
* **TactileMapLogging**: the touch log is a `TouchLogger` and records `TouchEvent`s.

Feedback, rendering and gestures are the app's own, tuned for these maps.

## Changing the maps

The JSON maps in `MultiNavStudy2/Maps` are generated; do not edit them by hand.

1. Edit `tools/route_spec.py`: the intersections on each route, which side of each street the walk uses,
   endpoint names, and traffic control the team has confirmed.
2. Run `python3 tools/build_maps.py --preview` (Python 3 with Pillow). It rewrites the maps, `docs/ROUTES.md`,
   and the previews in `docs/map_previews/`, drawn at true size.
3. Build the app.

The OpenStreetMap extracts are saved in `tools/osm/` so the maps rebuild the same way every time; the team's
map is in `tools/source/`. See [docs/DEVELOPER_GUIDE.md](docs/DEVELOPER_GUIDE.md) for how the maps are
made and how the code is laid out.

## Data

Map data © OpenStreetMap contributors, available under the Open Database License (ODbL). Route geometry and
intersection notes from the team's "MultiNav Walking Routes" map.

## Research context

A research prototype from UNAR Labs at Northeastern University's Roux Institute, studying non-visual
wayfinding with touchscreen tactile maps. It is not App Store production software.
