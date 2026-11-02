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
        let gorham = try #require(StudyContent.map(id: "return_5"))
        #expect(gorham.announcement == "You are at the 5-way intersection of Center Street, Fore Street, and "
                + "York Street. Your route first crosses Center Street, then turns left to cross Fore Street, and "
                + "continues along Fore Street.")
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
        let training = try #require(StudyContent.map(id: "training_intersection"))
        #expect(training.items[2].text == "The intersection is controlled by stop signs in all directions.")
    }

    @Test func overviewCuesAreTheTeamsWords() throws {
        let overview = try MapLoader.overview(named: "route_overview")
        #expect(overview.endpoints[0].announcement == "Start of route: You are here, at Dock Fore, 336 Fore Street.")
        #expect(overview.endpoints[1].announcement == "End of route: Your destination, Gorham's Corner.")
        #expect(overview.nodes.map(\.cue) == [
            "Intersection 1: 4-way intersection of Fore Street and Silver Street.",
            "Intersection 2: 4-way intersection of Fore Street, Moulton Street, and Exchange Street.",
            "4-way intersection of Commercial Street, Moulton Street, and Long Wharf.",
            "Intersection 3: 4-way intersection of Commercial Street and Union Street.",
            "Intersection 4: 4-way intersection of Union Street and Fore Street.",
            "Intersection 5: 5-way intersection of Fore Street, Center Street, York Street, and Pleasant Street.",
        ])
        #expect(overview.nodes.map(\.number) == [1, 2, 0, 3, 4, 5], "the added square has no number")
        let training = try MapLoader.overview(named: "training_overview")
        #expect(training.nodes.count == 3)
        #expect(training.endpoints[1].announcement == "End of route: Your destination, Nick's Bakery.")
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
                #expect(m.endpoints.map(\.announcement) == ["You are here", "End of intersection route"])
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

    /// Each turn dot says which way the walk turns (team, 10/30). The first
    /// turns on 1, 2, 5 and the reversed 3 and 4 went when the walks started
    /// at the corner.
    @Test func turnDotsSayWhichWay() throws {
        let expected: [String: [String]] = [
            "intersection_1": ["Turn left"], "intersection_3": ["Turn right"], "intersection_4": ["Turn left"],
            "intersection_5": ["Turn right"], "return_5": ["Turn left", "Turn right"],
            "return_2": ["Turn right"], "return_1": ["Turn right", "Turn left"],
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
        #expect(Mode.crosswalkEnd(onRoute: false).haptic == nil)
        #expect(Mode.median.haptic == .median)
        #expect(Mode.endpoint.haptic == .endpoint)
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
        var texts: [String] = ["Stopped.", "No details are turned on.", "End of details.",
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
