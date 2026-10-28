// IntersectionController.swift
// An intersection map: one junction at its true angles, turned so the way
// the participant walks in is up, with the walking path through it.
//
// Under the finger, in priority order:
//   turn (orange dot)           repeating ding and tap, "Turn"
//   crosswalk end (pink dot)    one ding
//   route start / end (yellow)  fast pulse, "You are here" / "End of intersection route"
//   median (green)              fast, sharp pulses, "Median", also where the
//                               route crosses it, between the two stages
//   route on a crosswalk        route pulse and crosswalk clicks, "Crosswalk across ..."
//   route (cyan)                rhythmic pulse, "Route"
//   centre of the intersection  two-note chime and no vibration, "Center"
//   crosswalk (white)           clicks, with the road buzz under them, "Crosswalk across ..."
//   sidewalk (grey)             softer steady buzz, "Sidewalk along ..."
//   road (blue)                 heavy buzz, street name
// The centre and the median always work, whatever information items the
// researcher has switched off.
//
// Gestures: double tap plays or stops the information items, two-finger
// double tap plays the announcement again or stops it, three-finger swipe up
// and down move between items, and three-finger swipe right (or the
// VoiceOver escape) tells the app the participant is ready to cross.
// While the announcement or an item plays, map names are held back so they
// do not cut it off; vibration and sounds carry on.

import UIKit

@MainActor
final class IntersectionController: StudyMapController {
    let map: IntersectionMap
    let player: DescriptionPlayer
    let canvasLabel: String
    weak var canvas: TactileCanvasView?
    var showMap = true
    var onFinishRequest: ((String) -> Void)?
    var onTouchDown: (() -> Void)?

    private let feedback = FeedbackManager.shared
    private let log = StudyLog.shared

    private var activeHit: Hit = .none
    private var announcedEnd = false
    private var spokenThisTouch: Set<Hit> = []
    private var lastTouchSpoken: Set<Hit> = []
    private var lastMoveLog: TimeInterval = 0

    enum Hit: Hashable {
        case none
        case turn(Int)
        case crosswalkEnd(Int)
        case endpoint(Int)
        case routeOnCrosswalk(Int)
        case route
        case center
        case crosswalk(Int, overRoad: Bool)
        case median(Int)
        case sidewalk(Int)
        case road(Int)
    }

    init(map: IntersectionMap, player: DescriptionPlayer, label: String) {
        self.map = map
        self.player = player
        canvasLabel = label
    }

    var mapSize: CGSize { map.size }
    var fillColor: UIColor { showMap ? MapStyle.background : .black }
    var isCentered: Bool { true }

    // MARK: Drawing

    func draw(in context: CGContext, transform t: MapTransform) {
        guard showMap else {
            MapDrawing.drawHiddenMap(in: context)
            return
        }
        let style = MapStyle.Intersection.self
        context.setLineCap(.round)
        context.setLineJoin(.round)

        for sidewalk in map.sidewalks {
            MapDrawing.stroke(sidewalk.points, width: sidewalk.width, color: MapStyle.sidewalkGray, in: context, t)
        }
        for road in map.roads {
            MapDrawing.stroke(road.points, width: road.width, color: MapStyle.roadBlue, in: context, t)
        }
        for median in map.medians {
            MapDrawing.stroke(median.points, width: median.width, color: MapStyle.medianGreen, in: context, t)
        }
        MapDrawing.stroke(map.route, width: style.routeWidth + 2 * style.routeOutline, color: MapStyle.roadBlue,
                          in: context, t)
        MapDrawing.stroke(map.route, width: style.routeWidth, color: MapStyle.routeCyan, in: context, t)
        for crosswalk in map.crosswalks {
            let a = t.point(crosswalk.paintStart)
            let b = t.point(crosswalk.paintEnd)
            switch crosswalk.marking {
            case .zebra:
                MapDrawing.crosswalkStripes(from: a, to: b,
                                            stripeLength: t.length(style.crosswalkStripeLength),
                                            stripeWidth: t.length(style.crosswalkStripeWidth),
                                            maxCount: style.crosswalkStripes,
                                            minGap: t.length(style.crosswalkStripeMinGap), in: context)
            case .unmarked:
                MapDrawing.unmarkedCrossing(from: a, to: b, offset: t.length(style.unmarkedLineOffset),
                                            lineWidth: max(1, t.length(style.unmarkedLineWidth)),
                                            dash: t.length(1.2), in: context)
            }
        }
        if let center = map.center, map.showsCenterMark {
            let c = t.point(center)
            let r = t.length(style.centerMarkDiameter) / 2
            context.setStrokeColor(MapStyle.outlineWhite.cgColor)
            context.setLineWidth(max(1, t.length(0.4)))
            context.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        }
        for end in map.crosswalkEnds {
            MapDrawing.dot(at: t.point(end), diameter: t.length(style.crosswalkEndDiameter),
                           border: t.length(style.dotBorder), color: MapStyle.crosswalkEndPink, in: context)
        }
        for turn in map.turns {
            MapDrawing.dot(at: t.point(turn), diameter: t.length(style.turnDiameter),
                           border: t.length(style.dotBorder), color: MapStyle.turnOrange, in: context)
        }
        for endpoint in map.endpoints {
            MapDrawing.dot(at: t.point(endpoint.position), diameter: t.length(style.endpointDiameter),
                           border: t.length(style.dotBorder), color: MapStyle.endpointYellow, in: context)
        }
    }

