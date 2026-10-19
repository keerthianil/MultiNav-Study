// StudySettings.swift
// Everything the researcher sets on the setup screen, kept between launches.
// The two stages, pre-journey learning and on route, each keep their own
// copy of the per-stage options, so the information a participant gets can
// differ between learning a route and walking it. A session takes a frozen
// copy of the settings (SessionConfig) when it starts.

import Foundation
import SwiftUI

enum StudyStage: String, Codable, CaseIterable, Identifiable, Hashable {
    case preJourney
    case onRoute

    var id: String { rawValue }

    var title: String {
        switch self {
        case .preJourney: return "Pre-journey learning"
        case .onRoute: return "On route"
        }
    }

    /// Part of the log file names.
    var fileToken: String {
        switch self {
        case .preJourney: return "PreJourney"
        case .onRoute: return "OnRoute"
        }
    }
}

enum MapMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case fullRoute
    case sections

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullRoute: return "Full route"
        case .sections: return "Section by section"
        }
    }
}

enum DistanceUnits: String, Codable, CaseIterable, Identifiable, Hashable {
    case feet
    case metres

    var id: String { rawValue }

    var title: String {
        switch self {
        case .feet: return "Feet"
        case .metres: return "Metres"
        }
    }
}

enum SideWords: String, Codable, CaseIterable, Identifiable, Hashable {
    case compass
    case relative

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compass: return "Compass"
        case .relative: return "Left or right"
        }
    }
}

enum VoiceSpeed: String, Codable, CaseIterable, Identifiable, Hashable {
    case slower
    case normal
    case faster

    var id: String { rawValue }

    var title: String {
        switch self {
        case .slower: return "Slower"
        case .normal: return "Normal"
        case .faster: return "Faster"
        }
    }

    /// Multiplier on the system's default speech rate.
    var rateMultiplier: Float {
        switch self {
        case .slower: return 0.9
        case .normal: return 1.1
        case .faster: return 1.3
        }
    }
}

/// Options that can differ between the two stages.
struct StageSettings: Codable, Hashable {
    var mapMode: MapMode = .fullRoute
    var turnByTurn = true
    var directionsWhenSectionOpens = true
    var spokenOverview = false
    var distances = true
    var streetSide = true
    var intersectionDetails = true
    var crosswalkDetails = true
    var intersectionCloseUps = true
    var landmarks = true
    var showMap = true
    var vibration = true
    var sounds = true
    var speech = true
    /// Pre-journey learning only; 0 means no limit.
    var timeLimitMinutes = 0

    static let timeLimitChoices = [0, 2, 5, 10, 15, 20, 30]

    static func defaults(for stage: StudyStage) -> StageSettings {
        var settings = StageSettings()
        settings.mapMode = stage == .preJourney ? .fullRoute : .sections
        return settings
    }

    init() {}

    /// Missing or unreadable values fall back to the defaults, so settings
    /// saved by an earlier build still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = StageSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        mapMode = value(.mapMode, d.mapMode)
        turnByTurn = value(.turnByTurn, d.turnByTurn)
        directionsWhenSectionOpens = value(.directionsWhenSectionOpens, d.directionsWhenSectionOpens)
        spokenOverview = value(.spokenOverview, d.spokenOverview)
        distances = value(.distances, d.distances)
        streetSide = value(.streetSide, d.streetSide)
        intersectionDetails = value(.intersectionDetails, d.intersectionDetails)
        crosswalkDetails = value(.crosswalkDetails, d.crosswalkDetails)
        intersectionCloseUps = value(.intersectionCloseUps, d.intersectionCloseUps)
        landmarks = value(.landmarks, d.landmarks)
        showMap = value(.showMap, d.showMap)
        vibration = value(.vibration, d.vibration)
        sounds = value(.sounds, d.sounds)
        speech = value(.speech, d.speech)
        timeLimitMinutes = value(.timeLimitMinutes, d.timeLimitMinutes)
    }
}

/// The whole setup screen.
struct StudySettings: Codable, Hashable {
    var routeID = "route1"
    var stage: StudyStage = .preJourney
    var practiceRun = false
    var preJourney = StageSettings.defaults(for: .preJourney)
    var onRoute = StageSettings.defaults(for: .onRoute)
    /// On by default, so the back gestures leave the map as they always have.
    var participantCanLeave = true
    var units: DistanceUnits = .feet
    var sideWords: SideWords = .compass
    var voiceSpeed: VoiceSpeed = .normal

