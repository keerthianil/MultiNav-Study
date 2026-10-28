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
4. **Customization**: the six information items for Trial 2, each on or off (all on by default). Practice and
   Trial 1 always play every item.
5. **Options**: whether the participant can finish with a gesture (on), the system voice speed (used when
   VoiceOver is off), and whether the map is shown on screen (off keeps it dark; touch still works).
6. **Data Files**: view, share and delete the logs.

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
| Two-finger double tap | play the announcement again; while it plays, stop it |
| Double tap | play the information items, one after another; while they play, stop them. The next double tap starts over from the first |
| Three-finger swipe up / down | next / previous information item, carrying on from there |
| Three-finger swipe right | ready to cross: records the end time and closes the map (the VoiceOver escape gesture does the same) |
| Single tap | a pulse, and the name of what is under the finger if it was not just said |

The information items, in order: intersection geometry, traffic direction, traffic control, pedestrian
signals, crosswalks, truncated domes and curb cuts. Stopping says "Stopped." While the announcement or an item
plays, the map keeps vibrating and sounding but holds back names, so the description is heard to the end. On
an overview, a double tap also plays the overview again.

### Route overviews

Laid out like the team's mockups, not to scale, with the start near the bottom.

| Under the finger | Looks like | Vibration | Sound | Speech |
|---|---|---|---|---|
| Start or end | yellow dot | fast pulse | | "Start of route: You are here, at Dock Fore, 336 Fore Street." |
| Intersection | red square | slow pulse | ding every 0.4 s | "Intersection 1: 4-way intersection of Fore Street and Silver Street." |
| Route | cyan line | rhythmic pulse | | "Route" |
| Cross street | blue line | steady heavy buzz | | street name |

### Intersection maps

Each junction at its true angles from OpenStreetMap, turned so the way the participant walks in is up, with
the walking path from "You are here" to "End of intersection route". The return maps are turned for the
return approach. Crosswalks follow the team's descriptions (zebra or unmarked, straight or angled) and the
aerial photos.

| Under the finger | Looks like | Vibration | Sound | Speech |
|---|---|---|---|---|
| Turn | orange dot | tap with each ding | ding every 0.4 s | "Turn" |
| Crosswalk end | pink dot | | one ding | |
| Start or end of the path | yellow dot | fast pulse | | "You are here" or "End of intersection route" |
| Median | green | fast, sharp pulses, also where the path crosses it | | "Median" |
| Path over a crosswalk | cyan on stripes | rhythmic pulse | clicks | "Crosswalk across Fore Street" |
| Path | cyan line | rhythmic pulse | | "Route" |
| Centre of the intersection | small white ring | **none** | two-note chime | "Center" |
| Crosswalk | white bars, or dashed lines when unmarked | road buzz under it | clicks | "Crosswalk across Silver Street" |
| Sidewalk | grey line | softer steady buzz | | "Sidewalk along Fore Street" |
| Road | blue | steady heavy buzz | | street name |

The centre and the median work the same whatever information items are switched off, as do all other map
sounds and vibration.

## VoiceOver

The map is a VoiceOver direct-touch area that stays silent on touch, so every finger movement reaches the map.
With VoiceOver on, everything is spoken as VoiceOver announcements in the listener's own voice and rate; the
app follows when each announcement ends to read the next item. A two-finger double tap arrives as the magic
tap, the three-finger swipes as scrolls (VoiceOver plays its boundary sound past the first or last item) and
the three-finger swipe right also as the escape gesture. When a map opens, VoiceOver moves onto it and reads
its name ("Intersection map"), then the announcement follows.

## Logs

Logs are saved in the app's Documents folder. They can be shared from **Data Files**, opened in the Files app
under *On My iPhone > MultiNav Study 2*, or copied off over USB in Finder. Each session writes three files,
named by participant and start time:

| File | Contents |
|---|---|
| `P07_20261028_142512_visits.csv` | one row per map visit: opened, first touch, ended and how (Done or the gesture), seconds from opening and from the first touch, announcement plays and repeats, double tap activations, plays of each item and replays, the items switched on when the map opened and at the end, settings changes during the visit, touches |
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
