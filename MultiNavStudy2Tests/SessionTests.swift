// SessionTests.swift
// The participant session, the settings and the log files it writes.

import Foundation
import Testing
@testable import MultiNavStudy2

@MainActor
@Suite(.serialized)
struct SessionTests {
    private func freshDefaults() -> UserDefaults {
        let name = "SessionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func sessionCountsVisitsAndFindsTheNextMap() throws {
        let session = StudySession(defaults: freshDefaults())
        let state = session.startIfNeeded(participantID: "P-test 07!")
        #expect(state.participantID == "P-test07")
        #expect(state.fileStem.hasPrefix("P-test07_"))
        let first = try #require(StudyContent.maps.first)
        #expect(session.nextMap?.id == first.id)
        #expect(session.beginVisit(first) == 1)
        #expect(session.beginVisit(first) == 2)
        #expect(session.nextMap?.id == first.id, "opened but not explored to the end")
        #expect(session.phaseBetweenMaps == "Training, between maps")
        session.markFinished(first)
        #expect(session.nextMap?.id == StudyContent.maps[1].id)
        for map in StudyContent.maps where map.phase != .trial2 { session.markFinished(map) }
        #expect(session.phaseBetweenMaps == "Customization")
        let trial2 = try #require(StudyContent.maps(in: .trial2).first)
        _ = session.beginVisit(trial2)
        #expect(session.phaseBetweenMaps == "Trial 2, between intersections")
        session.end(reason: "Test finished")
        #expect(!session.isActive)
        #expect(!StudyLog.shared.isSessionActive)
    }

    @Test func sessionSurvivesARelaunch() {
        let defaults = freshDefaults()
        let first = StudySession(defaults: defaults)
        first.startIfNeeded(participantID: "P08")
        _ = first.beginVisit(StudyContent.maps[0])
        StudyLog.shared.endSession(reason: "App closed")
        let again = StudySession(defaults: defaults)
        #expect(again.state?.participantID == "P08")
        #expect(again.visits(StudyContent.maps[0]) == 1)
        again.resumeAfterLaunch()
        #expect(StudyLog.shared.isSessionActive)
        again.end(reason: "Test finished")
    }

    @Test func settingsSurviveMissingKeys() throws {
        let saved = #"{"participantID":"P03","info":{"off":["control"]}}"#
        let settings = try JSONDecoder().decode(StudySettings.self, from: Data(saved.utf8))
        #expect(settings.participantID == "P03")
        #expect(!settings.info[.control])
        #expect(settings.info[.geometry])
        #expect(settings.participantCanFinish)
        #expect(settings.voiceSpeed == .normal)
        #expect(settings.showMap)
        let roundTrip = try JSONDecoder().decode(StudySettings.self, from: JSONEncoder().encode(settings))
        #expect(roundTrip == settings)
    }

    @Test func logFileNames() {
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 10
        parts.day = 28
        parts.hour = 14
        parts.minute = 25
        parts.second = 12
        let date = Calendar.current.date(from: parts)!
        #expect(StudyLog.fileStem(participant: "P07", date: date) == "P07_20261028_142512")
        #expect(StudyLog.fileStem(participant: "", date: date) == "Session_20261028_142512")
        #expect(LogFile.title(forStem: "P07_20261028_142512_visits") == "P07, visits")
        #expect(LogFile.title(forStem: "Session_20261028_142512_touches") == "No participant ID, touches")
        #expect(LogFile.title(forStem: "Route1_20261002_153012_touches") == "Route1, touches")
    }

    /// One visit writes one row to the visits file, with the counts the team asked for.
    @Test func visitRowIsWritten() throws {
        let session = StudySession(defaults: freshDefaults())
        let state = session.startIfNeeded(participantID: "PV1")
        let map = try #require(StudyContent.map(id: "return_3"))
        let opened = Date()
        var info = InfoSettings()
        info[.signals] = false
        StudyLog.shared.beginMap(map, visit: 1, opened: opened, settings: info)
        var summary = VisitSummary(phase: map.phase, mapID: map.logID, mapName: map.title, visit: 1, opened: opened,
                                   firstTouch: opened.addingTimeInterval(2), ended: opened.addingTimeInterval(32.5),
                                   endedBy: "Done button", settingsAtOpen: info, voiceOver: false)
        summary.announcementPlays = 2
        summary.announcementRepeats = 1
        summary.detailActivations = 1
        summary.itemPlays = [.geometry: 2, .direction: 1]
        summary.settingsAtEnd = info
        StudyLog.shared.endMap(summary)
        session.end(reason: "Test finished")

        let url = StudyLog.documents.appendingPathComponent(state.fileStem + "_visits.csv")
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
        #expect(lines.count == 2)
        let header = lines[0].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        let row = lines[1].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        #expect(header.count == row.count)
        func value(_ column: String) -> String? {
            header.firstIndex(of: column).map { row[$0] }
        }
        #expect(value("Participant") == "PV1")
        #expect(value("Phase") == "Trial 2")
        #expect(value("Map") == "Reversed intersection 3")
        #expect(value("Seconds From Opening") == "32.5")
        #expect(value("Seconds From First Touch") == "30.5")
        #expect(value("Announcement Plays") == "2")
        #expect(value("Items Played") == "3")
        #expect(value("Item Replays") == "1")
        #expect(value("Pedestrian signals Setting") == "Off")
        #expect(value("Intersection geometry Plays") == "2")
        for suffix in ["visits", "events", "touches"] {
            try? FileManager.default.removeItem(at: StudyLog.documents.appendingPathComponent(state.fileStem + "_\(suffix).csv"))
        }
    }
}
