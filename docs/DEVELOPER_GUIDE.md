# Developer guide

How MultiNav Study 2 is put together: where the maps come from, how they are drawn and touched, and where
to make common changes.

## Layout

```
MultiNavStudy2.xcodeproj      project; the app folder is a synchronized group
Config/Info.plist             file sharing key, merged into the generated Info.plist
MultiNavStudy2/
  App/                        app entry, lifecycle
  Home/                       route list (HomeView) and routes.json reader (RouteCatalog)
  Screens/                    the two map screens and the SwiftUI to UIKit bridge
  Map/                        map model, drawing, touch surface, the two map controllers
  Feedback/                   haptics, sounds, speech, and the FeedbackManager that runs them
  Logging/                    study logs and the Data Files screen
  Support/                    swipe-back blocker
  Maps/                       generated map JSON, bundled as resources
  Assets.xcassets             app icon and accent colour
MultiNavStudy2Tests/          map data tests (Swift Testing)
tools/                        map generator, OSM extracts, the team's KML, icon script (make_app_icon.py)
docs/                         this guide, ROUTES.md, map previews
```

## Files

| File | What it does |
|---|---|
| `App/MultiNavStudy2App.swift` | `@main`; starts the feedback engines, logs launch, background and foreground |
| `Home/HomeView.swift` | route list, participant ID, Data Files; ends the log session on returning to the list |
| `Home/RouteCatalog.swift` | reads `Maps/routes.json` |
| `Screens/MapScreens.swift` | Level 1 and Level 2 screens; loads a map when the screen is created, starts the log session, announces the screen |
| `Map/TactileCanvasView.swift` | the touch surface: draws a `MapScene`, reads raw touches, detects taps and double taps, VoiceOver direct touch, back gestures |
| `Map/OverviewController.swift` | Level 1: drawing, hit-testing, feedback, double tap to open an intersection |
| `Map/DetailController.swift` | Level 2: drawing, hit-testing, feedback, double tap to go back |
| `Map/MapModels.swift` | reads a map with the MultiNav `TactileMapDocument` loader into drawable elements; works out turn dots and crosswalk stripe spans |
| `Map/MapTransform.swift` | millimetres to points with MultiNav `PhysicalDimensions` |
| `Map/MapStyle.swift` | every colour, size and touch radius, in mm |
| `Map/MapDrawing.swift`, `Map/MapGeometry.swift` | drawing and geometry helpers |
| `Feedback/FeedbackManager.swift` | one feedback mode at a time; switching mode stops everything the last one started |
| `Feedback/HapticService.swift` | Core Haptics patterns; restarts the engine after a reset or a VoiceOver change |
| `Feedback/AudioService.swift` | the ding and the crosswalk click, synthesised once, played from one engine |
| `Feedback/SpeechService.swift` | VoiceOver announcement (default priority, so it can be cut off) or system voice |
| `Logging/StudyLog.swift` | session touch and event CSVs (the touch log is a MultiNav `TouchLogger`), the app log |
| `Logging/LogFilesView.swift` | list, share and delete logs |
| `Support/DisableInteractivePopGesture.swift` | turns off swipe-back on map screens |

## Coordinates

Everything on a map is in **millimetres on the glass**. `MapTransform` turns millimetres into points with
`PhysicalDimensions.mmToPoints`, so a 4 mm road is 4 mm wide on every iPhone.

* Level 1 maps have their origin at the top left, y down, inside a 60 by 116 mm reference area (a 6.1 inch
  iPhone below the navigation bar).
* Level 2 maps have their origin at the junction centre, y down, in the same reference area.

The map is centred in the space between the navigation bar and the home indicator. If a phone has less room
than the reference area, the whole map shrinks to fit; it never grows past true size.

## How the maps are made

`tools/build_maps.py` reads three things:

* `tools/osm/*.json`, OpenStreetMap extracts of the two areas (roads, sidewalks, crossings, signals);
* `tools/source/multinav_walking_routes.kml`, the team's map: route lines and the intersection pins;
* `tools/route_spec.py`, the study choices: the intersections on each route, the side of the street the walk
  uses at each one, endpoint names, and traffic control the team confirmed.

### Level 1

For each route the generator lists the stops in order (start, each intersection, destination) and gives
each street run one direction, the true bearing turned so the route goes up the screen and squared to 90
degrees (45 where a street really is diagonal). Gaps between stops follow real distance but never fall below
10 mm between intersections or 8 mm to an endpoint. Every arm the walk does not use becomes an 8 mm stub at
its own squared angle. The largest scale that fits the reference area is chosen, and then one axis may be
stretched by up to 2.6 times to use the rest of the screen.

