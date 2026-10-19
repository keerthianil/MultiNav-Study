# MultiNav Study 2

An iOS research app for blind and low-vision travellers, built at UNAR Labs, Roux Institute, Northeastern
University. Four real walking routes in Portland, Maine, can be explored by touch on a phone: the whole
route on one screen or one section at a time, with turn-by-turn directions and a close-up of every
intersection, each one felt through vibration, sound and speech, and designed for VoiceOver first. A setup
screen lets the researcher choose what participants get before a trip and while walking.

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

### Study setup, the first screen

The researcher sets up each session here, then hands the phone to the participant.

1. **Route**: Route 1 to Route 4, each with its name in small type underneath.
2. **Stage**: *Pre-journey learning* (learning the route before going) or *On route* (using the app while
   walking it). Each stage keeps its own settings and writes its own log files. *Practice run* marks the
   logs as practice.
3. **Start**: the button names the route and stage, and the line under it sums up what the participant will
   get.

The options below the Start button belong to the stage being set up:

| Group | Option | What it does |
|---|---|---|
| Map | Full route / Section by section | the whole walk on one screen, or one stretch at a time (below) |
| | Intersection close-ups | double tap an intersection to open its close-up |
| | Buildings at the start and destination | the purple boxes and "... on your right" |
| | Show the map on screen | off keeps the screen dark for participants with some vision; touch still works |
| Directions | Turn-by-turn directions | what to do at each intersection: crossings, then the turn |
| | Speak them when a section opens | section by section only; off leaves them for a tap or a two-finger double tap |
| | Spoken route overview | reads the whole route when the map opens |
| | Distances | "about 550 feet" |
| | Side of the street | "on the northwest side", in directions and sidewalk names |
| Details | Intersection type and traffic control | "3-way intersection. No traffic signals or stop signs." |
| | Crosswalk details | signals, push buttons, markings, one-way streets |
| Feedback | Vibration, Sounds, Speech | switch each off for a condition; prompts such as section numbers and time warnings are still spoken |
| Time limit | Learning time | pre-journey only: no limit, or 2 to 30 minutes, with "One minute left" and "Learning time is over" |

The last group applies to every stage: whether the participant can leave the map with the back gestures
(on by default, as before; turn it off to lock them on the map), distances in feet or metres, sides as compass words or left and right, and the speed of the system
voice (used when VoiceOver is off). *Reset All Settings* restores the defaults. Settings are kept between
launches.

Defaults: pre-journey learning uses the full route map, on route uses section by section, and every other
option is on except the spoken overview and the time limit.

### The map screen

The top bar shows the route (and the section, in section by section mode) and the learning time left. There
is no Back button: **End** ends the session after a confirmation, so a stray tap at the top of the screen
cannot end it. The back gestures still leave the map as before; with *Participant can leave the map* off, they
say "The map is locked. Ask the researcher to end the session." instead.

### Full route map

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
| Route | cyan line | rhythmic pulse | | "Route to 415 Forest Avenue, along Bedford Street" on the first stretch, then "Route along ..." |
| Street | blue line | steady heavy buzz | | street name |

With turn-by-turn directions on, **tap an intersection once** to hear what to do there, or **tap the route**
to hear that stretch of the walk. **Double tap an intersection** to open its close-up.

### Section by section

One stretch of the walk at a time: from where the traveller is, at the bottom of the screen, to the next
intersection, at the top. Each section is turned so the walking direction is up, and the route is drawn a
little past the top intersection to show the turn made there. The first section starts at the yellow start
dot; the last ends at the destination.

When a section opens it is announced with its directions, for example: "Section 1 of 7. Start at U S M,
Bedford Street. Walk along Bedford Street, on the northwest side, about 550 feet, to Deering Avenue. At
Deering Avenue. 3-way intersection. No traffic signals or stop signs. Cross Deering Avenue. Marked crosswalk.
Then turn right onto Deering Avenue, on the southwest side."

| Under the finger | Speech |
|---|---|
| Intersection at the top | "Next: 4-way intersection of ..."; a single tap gives what to do there |
| Intersection at the bottom | "Start of section: ..."; a single tap repeats the turn made there |
| Route | "Route along Deering Avenue, on the southwest side"; past the top: "Then turn right onto ..." |

**Three-finger swipe up** for the next section, **down** for the previous one. The arrows in the top bar do
the same. At either end the app says "This is the first section." or "This is the last section."