    // MARK: Hit testing (mm)

    private func hit(at p: CGPoint) -> Hit {
        let found = rawHit(at: p)
        if activeHit != .none, found != activeHit, priority(found) >= priority(activeHit),
           rawHit(at: p, slack: MapStyle.Hit.hysteresis) == activeHit {
            return activeHit
        }
        return found
    }

    private func rawHit(at p: CGPoint, slack: CGFloat = 0) -> Hit {
        let h = MapStyle.Hit.self
        if let i = map.turns.firstIndex(where: { MapGeometry.distance(p, $0) <= h.turn + slack }) {
            return .turn(i)
        }
        if let i = map.crosswalkEnds.firstIndex(where: { MapGeometry.distance(p, $0) <= h.crosswalkEnd + slack }) {
            return .crosswalkEnd(i)
        }
        if let i = map.endpoints.firstIndex(where: { MapGeometry.distance(p, $0.position) <= h.endpoint + slack }) {
            return .endpoint(i)
        }
        if let i = map.medians.firstIndex(where: {
            MapGeometry.polylineDistance(p, $0.points) <= $0.width / 2 + h.medianSlack + slack
        }) {
            return .median(i)
        }
        let onRoute = MapGeometry.polylineDistance(p, map.route) <= h.route + slack
        let crosswalk = nearestCrosswalk(p, slack: slack)
        if onRoute, let crosswalk { return .routeOnCrosswalk(crosswalk) }
        if onRoute { return .route }
        if let center = map.center, MapGeometry.distance(p, center) <= map.centerRadius + slack {
            return .center
        }
        if let crosswalk { return .crosswalk(crosswalk, overRoad: roadIndex(at: p) != nil) }
        var bestSidewalk: (index: Int, distance: CGFloat)?
        for (i, sidewalk) in map.sidewalks.enumerated() {
            let d = MapGeometry.polylineDistance(p, sidewalk.points)
            if d <= h.sidewalk + slack, d < (bestSidewalk?.distance ?? .infinity) {
                bestSidewalk = (i, d)
            }
        }
        if let bestSidewalk { return .sidewalk(bestSidewalk.index) }
        if let i = roadIndex(at: p, slack: slack) { return .road(i) }
        return .none
    }

    private func nearestCrosswalk(_ p: CGPoint, slack: CGFloat) -> Int? {
        var best: (index: Int, distance: CGFloat)?
        for (i, crosswalk) in map.crosswalks.enumerated() {
            let d = MapGeometry.segmentDistance(p, crosswalk.start, crosswalk.end).distance
            if d <= MapStyle.Hit.crosswalk + slack, d < (best?.distance ?? .infinity) {
                best = (i, d)
            }
        }
        return best?.index
    }

    private func roadIndex(at p: CGPoint, slack: CGFloat = 0) -> Int? {
        var best: (index: Int, distance: CGFloat)?
        for (i, road) in map.roads.enumerated() {
            let d = MapGeometry.polylineDistance(p, road.points)
            if d <= road.width / 2 + slack, d < (best?.distance ?? .infinity) {
                best = (i, d)
            }
        }
        return best?.index
    }

    private func priority(_ hit: Hit) -> Int {
        switch hit {
        case .turn: return 0
        case .crosswalkEnd: return 1
        case .endpoint: return 2
        case .median: return 3
        case .routeOnCrosswalk: return 4
        case .route: return 5
        case .center: return 6
        case .crosswalk: return 7
        case .sidewalk: return 8
        case .road: return 9
        case .none: return 10
        }
    }

