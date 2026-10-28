// MapModels.swift
// Turns the bundled map JSON into drawable, touchable map elements.
// The JSON is read with the MultiNav TactileMapDocument loader; this file
// only interprets the element types the study maps use.
// All coordinates are millimetres on screen.

import CoreGraphics
import Foundation
import TactileMapCore

extension TactileElementType {
    static let sidewalk = TactileElementType(rawValue: "sidewalk")
    static let median = TactileElementType(rawValue: "median")
    static let junctionCenter = TactileElementType(rawValue: "center")
    static let turn = TactileElementType(rawValue: "turn")
    static let crosswalkEnd = TactileElementType(rawValue: "crosswalk_end")
    static let mapLabel = TactileElementType(rawValue: "label")
}

// MARK: - Shared pieces

struct MapLine {
    let id: String
    let name: String
    let points: [CGPoint]
    let width: CGFloat
}

struct RouteEndpoint {
    enum Kind { case start, end }
    let kind: Kind
    let position: CGPoint
    let announcement: String
}

/// Text printed on a map for anyone watching; it is never spoken.
struct MapLabel {
    let text: String
    let position: CGPoint
    let size: CGFloat
    let angle: CGFloat
}

// MARK: - Route overviews

struct OverviewNode {
    let id: String
    let number: Int
    let name: String
    /// Spoken when the finger reaches the node, e.g. "Intersection 1: 4-way
    /// intersection of Fore Street and Silver Street."
    let cue: String
    let position: CGPoint
}

struct OverviewMap {
    let title: String
    let size: CGSize
    let streets: [MapLine]
    let nodes: [OverviewNode]
    let route: [CGPoint]
    let endpoints: [RouteEndpoint]
    let labels: [MapLabel]
}

// MARK: - Intersection maps

struct Crosswalk {
    enum Ends { case both, start, end }
    enum Marking { case zebra, unmarked }
    let id: String
    let name: String
    let start: CGPoint
    let end: CGPoint
    let ends: Ends
    let marking: Marking
    /// The part of the crossing that lies over the roadway, where it is painted.
    var paintStart: CGPoint
    var paintEnd: CGPoint
}

struct IntersectionMap {
    let title: String
    let size: CGSize
    let roads: [MapLine]
    let medians: [MapLine]
    let sidewalks: [MapLine]
    let crosswalks: [Crosswalk]
    let center: CGPoint?
    let centerRadius: CGFloat
    /// False where a crosswalk runs over the centre, so its ring is not drawn there.
    let showsCenterMark: Bool
    let route: [CGPoint]
    let endpoints: [RouteEndpoint]
    /// Crosswalk ends drawn as pink dots, placed by the map generator so no
    /// two dots overlap.
    let crosswalkEnds: [CGPoint]
    /// Bends on the walking path drawn as orange turn dots.
    let turns: [CGPoint]
}

// MARK: - Loading

enum MapLoadError: LocalizedError {
    case missing(String, String)

    var errorDescription: String? {
        switch self {
        case let .missing(file, what): return "\(file) has no \(what)"
        }
    }
}

enum MapLoader {
    static func overview(named file: String, bundle: Bundle = .main) throws -> OverviewMap {
        let document = try TactileMapDocument.load(from: file, bundle: bundle)
        var streets: [MapLine] = []
        var nodes: [OverviewNode] = []
        var route: [CGPoint] = []
        var startText = ""
        var endText = ""
        var labels: [MapLabel] = []

        for element in document.features {
            let custom = element.properties.custom
            switch element.elementType {
            case .corridor:
                streets.append(MapLine(id: element.id, name: element.properties.name,
                                       points: element.points, width: MapStyle.Overview.roadWidth))
            case .intersection:
                nodes.append(OverviewNode(
                    id: element.id,
                    number: Int(custom["number"] ?? "") ?? 0,
                    name: element.properties.name,
                    cue: custom["cue"] ?? element.properties.name,
                    position: element.points.first ?? .zero))
            case .route:
                route = element.points
                startText = custom["start_text"] ?? "Start of route"
                endText = custom["end_text"] ?? "End of route"
            case .mapLabel:
                labels.append(label(element))
            default:
                break
            }
        }
        guard route.count > 1 else { throw MapLoadError.missing(file, "route") }
        return OverviewMap(
            title: document.metadata?.name ?? file,
            size: CGSize(width: document.bounds.width, height: document.bounds.height),
            streets: streets, nodes: nodes, route: route,
            endpoints: [
                RouteEndpoint(kind: .start, position: route[0], announcement: startText),
                RouteEndpoint(kind: .end, position: route[route.count - 1], announcement: endText),
            ],
            labels: labels)
    }

