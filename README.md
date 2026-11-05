# MultiNav Study 2

An iOS research app for blind and low-vision travellers, built at UNAR Labs, Roux Institute, Northeastern
University, for the MultiNav user study in Portland, Maine. Participants learn a walking route from the
Maine Center (300 Fore Street) to Gorham's Corner on a touchscreen map, then stop at each intersection on
the way and explore it by touch, vibration, sound and speech before crossing. On the way back they hear only
the information they chose. It is designed for VoiceOver first and works the same without it.

The maps come from OpenStreetMap, checked against aerial photos, with every word spoken taken from the
research team's study plan and intersection descriptions. The app is built on the **MultiNav** foundational
package ([ProjectMultiNav](https://github.com/Hariprasath88/ProjectMultiNav)).

## The study

| Phase | Where | Maps |
|---|---|---|
| Training | indoors | a made-up route overview (Home to Nick's Bakery) and intersection (Pear Street and Apple Street) to learn the gestures, then the overview of the real route |
| Practice | Fore Street and Pearl Street | intersection 0, repeated as often as needed |
| Trial 1 | to Gorham's Corner | intersections 1 to 5, every information item on |
| Customization | between the trials | the participant picks the information items for Trial 2 |
| Trial 2 | back toward the Maine Center | the same five intersections in reverse, with the chosen items |

Intersections: 1 Fore Street and Silver Street (with a median), 2 Fore Street, Moulton Street and Exchange
Street (offset), 3 Commercial Street and Union Street, 4 Union Street and Fore Street, 5 Fore Street, Center
Street and York Street (Gorham's Corner, five legs). Turn-by-turn directions between intersections are given
by the researchers in person.

Every map and everything the app says on it is listed in [docs/STUDY.md](docs/STUDY.md), with the points the
team still needs to confirm at the top.

## The researcher's screen

The first screen follows the study from top to bottom.

1. **Participant**: type the participant ID (letters, digits and hyphens). Opening the first map starts the
   session; *End Session* closes its logs and clears the ID for the next participant. A session that was
   running when the app closed carries on when it opens again.
2. **Open Next**: opens the next map in study order. Between intersections this is the only button needed.
3. **The maps, by phase**: any map can be opened again. Each row shows how often it has been opened, and the
   practice shows its attempts; every visit is logged with its number.
4. **Customization**, between the trials: *Information items* shows which of the six items Trial 2 plays (all
   on by default) and opens their switches. Practice and Trial 1 always play every item.
5. **Data Files**: view, share and delete the logs.

The gear at the top opens **Settings**, which rarely change: whether the participant can finish with a gesture
(on), the system voice speed (used when VoiceOver is off), and whether the map is shown on screen (off keeps it
dark; touch still works). The app version is at the bottom.

On a map the top bar is for the researcher: **Done** when the participant is ready to cross (with a
confirmation when VoiceOver is off), and in Trial 2 a button for the information items, which can be changed
at any intersection. There is no Back button.

## On a map

When a map opens, its announcement plays: the route overview, or the intersection and the route's crossings
("You are at the 4-way intersection of Fore Street and Silver Street. Your route first crosses Fore Street and
then turns left to cross Silver Street, then continues along the other side of Fore Street.").

| Gesture | What it does |
|---|---|
| Drag one finger | explore; works the whole time, even while something is being read |
| Double tap | play the announcement (on an overview, the route overview) again; while it plays, stop it |
| Two-finger double tap | description mode: says "Description mode." and reads nothing more, so the next swipe starts from the first item; while an item is read, stop it |
| Two-finger swipe up / down | read the next / previous information item, on its own |
| Three-finger swipe right | ready to cross: records the end time and closes the map (the VoiceOver escape gesture does the same) |
| Single tap | a pulse, and the name of what is under the finger if it was not just said |

The information items, in order: intersection geometry, traffic direction, traffic control, pedestrian
signals, crosswalks, truncated domes and curb cuts. Each swipe reads one item and nothing after it; half a
second after its words comes its place, "1 of 6" to "6 of 6"; in Trial 2 only the items switched on are
counted. Stopping says "Stopped." Past the first or last item the map plays a low boundary sound. While the
announcement or an item plays, the map keeps vibrating and sounding but holds back names, so the description
is heard to the end. The gestures are the same on every map: one finger for the map and its announcement, two
fingers for the information items. An overview has no items, so there the two-finger gestures give the
boundary sound.

### Route overviews

Laid out like the team's mockups, not to scale, with the start near the bottom. The square without a number
is the corner of Commercial Street and Moulton Street, where the route turns. Where the route turns, the
square's cue ends with "Turn."; it gives no direction, since left and right on the map need not be the
traveller's.

| Under the finger | Looks like | Vibration | Sound | Speech |
|---|---|---|---|---|
| Start or end | yellow dot | fast pulse | | "Start of route: You are here, at Dock Fore, 336 Fore Street." |
| Intersection | red square | slow pulse | one ding as the finger arrives | "Intersection 4: 4-way intersection of Union Street and Fore Street. Turn." |
| Route | cyan line | rhythmic pulse | | the street it runs along: "Route on Fore Street" |
| Cross street | blue line | steady heavy buzz | | street name |

### Intersection maps

Each junction at its true angles from OpenStreetMap, with the walking path from "You are here", at the
corner where the participant is lined up, to "End of intersection route". Every map is turned the way the
participant faces there, so the first crossing points up; the return maps are turned for the return
approach. Crosswalks follow the team's descriptions (zebra or unmarked, straight or angled) and the aerial
photos.

| Under the finger | Looks like | Vibration | Sound | Speech |
|---|---|---|---|---|
| Turn | orange dot | rhythmic pulse, as on the path | ding every 0.4 s | "Turn left" or "Turn right" |
| Crosswalk end | pink dot at a corner | rhythmic pulse where the path runs through it, otherwise the sidewalk's buzz | one ding | |
| Start or end of the path | yellow dot | fast pulse | | "You are here" or "End of intersection route" |
| Median | green | fast, sharp pulses, also where the path crosses it | | "Median" |
| Path over a crosswalk | cyan on stripes | rhythmic pulse | clicks | "Route crossing Fore Street" |
| Path | cyan line | rhythmic pulse | | "Route" |
| Centre of the intersection | small white ring | steady heavy buzz, as on a road | two-note chime, once | "Center" |
| Crosswalk | white bars, or dashed lines when unmarked | road buzz over the road, the sidewalk's buzz between the road and the corner | steady clicks, one level all the way | "Silver Street crosswalk" |
| Sidewalk | grey line | softer steady buzz | | "Fore Street sidewalk" |
| Road | blue | steady heavy buzz | | street name |

The path keeps one pulse from end to end, over crosswalks, turns and crosswalk ends, so it can be followed
without a break; only its two ends and the median feel different. Nothing at a corner is still: the pink dot
and the end of the crosswalk vibrate like the sidewalk they sit on. Tones sound once when the finger arrives,
except the turn dot's ding. The centre and the median work the same whatever information items are switched
off, as do all other map sounds and vibration.

### Sizes and spacing

All in millimetres on the glass. A map is drawn for a 60 by 116 mm area (a 6.1 inch iPhone below the top
bar) and only shrinks on a smaller screen. "Touch" is how far from an element's centre or centre line the
finger counts as on it; once on an element, the finger keeps it 0.8 mm further, so an edge does not
flicker.

| Route overviews | Drawn | Touch |
|---|---|---|
| Street (blue) | 4 wide | 2 from its line |
| Cross street stub | 13.5 long from the square's centre; 9 for the two Fore Street stubs between intersections 2 and 4, which face each other 26.5 apart; 10 to 12 on the training overview | as a street |
| Route (cyan) | 3.5 wide | 3.65 from its line |
| Intersection (red square) | 8 square, 0.5 white edge | 4.65 from its centre |
| Start or end (yellow dot) | 6 across, 0.4 white edge | 4 from its centre |
| Distance between squares | 12 to 26.5 | |

| Intersection maps | Drawn | Touch |
|---|---|---|
| Road (blue) | 18 wide | its width |
| Sidewalk (grey) | 4 wide, centre line 12.2 from the road's centre line: 1.2 between road and sidewalk | 2.3 from its line, so 0.9 between road and sidewalk is not felt |
| Route (cyan) | 4 wide with a 0.3 blue edge, along the sidewalk; ends at least 5.5 inside the screen | 3.65 from its line |
| Crosswalk | corner to corner; zebra bars 1 along the crossing by 2.8 across, up to 3, at least 1 apart; unmarked: two dashed lines 0.35 wide, 1.4 either side of its line | 4 from its line |
| Median (green) | 3 wide | 2.7 from its line |
| Centre | white ring 2 across | 5 from the centre |
| Turn (orange dot) | 6 across | 3.2 from its centre |
| Crosswalk end (pink dot) | 5 across | 2.7 from its centre |
| Start or end of the path (yellow dot) | 6 across | 4 from its centre |
| Between any two dots | at least 1 clear | |
| Path after its last crosswalk | 14 (6 at Gorham's Corner), or to the screen edge | |

## VoiceOver

The map is a VoiceOver direct-touch area that stays silent on touch, so every finger movement reaches the map,
and VoiceOver hands the map's gestures to the app instead of acting on them itself: a two-finger swipe up or
down steps through the items rather than reading the screen. With VoiceOver on, everything is spoken as
VoiceOver announcements in the listener's own voice and rate; the app follows when each announcement ends, so
an item's place comes only after its words. The two-finger double tap also works as VoiceOver's magic tap, and
the three-finger swipe right as its scroll and escape gestures. When a map opens, VoiceOver moves onto it and
reads its name ("Intersection map"), then the announcement follows.

The two-finger double tap works even when VoiceOver focus has moved to the top bar. Closing a map, opening the
Trial 2 sheet or switching VoiceOver on or off stops whatever is being read, and nothing carries on after it.

## Logs

Logs are saved in the app's Documents folder. They can be shared from **Data Files**, opened in the Files app
under *On My iPhone > MultiNav Study 2*, or copied off over USB in Finder. Each session writes three files,
named by participant and start time:

| File | Contents |
|---|---|
| `P07_20261028_142512_visits.csv` | one row per map visit: opened, first touch, ended and how (Done or the gesture), seconds from opening and from the first touch, announcement plays and repeats, detail activations (two-finger double taps), plays of each item and replays, the items switched on when the map opened and at the end, settings changes during the visit, touches |
| `P07_20261028_142512_events.csv` | everything in order: maps opened and closed, every announcement and item started, finished, stopped or cut off, gestures, each change to the information items and when, what the map said, VoiceOver changes, errors |
| `P07_20261028_142512_touches.csv` | every touch down, move (10 per second) and up: what was under the finger, in points and mm, and what was being read at the time |
| `MultiNav_app_log.csv` | across all sessions: app launches, background and foreground, sessions and every error |

Every row carries the participant, the phase (Training, Practice, Trial 1, Customization, Trial 2), the map
("Intersection 2", "Reversed intersection 5") and the visit number, so practice attempts and repeated visits
can be told apart and matched to the researchers' notes and video.

## The MultiNav package

The app depends on [ProjectMultiNav](https://github.com/Hariprasath88/ProjectMultiNav) (product
`TactileMapKit`) as a Swift package from GitHub, pinned in `Package.resolved`. It builds on:

* **TactileMapCore**: every bundled map is a `TactileMapDocument` read with its loader; map elements are its
  `MapElement` and `TactileElementType`, extended with the study's own types (sidewalk, median, centre and so
  on); every size goes through `PhysicalDimensions` so a millimetre is a millimetre on every iPhone.
* **TactileMapLogging**: the touch log is a `TouchLogger` and records `TouchEvent`s.

Feedback, rendering and gestures are the app's own, tuned for these maps.

## Changing the maps or the wording

The JSON maps in `MultiNavStudy2/Maps` are generated; do not edit them by hand.

1. Edit `tools/study_spec.py`: the words spoken on every map, the overview layouts, which legs have which
   crosswalks, the median, and the way each walk goes through its intersection.
2. Run `python3 tools/build_maps.py --preview` (Python 3 with Pillow). It rewrites the maps, `study.json`,
   `docs/STUDY.md` and the true-size previews in `docs/map_previews/`, and stops if any spoken text has a dash
   or any dots on a map would overlap.
3. Build the app.

See [docs/DEVELOPER_GUIDE.md](docs/DEVELOPER_GUIDE.md) for how the maps are made and how the code is laid out.

## Data

Map data © OpenStreetMap contributors, available under the Open Database License (ODbL). Crosswalks and
medians checked against Maine GeoLibrary aerial photos (2017) and Vantor satellite imagery (2025), viewed
through Esri World Imagery. Intersection descriptions by the MultiNav research team.

## Research context

A research prototype from UNAR Labs at Northeastern University's Roux Institute, studying non-visual
wayfinding with touchscreen tactile maps. It is not App Store production software.