    // MARK: Feedback

    private func begin(_ hit: Hit) {
        switch hit {
        case .none: feedback.set(.none)
        case .turn: feedback.set(.turn)
        case .crosswalkEnd: feedback.set(.crosswalkEnd)
        case .endpoint(let i):
            feedback.set(.endpoint)
            if map.endpoints[i].kind == .end { announcedEnd = true }
        case .routeOnCrosswalk: feedback.set(.routeOverCrosswalk)
        case .route: feedback.set(.route)
        case .center: feedback.set(.center)
        case .crosswalk(_, let overRoad): feedback.set(.crosswalk(overRoad: overRoad))
        case .median: feedback.set(.median)
        case .sidewalk: feedback.set(.sidewalk)
        case .road: feedback.set(.road)
        }
        if let text = name(of: hit) {
            say(text, for: hit)
        }
    }

    /// A map name, unless a description is playing: then the map only
    /// vibrates and sounds, so the description is heard to the end.
    private func say(_ text: String, for hit: Hit) {
        guard !player.isPlaying else { return }
        spokenThisTouch.insert(hit)
        feedback.speak(text)
    }

    private func name(of hit: Hit) -> String? {
        switch hit {
        case .none, .crosswalkEnd: return nil
        case .turn: return "Turn"
        case .endpoint(let i): return map.endpoints[i].announcement
        case .routeOnCrosswalk(let i): return map.crosswalks[i].name
        case .route: return "Route"
        case .center: return "Center"
        case .crosswalk(let i, _): return map.crosswalks[i].name
        case .median(let i): return map.medians[i].name
        case .sidewalk(let i): return map.sidewalks[i].name
        case .road(let i): return map.roads[i].name
        }
    }

    private func logName(for hit: Hit) -> String {
        switch hit {
        case .none: return "Background"
        case .turn: return "Route Turn"
        case .crosswalkEnd: return "Crosswalk End"
        case .endpoint(let i): return map.endpoints[i].kind == .start ? "Route Start" : "Route End"
        case .routeOnCrosswalk(let i): return "Route on \(map.crosswalks[i].name)"
        case .route: return "Route"
        case .center: return "Center"
        case .crosswalk(let i, _): return map.crosswalks[i].name
        case .median: return "Median"
        case .sidewalk(let i): return map.sidewalks[i].name
        case .road(let i): return map.roads[i].name
        }
    }

    // MARK: TactileCanvasDelegate

    func canvas(_ canvas: TactileCanvasView, touch phase: CanvasTouchPhase, mm: CGPoint, screen: CGPoint) {
        switch phase {
        case .began:
            onTouchDown?()
            spokenThisTouch = []
            announcedEnd = false
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
            if phase == .ended, !announcedEnd, case .endpoint(let i) = rawHit(at: mm), map.endpoints[i].kind == .end {
                say(map.endpoints[i].announcement, for: .endpoint(i))
            }
            feedback.set(.none)
            lastTouchSpoken = spokenThisTouch
            activeHit = .none
        }
    }

    func canvas(_ canvas: TactileCanvasView, singleTapAt mm: CGPoint, screen: CGPoint) {
        let found = rawHit(at: mm)
        log.event(.gesture, "Single tap", detail: logName(for: found))
        switch found {
        case .turn:
            feedback.turnDing()
        case .crosswalkEnd:
            break
        default:
            feedback.pulse()
        }
        if !lastTouchSpoken.contains(found), let text = name(of: found) {
            say(text, for: found)
        }
    }

    func canvas(_ canvas: TactileCanvasView, doubleTapAt mm: CGPoint, screen: CGPoint) {
        log.event(.gesture, "Double tap", detail: logName(for: rawHit(at: mm)))
        feedback.pulse()
        player.toggleDetails(gesture: "Double tap")
    }

    func canvasTwoFingerDoubleTap(_ canvas: TactileCanvasView, gesture: String) {
        log.event(.gesture, gesture)
        player.toggleAnnouncement(gesture: gesture)
    }

    func canvasRequestsItem(_ canvas: TactileCanvasView, forward: Bool, gesture: String,
                            voiceOverScroll: Bool) -> Bool {
        log.event(.gesture, gesture)
        return player.step(forward: forward, gesture: gesture, voiceOverScroll: voiceOverScroll)
    }

    func canvasRequestsFinish(_ canvas: TactileCanvasView, gesture: String) {
        log.event(.gesture, gesture)
        onFinishRequest?(gesture)
    }
}
