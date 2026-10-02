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
    static let island = TactileElementType(rawValue: "island")
    static let roundabout = TactileElementType(rawValue: "roundabout")
    static let centralIsland = TactileElementType(rawValue: "central_island")
    static let junctionCenter = TactileElementType(rawValue: "center")
    static let info = TactileElementType(rawValue: "info")
}

// MARK: - Shared pieces

struct MapLine {
    let id: String
    let name: String
    let points: [CGPoint]
    let width: CGFloat
}

struct RouteEndpoint {
    enum Kind { case departure, destination }
    let kind: Kind
    let position: CGPoint
    let announcement: String
}

// MARK: - Level 1

struct OverviewIntersection {
    enum Kind { case junction, roundabout }
    let id: String
    let name: String
    let announcement: String
    let kind: Kind
    let legs: Int
    let detailFile: String
    let position: CGPoint
}

struct OverviewLandmark {
    let id: String
    let name: String
    let tag: String
    let announcement: String
    let anchor: CGPoint
    /// Unit vector from the road to the box, in screen axes.
    let offset: CGVector

    var boxCenter: CGPoint {
        let style = MapStyle.Overview.self
        let extent = abs(offset.dx) * style.landmarkWidth / 2 + abs(offset.dy) * style.landmarkHeight / 2
        let distance = style.roadWidth / 2 + style.landmarkGap + extent
        return CGPoint(x: anchor.x + offset.dx * distance, y: anchor.y + offset.dy * distance)
    }

    var boxRect: CGRect {
        let c = boxCenter
        let style = MapStyle.Overview.self
        return CGRect(x: c.x - style.landmarkWidth / 2, y: c.y - style.landmarkHeight / 2,
                      width: style.landmarkWidth, height: style.landmarkHeight)
    }
}

struct OverviewMap {
    let title: String
    let size: CGSize
    let streets: [MapLine]
    let intersections: [OverviewIntersection]
    let landmarks: [OverviewLandmark]
    let route: [CGPoint]
    let departureName: String
    let destinationName: String
    let waypointIDs: [String]
    let endpoints: [RouteEndpoint]

    /// Distance along the route at which each waypoint is reached.
    var legBoundaries: [CGFloat] {
        waypointIDs.compactMap { id in intersections.first { $0.id == id } }
            .map { MapGeometry.arcLength(of: $0.position, along: route) }
    }
}

// MARK: - Level 2

struct Crosswalk {
    enum Ends { case both, start, end }
    let id: String
    let name: String
    let start: CGPoint
    let end: CGPoint
    let ends: Ends
    let assumed: Bool
    /// The part of the crossing that lies over the roadway, where the stripes are painted.
    var paintStart: CGPoint
    var paintEnd: CGPoint
}

struct CircleArea {
    let name: String
    let radius: CGFloat
}

struct RingRoad {
    let name: String
    let radius: CGFloat
    let width: CGFloat
}

struct DetailMap {
    let title: String
    let spokenTitle: String
    let intro: String
    let isRoundabout: Bool
    let size: CGSize
    let roads: [MapLine]
    let islands: [MapLine]
    let sidewalks: [MapLine]
    let crosswalks: [Crosswalk]
    let ring: RingRoad?
    let centralIsland: CircleArea?
    let center: CircleArea?
    let route: [CGPoint]
    let endpoints: [RouteEndpoint]
    /// Crosswalk ends drawn as pink dots (shared corners appear once).
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
        var intersections: [OverviewIntersection] = []
        var landmarks: [OverviewLandmark] = []
        var route: [CGPoint] = []
        var departure = ""
        var destination = ""
        var waypoints: [String] = []

        for element in document.features {
            let custom = element.properties.custom
            switch element.elementType {
            case .corridor:
                streets.append(MapLine(id: element.id, name: element.properties.name,
                                       points: element.points, width: MapStyle.Overview.roadWidth))
            case .intersection:
                intersections.append(OverviewIntersection(
                    id: element.id,
                    name: element.properties.name,
                    announcement: custom["announcement"] ?? element.properties.name,
                    kind: custom["kind"] == "roundabout" ? .roundabout : .junction,
                    legs: Int(custom["legs"] ?? "") ?? 0,
                    detailFile: custom["detail"] ?? "",
                    position: element.points.first ?? .zero))
            case .landmark:
                landmarks.append(OverviewLandmark(
                    id: element.id,
                    name: element.properties.name,
                    tag: custom["tag"] ?? "",
                    announcement: custom["announcement"] ?? element.properties.name,
                    anchor: element.points.first ?? .zero,
                    offset: CGVector(dx: CGFloat(Double(custom["offset_x"] ?? "") ?? 0),
                                     dy: CGFloat(Double(custom["offset_y"] ?? "") ?? 0))))
            case .route:
                route = element.points
                departure = custom["departure"] ?? ""
                destination = custom["destination"] ?? ""
                waypoints = (custom["waypoints"] ?? "").split(separator: ",").map(String.init)
            default:
                break
            }
        }
        guard route.count > 1 else { throw MapLoadError.missing(file, "route") }

