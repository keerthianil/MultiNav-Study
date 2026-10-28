// StudyContent.swift
// The study as the research team designed it, read from Maps/study.json
// (written by tools/build_maps.py from tools/study_spec.py): every map in
// study order, the phase it belongs to, and the words spoken on it.

import Foundation

/// The information items a participant can step through on an intersection
/// map, in the order they are read. In Trial 2 the researcher can switch
/// each one off.
enum InfoCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case geometry
    case direction
    case control
    case signals
    case crosswalks
    case domes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .geometry: return "Intersection geometry"
        case .direction: return "Traffic direction"
        case .control: return "Traffic control"
        case .signals: return "Pedestrian signals"
        case .crosswalks: return "Crosswalks"
        case .domes: return "Truncated domes and curb cuts"
        }
    }

    /// Item number as the team's descriptions number them, 1 to 6.
    var number: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }
}

enum StudyPhase: String, Codable, CaseIterable, Identifiable, Hashable {
    case training
    case practice
    case trial1
    case trial2

    var id: String { rawValue }

    var title: String {
        switch self {
        case .training: return "Training"
        case .practice: return "Practice"
        case .trial1: return "Trial 1"
        case .trial2: return "Trial 2"
        }
    }

    /// Only Trial 2 uses the participant's chosen information items; every
    /// other phase plays them all.
    var usesCustomInfo: Bool { self == .trial2 }
}

struct InfoItem: Codable, Hashable {
    let category: InfoCategory
    let text: String
}

/// One map of the study: a route overview or an intersection.
struct StudyMap: Codable, Hashable, Identifiable {
    enum Kind: String, Codable {
        case overview
        case intersection
    }

    let id: String
    let kind: Kind
    let phase: StudyPhase
    /// How the logs name the map, e.g. "Intersection 2" or "Reversed intersection 5".
    let logID: String
    let title: String
    let subtitle: String
    let file: String
    /// Spoken when the map opens: the route overview, or the intersection
    /// announcement and route direction.
    let announcement: String
    let items: [InfoItem]

    enum CodingKeys: String, CodingKey {
        case id, kind, phase, title, subtitle, file, announcement, items
        case logID = "log_id"
    }

    /// The items played on this map, in order: all of them, except in Trial 2,
    /// where only those switched on.
    func items(with settings: InfoSettings) -> [InfoItem] {
        guard phase.usesCustomInfo else { return items }
        return items.filter { settings[$0.category] }
    }
}

enum StudyContent {
    static let maps: [StudyMap] = load()

    static func map(id: String) -> StudyMap? {
        maps.first { $0.id == id }
    }

    static func maps(in phase: StudyPhase) -> [StudyMap] {
        maps.filter { $0.phase == phase }
    }

    private static func load() -> [StudyMap] {
        struct Manifest: Codable { let maps: [StudyMap] }
        guard let url = Bundle.main.url(forResource: "study", withExtension: "json") else {
            Task { @MainActor in StudyLog.shared.error("study.json is missing from the app bundle") }
            return []
        }
        do {
            return try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url)).maps
        } catch {
            Task { @MainActor in StudyLog.shared.error("study.json could not be read: \(error.localizedDescription)") }
            return []
        }
    }
}
