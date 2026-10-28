// StudySettings.swift
// What the researcher sets on the first screen, kept between launches: the
// participant ID, the information items for Trial 2, and a few options.
// Every change to the information items is logged (see InfoSettingsSection).

import Foundation
import SwiftUI

/// Which information items Trial 2 plays. Training, practice and Trial 1
/// always play every item; the announcement always plays; map sounds and
/// vibration are never affected.
struct InfoSettings: Codable, Hashable {
    private var off: Set<InfoCategory> = []

    init() {}

    subscript(category: InfoCategory) -> Bool {
        get { !off.contains(category) }
        set {
            if newValue { off.remove(category) } else { off.insert(category) }
        }
    }

    var allOn: Bool { off.isEmpty }

    var enabled: [InfoCategory] { InfoCategory.allCases.filter { self[$0] } }

    /// "All on", or which items are off, in item order.
    var summary: String {
        if off.isEmpty { return "All on" }
        if off.count == InfoCategory.allCases.count { return "All off" }
        return "Off: " + InfoCategory.allCases.filter { !self[$0] }.map(\.title).joined(separator: ", ")
    }

    /// "On" or "Off" for each item, in item order, for the logs.
    var columns: [String] { InfoCategory.allCases.map { self[$0] ? "On" : "Off" } }
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

struct StudySettings: Codable, Hashable {
    var participantID = ""
    var info = InfoSettings()
    /// On by default: a three-finger swipe right or the VoiceOver escape
    /// gesture tells the app the participant is ready to cross and closes
    /// the map, as the researcher's Done does.
    var participantCanFinish = true
    var voiceSpeed: VoiceSpeed = .normal
    var showMap = true

    init() {}

    /// Missing or unreadable values fall back to the defaults, so settings
    /// saved by an earlier build still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = StudySettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        participantID = value(.participantID, d.participantID)
        info = value(.info, d.info)
        participantCanFinish = value(.participantCanFinish, d.participantCanFinish)
        voiceSpeed = value(.voiceSpeed, d.voiceSpeed)
        showMap = value(.showMap, d.showMap)
    }

    /// Letters, digits and hyphens only, so the ID is safe in a file name.
    static func cleanID(_ text: String) -> String {
        let kept = text.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" }
        return String(String(String.UnicodeScalarView(kept)).prefix(24))
    }
}

/// Keeps the first screen's settings in UserDefaults.
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    static let storageKey = "studySettings2"

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

    /// Switches one information item on or off and logs the change.
    func setInfo(_ category: InfoCategory, _ on: Bool) {
        guard settings.info[category] != on else { return }
        settings.info[category] = on
        StudyLog.shared.infoChanged(category: category, on: on, settings: settings.info)
    }

    /// Switches every information item on, logging each one that changes.
    func allInfoOn() {
        for category in InfoCategory.allCases where !settings.info[category] {
            setInfo(category, true)
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
