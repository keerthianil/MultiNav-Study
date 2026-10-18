// RouteDirections.swift
// Turn-by-turn directions for one route, read from Maps/routeN_directions.json
// (written by tools/build_maps.py). Each section runs from where the
// traveller is to the next intersection, or to the destination, and lists
// what to do there: the crossings, then the turn.

import Foundation

struct RouteDirections: Codable {
    let route: String
    let number: Int
    let title: String
    let start: String
    let destination: String
    /// "left" or "right" for the destination building, or empty.
    let destinationSide: String
    let intersections: Int
    let totalM: Int
    let sections: [Section]

    struct Section: Codable, Hashable {
        let index: Int
        let count: Int
        let map: String
        let street: String
        let distanceM: Int
        let from: String
        /// "start" or "intersection".
        let fromKind: String
        /// How the next point is named in "walk ... to ...".
        let to: String
        /// "intersection", "roundabout" or "destination".
        let toKind: String
        let toName: String
        /// Id of the next intersection on the route maps, or empty.
        let junctionId: String
        /// Close-up file of the next intersection, or empty.
        let detail: String
        let typeText: String
        let controlText: String
        /// Compass side of the street walked, and the same side as left or right.
        let side: String
        let sideRelative: String
        let crossings: [Crossing]
        /// Compass side of a roundabout walked round, or empty.
        let around: String
        /// "straight", "left", "slight right", ... or empty at the destination.
        let turn: String
        let nextStreet: String
        let nextSide: String
        let nextSideRelative: String

        var endsAtDestination: Bool { toKind == "destination" }
    }

    struct Crossing: Codable, Hashable {
        let street: String
        let detail: String
        let twoStage: Bool
        let island: String
        let oneWay: Bool
    }

    static func load(named file: String, bundle: Bundle = .main) throws -> RouteDirections {
        guard let url = bundle.url(forResource: file, withExtension: "json") else {
            throw MapLoadError.missing(file, "directions file")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(RouteDirections.self, from: Data(contentsOf: url))
    }

    /// The section that ends at the given intersection (by route map id).
    func section(endingAt junctionID: String) -> Section? {
        sections.first { $0.junctionId == junctionID }
    }

    /// The section that ends at the intersection with the given close-up file.
    func section(withDetail file: String) -> Section? {
        sections.first { $0.detail == file }
    }
}