    static func intersection(named file: String, bundle: Bundle = .main) throws -> IntersectionMap {
        let document = try TactileMapDocument.load(from: file, bundle: bundle)
        var roads: [MapLine] = []
        var medians: [MapLine] = []
        var sidewalks: [MapLine] = []
        var crosswalks: [Crosswalk] = []
        var center: CGPoint?
        var centerRadius: CGFloat = 0
        var showsCenterMark = true
        var route: [CGPoint] = []
        var startText = ""
        var endText = ""
        var crosswalkEnds: [CGPoint] = []
        var turns: [CGPoint] = []

        for element in document.features {
            let custom = element.properties.custom
            let name = element.properties.name
            let width = CGFloat(Double(custom["width_mm"] ?? "") ?? 0)
            switch element.elementType {
            case .corridor:
                roads.append(MapLine(id: element.id, name: name, points: element.points, width: width))
            case .median:
                medians.append(MapLine(id: element.id, name: name, points: element.points, width: width))
            case .sidewalk:
                sidewalks.append(MapLine(id: element.id, name: name, points: element.points,
                                         width: MapStyle.Intersection.sidewalkWidth))
            case .crosswalk:
                let points = element.points
                guard points.count >= 2 else { continue }
                let ends: Crosswalk.Ends
                switch custom["endpoints"] {
                case "start": ends = .start
                case "end": ends = .end
                default: ends = .both
                }
                crosswalks.append(Crosswalk(id: element.id, name: name, start: points[0],
                                            end: points[points.count - 1], ends: ends,
                                            marking: custom["marking"] == "unmarked" ? .unmarked : .zebra,
                                            paintStart: points[0], paintEnd: points[points.count - 1]))
            case .junctionCenter:
                center = element.points.first
                centerRadius = CGFloat(Double(custom["radius_mm"] ?? "") ?? 0)
                showsCenterMark = custom["mark"] != "no"
            case .route:
                route = element.points
                startText = custom["start_text"] ?? "You are here"
                endText = custom["end_text"] ?? "End of intersection route"
            case .turn:
                if let p = element.points.first { turns.append(p) }
            case .crosswalkEnd:
                if let p = element.points.first { crosswalkEnds.append(p) }
            default:
                break
            }
        }
        guard route.count > 1 else { throw MapLoadError.missing(file, "walking route") }

        // Stripes and markings are painted only over the roadway.
        func isOnRoadway(_ p: CGPoint) -> Bool {
            roads.contains { MapGeometry.polylineDistance(p, $0.points) <= $0.width / 2 }
        }
        for i in crosswalks.indices {
            let a = crosswalks[i].start
            let b = crosswalks[i].end
            let samples = 60
            let inside = (0...samples).map { CGFloat($0) / CGFloat(samples) }.filter {
                isOnRoadway(CGPoint(x: a.x + (b.x - a.x) * $0, y: a.y + (b.y - a.y) * $0))
            }
            if let first = inside.first, let last = inside.last, last > first {
                crosswalks[i].paintStart = CGPoint(x: a.x + (b.x - a.x) * first, y: a.y + (b.y - a.y) * first)
                crosswalks[i].paintEnd = CGPoint(x: a.x + (b.x - a.x) * last, y: a.y + (b.y - a.y) * last)
            }
        }

        return IntersectionMap(
            title: document.metadata?.name ?? file,
            size: CGSize(width: document.bounds.width, height: document.bounds.height),
            roads: roads, medians: medians, sidewalks: sidewalks, crosswalks: crosswalks,
            center: center, centerRadius: centerRadius, showsCenterMark: showsCenterMark,
            route: route,
            endpoints: [
                RouteEndpoint(kind: .start, position: route[0], announcement: startText),
                RouteEndpoint(kind: .end, position: route[route.count - 1], announcement: endText),
            ],
            crosswalkEnds: crosswalkEnds,
            turns: turns)
    }

    private static func label(_ element: MapElement) -> MapLabel {
        let custom = element.properties.custom
        return MapLabel(text: element.properties.name,
                        position: element.points.first ?? .zero,
                        size: CGFloat(Double(custom["size_mm"] ?? "") ?? 3),
                        angle: CGFloat(Double(custom["angle"] ?? "") ?? 0))
    }
}

extension MapElement {
    /// Geometry as millimetre points.
    var points: [CGPoint] {
        switch geometry {
        case .point(let c):
            return [CGPoint(x: c.x, y: c.y)]
        case .lineString(let cs), .polygon(let cs):
            return cs.map { CGPoint(x: $0.x, y: $0.y) }
        }
    }
}
