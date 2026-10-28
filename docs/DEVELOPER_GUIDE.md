# Developer guide

How MultiNav Study 2 is put together: where the maps and the wording come from, how a map is drawn, touched
and read aloud, and where to make common changes.

## Layout

```
MultiNavStudy2.xcodeproj      project; the app folder is a synchronized group
Config/Info.plist             file sharing key, merged into the generated Info.plist
MultiNavStudy2/
  App/                        app entry, lifecycle
  Study/                      the study (study.json reader), settings, the session, the researcher's screen
  Screens/                    the map screen and the visit that times and counts it
  Map/                        map model, drawing, touch surface, the two map controllers, the description player
  Feedback/                   haptics, sounds, speech, and the FeedbackManager that runs them
  Logging/                    study logs and the Data Files screen
  Support/                    swipe-back blocker
  Maps/                       generated map JSON and study.json, bundled as resources
  Assets.xcassets             app icon and accent colour
MultiNavStudy2Tests/          content, player, session and robustness tests (Swift Testing)
tools/                        map generator, study spec, OSM extract, icon script (make_app_icon.py)
docs/                         this guide, STUDY.md, map previews
```

## Files

| File | What it does |
|---|---|
| `App/MultiNavStudy2App.swift` | `@main`; resumes a session the app was closed in, starts the feedback engines, logs launch, background and foreground |
| `Study/StudyContent.swift` | reads `Maps/study.json`: every map in study order with its phase, log name, announcement and information items; `InfoCategory` and `StudyPhase` |
| `Study/StudySettings.swift` | the participant ID, the information items for Trial 2 (`InfoSettings`), and the options, saved in UserDefaults by `SettingsStore`; each change to an item is logged |
| `Study/StudySession.swift` | one participant's session: start, end, visits per map, which maps are done, the next map, kept in UserDefaults so it survives a relaunch |
| `Study/StudyHomeView.swift` | the researcher's screen: participant, Open Next, the maps by phase, customization, options, data |
| `Screens/MapScreen.swift` | a map full screen, with Done, the title and (Trial 2) the information items sheet |
| `Screens/MapVisit.swift` | one visit: starts the session if needed, plays the announcement when the map opens, times the visit, counts plays, writes the visit row when it ends |
| `Map/DescriptionPlayer.swift` | the announcement and the information items: play, stop, start over, step forward and back, carry on to the next item |
| `Map/TactileCanvasView.swift` | the touch surface: draws a `MapScene`, reads raw touches, detects taps, double taps, two-finger double taps and three-finger swipes, VoiceOver direct touch, magic tap, scroll and escape |
| `Map/OverviewController.swift` | route overviews: drawing, hit-testing, feedback, gestures |
| `Map/IntersectionController.swift` | intersection maps: drawing, hit-testing, feedback, gestures |
| `Map/StudyMapController.swift` | what the map screen needs from either controller |
| `Map/MapModels.swift` | reads a map with the MultiNav `TactileMapDocument` loader into drawable elements |
| `Map/MapTransform.swift` | millimetres to points with MultiNav `PhysicalDimensions` |
| `Map/MapStyle.swift` | every colour, size and touch radius, in mm |
| `Map/MapDrawing.swift`, `Map/MapGeometry.swift` | drawing (stripes, unmarked crossings, labels) and geometry helpers |
| `Feedback/FeedbackManager.swift` | one feedback mode at a time; switching mode stops everything the last one started; map speech and tracked description speech |
| `Feedback/HapticService.swift` | Core Haptics patterns; restarts the engine after a reset or a VoiceOver change |
| `Feedback/AudioService.swift` | the ding, the crosswalk click, the centre chime and the boundary thud, synthesised once, played from one engine |
| `Feedback/SpeechService.swift` | VoiceOver announcements (default priority, so they can be cut off) or the system voice, reporting when each phrase ends |
| `Logging/StudyLog.swift` | the visits, events and touches CSVs (the touch log is a MultiNav `TouchLogger`), the app log |
| `Logging/LogFilesView.swift` | list, share and delete logs |
| `Support/DisableInteractivePopGesture.swift` | turns off swipe-back on map screens |

## Coordinates

Everything on a map is in **millimetres on the glass**. `MapTransform` turns millimetres into points with
`PhysicalDimensions.mmToPoints`, so a 12 mm road is 12 mm wide on every iPhone.