Orientation: Routes 1 and 2 have northeast at the top, Route 3 southwest, Route 4 southeast. Portland's
downtown grid runs northeast and northwest, so a turn of 45 degrees squares its streets to the screen.

### Level 2

Each arm keeps its true bearing, turned the same way as the overview. Roads are 12 mm wide (7 mm at the
roundabout). Sidewalks run 13.1 mm from each road's centre line and meet at the corners; crosswalks run
from corner to corner across the arms where OpenStreetMap records a crossing, so a walk along a sidewalk
meets the crosswalk exactly where the sidewalk turns. Crossings with a refuge island are split in two at the
island. The walking path follows the sidewalk on the chosen side, crossing arms corner to corner by the
shorter way round, unless `via` in the spec says otherwise.

Zebra bars are painted only where a crossing lies over the road: up to three, one centred in each equal share
of that span, with fewer on a short span (half of a split crossing) so bars stay at least 1 mm apart.
`MapDrawing.stripeLayout` and `tools/preview.py` use the same rule.

Crosswalks marked *assumed* in `docs/ROUTES.md` come from `assume_crossing` in the spec and should be
checked on site.

## Touch handling

`TactileCanvasView` reads touches directly whether VoiceOver is on or off, so both behave the same. Under
VoiceOver it is a direct-touch element (`.allowsDirectInteraction`, `.silentOnTouch`). It follows one finger;
a second finger stops exploring so multi-finger gestures do not buzz.

* A tap is a touch shorter than 0.45 s that moves less than 28 points. A second tap within 0.45 s and 48
  points is a double tap; a single tap is reported once the double-tap window has passed.
* Back: three-finger swipe right (a gesture recogniser, plus a raw-touch check), VoiceOver escape,
  VoiceOver three-finger scroll right. Each controller ignores a second back request.

Each controller hit-tests in millimetres in a fixed priority order (see the tables in the README). Once the
finger is on an element it keeps it within an extra 0.8 mm, so a finger resting on an edge does not flicker
between two elements. Feedback changes only when the element changes. Move events are logged at most 10
times a second; feedback reacts to every move.

## Feedback

`FeedbackManager.set(_:)` takes one mode. A new mode stops the old one's haptic loop and timers first, so
nothing is left running. Speech is separate and is never stopped by a mode change; a new phrase cuts off the
old one, and the same phrase asked for twice within half a second is spoken once.

| Mode | Haptic | Sound |
|---|---|---|
| road | continuous, intensity 1.0, sharpness 0.1 | |
| sidewalk | continuous, 0.78, 0.78 | |
| intersection | 0.15 s pulse every 0.25 s, 1.0, 0.5 | ding every 0.4 s |
| landmark | 0.08 s pulse every 0.12 s, 1.0, 0.7 | |
| route | 0.12 s pulse every 0.2 s, 1.0, 0.85 | |
| crosswalk | road buzz when over a road | click every 0.17 s |
| routeOverCrosswalk | route pulse | click every 0.17 s |
| turn | medium impact with each ding | ding every 0.4 s |
| crosswalkEnd | | one ding |
| island | two transients 0.11 s apart, every 0.55 s, 0.85, 0.4 | |

The ding is a 1120 Hz tone with an 8 ms attack and fast decay; the click is a 12 ms tick. The audio session
is playback mixed with others, so both are heard with the ringer switch off and alongside VoiceOver.

## Common changes

| Change | Where |
|---|---|
| Colours, line widths, dot sizes, touch radii | `Map/MapStyle.swift` (keep `tools/build_maps.py` and `tools/preview.py` in step for the generator) |
| Haptic strengths and timings | `Feedback/HapticService.swift`, `Feedback/FeedbackManager.swift` |
| Spoken wording of crosswalks, sidewalks, intro lines | `tools/build_maps.py` (`crosswalk_name`, `control_sentence`, `build_level2`) |
| Which side of a street a route walks, endpoint names, control | `tools/route_spec.py` |
| Minimum spacing on the overview | `MIN_GAP_JUNCTIONS`, `STUB` in `tools/build_maps.py` |
| Log columns | `Logging/StudyLog.swift` |

After changing anything under `tools/`, run `python3 tools/build_maps.py --preview` and the tests.

## Refreshing the OpenStreetMap data

`tools/fetch_osm.sh` downloads both extracts again from the Overpass API (USM and Forest Avenue:
43.6585, -70.2825 to 43.6680, -70.2715; Old Port: 43.6535, -70.2600 to 43.6635, -70.2440). Rebuild the maps
afterwards and compare the previews. Node IDs in `route_spec.py` may need updating if OpenStreetMap has been
re-edited around a junction; the build stops with the junction's name if an arm it expects is missing.
