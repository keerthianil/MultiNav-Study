// StudyContentTests.swift
// Checks the study as bundled: every map in order, the team's wording word
// for word, and maps that load, fit the screen and keep their dots apart.

import CoreGraphics
import Foundation
import Testing
@testable import MultiNavStudy2

@MainActor
struct StudyContentTests {
    private let maps = StudyContent.maps

    @Test func studyOrder() {
        #expect(maps.map(\.id) == [
            "training_overview", "training_intersection", "route_overview", "intersection_0",
            "intersection_1", "intersection_2", "intersection_3", "intersection_4", "intersection_5",
            "return_5", "return_4", "return_3", "return_2", "return_1",
        ])
        #expect(StudyContent.maps(in: .training).count == 3)
        #expect(StudyContent.maps(in: .practice).map(\.logID) == ["Intersection 0"])
        #expect(StudyContent.maps(in: .trial1).map(\.logID) == (1...5).map { "Intersection \($0)" })
        #expect(StudyContent.maps(in: .trial2).map(\.logID) == [5, 4, 3, 2, 1].map { "Reversed intersection \($0)" })
    }

    @Test func everyIntersectionHasSixItemsInOrder() {
        for map in maps {
            if map.kind == .overview {
                #expect(map.items.isEmpty)
            } else {
                #expect(map.items.map(\.category) == InfoCategory.allCases, "\(map.id)")
                #expect(map.items.allSatisfy { !$0.text.isEmpty })
            }
            #expect(!map.announcement.isEmpty)
        }
    }

    /// The wording is the research team's, from their 10/28 descriptions.
    @Test func wordingMatchesTheTeamsDescriptions() throws {
        let practice = try #require(StudyContent.map(id: "intersection_0"))
        #expect(practice.announcement == "You are at the 4-way intersection of Fore Street and Pearl Street. "
                + "Your route crosses Pearl Street, then continues along Fore Street.")
        #expect(practice.items[2].text == "The intersection is controlled by a traffic signal. "
                + "Right turns are permitted during the walking cycle.")
        let silver = try #require(StudyContent.map(id: "intersection_1"))
        #expect(silver.items[4].text == "The Fore Street crossing is unmarked and divided into two stages by a "
                + "median. The Silver Street crossing is unmarked.")
        let commercial = try #require(StudyContent.map(id: "intersection_3"))
        #expect(commercial.items[3].text == "The intersection has APS, located on a pole about 6 feet back from "
                + "the intersection.")
        let union = try #require(StudyContent.map(id: "return_4"))
        #expect(union.items[5].text == "The truncated dome is misaligned with the crosswalk when approaching the "
                + "Fore Street crossing. The truncated dome at the end of the crossing is aligned.")
        // The 10/30 updates.
        let overview = try #require(StudyContent.map(id: "route_overview"))
        #expect(overview.announcement == "Your route to Gorham's Corner is approximately 0.5 miles away, primarily "
                + "travelling Southwest. There are 5 intersection crossings along the route.")
        let gorhamsCorner = try #require(StudyContent.map(id: "intersection_5"))
        #expect(gorhamsCorner.announcement == "You are at the 5-way intersection of Fore Street, Center Street, York "
                + "Street, and Pleasant Street. Your route first crosses Fore Street, then turns right to cross "
                + "Center Street, and continues along York Street to your destination.")
        // The return names Pleasant Street the same way.
        let gorhamsReturn = try #require(StudyContent.map(id: "return_5"))
        #expect(gorhamsReturn.announcement == "You are at the 5-way intersection of Center Street, Fore Street, "
                + "York Street, and Pleasant Street. Your route first crosses Center Street, then turns left to "
                + "cross Fore Street, and continues along Fore Street.")
        let training = try #require(StudyContent.map(id: "training_intersection"))
        #expect(training.items[2].text == "The intersection is controlled by stop signs in all directions.")
        // Intersection 2 continues straight now that its map is turned (team, 11/05).
        let offset = try #require(StudyContent.map(id: "intersection_2"))
        #expect(offset.announcement == "You are at the 4-way intersection of Fore Street, Moulton Street, and "
                + "Exchange Street. Your route crosses Fore Street, then continues straight along Moulton Street.")
    }

    @Test func overviewCuesAreTheTeamsWords() throws {
        let overview = try MapLoader.overview(named: "route_overview")
        #expect(overview.endpoints[0].announcement == "Start of route: You are here, at Dock Fore, 336 Fore Street.")
        #expect(overview.endpoints[1].announcement == "End of route: Your destination, Gorham's Corner.")
        // "Turn." where the route turns, and the wharves opposite Moulton
        // Street and Union Street named (team, 11/05).
        #expect(overview.nodes.map(\.cue) == [
            "Intersection 1: 4-way intersection of Fore Street and Silver Street.",
            "Intersection 2: 4-way intersection of Fore Street, Moulton Street, and Exchange Street. Turn.",
            "4-way intersection of Commercial Street, Moulton Street, and Long Wharf. Turn.",
            "Intersection 3: 4-way intersection of Commercial Street, Union Street, and Union Wharf. Turn.",
            "Intersection 4: 4-way intersection of Union Street and Fore Street. Turn.",
            "Intersection 5: 5-way intersection of Fore Street, Center Street, York Street, and Pleasant Street. "
                + "Turn.",
        ])
        #expect(overview.nodes.map(\.number) == [1, 2, 0, 3, 4, 5], "the added square has no number")
        let training = try MapLoader.overview(named: "training_overview")
        #expect(training.nodes.map(\.cue) == [
            "Intersection 1: 4-way intersection of Pear Street and Apple Street.",
            "Intersection 2: 3-way intersection of Pear Street and Orange Road. Turn.",
            "Intersection 3: 4-way intersection of Orange Road and Banana Lane. Turn.",
        ])
        #expect(training.endpoints[1].announcement == "End of route: Your destination, Nick's Bakery.")
    }

    /// A square says "Turn." exactly where the route leaves it in another
    /// direction.
    @Test func overviewSaysTurnWhereTheRouteTurns() throws {
        for file in ["route_overview", "training_overview"] {
            let overview = try MapLoader.overview(named: file)
            for node in overview.nodes {
                guard let i = overview.route.firstIndex(where: { MapGeometry.distance($0, node.position) < 0.1 }),
                      i > 0, i + 1 < overview.route.count else {
                    Issue.record("\(file): \(node.name) is not on the route")
                    continue
                }
                let a = overview.route[i - 1], b = overview.route[i], c = overview.route[i + 1]
                let turnsHere = abs((b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)) > 0.5
                #expect(node.cue.hasSuffix(" Turn.") == turnsHere, "\(file): \(node.cue)")
            }
        }
    }

    /// Cross street stubs on the route overview are half again as long as
    /// the first 9 mm (team, 11/05), except the two Fore Street stubs that
    /// face each other between intersections 2 and 4.
    @Test func overviewStubsAreLonger() throws {
        let overview = try MapLoader.overview(named: "route_overview")
        let two = try #require(overview.nodes.first { $0.number == 2 }).position
        let four = try #require(overview.nodes.first { $0.number == 4 }).position
        var stubs = 0
        for street in overview.streets where street.id.hasPrefix("cross_") {
            guard let node = overview.nodes.first(where: { n in street.points.contains { MapGeometry.distance($0, n.position) < 0.1 } })
            else {
                Issue.record("\(street.name) stub has no square")
                continue
            }
            for end in street.points where MapGeometry.distance(end, node.position) > 0.1 {
                let length = MapGeometry.distance(end, node.position)
                let facing = street.name == "Fore Street" && (node.position == two || node.position == four)
                #expect(abs(length - (facing ? 9 : 13.5)) < 0.05, "\(street.name) at \(node.name) is \(length) mm")
                stubs += 1
            }
        }
        #expect(stubs == 13, "every stub end on the route overview")
        #expect(MapStyle.Overview.intersectionSide == 8, "squares are larger than the first 6 mm")
        #expect(MapStyle.Hit.intersection > MapStyle.Overview.intersectionSide / 2)
    }

    /// The square at Commercial Street and Moulton Street has its two other
    /// legs, as in the team's sketch.
    @Test func commercialAndMoultonHasItsLegs() throws {
        let overview = try MapLoader.overview(named: "route_overview")
        let square = try #require(overview.nodes.first { $0.number == 0 })
        let legs = overview.streets.filter { street in
            street.points.contains { MapGeometry.distance($0, square.position) < 0.1 }
        }
        #expect(legs.filter { $0.name == "Long Wharf" }.count == 1)
        #expect(legs.filter { $0.name == "Commercial Street" }.count == 2, "the route on it and the leg behind")
        #expect(legs.filter { $0.name == "Moulton Street" }.count == 1)
    }

    /// Touching the route on an overview names the street it runs along.
    @Test func overviewRouteSaysItsStreet() throws {
        let overview = try MapLoader.overview(named: "route_overview")
        #expect(overview.routeStreets == ["Fore Street", "Fore Street", "Moulton Street", "Commercial Street",
                                          "Union Street", "Fore Street", "York Street"])
        for (i, street) in overview.routeStreets.enumerated() {
            let a = overview.route[i]
            let b = overview.route[i + 1]
            let middle = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            #expect(overview.routeStreet(near: middle) == street)
        }
        let training = try MapLoader.overview(named: "training_overview")
        #expect(Set(training.routeStreets) == ["Pear Street", "Orange Road", "Banana Lane"])
    }

    /// Trial 2 plays only the items switched on; every other phase plays them all.
    @Test func onlyTrialTwoIsCustomised() throws {
        var settings = InfoSettings()
        settings[.control] = false
        settings[.domes] = false
        let trial1 = try #require(StudyContent.map(id: "intersection_2"))
        let trial2 = try #require(StudyContent.map(id: "return_2"))
        let practice = try #require(StudyContent.map(id: "intersection_0"))
        #expect(trial1.items(with: settings).count == 6)
        #expect(practice.items(with: settings).count == 6)
        #expect(trial2.items(with: settings).map(\.category) == [.geometry, .direction, .signals, .crosswalks])
        #expect(settings.summary == "Off: Traffic control, Truncated domes and curb cuts")
        #expect(settings.columns == ["On", "On", "Off", "On", "On", "Off"])
    }

    @Test func everyMapLoadsAndFitsTheScreen() throws {
        for map in maps {
            switch map.kind {
            case .overview:
                let overview = try MapLoader.overview(named: map.file)
                #expect(overview.route.count > 1)
                for p in overview.route + overview.nodes.map(\.position) {
                    #expect(p.x > 0 && p.x < overview.size.width && p.y > 0 && p.y < overview.size.height, "\(map.id)")
                }
            case .intersection:
                let m = try MapLoader.intersection(named: map.file)
                #expect(!m.roads.isEmpty && !m.sidewalks.isEmpty && !m.crosswalks.isEmpty, "\(map.id)")
                #expect(m.center != nil && m.centerRadius > 0, "\(map.id) has no centre point")
                // The last walk of Trial 1 ends at the destination (team, 11/09).
                let end = map.id == "intersection_5" ? "Destination, Gorham's Corner" : "End of intersection route"
                #expect(m.endpoints.map(\.announcement) == ["You are here", end], "\(map.id)")
                let halfW = m.size.width / 2 - 3
                let halfH = m.size.height / 2 - 3
                for p in m.route {
                    #expect(abs(p.x) <= halfW && abs(p.y) <= halfH, "\(map.id): route leaves the screen at \(p)")
                }
                // Participants are lined up at the corner: the walk starts
                // where its first crosswalk begins.
                let start = m.route[0]
                #expect(m.crosswalks.contains {
                    MapGeometry.distance($0.start, start) < 0.1 || MapGeometry.distance($0.end, start) < 0.1
                }, "\(map.id) does not start at the corner")
                #expect(m.roads.allSatisfy { $0.width == 18 }, "\(map.id): roads are 18 mm wide")
            }
        }
    }

    /// Intersection 1 lies further from the start, so some route is felt
    /// before it, and York Street runs on longer to the end (team, 11/09).
    @Test func overviewRouteHasRoomAtBothEnds() throws {
        let overview = try MapLoader.overview(named: "route_overview")
        let one = try #require(overview.nodes.first { $0.number == 1 })
        #expect(MapGeometry.distance(overview.route[0], one.position) >= 16)
        let n = overview.route.count
        #expect(MapGeometry.distance(overview.route[n - 2], overview.route[n - 1]) >= 25, "York Street")
        #expect(overview.routeStreets.last == "York Street")
    }

    /// The training overview's stubs are longer too (team, 11/09): 15 mm.
    @Test func trainingStubsAreLonger() throws {
        let training = try MapLoader.overview(named: "training_overview")
        var ends = 0
        for street in training.streets where street.id.hasPrefix("cross_") {
            let node = try #require(training.nodes.first { n in
                street.points.contains { MapGeometry.distance($0, n.position) < 0.1 }
            })
            for end in street.points where MapGeometry.distance(end, node.position) > 0.1 {
                #expect(abs(MapGeometry.distance(end, node.position) - 15) < 0.05, "\(street.name) at \(node.name)")
                ends += 1
            }
        }
        #expect(ends == 5)
    }

    /// Intersections 3 and 4 sit near the middle of the screen with their
    /// whole walk still on it (team, 11/09), so all four legs are drawn.
    @Test func intersectionsThreeAndFourSitNearTheMiddle() throws {
        for id in ["intersection_3", "intersection_4"] {
            let m = try MapLoader.intersection(named: id)
            let center = try #require(m.center)
            #expect(hypot(center.x, center.y) < 10, "\(id): the junction is \(center) from the middle")
            #expect(m.crosswalks.count == 4, "\(id): every leg's crosswalk is on screen")
            for p in m.route {
                #expect(abs(p.x) <= m.size.width / 2 - 5 && abs(p.y) <= m.size.height / 2 - 5, "\(id): \(p)")
            }
        }
    }

    /// The centre is felt 6.5 mm round, or less where a crosswalk comes
    /// closer, and never over a crosswalk (team, 11/09).
    @Test func centreIsBigger() throws {
        for map in maps where map.kind == .intersection {
            let m = try MapLoader.intersection(named: map.file)
            let center = try #require(m.center)
            let nearest = m.crosswalks.map { MapGeometry.segmentDistance(center, $0.start, $0.end).distance }.min() ?? 99
            if map.subtitle.contains("Moulton") {
                #expect(m.centerRadius == 5, "\(map.id): the angled crosswalk runs over the centre")
            } else {
                #expect(m.centerRadius >= 6.4, "\(map.id)")
                #expect(m.centerRadius <= nearest - MapStyle.Hit.crosswalk, "\(map.id)")
            }
        }
        #expect(MapStyle.Intersection.centerMarkDiameter == 3)
    }

    /// No street is named between the centre and its crosswalk, and beyond
    /// it a road says only its own name (team, 11/09).
    @Test func streetNamesStartBeyondTheCrosswalk() throws {
        for map in maps where map.kind == .intersection {
            let m = try MapLoader.intersection(named: map.file)
            let controller = IntersectionController(map: m, player: DescriptionPlayer(
                announcement: map.announcement, items: map.items, speaker: FakeSpeaker()), label: "Intersection map")
            let roadNames = Set(m.roads.map(\.name))
            var quietSamples = 0
            for road in m.roads {
                let quiet = try #require(road.quiet, "\(map.id): \(road.name) has no quiet stretch")
                let length = MapGeometry.length(of: road.points)
                for d in stride(from: CGFloat(0), through: length, by: 0.5) {
                    guard let p = MapGeometry.point(at: d, along: road.points),
                          abs(p.x) < m.size.width / 2, abs(p.y) < m.size.height / 2 else { continue }
                    let said = controller.spokenName(at: p)
                    if quiet.contains(d) {
                        quietSamples += 1
                        #expect(said.map { !roadNames.contains($0) } ?? true, "\(map.id): \(said ?? "") at \(p)")
                    } else if d > quiet.upperBound + MapStyle.Hit.crosswalk + 0.5, let said, roadNames.contains(said) {
                        #expect(said == road.name, "\(map.id): \(said) on \(road.name) at \(p)")
                    }
                }
            }
            #expect(quietSamples > 0, "\(map.id)")
        }
    }

    /// "Route crossing" is said only where the route crosses that street;
    /// where it walks on past another street's crosswalk it is just "Route"
    /// (team, 11/09).
    @Test func routeSaysCrossingOnlyWhereItCrosses() throws {
        for map in maps where map.kind == .intersection {
            let m = try MapLoader.intersection(named: map.file)
            let controller = IntersectionController(map: m, player: DescriptionPlayer(
                announcement: map.announcement, items: map.items, speaker: FakeSpeaker()), label: "Intersection map")
            let dots = m.turns.map(\.position) + m.crosswalkEnds.map(\.position) + m.endpoints.map(\.position)
            for k in 0..<(m.route.count - 1) {
                let a = m.route[k], b = m.route[k + 1]
                let crossed = Set(m.routeCrossings[k].map { m.crosswalks[$0].street })
                for t in stride(from: CGFloat(0.05), through: 0.95, by: 0.05) {
                    let p = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                    guard dots.allSatisfy({ MapGeometry.distance($0, p) > 4.5 }),
                          m.medians.allSatisfy({ MapGeometry.polylineDistance(p, $0.points) > 3.5 }) else { continue }
                    let said = controller.spokenName(at: p) ?? ""
                    if crossed.isEmpty {
                        #expect(said == "Route", "\(map.id) segment \(k): \(said) at \(p)")
                    } else {
                        #expect(crossed.map { "Route crossing \($0)" }.contains(said), "\(map.id) segment \(k): \(said)")
                    }
                }
            }
            #expect(m.routeCrossings.contains { !$0.isEmpty }, "\(map.id) crosses something")
        }
    }

    /// Sidewalk centre lines run 12.2 mm from the road's centre line, leaving
    /// a 1.2 mm gap between the road and the 4 mm sidewalk (team, 11/05), so
    /// the band where nothing is felt is under 1 mm.
    @Test func sidewalksSitCloseToTheRoad() throws {
        for map in maps where map.kind == .intersection {
            let m = try MapLoader.intersection(named: map.file)
            var nearest = CGFloat.infinity
            for sidewalk in m.sidewalks {
                for (a, b) in zip(sidewalk.points, sidewalk.points.dropFirst()) {
                    for k in 0...20 {
                        let t = CGFloat(k) / 20
                        let p = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                        for road in m.roads { nearest = min(nearest, MapGeometry.polylineDistance(p, road.points)) }
                    }
                }
            }
            let gap = nearest - 9 - MapStyle.Intersection.sidewalkWidth / 2
            #expect(abs(gap - 1.2) < 0.05, "\(map.id): the gap is \(gap) mm")
            let untouched = nearest - MapStyle.Hit.sidewalk - 9
            #expect(untouched < 1, "\(map.id): \(untouched) mm between road and sidewalk is not felt")
        }
    }

    /// Participants are lined up at the corner facing their first crossing,
    /// so on every intersection map the walk sets off up the screen; the
    /// five maps that start by crossing to the side are turned a quarter
    /// turn for it (team, 11/03). Angled crosswalks lean up to about 30
    /// degrees.
    @Test func everyWalkSetsOffUpTheScreen() throws {
        for map in maps where map.kind == .intersection {
            let m = try MapLoader.intersection(named: map.file)
            let a = m.route[0]
            let b = m.route[1]
            let degrees = atan2(b.x - a.x, a.y - b.y) * 180 / .pi
            #expect(abs(degrees) < 35, "\(map.id): the first crossing is \(degrees) degrees from up")
        }
    }

    /// Each turn dot says which way the walk turns (team, 10/30), with a
    /// comma for a short pause before the direction (team, 11/09). The first
    /// turns on 1, 2, 5 and the reversed 3 and 4 went when the walks started
    /// at the corner.
    @Test func turnDotsSayWhichWay() throws {
        let expected: [String: [String]] = [
            "intersection_1": ["Turn, left"], "intersection_3": ["Turn, right"], "intersection_4": ["Turn, left"],
            "intersection_5": ["Turn, right"], "return_5": ["Turn, left", "Turn, right"],
            "return_2": ["Turn, right"], "return_1": ["Turn, right", "Turn, left"],
        ]
        for map in maps where map.kind == .intersection {
            let m = try MapLoader.intersection(named: map.file)
            #expect(m.turns.map(\.cue) == expected[map.id, default: []], "\(map.id)")
        }
    }

    /// Names as the team asked for them on 10/30.
    @Test func sidewalksAndCrosswalksAreNamedByStreet() throws {
        let m = try MapLoader.intersection(named: "intersection_1")
        #expect(Set(m.sidewalks.map(\.name)) == ["Fore Street sidewalk", "Silver Street sidewalk"])
        #expect(Set(m.crosswalks.map(\.name)) == ["Fore Street crosswalk", "Silver Street crosswalk"])
        #expect(Set(m.crosswalks.map(\.street)) == ["Fore Street", "Silver Street"])
    }

    /// The route feels the same all along: its turn dots and the crosswalk
    /// ends on it keep the route's vibration, and the centre buzzes like the
    /// street (team, 10/30).
    @Test func routeVibrationCarriesOnAndCentreBuzzes() throws {
        typealias Mode = FeedbackManager.Mode
        for mode: Mode in [.route, .routeOverCrosswalk, .turn, .crosswalkEnd(onRoute: true)] {
            #expect(mode.haptic == .route, "\(mode)")
        }
        #expect(Mode.center.haptic == Mode.road.haptic)
        #expect(Mode.median.haptic == .median)
        #expect(Mode.endpoint.haptic == .endpoint)
        // A corner never goes still: its pink dot and the end of a crosswalk
        // off the road buzz like the sidewalk (team, 11/05).
        #expect(Mode.crosswalkEnd(onRoute: false).haptic == .sidewalk)
        #expect(Mode.crosswalk(overRoad: false).haptic == .sidewalk)
        #expect(Mode.crosswalk(overRoad: true).haptic == .road)
        var onRoute = 0
        for map in maps where map.kind == .intersection {
            let m = try MapLoader.intersection(named: map.file)
            for end in m.crosswalkEnds {
                #expect(end.onRoute == (MapGeometry.polylineDistance(end.position, m.route) < 0.5))
                if end.onRoute { onRoute += 1 }
            }
        }
        #expect(onRoute > 0, "some crosswalk ends lie on a route")
    }

    /// Tones sound once as the finger arrives (team, 11/05); only a turn dot
    /// repeats its ding. The clicks carry on between the two halves of a
    /// crosswalk and the route over it, so they never restart at the road.
    @Test func tonesSoundOnceAndClicksCarryOn() {
        typealias Mode = FeedbackManager.Mode
        #expect(Mode.intersection.tone == .ding && Mode.intersection.toneRepeat == nil)
        #expect(Mode.center.tone == .chime && Mode.center.toneRepeat == nil)
        #expect(Mode.crosswalkEnd(onRoute: false).tone == .ding && Mode.crosswalkEnd(onRoute: true).toneRepeat == nil)
        #expect(Mode.turn.tone == .ding && Mode.turn.toneRepeat == 0.4)
        for mode: Mode in [.crosswalk(overRoad: true), .crosswalk(overRoad: false), .routeOverCrosswalk] {
            #expect(mode.clicks && mode.tone == nil, "\(mode)")
        }
        for mode: Mode in [.none, .road, .sidewalk, .intersection, .endpoint, .route, .turn,
                           .crosswalkEnd(onRoute: true), .center, .median] {
            #expect(!mode.clicks, "\(mode)")
        }
    }

    /// No two dots on a map touch, so each can be found and felt on its own.
    @Test func dotsNeverOverlap() throws {
        for map in maps where map.kind == .intersection {
            let m = try MapLoader.intersection(named: map.file)
            var dots: [(CGPoint, CGFloat)] = m.endpoints.map { ($0.position, 3) }
            dots += m.turns.map { ($0.position, 3) }
            dots += m.crosswalkEnds.map { ($0.position, 2.5) }
            for i in dots.indices {
                for j in dots.indices where j > i {
                    let gap = MapGeometry.distance(dots[i].0, dots[j].0) - dots[i].1 - dots[j].1
                    #expect(gap >= 0.9, "\(map.id): dots at \(dots[i].0) and \(dots[j].0) overlap")
                }
            }
        }
    }

    /// The Boothby Square island splits Fore Street at Silver Street (both
    /// legs) and at the tip by Pearl Street (one leg). Silver Street's
    /// crossings are unpainted setts; Pearl's island crossing and Moulton
    /// Street's brick band are unpainted too. Every other crosswalk is a zebra.
    @Test func mediansAndMarkings() throws {
        for map in maps where map.kind == .intersection {
            let m = try MapLoader.intersection(named: map.file)
            let unmarked = m.crosswalks.filter { $0.marking == .unmarked }
            #expect(m.medians.allSatisfy { $0.name == "Median" })
            switch map.subtitle {
            case "Fore Street and Silver Street":
                #expect(m.medians.count == 2, "\(map.id)")
                #expect(unmarked.count == m.crosswalks.count, "\(map.id)")
            case "Fore Street and Pearl Street":
                #expect(m.medians.count == 1, "\(map.id)")
                #expect(Set(unmarked.map(\.name)) == ["Fore Street crosswalk"], "\(map.id)")
            case let s where s.contains("Moulton"):
                #expect(m.medians.isEmpty, "\(map.id)")
                #expect(Set(unmarked.map(\.name)) == ["Moulton Street crosswalk"], "\(map.id)")
            default:
                #expect(m.medians.isEmpty, "\(map.id)")
                #expect(unmarked.isEmpty, "\(map.id)")
            }
        }
    }

    /// No dash or arrow in anything spoken: VoiceOver reads them out.
    @Test func spokenTextHasNoDashes() throws {
        var texts: [String] = ["Stopped.", "No details are turned on.", "End of details.", "Start of details.",
                               "Tell the researcher when you are ready."]
        for map in maps {
            texts.append(map.announcement)
            texts += map.items.map(\.text)
            if map.kind == .overview {
                let m = try MapLoader.overview(named: map.file)
                texts += m.nodes.map(\.cue) + m.endpoints.map(\.announcement) + m.streets.map(\.name)
                texts += m.routeStreets.map { "Route on \($0)" }
            } else {
                let m = try MapLoader.intersection(named: map.file)
                texts += m.roads.map(\.name) + m.sidewalks.map(\.name) + m.crosswalks.map(\.name)
                texts += m.crosswalks.map { "Route crossing \($0.street)" } + m.turns.map(\.cue)
                texts += m.medians.map(\.name) + m.endpoints.map(\.announcement)
            }
        }
        for text in texts {
            #expect(!text.contains("\u{2014}") && !text.contains("\u{2013}") && !text.contains("\u{2192}"),
                    "dash or arrow in: \(text)")
            #expect(!text.contains("  ") && !text.contains(" ,"), "spacing in: \(text)")
        }
    }

    @Test func csvFieldsAreEscaped() {
        #expect(CSVWriter.escape("plain") == "plain")
        #expect(CSVWriter.escape("a, b") == "\"a, b\"")
        #expect(CSVWriter.escape("say \"hi\"") == "\"say \"\"hi\"\"\"")
    }

    @Test func clockFormat() {
        #expect(StudyLog.clock(0) == "00:00.0")
        #expect(StudyLog.clock(127.44) == "02:07.4")
        #expect(StudyLog.clock(3725.2) == "1:02:05.2")
    }
}
