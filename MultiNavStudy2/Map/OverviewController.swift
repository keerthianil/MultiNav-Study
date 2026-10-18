// OverviewController.swift
// The route map: the whole walk on one screen (full route mode) or one
// section of it (section by section mode). Both use the same elements.
//
// Under the finger, in priority order:
//   route start / end (yellow)  fast pulse, "Your location ..." / "Destination ..."
//   landmark (purple box)       fast pulse, "... on your right"
//   intersection (red square)   slow pulse and a ding, "4-way intersection of ..."
//   roundabout (red ring)       slow pulse and a ding, "Roundabout of ..."
//   route (cyan)                rhythmic pulse, "Route along ..."
//   street (blue)               steady heavy buzz, street name
// A single tap gives the turn-by-turn direction for an intersection or a
// stretch of route. A double tap on an intersection opens its close-up.
// On a section map the next intersection is at the top ("Next: ...") and
// the section starts at the bottom; the route drawn past the top shows the
// turn made there.

import UIKit

@MainActor
final class OverviewController: MapScene, TactileCanvasDelegate {
    let config: SessionConfig
    let composer: DirectionsComposer
    private(set) var map: OverviewMap
    /// The section shown, or nil on the full route.
    private(set) var section: RouteDirections.Section?
    weak var canvas: TactileCanvasView?

    var onOpenIntersection: ((OverviewIntersection) -> Void)?
    /// A back gesture on the map itself; the session decides what it does.
    var onBack: ((String) -> Void)?
    /// Next (true) or previous section; returns false at either end.
    var onSection: ((Bool, String) -> Bool)?
    var onMagicTap: (() -> Void)?

    private let feedback = FeedbackManager.shared
    private let log = StudyLog.shared
    private var legBoundaries: [CGFloat]

    private var activeHit: Hit = .none
    private var lastAnnouncedLeg: Int?
    private var spokenThisTouch: Set<Hit> = []
    private var lastTouchSpoken: Set<Hit> = []
    private var lastMoveLog: TimeInterval = 0

    enum Hit: Hashable {
        case none
        case endpoint(Int)
        case landmark(Int)
        case intersection(Int)
        case route(leg: Int)
        case street(Int)
    }

    init(config: SessionConfig, composer: DirectionsComposer, map: OverviewMap, section: RouteDirections.Section?) {
        self.config = config
        self.composer = composer
        self.map = map
        self.section = section
        self.legBoundaries = map.legBoundaries
    }

    /// Shows another map, such as the next section.
    func show(map newMap: OverviewMap, section newSection: RouteDirections.Section?) {
        canvas?.reset()
        feedback.set(.none)
        map = newMap
        section = newSection
        legBoundaries = newMap.legBoundaries
        activeHit = .none
        lastAnnouncedLeg = nil
        spokenThisTouch = []
        lastTouchSpoken = []
        canvas?.configureAccessibility(label: accessibilityLabel, hint: accessibilityHint)
        canvas?.setNeedsLayout()
        canvas?.setNeedsDisplay()
    }

    var mapSize: CGSize { map.size }
    var isCentered: Bool { false }
    private var options: StageSettings { config.options }

    var accessibilityLabel: String {
        if let section {
            return "Route \(config.route.number), section \(section.index) of \(section.count). "
                + "\(section.street) to \(section.to)"
        }
        return "Map overview. Route \(config.route.number), \(config.route.title)"
    }

    var accessibilityHint: String {
        var hint = "Drag to explore."
        if options.intersectionCloseUps { hint += " Double tap an intersection to open it." }
        if section != nil { hint += " Three-finger swipe up for the next section, down for the previous one." }
        return hint
    }

    // MARK: Drawing