* Overviews have their origin at the top left, y down, inside a 60 by 116 mm reference area (a 6.1 inch iPhone
  below the navigation bar).
* Intersection maps have their origin at the centre of the screen, y down, in the same reference area. The
  junction itself sits at the centre unless the walk would not fit; then the map is centred on the walk (see
  `frame_for`), so the junction centre is read from the map's `center` element, not assumed at (0, 0).

The map is centred in the space between the navigation bar and the home indicator, and drawing is clipped to
that space. If a phone has less room than the reference area, the whole map shrinks to fit; it never grows
past true size.

## How the maps are made

`tools/build_maps.py` reads:

* `tools/osm/old_port_area.json`, an OpenStreetMap extract of the Old Port (roads and crossings);
* `tools/study_spec.py`, the study: the words spoken on every map (copied from the team's descriptions), the
  overview layouts, and for each intersection which legs have crosswalks, zebra or unmarked, which are
  straight or angled, the median, and the way the walk goes through it.

It writes one JSON map per entry in `ORDER`, `Maps/study.json`, `docs/STUDY.md` and, with `--preview`, a
true-size PNG of every map. It stops if a spoken text contains a dash or an arrow, if two dots on a map would
touch, or if a route end falls off the screen.

### Overviews

Each overview is a list of legs from the start, each a screen direction and a length in mm ending at an
intersection (red square with its spoken cue), a plain corner or the end. Stubs are the streets the walk does
not follow. The layouts follow the team's mockups and are not to scale.

### Intersection maps

* **Arms** come from OpenStreetMap at their true bearings, with the names the team uses (`rename`).
* **Orientation**: the map is turned so the arm walked in on points down and the walk goes up. The return at
  Gorham's Corner, which starts at the corner, faces its first crossing instead (`"heading": "first_crossing"`).
* **Roads** are 12 mm wide and run off the screen. Sidewalk centre lines run 13.1 mm from each road's centre
  and meet at the corners.
* **Crosswalks** run corner to corner on the legs listed in the spec. `straight` squares one up when its ends
  are more than 2 mm uneven; `skew` moves one end further out along its arm, for the crosswalks the team
  describes as angled. A leg with a `median` gets a green strip from just inside its crosswalk outwards, and
  its crosswalk is split in two around it.
* **The walk** follows the chosen side of the arm walked in on, crosses arms corner to corner (the shorter way
  round unless `via` says otherwise) and leaves along the chosen side of the arm walked out on. It starts 16 mm
  before its first crosswalk and ends 14 mm after its last, unless the spec or the screen edge says otherwise.
  Jogs shorter than 1.5 mm are smoothed out.
* **The offset intersection** (Exchange Street and Moulton Street) has its own builder, `build_offset`: Fore
  Street straight through two junction points `offset_mm` apart, Exchange Street on one side and Moulton
  Street on the other, and the angled crosswalk between their corners.
* **Dots** are placed by the generator: an orange turn dot where the walk bends more than 40 degrees, a pink
  dot at each crosswalk end, and the two yellow route ends. A route end wins over a turn, and a turn over a
  crosswalk end; dots that would touch, or that the screen edge would cut, are left out.
* **Tidying**: sidewalks, crosswalks and medians shorter than 1.5 mm or wholly off screen are left out.

Zebra bars are painted only where a crossing lies over the road: up to three, one centred in each equal share
of that span, with fewer on a short span (half of a split crossing) so bars stay at least 1 mm apart.
`MapDrawing.stripeLayout` and `tools/preview.py` use the same rule. An unmarked crossing is drawn as two thin
dashed lines; it feels and sounds the same as a zebra.

## Touch handling

`TactileCanvasView` reads touches directly whether VoiceOver is on or off, so both behave the same. Under
VoiceOver it is a direct-touch element (`.allowsDirectInteraction`, `.silentOnTouch`) with no hint, so
VoiceOver reads only its short name when the map opens.

* A tap is a touch shorter than 0.45 s that moves less than 28 points. A second tap within 0.45 s and 48 points
  is a double tap; a single tap is reported once the double-tap window has passed.
* A two-finger tap is two fingers down and up within 0.4 s without moving; two within 0.5 s are a two-finger
  double tap. VoiceOver sends the same gesture as the magic tap; either way it is acted on once.
* Three-finger swipes are seen by a gesture recogniser and by a raw-touch check, and by VoiceOver as scrolls;
  each is acted on once. Up and down step through the information items (returning false at either end so
  VoiceOver plays its boundary sound); right, and the VoiceOver escape gesture, mean ready to cross.
* A second finger stops exploring, so multi-finger gestures do not buzz.

Each controller hit-tests in millimetres in a fixed priority order (see the tables in the README). On an
intersection map the median comes before the path, so it is felt where the path crosses it, and the centre
after it, so it never interrupts the path. Once the finger is on an element it keeps it within an extra 0.8 mm,
so a finger resting on an edge does not flicker between two elements. Move events are logged at most 10 times
a second; feedback reacts to every move.

## Speech and the description player

`FeedbackManager.speak` says a map name at once, cutting off the name before it; the same words within half a
second are said once. `speakTracked` speaks part of a description and reports when it ends: finished, or cut
off. `SpeechService` gets that from VoiceOver's announcement-finished notification (matched by text; an
announcement cut off by one with the same words is told apart by a short window) or from the speech
synthesiser's delegate.

