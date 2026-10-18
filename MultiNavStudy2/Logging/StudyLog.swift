// StudyLog.swift
// Study logs, written to the app's Documents folder (visible in the Files
// app under On My iPhone > MultiNav Study 2, and from Finder over USB).
//
// Each session (one route, one stage) writes two CSV files:
//   Route1_PreJourney_20261016_153012_touches.csv  every touch down, move
//       (10 per second) and up, with the element under the finger, in
//       points and mm, and the stage, view and section it happened in
//   Route1_PreJourney_20261016_153012_events.csv   every setting used,
//       screens and sections opened, taps, double taps, back gestures,
//       everything spoken, time warnings, VoiceOver changes, errors
// A practice run adds "_Practice" after the stage. Across all sessions,
// MultiNav_app_log.csv keeps app starts, background and foreground changes,
// sessions and every error.
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
    static let header = ["Time Stamp", "Trial Time", "Touch Event", "Object Type", "Touch X", "Touch Y",
                         "Touch X (mm)", "Touch Y (mm)", "Stage", "View", "Section", "Condition", "VoiceOver"]

    private var writer: CSVWriter?
    private(set) var fileURL: URL?

    var isSessionActive: Bool { writer != nil }

    /// `metadata["file"]` is the full path of the CSV to create.
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
        writer.write([
            StudyLog.timestamp(event.timestamp),
            StudyLog.trialTime(event.sessionElapsed),
            event.eventType.rawValue,
            event.elementName,
            String(format: "%.1f", event.touchPoint.x),
            String(format: "%.1f", event.touchPoint.y),
            event.custom["x_mm"] ?? "",
            event.custom["y_mm"] ?? "",
            event.custom["stage"] ?? "",
            event.custom["view"] ?? "",
            event.custom["section"] ?? "",
            event.custom["condition"] ?? "",
            event.custom["voiceover"] ?? "",
        ])
        return true
    }

    func flush() {
        writer?.flush()
    }
}

// MARK: - Study log

@MainActor
final class StudyLog {
    static let shared = StudyLog()

    enum Category: String {
        case session = "Session"
        case setting = "Setting"
        case screen = "Screen"
        case section = "Section"
        case gesture = "Gesture"
        case speech = "Speech"
        case timer = "Timer"
        case voiceOver = "VoiceOver"
        case app = "App"
        case error = "Error"
    }

    /// Which map the participant is on, for the View column.
    enum View: String {
        case fullRoute = "Full route"
        case section = "Section"
        case intersection = "Intersection"
    }

    static let eventHeader = ["Time Stamp", "Trial Time", "Category", "Event", "Detail",
                              "Stage", "View", "Section", "Condition"]

    private let touchLogger = StudyTouchLogger()
    private var eventWriter: CSVWriter?
    private var appLog: CSVWriter?
    private var sessionStart: Date?
    private(set) var activeSessionID: UUID?
    private var stage = ""
    private var view = ""
    private var section = ""
    private var condition = ""
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

    // MARK: Sessions

    /// Log file name without the ending, e.g. Route1_PreJourney_20261016_153012.
    static func fileStem(route: Int, stage: StudyStage, practice: Bool, date: Date) -> String {
        "Route\(route)_\(stage.fileToken)" + (practice ? "_Practice" : "") + "_\(fileStamp(date))"
    }

    func startSession(config: SessionConfig) {
        if activeSessionID == config.id, isSessionActive { return }
        endSession(reason: "New session started")

        let now = Date()
        sessionStart = now
        activeSessionID = config.id
        stage = config.stageDescription
        view = ""
        section = ""
        condition = "Route \(config.route.number), \(config.stageDescription)"

        let base = Self.fileStem(route: config.route.number, stage: config.stage, practice: config.practiceRun, date: now)
        let touchURL = Self.documents.appendingPathComponent(base + "_touches.csv")
        let eventURL = Self.documents.appendingPathComponent(base + "_events.csv")

        touchLogger.startSession(metadata: ["file": touchURL.path])
        do {
            eventWriter = try CSVWriter(url: eventURL, header: Self.eventHeader)
        } catch {
            self.error("Could not create event log \(eventURL.lastPathComponent): \(error.localizedDescription)")
        }

        event(.session, "Session started", detail: "Route \(config.route.number): \(config.route.title)")
        for (name, value) in config.logEntries {
            event(.setting, name, detail: value)
        }
        event(.session, "Device", detail: "\(UIDevice.current.model), \(AppInfo.versionDescription)")
        event(.voiceOver, UIAccessibility.isVoiceOverRunning ? "VoiceOver on" : "VoiceOver off")
        appEvent("Session started", detail: base)
    }

    func endSession(reason: String) {
        guard isSessionActive else { return }
        event(.session, "Session ended", detail: reason)
        appEvent("Session ended", detail: reason)
        touchLogger.endSession()
        eventWriter?.close()
        eventWriter = nil
        sessionStart = nil
        activeSessionID = nil
    }

    /// Records the map now on screen. `section` is the section number in
    /// section by section mode (kept while an intersection close-up is open).
    func setView(_ newView: View, section newSection: Int?, condition text: String) {
        view = newView.rawValue
        section = newSection.map(String.init) ?? ""
        condition = text
        event(.screen, "Opened", detail: text)
    }

    // MARK: Writing

    func touch(_ type: StudyTouchType, element: String, screen: CGPoint, mm: CGPoint) {
        guard let start = sessionStart else { return }
        let now = Date()
        touchLogger.logEvent(TouchEvent(
            timestamp: now,
            sessionElapsed: now.timeIntervalSince(start),
            eventType: type,
            elementName: element,
            elementType: nil,
            touchPoint: screen,
            custom: [
                "x_mm": String(format: "%.2f", mm.x),
                "y_mm": String(format: "%.2f", mm.y),
                "stage": stage,
                "view": view,
                "section": section,
                "condition": condition,
                "voiceover": UIAccessibility.isVoiceOverRunning ? "On" : "Off",
            ]))
    }

    func event(_ category: Category, _ name: String, detail: String = "") {
        guard let start = sessionStart, let eventWriter else { return }
        let now = Date()
        eventWriter.write([Self.timestamp(now), Self.trialTime(now.timeIntervalSince(start)),
                           category.rawValue, name, detail, stage, view, section, condition])
    }

    /// App-wide events, kept across sessions.
    func appEvent(_ name: String, detail: String = "") {
        appLog?.write([Self.timestamp(Date()), Category.app.rawValue, name, detail])
        logger.info("\(name, privacy: .public) \(detail, privacy: .public)")
    }

    func error(_ message: String) {
        appLog?.write([Self.timestamp(Date()), Category.error.rawValue, message, condition])
        appLog?.flush()
        event(.error, message)
        logger.error("\(message, privacy: .public)")
    }

    func flush() {
        touchLogger.flush()
        eventWriter?.flush()
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

    /// Minutes, seconds and tenths since the session began, e.g. 02:07.4.
    static func trialTime(_ seconds: TimeInterval) -> String {
        let tenths = Int(max(seconds, 0) * 10)
        return String(format: "%02d:%02d.%d", tenths / 600, (tenths / 10) % 60, tenths % 10)
    }
}