    func draw(in context: CGContext, transform t: MapTransform) {
        guard options.showMap else {
            MapDrawing.drawHiddenMap(in: context)
            return
        }
        let style = MapStyle.Overview.self
        context.setLineCap(.round)
        context.setLineJoin(.round)

        for street in map.streets {
            MapDrawing.stroke(street.points, width: style.roadWidth, color: MapStyle.roadBlue, in: context, t)
        }
        MapDrawing.stroke(map.route, width: style.routeWidth, color: MapStyle.routeCyan, in: context, t)

        for intersection in map.intersections {
            let center = t.point(intersection.position)
            switch intersection.kind {
            case .junction:
                let side = t.length(style.intersectionSide)
                let rect = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
                context.setFillColor(MapStyle.intersectionRed.cgColor)
                context.fill(rect)
                context.setStrokeColor(MapStyle.outlineWhite.cgColor)
                context.setLineWidth(t.length(style.intersectionBorder))
                context.setLineJoin(.miter)
                context.stroke(rect.insetBy(dx: t.length(style.intersectionBorder) / 2,
                                            dy: t.length(style.intersectionBorder) / 2))
                context.setLineJoin(.round)
            case .roundabout:
                let r = t.length(style.roundaboutRadius)
                let ring = CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)
                context.setStrokeColor(MapStyle.outlineWhite.cgColor)
                context.setLineWidth(t.length(style.roundaboutStroke + 2 * style.intersectionBorder))
                context.strokeEllipse(in: ring)
                context.setStrokeColor(MapStyle.intersectionRed.cgColor)
                context.setLineWidth(t.length(style.roundaboutStroke))
                context.strokeEllipse(in: ring)
            }
        }

        if options.landmarks {
            for landmark in map.landmarks {
                let rect = CGRect(origin: t.point(landmark.boxRect.origin),
                                  size: CGSize(width: t.length(landmark.boxRect.width),
                                               height: t.length(landmark.boxRect.height)))
                let path = UIBezierPath(roundedRect: rect, cornerRadius: t.length(style.landmarkCorner))
                context.setFillColor(MapStyle.landmarkPurple.cgColor)
                context.addPath(path.cgPath)
                context.fillPath()
                context.setStrokeColor(MapStyle.outlineWhite.cgColor)
                context.setLineWidth(t.length(style.landmarkBorder))
                context.addPath(path.cgPath)
                context.strokePath()
                MapDrawing.drawTag(landmark.tag, in: rect.insetBy(dx: t.length(0.6), dy: t.length(0.4)))
            }
        }