        let endpoints = [
            RouteEndpoint(kind: .departure, position: route[0], announcement: "Your location, \(departure)"),
            RouteEndpoint(kind: .destination, position: route[route.count - 1], announcement: "Destination, \(destination)"),
        ]
        return OverviewMap(
            title: document.metadata?.name ?? file,
            size: CGSize(width: document.bounds.width, height: document.bounds.height),
            streets: streets, intersections: intersections, landmarks: landmarks,
            route: route, departureName: departure, destinationName: destination,
            waypointIDs: waypoints, endpoints: endpoints)
    }

    static func detail(named file: String, bundle: Bundle = .main) throws -> DetailMap {
        let document = try TactileMapDocument.load(from: file, bundle: bundle)
        var title = document.metadata?.name ?? file
        var spokenTitle = title
        var intro = title
        var isRoundabout = false
        var roads: [MapLine] = []
        var islands: [MapLine] = []
        var sidewalks: [MapLine] = []
        var crosswalks: [Crosswalk] = []
        var ring: RingRoad?
        var centralIsland: CircleArea?
        var center: CircleArea?
        var route: [CGPoint] = []
        var departure = ""
        var destination = ""

        for element in document.features {
            let custom = element.properties.custom
            let name = element.properties.name
            let width = CGFloat(Double(custom["width_mm"] ?? "") ?? 0)
            switch element.elementType {
            case .info:
                intro = name
                title = custom["title"] ?? title
                spokenTitle = custom["spoken_title"] ?? title
                isRoundabout = custom["kind"] == "roundabout"
            case .corridor:
                roads.append(MapLine(id: element.id, name: name, points: element.points, width: width))
            case .island:
                islands.append(MapLine(id: element.id, name: name, points: element.points, width: width))
            case .sidewalk:
                sidewalks.append(MapLine(id: element.id, name: name, points: element.points,
                                         width: MapStyle.Detail.sidewalkWidth))
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
                                            assumed: custom["assumed"] == "yes",
                                            paintStart: points[0], paintEnd: points[points.count - 1]))
            case .roundabout:
                ring = RingRoad(name: name, radius: CGFloat(Double(custom["radius_mm"] ?? "") ?? 0), width: width)
            case .centralIsland:
                centralIsland = CircleArea(name: name, radius: CGFloat(Double(custom["radius_mm"] ?? "") ?? 0))
            case .junctionCenter:
                center = CircleArea(name: name, radius: CGFloat(Double(custom["radius_mm"] ?? "") ?? 0))
            case .route:
                route = element.points
                departure = custom["departure"] ?? "Your location"
                destination = custom["destination"] ?? "End of route"
            default:
                break
            }
        }
        guard route.count > 1 else { throw MapLoadError.missing(file, "walking route") }

        func isOnRoadway(_ p: CGPoint) -> Bool {
            if let ring, abs(hypot(p.x, p.y) - ring.radius) <= ring.width / 2 { return true }
            return roads.contains { MapGeometry.polylineDistance(p, $0.points) <= $0.width / 2 }
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

        var crosswalkEnds: [CGPoint] = []
        for crosswalk in crosswalks {
            var points: [CGPoint] = []
            if crosswalk.ends != .end { points.append(crosswalk.start) }
            if crosswalk.ends != .start { points.append(crosswalk.end) }
            for point in points where !crosswalkEnds.contains(where: { MapGeometry.distance($0, point) < 2.0 }) {
                crosswalkEnds.append(point)
            }
        }

        return DetailMap(
            title: title, spokenTitle: spokenTitle, intro: intro, isRoundabout: isRoundabout,
            size: CGSize(width: document.bounds.width, height: document.bounds.height),
            roads: roads, islands: islands, sidewalks: sidewalks,
            crosswalks: crosswalks, ring: ring, centralIsland: centralIsland, center: center,
            route: route,
            endpoints: [
                RouteEndpoint(kind: .departure, position: route[0], announcement: departure),
                RouteEndpoint(kind: .destination, position: route[route.count - 1], announcement: destination),
            ],
            crosswalkEnds: crosswalkEnds,
            turns: routeTurns(route))
    }

    /// Bends on the walking path sharper than the turn threshold, at least 4 mm apart.
    static func routeTurns(_ route: [CGPoint]) -> [CGPoint] {
        guard route.count >= 3 else { return [] }
        var turns: [CGPoint] = []
        for i in 1..<(route.count - 1) {
            let angle = abs(MapGeometry.turnAngle(route[i - 1], route[i], route[i + 1]))
            guard angle > MapStyle.Detail.turnThresholdDegrees else { continue }
            if turns.contains(where: { MapGeometry.distance($0, route[i]) < MapStyle.Detail.turnMergeDistance }) {
                continue
            }
            turns.append(route[i])
        }
        return turns
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
