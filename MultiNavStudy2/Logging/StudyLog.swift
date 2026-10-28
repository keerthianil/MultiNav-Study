// StudyLog.swift
// Study logs, written to the app's Documents folder (visible in the Files
// app under On My iPhone > MultiNav Study 2, and from Finder over USB).
//
// Each participant session writes three CSV files, named by participant ID
// and start time:
//   P07_20261028_142512_visits.csv   one row per map visit: when the map
//       opened, the first touch, when exploring ended and how, how long it
//       took, how often the announcement and each information item played,
//       which items were switched on, and how many settings changed
//   P07_20261028_142512_events.csv   everything in order: maps opened and
//       closed, every announcement and item started, finished, stopped or
//       replayed, gestures, every change to the information items, what
//       the map said, VoiceOver changes, errors
//   P07_20261028_142512_touches.csv  every touch down, move (10 per second)
//       and up, with what was under the finger and what was being spoken
// Every row carries the participant, the phase (Training, Practice, Trial 1,
// Customization, Trial 2), the map ("Intersection 2", "Reversed intersection
// 5") and the visit number, so practice attempts and repeated visits can be
// told apart. Across sessions, MultiNav_app_log.csv keeps app starts,
// background and foreground changes, sessions and every error.
//
// The touch file is written by a TouchLogger, the logging protocol from the
// MultiNav package.

import Foundation
import os
import TactileMapLogging
import UIKit

typealias StudyTouchType = TouchEventType

// MARK: - CSV writer

final class CSVWriter {
    let url: URL
    private var handle: FileHandle?

    init(url: URL, header: [String]) throws {
        self.url = url
        if !FileManager.default.fileExists(atPath: url.path) {
            let line = header.map(CSVWriter.escape).joined(separator: ",") + "\n"
            try Data(line.utf8).write(to: url, options: .atomic)
        }
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        self.handle = handle
    }

    func write(_ fields: [String]) {
        guard let handle else { return }
        let line = fields.map(CSVWriter.escape).joined(separator: ",") + "\n"
        try? handle.write(contentsOf: Data(line.utf8))
    }

    func flush() {
        try? handle?.synchronize()
    }

    func close() {
        try? handle?.synchronize()
        try? handle?.close()
        handle = nil
    }

    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

// MARK: - Touch logger

@MainActor
final class StudyTouchLogger: TouchLogger {
    static let header = ["Time Stamp", "Session Time", "Map Time", "Participant", "Phase", "Map", "Visit",
                         "Touch Event", "Object", "Touch X", "Touch Y", "Touch X (mm)", "Touch Y (mm)",
                         "Speaking", "VoiceOver"]

    private var writer: CSVWriter?
    private(set) var fileURL: URL?

    var isSessionActive: Bool { writer != nil }

