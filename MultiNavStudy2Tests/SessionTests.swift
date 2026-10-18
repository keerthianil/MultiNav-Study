// SessionTests.swift
// Checks the setup settings, the spoken directions and the log file names.

import Foundation
import Testing
@testable import MultiNavStudy2

@MainActor
struct SessionTests {
    private func composer(_ route: Int, _ change: (inout StageSettings) -> Void = { _ in },
                          units: DistanceUnits = .feet, sides: SideWords = .compass) throws -> DirectionsComposer {
        let directions = try RouteDirections.load(named: "route\(route)_directions")
        var options = StageSettings.defaults(for: .onRoute)
        change(&options)
        return DirectionsComposer(directions: directions, options: options, units: units, sideWords: sides)
    }

    /// The wording participants hear, with every detail on, matches docs/ROUTES.md.
    @Test func firstSectionOfRouteOne() throws {
        let words = try composer(1)
        let section = try #require(words.directions.sections.first)
        #expect(words.sectionIntro(section, withDirections: true) ==
            "Section 1 of 7. Start at U S M, Bedford Street. Walk along Bedford Street, on the northwest side, "
            + "about 550 feet, to Deering Avenue. At Deering Avenue. 3-way intersection. "
            + "No traffic signals or stop signs. Cross Deering Avenue. Marked crosswalk. "
            + "Then turn right onto Deering Avenue, on the southwest side.")
    }

    @Test func switchedOffPartsAreLeftOut() throws {
        let words = try composer(1, {
            $0.distances = false
            $0.intersectionDetails = false
            $0.crosswalkDetails = false
        }, sides: .relative)
        let section = try #require(words.directions.sections.first)
        #expect(words.directionsText(section) ==
            "Start at U S M, Bedford Street. Walk along Bedford Street, on the right-hand side, to Deering Avenue. "
            + "At Deering Avenue. Cross Deering Avenue. Then turn right onto Deering Avenue, on the left-hand side.")
        let roundabout = words.directions.sections[1]
        #expect(words.maneuver(roundabout).contains("Two stages, with a splitter island."))
        #expect(words.maneuver(roundabout).contains("Walk around the east side of the roundabout."))
    }

    @Test func distancesRoundSensibly() throws {
        let feet = try composer(1)
        #expect(feet.distance(168) == "about 550 feet")
        #expect(feet.distance(20) == "about 70 feet")
        let metres = try composer(1, units: .metres)
        #expect(metres.distance(168) == "about 170 metres")
        #expect(metres.distance(2) == "about 5 metres")
    }

    /// No dash or arrow in any direction, whatever the researcher switches off.
    @Test(arguments: [1, 2, 3, 4])
    func directionsHaveNoDashes(route: Int) throws {
        for mask in 0..<32 {
            for units in DistanceUnits.allCases {
                for sides in SideWords.allCases {
                    let words = try composer(route, {
                        $0.turnByTurn = mask & 1 != 0
                        $0.distances = mask & 2 != 0
                        $0.streetSide = mask & 4 != 0
                        $0.intersectionDetails = mask & 8 != 0
                        $0.crosswalkDetails = mask & 16 != 0
                    }, units: units, sides: sides)
                    var texts = [words.overview(), words.summary()]
                    for section in words.directions.sections {
                        texts += [words.sectionIntro(section, withDirections: true), words.brief(section),
                                  words.routeLeg(section, first: section.index == 1)]
                        if !section.endsAtDestination { texts.append(words.routeContinuation(section)) }
                    }
                    for text in texts {
                        #expect(!text.contains("\u{2014}") && !text.contains("\u{2013}") && !text.contains("\u{2192}"),
                                "dash or arrow in: \(text)")
                        #expect(!text.contains("  ") && !text.contains(" ,") && !text.contains(".."), "spacing in: \(text)")
                    }
                }
            }
        }
    }

    @Test func settingsSurviveMissingKeys() throws {
        let saved = #"{"routeID":"route3","stage":"onRoute","onRoute":{"mapMode":"fullRoute","speech":false}}"#
        let settings = try JSONDecoder().decode(StudySettings.self, from: Data(saved.utf8))
        #expect(settings.routeID == "route3")
        #expect(settings.stage == .onRoute)
        #expect(settings.onRoute.mapMode == .fullRoute)
        #expect(settings.onRoute.speech == false)
        #expect(settings.onRoute.turnByTurn == true)
        #expect(settings.preJourney == StageSettings.defaults(for: .preJourney))
        #expect(settings.units == .feet)
    }

    @Test func stagesKeepTheirOwnOptions() {
        var settings = StudySettings()
        settings[.onRoute].landmarks = false
        #expect(settings.preJourney.landmarks)
        #expect(!settings.onRoute.landmarks)
        #expect(settings.preJourney.mapMode == .fullRoute)
        #expect(settings.onRoute.mapMode == .sections)
    }

    @Test func logFileNames() {
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 10
        parts.day = 16
        parts.hour = 15
        parts.minute = 30
        parts.second = 12
        let date = Calendar.current.date(from: parts)!
        #expect(StudyLog.fileStem(route: 2, stage: .preJourney, practice: false, date: date) == "Route2_PreJourney_20261016_153012")
        #expect(StudyLog.fileStem(route: 4, stage: .onRoute, practice: true, date: date) == "Route4_OnRoute_Practice_20261016_153012")
        #expect(LogFile.title(forStem: "Route2_PreJourney_20261016_153012_touches") == "Route 2, pre-journey learning, touches")
        #expect(LogFile.title(forStem: "Route4_OnRoute_Practice_20261016_153012_events") == "Route 4, on route, practice, events")
        #expect(LogFile.title(forStem: "Route1_20261002_153012_touches") == "Route 1, touches")
    }
}
