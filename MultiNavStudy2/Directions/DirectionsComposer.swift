// DirectionsComposer.swift
// Builds every spoken direction from the pieces in RouteDirections, leaving
// out whatever the researcher has switched off (distances, sides, details)
// without rewording the rest. With every detail on, the wording matches the
// directions tools/build_maps.py writes into docs/ROUTES.md.

import Foundation

struct DirectionsComposer {
    typealias Section = RouteDirections.Section

    let directions: RouteDirections
    let options: StageSettings
    let units: DistanceUnits
    let sideWords: SideWords

    init(directions: RouteDirections, config: SessionConfig) {
        self.init(directions: directions, options: config.options, units: config.units, sideWords: config.sideWords)
    }

    init(directions: RouteDirections, options: StageSettings, units: DistanceUnits, sideWords: SideWords) {
        self.directions = directions
        self.options = options
        self.units = units
        self.sideWords = sideWords
    }

    // MARK: Pieces

    /// "about 550 feet" or "about 170 metres".
    func distance(_ metres: Int) -> String {
        switch units {
        case .feet:
            let feet = Double(metres) * 3.28084
            let step = feet < 500 ? 10.0 : 50.0
            return "about \(Int(max(step, (feet / step + 0.5).rounded(.down) * step))) feet"
        case .metres:
            let value = Double(metres)
            let step = value < 200 ? 5.0 : 10.0
            return "about \(Int(max(step, (value / step + 0.5).rounded(.down) * step))) metres"
        }
    }

    /// "on the northwest side" or "on the right-hand side", or nil when sides are off.
    func side(compass: String, relative: String) -> String? {
        guard options.streetSide else { return nil }
        switch sideWords {
        case .compass: return compass.isEmpty ? nil : "on the \(compass) side"
        case .relative: return relative.isEmpty ? nil : "on the \(relative)-hand side"
        }
    }

    /// "Walk along Bedford Street, on the northwest side, about 550 feet, to Deering Avenue."
    func walk(_ s: Section) -> String {
        var text = s.index == 1 ? "Start at \(directions.start). " : ""
        text += "Walk along \(s.street)"
        if let side = side(compass: s.side, relative: s.sideRelative) {
            text += ", \(side)"
        }
        if options.distances {
            text += ", \(distance(s.distanceM))"
        }
        text += ", to \(s.to)."
        if s.endsAtDestination, !directions.destinationSide.isEmpty {
            text += " It is on your \(directions.destinationSide)."
        }
        return text
    }

    /// "Then turn right onto Deering Avenue, on the southwest side."
    func turn(_ s: Section, then: Bool) -> String {
        guard !s.turn.isEmpty else { return "" }
        var text: String
        if s.turn == "straight" {
            text = "continue straight on \(s.nextStreet)"
        } else if s.turn.hasPrefix("slight ") {
            text = "bear \(s.turn.dropFirst("slight ".count)) onto \(s.nextStreet)"
        } else if s.turn.hasPrefix("sharp ") {
            text = "make a sharp \(s.turn.dropFirst("sharp ".count)) onto \(s.nextStreet)"
        } else {
            text = "turn \(s.turn) onto \(s.nextStreet)"
        }
        if let side = side(compass: s.nextSide, relative: s.nextSideRelative) {
            text += ", \(side)"
        }
        return (then ? "Then " + text : Self.capitalizedFirst(text)) + "."
    }

    /// What to do at the intersection a section ends at, or "" at the destination.
    func maneuver(_ s: Section) -> String {
        guard !s.endsAtDestination else { return "" }
        var parts = ["At \(s.to)."]
        if options.intersectionDetails {
            parts.append(Self.capitalizedFirst(s.typeText) + ".")
            if !s.controlText.isEmpty { parts.append(s.controlText) }
        }
        for (n, crossing) in s.crossings.enumerated() {
            var text = "Cross \(crossing.street)."
            if options.crosswalkDetails, !crossing.detail.isEmpty { text += " \(crossing.detail)." }
            if crossing.twoStage, !crossing.island.isEmpty { text += " Two stages, with a \(crossing.island)." }
            if options.crosswalkDetails, crossing.oneWay { text += " One-way street." }
            parts.append(text)
            if n == 0, !s.around.isEmpty, s.crossings.count > 1 {
                parts.append("Walk around the \(s.around) side of the roundabout.")
            }
        }
        let turnText = turn(s, then: !s.crossings.isEmpty)
        if !turnText.isEmpty { parts.append(turnText) }
        return parts.joined(separator: " ")
    }

    /// The walk and what to do at its end.
    func directionsText(_ s: Section) -> String {
        let atEnd = maneuver(s)
        return atEnd.isEmpty ? walk(s) : walk(s) + " " + atEnd
    }

    /// Where a section goes, without directions.
    func brief(_ s: Section) -> String {
        "Along \(s.street) to \(s.to)."
    }

    // MARK: Spoken passages

    func sectionStatus(_ s: Section) -> String {
        "Section \(s.index) of \(s.count)."
    }

    /// Spoken when a section opens.
    func sectionIntro(_ s: Section, withDirections: Bool) -> String {
        sectionStatus(s) + " " + (withDirections ? directionsText(s) : brief(s))
    }

    /// The whole route read aloud.
    func overview() -> String {
        var text = "Route \(directions.number): \(directions.title). \(directions.intersections) intersections"
        if options.distances { text += ", \(distance(directions.totalM))" }
        text += "."
        for s in directions.sections {
            text += " Section \(s.index). " + (options.turnByTurn ? directionsText(s) : brief(s))
        }
        return text
    }

    /// A short summary of the route.
    func summary() -> String {
        var text = "Route \(directions.number), from \(directions.start) to \(directions.destination). "
            + "\(directions.intersections) intersections"
        if options.distances { text += ", \(distance(directions.totalM))" }
        return text + "."
    }

    /// Spoken when the finger reaches the route on the full route map.
    func routeLeg(_ s: Section, first: Bool) -> String {
        var text = first ? "Route to \(directions.destination), along \(s.street)" : "Route along \(s.street)"
        if let side = side(compass: s.side, relative: s.sideRelative) {
            text += ", \(side)"
        }
        return text
    }

    /// Spoken on the route drawn past the next intersection in a section.
    func routeContinuation(_ s: Section) -> String {
        if options.turnByTurn, !s.turn.isEmpty { return turn(s, then: true) }
        return "Route continues on \(s.nextStreet)"
    }

    /// The name spoken for an intersection on a route map.
    func intersectionName(_ intersection: OverviewIntersection) -> String {
        if options.intersectionDetails || intersection.kind == .roundabout || intersection.namesText.isEmpty {
            return intersection.announcement
        }
        return "Intersection of \(intersection.namesText)"
    }

    static func capitalizedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}
