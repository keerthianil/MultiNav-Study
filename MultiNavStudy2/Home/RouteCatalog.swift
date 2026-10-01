// RouteCatalog.swift
// The four study routes, read from Maps/routes.json (written by
// tools/build_maps.py together with the maps themselves).

import Foundation

struct RouteInfo: Codable, Hashable, Identifiable {
    let id: String
    let number: Int
    let title: String
    let summary: String
    let overview: String
    let details: [String]
    let departure: String
    let destination: String
}

enum RouteCatalog {
    static let routes: [RouteInfo] = load()

    static func route(id: String) -> RouteInfo? {
        routes.first { $0.id == id }
    }

    private static func load() -> [RouteInfo] {
        struct Manifest: Codable { let routes: [RouteInfo] }
        guard let url = Bundle.main.url(forResource: "routes", withExtension: "json") else {
            Task { @MainActor in StudyLog.shared.error("routes.json is missing from the app bundle") }
            return []
        }
        do {
            return try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url)).routes
        } catch {
            Task { @MainActor in StudyLog.shared.error("routes.json could not be read: \(error.localizedDescription)") }
            return []
        }
    }
}
