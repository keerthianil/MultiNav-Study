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
        let overview = try #require(StudyContent.map(id: "route_overview"))
        #expect(overview.announcement == "Your route to Gorham's Corner is approximately 0.5 miles away, primarily "
                + "travelling Southwest. There are 5 intersections along the route, with 7 turns and 6 total street "
                + "crossings.")
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
            "Intersection 3: 4-way intersection of Commercial Street and Union Street.",
            "Intersection 4: 4-way intersection of Union Street and Fore Street.",
            "Intersection 5: 5-way intersection of Fore Street, Center Street, and York Street.",
        ])
        let training = try MapLoader.overview(named: "training_overview")
        #expect(training.nodes.count == 3)
        #expect(training.endpoints[1].announcement == "End of route: Your destination, Nick's Bakery.")
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
                // The walk starts at the bottom half of the screen: the way in is up.
                #expect(m.route[0].y > m.route[m.route.count - 1].y - 1 || map.id == "intersection_2",
                        "\(map.id) does not start below where it ends")
            }
        }
    }

    /// No two dots on a map touch, so each can be found and felt on its own.
    @Test func dotsNeverOverlap() throws {
        for map in maps where map.kind == .intersection {
            let m = try MapLoader.intersection(named: map.file)
            var dots: [(CGPoint, CGFloat)] = m.endpoints.map { ($0.position, 3) }
            dots += m.turns.map { ($0, 3) }
            dots += m.crosswalkEnds.map { ($0, 2.5) }
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
                #expect(Set(unmarked.map(\.name)) == ["Crosswalk across Fore Street"], "\(map.id)")
            case let s where s.contains("Moulton"):
                #expect(m.medians.isEmpty, "\(map.id)")
                #expect(Set(unmarked.map(\.name)) == ["Crosswalk across Moulton Street"], "\(map.id)")
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
            } else {
                let m = try MapLoader.intersection(named: map.file)
                texts += m.roads.map(\.name) + m.sidewalks.map(\.name) + m.crosswalks.map(\.name)
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