    /// `metadata["file"]` is the full path of the CSV to create or append to.
    func startSession(metadata: [String: String]) {
        endSession()
        guard let path = metadata["file"] else { return }
        let url = URL(fileURLWithPath: path)
        do {
            writer = try CSVWriter(url: url, header: Self.header)
            fileURL = url
        } catch {
            StudyLog.shared.error("Could not create touch log \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    func endSession() {
        writer?.close()
        writer = nil
    }

    @discardableResult
    func logEvent(_ event: TouchEvent) -> Bool {
        guard let writer else { return false }
        let c = event.custom
        writer.write([
            StudyLog.timestamp(event.timestamp),
            StudyLog.clock(event.sessionElapsed),
            c["map_time"] ?? "",
            c["participant"] ?? "",
            c["phase"] ?? "",
            c["map"] ?? "",
            c["visit"] ?? "",
            event.eventType.rawValue,
            event.elementName,
            String(format: "%.1f", event.touchPoint.x),
            String(format: "%.1f", event.touchPoint.y),
            c["x_mm"] ?? "",
            c["y_mm"] ?? "",
            c["speaking"] ?? "",
            c["voiceover"] ?? "",
        ])
        return true
    }

    func flush() {
        writer?.flush()
    }
}

// MARK: - One map visit, summed up

/// Everything the visits file records about one visit to one map.
struct VisitSummary {
    var phase: StudyPhase
    var mapID: String
    var mapName: String
    var visit: Int
    var opened: Date
    var firstTouch: Date?
    var ended: Date
    var endedBy: String
    var announcementPlays = 0
    var announcementRepeats = 0
    var detailActivations = 0
    var itemPlays: [InfoCategory: Int] = [:]
    /// Information items in use when the map opened, or nil on an overview.
    var settingsAtOpen: InfoSettings?
    var settingsAtEnd: InfoSettings?
    var settingsChanges = 0
    var touches = 0
    var voiceOver: Bool

    var itemsPlayed: Int { itemPlays.values.reduce(0, +) }
    /// Plays of an item beyond its first in this visit.
    var itemReplays: Int { itemPlays.values.reduce(0) { $0 + max($1 - 1, 0) } }
}

// MARK: - Study log

@MainActor
final class StudyLog {
    static let shared = StudyLog()

    enum Category: String {
        case session = "Session"
        case map = "Map"
        case description = "Description"
        case setting = "Setting"
        case gesture = "Gesture"
        case speech = "Speech"
        case voiceOver = "VoiceOver"
        case app = "App"
        case error = "Error"
    }

    static let eventHeader = ["Time Stamp", "Session Time", "Map Time", "Participant", "Phase", "Map", "Visit",
                              "Category", "Event", "Detail", "VoiceOver"]

    static var visitHeader: [String] {
        var header = ["Participant", "Phase", "Map", "Map Name", "Visit", "Opened", "First Touch", "Ended",
                      "Ended By", "Seconds From Opening", "Seconds From First Touch", "Announcement Plays",
                      "Announcement Repeats", "Detail Activations", "Items Played", "Item Replays"]
        header += InfoCategory.allCases.map { "\($0.title) Plays" }
        header += InfoCategory.allCases.map { "\($0.title) Setting" }
        header += ["Settings Changes", "Settings At End", "Touches", "VoiceOver"]
        return header
    }

    private struct MapContext {
        let phase: String
        let map: String
        let visit: Int
        let opened: Date
    }

    private let touchLogger = StudyTouchLogger()
    private var eventWriter: CSVWriter?
    private var visitWriter: CSVWriter?
    private var appLog: CSVWriter?
    private var sessionStart: Date?
    private(set) var participant = ""
    private(set) var fileStem = ""
    private var context: MapContext?
    /// Phase written while no map is open, for changes made between maps.
    var phaseBetweenMaps: () -> String = { "" }
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MultiNavStudy2", category: "study")

    nonisolated static let appLogName = "MultiNav_app_log.csv"

    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private init() {
        let url = Self.documents.appendingPathComponent(Self.appLogName)
        appLog = try? CSVWriter(url: url, header: ["Time Stamp", "Category", "Message", "Detail"])
    }

    var isSessionActive: Bool { sessionStart != nil }
    var isMapOpen: Bool { context != nil }

    // MARK: Sessions

    /// Log file name without its ending, e.g. P07_20261028_142512, or
    /// Session_20261028_142512 without a participant ID.
    static func fileStem(participant: String, date: Date) -> String {
        (participant.isEmpty ? "Session" : participant) + "_" + fileStamp(date)
    }

    func startSession(participant id: String, stem: String, started: Date, resumed: Bool) {
        if isSessionActive, stem == fileStem { return }
        endSession(reason: "New session started")
        sessionStart = started
        participant = id
        fileStem = stem
        context = nil

        let touchURL = Self.documents.appendingPathComponent(stem + "_touches.csv")
        let eventURL = Self.documents.appendingPathComponent(stem + "_events.csv")
        let visitURL = Self.documents.appendingPathComponent(stem + "_visits.csv")
        touchLogger.startSession(metadata: ["file": touchURL.path])
        do {
            eventWriter = try CSVWriter(url: eventURL, header: Self.eventHeader)
            visitWriter = try CSVWriter(url: visitURL, header: Self.visitHeader)
        } catch {
            self.error("Could not create the logs for \(stem): \(error.localizedDescription)")
        }
        if resumed {
            event(.session, "Session resumed", detail: "The app was reopened during the session")
        } else {
            event(.session, "Session started", detail: id.isEmpty ? "No participant ID" : "Participant \(id)")
        }
        event(.session, "Device", detail: "\(UIDevice.current.model), \(AppInfo.versionDescription)")
        event(.voiceOver, UIAccessibility.isVoiceOverRunning ? "VoiceOver on" : "VoiceOver off")
        appEvent(resumed ? "Session resumed" : "Session started", detail: stem)
    }

    func endSession(reason: String) {
        guard isSessionActive else { return }
        event(.session, "Session ended", detail: reason)
        appEvent("Session ended", detail: reason)
        touchLogger.endSession()
        eventWriter?.close()
        eventWriter = nil
        visitWriter?.close()
        visitWriter = nil
        sessionStart = nil
        context = nil
        participant = ""
        fileStem = ""
    }

    // MARK: Maps

    /// Records a map opening. Every event and touch until `endMap` belongs to it.
    func beginMap(_ map: StudyMap, visit: Int, opened: Date, settings: InfoSettings?) {
        context = MapContext(phase: map.phase.title, map: map.logID, visit: visit, opened: opened)
        event(.map, "Map opened", detail: "\(map.title), \(map.subtitle)")
        if let settings {
            event(.setting, "Information items", detail: settings.summary)
        }
    }

    /// Writes the visit's row to the visits file and closes the map's context.
    func endMap(_ summary: VisitSummary) {
        event(.map, "Map closed", detail: summary.endedBy)
        context = nil
        guard let visitWriter else { return }
        func seconds(_ from: Date?) -> String {
            guard let from else { return "" }
            return String(format: "%.1f", summary.ended.timeIntervalSince(from))
        }
        var row = [participant, summary.phase.title, summary.mapID, summary.mapName, String(summary.visit),
                   Self.timestamp(summary.opened), summary.firstTouch.map(Self.timestamp) ?? "",
                   Self.timestamp(summary.ended), summary.endedBy, seconds(summary.opened),
                   seconds(summary.firstTouch), String(summary.announcementPlays),
                   String(summary.announcementRepeats), String(summary.detailActivations),
                   String(summary.itemsPlayed), String(summary.itemReplays)]
        row += InfoCategory.allCases.map { String(summary.itemPlays[$0] ?? 0) }
        row += summary.settingsAtOpen?.columns ?? InfoCategory.allCases.map { _ in "" }
        row += [String(summary.settingsChanges), summary.settingsAtEnd?.summary ?? "", String(summary.touches),
                summary.voiceOver ? "On" : "Off"]
        visitWriter.write(row)
        visitWriter.flush()
    }

    /// A change to the information items, from the first screen or from the
    /// map's Information sheet.
    func infoChanged(category: InfoCategory, on: Bool, settings: InfoSettings) {
        event(.setting, "\(category.title) \(on ? "on" : "off")", detail: "Now: \(settings.summary)")
        NotificationCenter.default.post(name: .studyInfoChanged, object: nil)
    }

    // MARK: Writing

    func touch(_ type: StudyTouchType, element: String, screen: CGPoint, mm: CGPoint, speaking: String) {
        guard let start = sessionStart else { return }
        let now = Date()
        var custom = contextFields(now)
        custom["x_mm"] = String(format: "%.2f", mm.x)
        custom["y_mm"] = String(format: "%.2f", mm.y)
        custom["speaking"] = speaking
        custom["voiceover"] = UIAccessibility.isVoiceOverRunning ? "On" : "Off"
        touchLogger.logEvent(TouchEvent(
            timestamp: now,
            sessionElapsed: now.timeIntervalSince(start),
            eventType: type,
            elementName: element,
            elementType: nil,
            touchPoint: screen,
            custom: custom))
    }

    func event(_ category: Category, _ name: String, detail: String = "") {
        guard let start = sessionStart, let eventWriter else { return }
        let now = Date()
        let c = contextFields(now)
        eventWriter.write([Self.timestamp(now), Self.clock(now.timeIntervalSince(start)), c["map_time"] ?? "",
                           participant, c["phase"] ?? "", c["map"] ?? "", c["visit"] ?? "",
                           category.rawValue, name, detail,
                           UIAccessibility.isVoiceOverRunning ? "On" : "Off"])
    }

    private func contextFields(_ now: Date) -> [String: String] {
        guard let context else {
            return ["participant": participant, "phase": phaseBetweenMaps(), "map": "", "visit": "", "map_time": ""]
        }
        return ["participant": participant, "phase": context.phase, "map": context.map,
                "visit": String(context.visit), "map_time": Self.clock(now.timeIntervalSince(context.opened))]
    }

    /// App-wide events, kept across sessions.
    func appEvent(_ name: String, detail: String = "") {
        appLog?.write([Self.timestamp(Date()), Category.app.rawValue, name, detail])
        logger.info("\(name, privacy: .public) \(detail, privacy: .public)")
    }

    func error(_ message: String) {
        appLog?.write([Self.timestamp(Date()), Category.error.rawValue, message, context?.map ?? ""])
        appLog?.flush()
        event(.error, message)
        logger.error("\(message, privacy: .public)")
    }

    func flush() {
        touchLogger.flush()
        eventWriter?.flush()
        visitWriter?.flush()
        appLog?.flush()
    }

    // MARK: Formatting

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let fileFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    static func timestamp(_ date: Date) -> String {
        timestampFormatter.string(from: date)
    }

    static func fileStamp(_ date: Date) -> String {
        fileFormatter.string(from: date)
    }

    /// Minutes, seconds and tenths, e.g. 02:07.4 (hours are added past an hour).
    static func clock(_ seconds: TimeInterval) -> String {
        let tenths = Int(max(seconds, 0) * 10)
        let minutes = tenths / 600
        if minutes >= 60 {
            return String(format: "%d:%02d:%02d.%d", minutes / 60, minutes % 60, (tenths / 10) % 60, tenths % 10)
        }
        return String(format: "%02d:%02d.%d", minutes, (tenths / 10) % 60, tenths % 10)
    }
}

extension Notification.Name {
    /// Posted after the researcher switches an information item on or off.
    static let studyInfoChanged = Notification.Name("studyInfoChanged")
}