`DescriptionPlayer` keeps one thing playing at a time. Starting anything cuts off what was playing; a stop by
the participant says "Stopped."; an item that finishes starts the next; a token makes sure a late report from
an older phrase is ignored. Controllers ask `player.isPlaying` before saying a map name, so names never cut
the description off. `MapVisit` counts what the player reports for the visits log.

## Feedback

`FeedbackManager.set(_:)` takes one mode. A new mode stops the old one's haptic loop and timers first, so
nothing is left running.

| Mode | Haptic | Sound |
|---|---|---|
| road | continuous, intensity 1.0, sharpness 0.1 | |
| sidewalk | continuous, 0.78, 0.78 | |
| intersection | 0.15 s pulse every 0.25 s, 1.0, 0.5 | ding every 0.4 s |
| endpoint | 0.08 s pulse every 0.12 s, 1.0, 0.7 | |
| route | 0.12 s pulse every 0.2 s, 1.0, 0.85 | |
| crosswalk | road buzz when over a road | click every 0.17 s |
| routeOverCrosswalk | route pulse | click every 0.17 s |
| turn | medium impact with each ding | ding every 0.4 s |
| crosswalkEnd | | one ding |
| center | none | two-note chime (784 then 523 Hz) every 0.7 s |
| median | sharp taps every 0.08 s, 1.0, 0.9 | |

The ding is a 1120 Hz tone with an 8 ms attack and fast decay; the click is a 12 ms tick; the boundary thud is a
90 ms 330 Hz tone. The audio session is playback mixed with others, so all of them are heard with the ringer
switch off and alongside VoiceOver.

## Common changes

| Change | Where |
|---|---|
| Words spoken on any map | `tools/study_spec.py` (`STOPS`, `TRAINING_OVERVIEW`, `ROUTE_OVERVIEW`), then rebuild |
| Which legs have crosswalks, markings, angles, medians | `JUNCTIONS` and `OFFSET_JUNCTIONS` in `tools/study_spec.py` |
| The walk through an intersection, start and end gaps | `in`, `out`, `via`, `start_gap`, `end_gap` on the stop in `tools/study_spec.py` |
| Overview layout | `legs` in `TRAINING_OVERVIEW` or `ROUTE_OVERVIEW` |
| Colours, line widths, dot sizes, touch radii | `Map/MapStyle.swift` (keep `tools/build_maps.py` and `tools/preview.py` in step) |
| Haptic strengths and timings | `Feedback/HapticService.swift`, `Feedback/FeedbackManager.swift` |
| Gestures | `Map/TactileCanvasView.swift`, and what they do in the two controllers |
| Researcher options and their defaults | `Study/StudySettings.swift`, `Study/StudyHomeView.swift` |
| Log columns | `Logging/StudyLog.swift` |

After changing anything under `tools/`, run `python3 tools/build_maps.py --preview` and the tests.

## Refreshing the OpenStreetMap data

`tools/fetch_osm.sh` downloads the extract again from the Overpass API (Old Port: 43.6535, -70.2600 to
43.6635, -70.2440). Rebuild the maps afterwards and compare the previews. Node IDs in `study_spec.py` may need
updating if OpenStreetMap has been re-edited around a junction; the build stops with the junction's name if an
arm it expects is missing.
