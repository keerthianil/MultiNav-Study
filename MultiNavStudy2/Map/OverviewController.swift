// OverviewController.swift
// Level 1: the whole route on one screen.
//
// Under the finger, in priority order:
//   route start / end (yellow)  fast pulse, "Your location ..." / "Destination ..."
//   landmark (purple box)       fast pulse, "... on your right"
//   intersection (red square)   slow pulse and a ding, "4-way intersection of ..."
//   roundabout (red ring)       slow pulse and a ding, "Roundabout of ..."
//   route (cyan)                rhythmic pulse, "Route to ..." on the first leg, then "Route"
//   street (blue)               steady heavy buzz, street name
// Double tap an intersection on the route to open its close-up.

import UIKit

@MainActor
final class OverviewController: MapScene, TactileCanvasDelegate {
    let route: RouteInfo
    let map: OverviewMap
    weak var canvas: TactileCanvasView?

    var onOpenIntersection: ((OverviewIntersection) -> Void)?
    var onBack: (() -> Void)?

    private let feedback = FeedbackManager.shared
    private let log = StudyLog.shared
    private let legBoundaries: [CGFloat]

    private var activeHit: Hit = .none
    private var lastAnnouncedLeg: Int?
    private var spokenThisTouch: Set<Hit> = []
    private var lastTouchSpoken: Set<Hit> = []
    private var lastMoveLog: TimeInterval = 0
    private var isLeaving = false

    enum Hit: Hashable {
        case none
        case endpoint(Int)
        case landmark(Int)
        case intersection(Int)
        case route(leg: Int)
        case street(Int)
    }

    init(route: RouteInfo, map: OverviewMap) {
        self.route = route
        self.map = map
        self.legBoundaries = map.legBoundaries
    }

    var mapSize: CGSize { map.size }
    var isCentered: Bool { false }

    var accessibilityLabel: String {
        "Map overview. Route \(route.number), \(route.title)"
    }

    var accessibilityHint: String {
        "Drag to explore. Double tap an intersection to open it. Three-finger swipe right to go back."
    }

    var magicTapSummary: String {
        let count = map.intersections.count
        return "Route \(route.number), from \(route.departure) to \(route.destination). \(count) intersections."
    }

    func screenDidAppear() {
        isLeaving = false
    }

    // MARK: Drawing

    func draw(in context: CGContext, transform t: MapTransform) {
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

        for landmark in map.landmarks {
            let rect = CGRect(origin: t.point(landmark.boxRect.origin),
                              size: CGSize(width: t.length(landmark.boxRect.width), height: t.length(landmark.boxRect.height)))
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
        for (i, landmark) in map.landmarks.enumerated() {
            if MapGeometry.distance(p, landmark.anchor) <= h.landmarkAnchor + slack
                || landmark.boxRect.insetBy(dx: -(h.landmarkBoxSlack + slack), dy: -(h.landmarkBoxSlack + slack)).contains(p) {
                return .landmark(i)
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

    /// Leg 0 runs from the start to the first intersection, leg 1 to the next, and so on.
    private func legIndex(at p: CGPoint) -> Int {
        let progress = MapGeometry.arcLength(of: p, along: map.route)
        var leg = 0
        for (i, boundary) in legBoundaries.enumerated() where progress + 1.0 >= boundary {
            leg = i + 1
        }
        return min(leg, legBoundaries.count)
    }

    // MARK: Feedback

    private func begin(_ hit: Hit) {
        switch hit {
        case .none:
            feedback.set(.none)
        case .endpoint(let i):
            feedback.set(.landmark)
            let endpoint = map.endpoints[i]
            if endpoint.kind == .departure {
                speak("\(endpoint.announcement). \(routeToDestination)", for: hit)
            } else {
                speak(endpoint.announcement, for: hit)
            }
        case .landmark(let i):
            feedback.set(.landmark)
            speak(map.landmarks[i].announcement, for: hit)
        case .intersection(let i):
            feedback.set(.intersection)
            speak(map.intersections[i].announcement, for: hit)
        case .route(let leg):
            feedback.set(.route)
            if leg != lastAnnouncedLeg {
                lastAnnouncedLeg = leg
                speak(routeAnnouncement(leg: leg), for: hit)
            }
        case .street(let i):
            feedback.set(.road)
            speak(map.streets[i].name, for: hit)
        }
    }

    private var routeToDestination: String {
        "Route to \(map.destinationName)"
    }

    private func routeAnnouncement(leg: Int) -> String {
        leg == 0 ? routeToDestination : "Route"
    }

    private func speak(_ text: String, for hit: Hit) {
        spokenThisTouch.insert(hit)
        feedback.speak(text)
    }

    private func announcement(for hit: Hit) -> String? {
        switch hit {
        case .none: return nil
        case .endpoint(let i):
            let endpoint = map.endpoints[i]
            return endpoint.kind == .departure ? "\(endpoint.announcement). \(routeToDestination)" : endpoint.announcement
        case .landmark(let i): return map.landmarks[i].announcement
        case .intersection(let i): return map.intersections[i].announcement
        case .route(let leg): return routeAnnouncement(leg: leg)
        case .street(let i): return map.streets[i].name
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
            return (x.kind == .roundabout ? "Roundabout - " : "Intersection - ") + x.name
        case .route(let leg): return "Route (leg \(leg + 1))"
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
        // The element was already named when the finger landed on it.
        if !lastTouchSpoken.contains(found), let text = announcement(for: found) {
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
        log.event(.gesture, "Double tap", detail: "\(tapped.name)")
        guard map.waypointIDs.contains(tapped.id), !tapped.detailFile.isEmpty else {
            feedback.speak("This intersection is not on your route.")
            return
        }
        feedback.stopAll()
        onOpenIntersection?(tapped)
    }

    func canvasRequestsBack(_ canvas: TactileCanvasView, gesture: String) {
        guard !isLeaving else { return }
        isLeaving = true
        log.event(.gesture, "Back", detail: gesture)
        canvas.reset()
        feedback.stopAll()
        feedback.backTap()
        onBack?()
    }

    func canvasMagicTap(_ canvas: TactileCanvasView) {
        log.event(.gesture, "Magic tap", detail: "Route summary")
        feedback.speak(magicTapSummary)
    }

    private func logTouch(_ type: StudyTouchType, hit: Hit, mm: CGPoint, screen: CGPoint) {
        log.touch(type, element: logName(for: hit), screen: screen, mm: mm)
    }
}