        for endpoint in map.endpoints {
            MapDrawing.dot(at: t.point(endpoint.position), diameter: t.length(style.endpointDiameter),
                           border: t.length(style.endpointBorder), color: MapStyle.endpointYellow, in: context)
        }
    }

    // MARK: Hit testing (mm)

    private func hit(at p: CGPoint) -> Hit {
        let found = rawHit(at: p)
        // Keep the current element while the finger is still close to it, unless
        // something with higher priority has been reached.
        if activeHit != .none, found != activeHit, priority(found) >= priority(activeHit),
           isStillNear(activeHit, p) {
            return activeHit
        }
        return found
    }

    private func rawHit(at p: CGPoint, slack: CGFloat = 0) -> Hit {
        let h = MapStyle.Hit.self
        for (i, endpoint) in map.endpoints.enumerated()
        where MapGeometry.distance(p, endpoint.position) <= h.endpoint + slack {
            return .endpoint(i)
        }
        if options.landmarks {
            for (i, landmark) in map.landmarks.enumerated() {
                if MapGeometry.distance(p, landmark.anchor) <= h.landmarkAnchor + slack
                    || landmark.boxRect.insetBy(dx: -(h.landmarkBoxSlack + slack),
                                                dy: -(h.landmarkBoxSlack + slack)).contains(p) {
                    return .landmark(i)
                }
            }
        }
        var bestIntersection: (index: Int, distance: CGFloat)?
        for (i, intersection) in map.intersections.enumerated() {
            let radius = intersection.kind == .roundabout ? h.roundabout : h.intersection
            let d = MapGeometry.distance(p, intersection.position)
            if d <= radius + slack, d < (bestIntersection?.distance ?? .infinity) {
                bestIntersection = (i, d)
            }
        }
        if let bestIntersection { return .intersection(bestIntersection.index) }
        if MapGeometry.polylineDistance(p, map.route) <= h.route + slack {
            return .route(leg: legIndex(at: p))
        }
        var bestStreet: (index: Int, distance: CGFloat)?
        for (i, street) in map.streets.enumerated() {
            let d = MapGeometry.polylineDistance(p, street.points)
            if d <= h.overviewRoad + slack, d < (bestStreet?.distance ?? .infinity) {
                bestStreet = (i, d)
            }
        }
        if let bestStreet { return .street(bestStreet.index) }
        return .none
    }

    private func isStillNear(_ hit: Hit, _ p: CGPoint) -> Bool {
        let slack = MapStyle.Hit.hysteresis
        switch hit {
        case .street(let i):
            return MapGeometry.polylineDistance(p, map.streets[i].points) <= MapStyle.Hit.overviewRoad + slack
        case .route:
            return MapGeometry.polylineDistance(p, map.route) <= MapStyle.Hit.route + slack
        default:
            return rawHit(at: p, slack: slack) == hit
        }
    }

    private func priority(_ hit: Hit) -> Int {
        switch hit {
        case .endpoint: return 0
        case .landmark: return 1
        case .intersection: return 2
        case .route: return 3
        case .street: return 4
        case .none: return 5
        }
    }

    /// Leg 0 runs from the start to the first intersection, leg 1 to the next,
    /// and so on. On a section map, leg 1 is the route drawn past the next
    /// intersection to show the turn.
    private func legIndex(at p: CGPoint) -> Int {
        let progress = MapGeometry.arcLength(of: p, along: map.route)
        var leg = 0
        for (i, boundary) in legBoundaries.enumerated() where progress + 1.0 >= boundary {
            leg = i + 1
        }
        return min(leg, legBoundaries.count)
    }

    /// The directions section a stretch of route belongs to.
    private func sectionForLeg(_ leg: Int) -> RouteDirections.Section? {
        if let section { return section }
        let sections = composer.directions.sections
        guard !sections.isEmpty else { return nil }
        return sections[min(leg, sections.count - 1)]
    }

    // MARK: Speech

    private func announcement(for hit: Hit) -> String? {
        switch hit {
        case .none:
            return nil
        case .endpoint(let i):
            let endpoint = map.endpoints[i]
            if endpoint.kind == .departure {
                return "\(endpoint.announcement). Route to \(map.destinationName)"
            }
            return endpoint.announcement
        case .landmark(let i):
            return map.landmarks[i].announcement
        case .intersection(let i):
            let intersection = map.intersections[i]
            let name = composer.intersectionName(intersection)
            switch intersection.role {
            case .next: return "Next: \(name)"
            case .sectionStart: return "Start of section: \(name)"
            case .route, .beyond: return name
            }
        case .route(let leg):
            guard let s = sectionForLeg(leg) else { return "Route" }
            if section != nil {
                return leg == 0 ? composer.routeLeg(s, first: false) : composer.routeContinuation(s)
            }
            return composer.routeLeg(s, first: leg == 0)
        case .street(let i):
            return map.streets[i].name
        }
    }

    /// What a single tap adds: the turn-by-turn direction where there is one.
    private func tapDetail(for hit: Hit) -> String? {
        guard options.turnByTurn else { return nil }
        let directions = composer.directions
        switch hit {
        case .intersection(let i):
            let intersection = map.intersections[i]
            switch intersection.role {
            case .next:
                return section.map(composer.maneuver)
            case .sectionStart:
                // The turn made at the intersection this section starts from.
                guard let section, section.index > 1 else { return nil }
                return composer.maneuver(directions.sections[section.index - 2])
            case .route:
                return directions.section(endingAt: intersection.id).map(composer.maneuver)
            case .beyond:
                return nil
            }
        case .route(let leg):
            guard let s = sectionForLeg(leg) else { return nil }
            if section != nil, leg > 0 { return composer.routeContinuation(s) }
            return composer.walk(s)
        default:
            return nil
        }
    }

    private func speak(_ text: String, for hit: Hit) {
        spokenThisTouch.insert(hit)
        feedback.speak(text)
    }

    private func begin(_ hit: Hit) {
        switch hit {
        case .none:
            feedback.set(.none)
        case .endpoint, .landmark:
            feedback.set(.landmark)
            if let text = announcement(for: hit) { speak(text, for: hit) }
        case .intersection:
            feedback.set(.intersection)
            if let text = announcement(for: hit) { speak(text, for: hit) }
        case .route(let leg):
            feedback.set(.route)
            if leg != lastAnnouncedLeg {
                lastAnnouncedLeg = leg
                if let text = announcement(for: hit) { speak(text, for: hit) }
            }
        case .street:
            feedback.set(.road)
            if let text = announcement(for: hit) { speak(text, for: hit) }
        }
    }

    private func logName(for hit: Hit) -> String {
        switch hit {
        case .none: return "Background"
        case .endpoint(let i):
            return map.endpoints[i].kind == .departure
                ? "Route Start - \(map.departureName)" : "Route End - \(map.destinationName)"
        case .landmark(let i): return "Landmark - \(map.landmarks[i].name)"
        case .intersection(let i):
            let x = map.intersections[i]
            var name = (x.kind == .roundabout ? "Roundabout - " : "Intersection - ") + x.name
            switch x.role {
            case .next: name += " (next)"
            case .sectionStart: name += " (section start)"
            case .beyond: name += " (beyond destination)"
            case .route: break
            }
            return name
        case .route(let leg):
            if section != nil { return leg == 0 ? "Route" : "Route (turn)" }
            return "Route (leg \(leg + 1))"
        case .street(let i): return map.streets[i].name
        }
    }

    // MARK: TactileCanvasDelegate

    func canvas(_ canvas: TactileCanvasView, touch phase: CanvasTouchPhase, mm: CGPoint, screen: CGPoint) {
        switch phase {
        case .began:
            spokenThisTouch = []
            lastAnnouncedLeg = nil
            activeHit = .none
            let found = rawHit(at: mm)
            activeHit = found
            begin(found)
            logTouch(.touchDown, hit: found, mm: mm, screen: screen)
        case .moved:
            let found = hit(at: mm)
            if found != activeHit {
                activeHit = found
                begin(found)
            }
            let now = CACurrentMediaTime()
            if now - lastMoveLog >= 0.1 {
                lastMoveLog = now
                logTouch(.touchMove, hit: found, mm: mm, screen: screen)
            }
        case .ended, .cancelled:
            logTouch(.touchUp, hit: activeHit, mm: mm, screen: screen)
            feedback.set(.none)
            lastTouchSpoken = spokenThisTouch
            activeHit = .none
            lastAnnouncedLeg = nil
        }
    }

    func canvas(_ canvas: TactileCanvasView, singleTapAt mm: CGPoint, screen: CGPoint) {
        let found = rawHit(at: mm)
        feedback.pulse()
        log.event(.gesture, "Single tap", detail: logName(for: found))
        if let detail = tapDetail(for: found) {
            feedback.speak(detail)
        } else if !lastTouchSpoken.contains(found), let text = announcement(for: found) {
            // The element was already named when the finger landed on it.
            feedback.speak(text)
        }
    }

    func canvas(_ canvas: TactileCanvasView, doubleTapAt mm: CGPoint, screen: CGPoint) {
        feedback.pulse()
        let tapped = map.intersections
            .map { ($0, MapGeometry.distance(mm, $0.position)) }
            .filter { $0.1 <= MapStyle.Hit.intersectionDoubleTap }
            .min { $0.1 < $1.1 }?.0
        guard let tapped else {
            log.event(.gesture, "Double tap", detail: "No intersection")
            return
        }
        log.event(.gesture, "Double tap", detail: tapped.name)
        guard options.intersectionCloseUps else {
            feedback.speak("Intersection close-ups are turned off.", essential: true)
            return
        }
        guard config.route.details.contains(tapped.detailFile) else {
            feedback.speak("There is no close-up for this intersection.", essential: true)
            return
        }
        feedback.silence()
        onOpenIntersection?(tapped)
    }

    func canvasRequestsBack(_ canvas: TactileCanvasView, gesture: String) {
        onBack?(gesture)
    }

    func canvasRequestsSection(_ canvas: TactileCanvasView, forward: Bool, gesture: String) -> Bool {
        guard section != nil else {
            log.event(.gesture, forward ? "Next section" : "Previous section", detail: "\(gesture), full route map")
            feedback.speak("Sections are not used on this map.", essential: true)
            return false
        }
        return onSection?(forward, gesture) ?? false
    }

    func canvasMagicTap(_ canvas: TactileCanvasView) {
        onMagicTap?()
    }

    private func logTouch(_ type: StudyTouchType, hit: Hit, mm: CGPoint, screen: CGPoint) {
        log.touch(type, element: logName(for: hit), screen: screen, mm: mm)
    }
}
