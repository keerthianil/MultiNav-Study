// StudySession.swift
// One participant's session, from the first map opened to End Session:
// which maps have been opened and how often, and which one comes next.
// A session writes one set of log files. It is kept in UserDefaults, so if
// the app is closed or stops during a session, it carries on, appending to
// the same files, the next time the app opens.

import Foundation

@MainActor
final class StudySession: ObservableObject {
    static let shared = StudySession()
    static let storageKey = "studySession"

    struct State: Codable, Equatable {
        var participantID: String
        var started: Date
        /// Log file names without their endings, e.g. P07_20261028_142512.
        var fileStem: String
        /// Times each map has been opened, by map id.
        var visits: [String: Int] = [:]
        /// Maps explored to the end (Done or the participant's gesture) at least once.
        var finished: [String] = []
    }

    @Published private(set) var state: State?

    private let defaults: UserDefaults
    private let log: StudyLog

    init(defaults: UserDefaults = .standard, log: StudyLog? = nil) {
        self.defaults = defaults
        self.log = log ?? .shared
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(State.self, from: data) {
            state = saved
        }
    }

    var isActive: Bool { state != nil }

    /// Reopens the log files of a session that was running when the app last
    /// closed. Called once at launch.
    func resumeAfterLaunch() {
        guard let state, !log.isSessionActive else { return }
        log.startSession(participant: state.participantID, stem: state.fileStem, started: state.started, resumed: true)
    }

    /// Starts a session for the participant, unless one is already running.
    @discardableResult
    func startIfNeeded(participantID: String) -> State {
        if let state {
            if !log.isSessionActive {
                log.startSession(participant: state.participantID, stem: state.fileStem, started: state.started,
                                 resumed: true)
            }
            return state
        }
        let now = Date()
        let id = StudySettings.cleanID(participantID)
        let new = State(participantID: id, started: now, fileStem: StudyLog.fileStem(participant: id, date: now))
        state = new
        save()
        log.startSession(participant: id, stem: new.fileStem, started: now, resumed: false)
        return new
    }

    func end(reason: String) {
        guard state != nil else { return }
        log.endSession(reason: reason)
        state = nil
        save()
    }

    /// Counts a new visit to a map and returns its number (1 for the first).
    func beginVisit(_ map: StudyMap) -> Int {
        guard var current = state else { return 1 }
        let number = (current.visits[map.id] ?? 0) + 1
        current.visits[map.id] = number
        state = current
        save()
        return number
    }

    func markFinished(_ map: StudyMap) {
        guard var current = state, !current.finished.contains(map.id) else { return }
        current.finished.append(map.id)
        state = current
        save()
    }

    func visits(_ map: StudyMap) -> Int {
        state?.visits[map.id] ?? 0
    }

    func isFinished(_ map: StudyMap) -> Bool {
        state?.finished.contains(map.id) ?? false
    }

    /// The first map in study order not yet explored to the end.
    var nextMap: StudyMap? {
        StudyContent.maps.first { !isFinished($0) }
    }

    /// The phase the study is in while no map is open, for logging changes to
    /// the information items: "Customization" once Trial 1 is done and until
    /// Trial 2 begins, "Trial 2, between intersections" after that, and
    /// otherwise the phase of the next map, e.g. "Training, between maps".
    var phaseBetweenMaps: String {
        if StudyContent.maps(in: .trial2).contains(where: { visits($0) > 0 }) {
            return StudyPhase.trial2.title + ", between intersections"
        }
        guard let next = nextMap else { return "After the last map" }
        if next.phase == .trial2 { return "Customization" }
        return next.phase.title + ", between maps"
    }

    private func save() {
        if let state, let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: Self.storageKey)
        } else {
            defaults.removeObject(forKey: Self.storageKey)
        }
    }
}