    subscript(stage: StudyStage) -> StageSettings {
        get { stage == .preJourney ? preJourney : onRoute }
        set {
            if stage == .preJourney { preJourney = newValue } else { onRoute = newValue }
        }
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = StudySettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        routeID = value(.routeID, d.routeID)
        stage = value(.stage, d.stage)
        practiceRun = value(.practiceRun, d.practiceRun)
        preJourney = value(.preJourney, d.preJourney)
        onRoute = value(.onRoute, d.onRoute)
        participantCanLeave = value(.participantCanLeave, d.participantCanLeave)
        units = value(.units, d.units)
        sideWords = value(.sideWords, d.sideWords)
        voiceSpeed = value(.voiceSpeed, d.voiceSpeed)
    }
}

/// Keeps the setup screen's settings in UserDefaults.
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    static let storageKey = "studySettings"

    @Published var settings: StudySettings {
        didSet { save() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(StudySettings.self, from: data) {
            settings = saved
        } else {
            settings = StudySettings()
        }
    }

    func resetToDefaults() {
        settings = StudySettings()
        StudyLog.shared.appEvent("Settings reset to defaults")
    }

    /// A frozen copy of the settings for a new session, or nil if the chosen
    /// route is missing from the app.
    func makeSessionConfig() -> SessionConfig? {
        guard let route = RouteCatalog.route(id: settings.routeID) ?? RouteCatalog.routes.first else { return nil }
        return SessionConfig(route: route, settings: settings)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

/// Everything one session needs, fixed when it starts.
struct SessionConfig: Hashable {
    let id = UUID()
    let route: RouteInfo
    let stage: StudyStage
    let practiceRun: Bool
    let options: StageSettings
    let units: DistanceUnits
    let sideWords: SideWords
    let voiceSpeed: VoiceSpeed
    let participantCanLeave: Bool

    init(route: RouteInfo, settings: StudySettings) {
        self.route = route
        stage = settings.stage
        practiceRun = settings.practiceRun
        options = settings[settings.stage]
        units = settings.units
        sideWords = settings.sideWords
        voiceSpeed = settings.voiceSpeed
        participantCanLeave = settings.participantCanLeave
    }

    var mapMode: MapMode { options.mapMode }

    /// The learning time limit in seconds, or 0 for none.
    var timeLimitSeconds: Int {
        stage == .preJourney ? options.timeLimitMinutes * 60 : 0
    }

    /// Stage and map mode, for log conditions and summaries.
    var stageDescription: String {
        stage.title + (practiceRun ? " (practice)" : "")
    }

    /// Every setting as a name and a value, written to the session log.
    var logEntries: [(String, String)] {
        func onOff(_ value: Bool) -> String { value ? "On" : "Off" }
        let o = options
        return [
            ("Stage", stage.title),
            ("Practice run", onOff(practiceRun)),
            ("Map mode", o.mapMode.title),
            ("Turn-by-turn directions", onOff(o.turnByTurn)),
            ("Directions when a section opens", onOff(o.directionsWhenSectionOpens)),
            ("Spoken route overview", onOff(o.spokenOverview)),
            ("Distances", onOff(o.distances)),
            ("Side of the street", onOff(o.streetSide)),
            ("Intersection type and control", onOff(o.intersectionDetails)),
            ("Crosswalk details", onOff(o.crosswalkDetails)),
            ("Intersection close-ups", onOff(o.intersectionCloseUps)),
            ("Buildings at the ends", onOff(o.landmarks)),
            ("Map shown on screen", onOff(o.showMap)),
            ("Vibration", onOff(o.vibration)),
            ("Sounds", onOff(o.sounds)),
            ("Speech", onOff(o.speech)),
            ("Time limit", timeLimitSeconds > 0 ? "\(o.timeLimitMinutes) minutes" : "None"),
            ("Participant can leave the map", onOff(participantCanLeave)),
            ("Distance units", units.title),
            ("Sides", sideWords.title),
            ("System voice speed", voiceSpeed.title),
        ]
    }
}