Every route's directions, as spoken with every detail on, are in [docs/ROUTES.md](docs/ROUTES.md).

### Intersection close-up

The junction at its true angles from OpenStreetMap, in the same orientation as the map it was opened from,
with the roads, sidewalks, crosswalks and islands it really has, and the walking path through it.

| Under the finger | Looks like | Vibration | Sound | Speech |
|---|---|---|---|---|
| Turn | orange dot | tap with each ding | ding every 0.4 s | "Turn" |
| Crosswalk end | pink dot | none | one ding | |
| Centre of the junction | | steady heavy buzz | | "Center" |
| Start or end of the path | yellow dot | fast pulse | | "Your location at the intersection of ..." or "End of route. Double tap to return to the map." |
| Path over a crosswalk | cyan on stripes | rhythmic pulse | clicks | crosswalk name |
| Path | cyan line | rhythmic pulse | | "Route"; a single tap gives what to do here |
| Crosswalk | white stripes | road buzz under it | clicks | "Crosswalk with signal across Franklin Street, push button" |
| Refuge or splitter island | green | two soft taps, repeating | | "Splitter island on Deering Avenue. Pedestrian refuge between the entry and exit lanes" |
| Sidewalk | grey line | softer steady buzz | | "Sidewalk on the northwest side of Fore Street" |
| Road | blue | steady heavy buzz | | street name, "one way" where it is |

**Double tap anywhere** to return to the map.

### Gestures

| Gesture | Where | What it does |
|---|---|---|
| Drag one finger | every map | explore |
| Tap | route maps | the turn-by-turn direction for an intersection or stretch of route, or the name |
| Tap | close-up | a pulse, and the name if it was not just spoken; on the path, what to do here |
| Double tap | route maps | open the intersection under the finger |
| Double tap | close-up | back to the map |
| Three-finger swipe up / down | section by section | next / previous section |
| Three-finger swipe right | close-up | back to the map |
| Three-finger swipe right | route maps | leave the map and end the session (unless the setup locks the map) |
| Two-finger scrub (VoiceOver escape) | as three-finger swipe right | |
| Two-finger double tap (VoiceOver magic tap) | every map | repeat the section's directions, the route overview or summary, or the intersection summary |

The system edge swipe-back is turned off on map screens, so exploring near the left edge never leaves the
screen.

## VoiceOver

The map is a VoiceOver direct-touch area that stays silent on touch, so every finger movement reaches the
map rather than VoiceOver. With VoiceOver on, the map's speech is sent as VoiceOver announcements in the
listener's own voice and rate; with it off, the system voice is used at the speed set on the setup screen.
Either way a phrase plays to the end until the next thing is spoken, which cuts it off, and stops as soon as
the map is left. When a map opens, VoiceOver focus moves onto it and reads its name ("Route 1, section 1 of
7. Bedford Street to Deering Avenue") and how to use it; the directions or overview follow once VoiceOver has
finished. A three-finger swipe up or down is reported to VoiceOver as a page change, and VoiceOver plays its
boundary sound at the first and last section. Haptics and sounds behave the same either way.

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
app under *On My iPhone > MultiNav Study 2*, or copied off over USB in Finder. Each session (one route, one
stage) writes a pair of files; a practice run adds `_Practice` after the stage.

| File | Contents |
|---|---|
| `Route1_PreJourney_20261016_153012_touches.csv` | every touch down, move (10 per second) and up: time, trial time, element under the finger, position in points and in mm, stage, view (full route, section or intersection), section number, condition, VoiceOver on or off |
| `Route1_PreJourney_20261016_153012_events.csv` | every setting used, session start and end, screens and sections opened, taps, double taps, back gestures (including blocked ones), everything spoken, time warnings, VoiceOver changes, errors; each row with the same stage, view and section columns |
| `MultiNav_app_log.csv` | across all sessions: app launches, background and foreground, sessions, settings resets, and every error |

A session starts when the map opens and ends when the researcher presses End (or the participant leaves,
if allowed); visits to intersection close-ups belong to the same session.

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
2. Run `python3 tools/build_maps.py --preview` (Python 3 with Pillow). It rewrites the maps (full route,
   sections and close-ups), the turn-by-turn directions, `docs/ROUTES.md`, and the previews in
   `docs/map_previews/`, drawn at true size.
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
