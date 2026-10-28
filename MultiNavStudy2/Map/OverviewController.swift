// OverviewController.swift
// A route overview: the whole walk on one screen as a schematic, laid out
// like the research team's mockup, with the start near the bottom.
//
// Under the finger, in priority order:
//   start / end (yellow dot)     fast pulse, "Start of route: You are here, at ..."
//                                or "End of route: Your destination, ..."
//   intersection (red square)    slow pulse and a ding, "Intersection 1: 4-way
//                                intersection of ..."
//   route (cyan)                 rhythmic pulse, "Route"
//   street (blue)                steady heavy buzz, street name
// The route overview plays when the map opens. A double tap or a two-finger
// double tap plays it again, or stops it while it plays. Three-finger swipe
// right (or the VoiceOver escape) finishes with the map.

import UIKit

@MainActor
final class OverviewController: StudyMapController {
    let map: OverviewMap
    let player: DescriptionPlayer
    let canvasLabel: String
    weak var canvas: TactileCanvasView?
    var showMap = true
    var onFinishRequest: ((String) -> Void)?
    var onTouchDown: (() -> Void)?

    private let feedback = FeedbackManager.shared
    private let log = StudyLog.shared

    private var activeHit: Hit = .none
    private var spokenThisTouch: Set<Hit> = []
    private var lastTouchSpoken: Set<Hit> = []
    private var lastMoveLog: TimeInterval = 0

    enum Hit: Hashable {
        case none
        case endpoint(Int)
        case node(Int)
        case route
        case street(Int)
    }

    init(map: OverviewMap, player: DescriptionPlayer, label: String) {
        self.map = map
        self.player = player
        canvasLabel = label
    }

    var mapSize: CGSize { map.size }
    var fillColor: UIColor { showMap ? MapStyle.background : .black }
    var isCentered: Bool { false }

    // MARK: Drawing

    func draw(in context: CGContext, transform t: MapTransform) {
        guard showMap else {
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

        for node in map.nodes {
            let center = t.point(node.position)
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
        }
        for endpoint in map.endpoints {
            MapDrawing.dot(at: t.point(endpoint.position), diameter: t.length(style.endpointDiameter),
                           border: t.length(style.endpointBorder), color: MapStyle.endpointYellow, in: context)
        }
        for label in map.labels {
            MapDrawing.label(label.text, at: t.point(label.position), size: t.length(label.size),
                             angle: label.angle, in: context)
        }
    }

    // MARK: Hit testing (mm)

    private func hit(at p: CGPoint) -> Hit {
        let found = rawHit(at: p)
        // Keep the current element while the finger is still close to it, unless
        // something with higher priority has been reached.
        if activeHit != .none, found != activeHit, priority(found) >= priority(activeHit),
           rawHit(at: p, slack: MapStyle.Hit.hysteresis) == activeHit || isStillNear(activeHit, p) {
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
        var bestNode: (index: Int, distance: CGFloat)?
        for (i, node) in map.nodes.enumerated() {
            let d = MapGeometry.distance(p, node.position)
            if d <= h.intersection + slack, d < (bestNode?.distance ?? .infinity) {
                bestNode = (i, d)
            }
        }
        if let bestNode { return .node(bestNode.index) }
        if MapGeometry.polylineDistance(p, map.route) <= h.route + slack {
            return .route
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
            return false
        }
    }

    private func priority(_ hit: Hit) -> Int {
        switch hit {
        case .endpoint: return 0
        case .node: return 1
        case .route: return 2
        case .street: return 3
        case .none: return 4
        }
    }

    // MARK: Feedback

    private func name(of hit: Hit) -> String? {
        switch hit {
        case .none: return nil
        case .endpoint(let i): return map.endpoints[i].announcement
        case .node(let i): return map.nodes[i].cue
        case .route: return "Route"
        case .street(let i): return map.streets[i].name
        }
    }

    private func begin(_ hit: Hit) {
        switch hit {
        case .none: feedback.set(.none)
        case .endpoint: feedback.set(.endpoint)
        case .node: feedback.set(.intersection)
        case .route: feedback.set(.route)
        case .street: feedback.set(.road)
        }
        if let text = name(of: hit) { say(text, for: hit) }
    }

    /// A map name, unless the overview is playing: then the map only
    /// vibrates and sounds, so the overview is heard to the end.
    private func say(_ text: String, for hit: Hit) {
        guard !player.isPlaying else { return }
        spokenThisTouch.insert(hit)
        feedback.speak(text)
    }

    private func logName(for hit: Hit) -> String {
        switch hit {
        case .none: return "Background"
        case .endpoint(let i): return map.endpoints[i].kind == .start ? "Route Start" : "Route End"
        case .node(let i): return map.nodes[i].name
        case .route: return "Route"
        case .street(let i): return map.streets[i].name
        }
    }

    // MARK: TactileCanvasDelegate

    func canvas(_ canvas: TactileCanvasView, touch phase: CanvasTouchPhase, mm: CGPoint, screen: CGPoint) {
        switch phase {
        case .began:
            onTouchDown?()
            spokenThisTouch = []
            activeHit = .none
            let found = rawHit(at: mm)
            activeHit = found
            begin(found)
            log.touch(.touchDown, element: logName(for: found), screen: screen, mm: mm, speaking: player.speaking)
        case .moved:
            let found = hit(at: mm)
            if found != activeHit {
                activeHit = found
                begin(found)
            }
            let now = CACurrentMediaTime()
            if now - lastMoveLog >= 0.1 {
                lastMoveLog = now
                log.touch(.touchMove, element: logName(for: found), screen: screen, mm: mm, speaking: player.speaking)
            }
        case .ended, .cancelled:
            log.touch(.touchUp, element: logName(for: activeHit), screen: screen, mm: mm, speaking: player.speaking)
            feedback.set(.none)
            lastTouchSpoken = spokenThisTouch
            activeHit = .none
        }
    }

    func canvas(_ canvas: TactileCanvasView, singleTapAt mm: CGPoint, screen: CGPoint) {
        let found = rawHit(at: mm)
        feedback.pulse()
        log.event(.gesture, "Single tap", detail: logName(for: found))
        if !lastTouchSpoken.contains(found), let text = name(of: found) {
            // The element was already named when the finger landed on it.
            say(text, for: found)
        }
    }

    func canvas(_ canvas: TactileCanvasView, doubleTapAt mm: CGPoint, screen: CGPoint) {
        log.event(.gesture, "Double tap", detail: logName(for: rawHit(at: mm)))
        feedback.pulse()
        player.toggleAnnouncement(gesture: "Double tap")
    }

    func canvasTwoFingerDoubleTap(_ canvas: TactileCanvasView, gesture: String) {
        log.event(.gesture, gesture)
        player.toggleAnnouncement(gesture: gesture)
    }

    func canvasRequestsItem(_ canvas: TactileCanvasView, forward: Bool, gesture: String,
                            voiceOverScroll: Bool) -> Bool {
        log.event(.gesture, gesture, detail: "No information items on an overview")
        if !voiceOverScroll { feedback.boundary() }
        return false
    }

    func canvasRequestsFinish(_ canvas: TactileCanvasView, gesture: String) {
        log.event(.gesture, gesture)
        onFinishRequest?(gesture)
    }
}
