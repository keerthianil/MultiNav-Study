// DetailController.swift
// Intersection close-up: one intersection, drawn from OpenStreetMap at its true angles.
//
// Under the finger, in priority order:
//   turn (orange dot)          repeating ding and tap, "Turn"
//   crosswalk end (pink dot)   one ding, nothing else
//   centre of the junction     heavy buzz, "Center"
//   route start / end (yellow) fast pulse, "Your location ..." / "End of route ..."
//   route on a crosswalk       route pulse plus crosswalk clicks, crosswalk name
//   route (cyan)               rhythmic pulse, "Route"
//   crosswalk (white stripes)  clicks, with the road buzz under them, crosswalk name
//   island (green)             double-tap pattern, refuge or splitter island name
//   centre island (green)      silence, "Center island. Not a walkway"
//   sidewalk (grey)            softer steady buzz, sidewalk name
//   roundabout road (blue)     heavy buzz, "Roundabout. Traffic moves counterclockwise"
//   road (blue)                heavy buzz, street name
// Double tap anywhere returns to the map. A two-finger double tap repeats the
// intersection's summary and, with turn-by-turn directions on, what to do here.

import UIKit

@MainActor
final class DetailController: MapScene, TactileCanvasDelegate {
    let config: SessionConfig
    let map: DetailMap
    /// The directions section that ends at this intersection, if any.
    let section: RouteDirections.Section?
    let composer: DirectionsComposer?
    weak var canvas: TactileCanvasView?
    var onBack: (() -> Void)?

    private let feedback = FeedbackManager.shared
    private let log = StudyLog.shared

    private var activeHit: Hit = .none
    private var announcedDestination = false
    private var spokenThisTouch: Set<Hit> = []
    private var lastTouchSpoken: Set<Hit> = []
    private var lastMoveLog: TimeInterval = 0
    private var isLeaving = false

    enum Hit: Hashable {
        case none
        case turn(Int)
        case crosswalkEnd(Int)
        case center
        case endpoint(Int)
        case routeOnCrosswalk(Int)
        case route
        case crosswalk(Int, overRoad: Bool)
        case island(Int)
        case centralIsland
        case sidewalk(Int)
        case ring
        case road(Int)
    }

    init(config: SessionConfig, map: DetailMap, composer: DirectionsComposer?, section: RouteDirections.Section?) {
        self.config = config
        self.map = map
        self.composer = composer
        self.section = section
    }

    var mapSize: CGSize { map.size }
    var isCentered: Bool { true }
    private var options: StageSettings { config.options }

    /// "Intersection view. Fore Street and Franklin Street. 4-way intersection.
    /// Traffic signals.", without the type and control when those are off.
    var intro: String {
        guard !map.typeText.isEmpty else { return map.intro }
        var text = (map.isRoundabout ? "Roundabout view. " : "Intersection view. ") + map.title + "."
        if options.intersectionDetails {
            text += " " + DirectionsComposer.capitalizedFirst(map.typeText) + "."
            if !map.controlText.isEmpty { text += " " + map.controlText }
        }
        return text
    }

    var accessibilityLabel: String { intro }

    var accessibilityHint: String {
        "Drag to follow the route. Double tap anywhere to return to the map."
    }

    private func crosswalkName(_ i: Int) -> String {
        options.crosswalkDetails ? map.crosswalks[i].name : map.crosswalks[i].simpleName
    }

    private func sidewalkName(_ i: Int) -> String {
        let sidewalk = map.sidewalks[i]
        return options.streetSide ? sidewalk.name : (sidewalk.simpleName ?? sidewalk.name)
    }

    func screenDidAppear() {
        isLeaving = false
    }

    // MARK: Drawing

    func draw(in context: CGContext, transform t: MapTransform) {
        guard options.showMap else {
            MapDrawing.drawHiddenMap(in: context)
            return
        }
        let style = MapStyle.Detail.self
        context.setLineCap(.round)
        context.setLineJoin(.round)

        for sidewalk in map.sidewalks {
            MapDrawing.stroke(sidewalk.points, width: sidewalk.width, color: MapStyle.sidewalkGray, in: context, t)
        }
        for road in map.roads {
            MapDrawing.stroke(road.points, width: road.width, color: MapStyle.roadBlue, in: context, t)
        }
        if let ring = map.ring {
            let r = t.length(ring.radius)
            let center = t.point(.zero)
            context.setStrokeColor(MapStyle.roadBlue.cgColor)
            context.setLineWidth(t.length(ring.width))
            context.strokeEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
        }
        if let island = map.centralIsland {
            let r = t.length(island.radius)
            let center = t.point(.zero)
            context.setFillColor(MapStyle.islandGreen.cgColor)
            context.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
        }
        for line in map.islands {
            MapDrawing.stroke(line.points, width: line.width, color: MapStyle.islandGreen, in: context, t)
        }
        MapDrawing.stroke(map.route, width: style.routeWidth, color: MapStyle.routeCyan, in: context, t)
        for crosswalk in map.crosswalks {
            MapDrawing.crosswalkStripes(from: t.point(crosswalk.paintStart), to: t.point(crosswalk.paintEnd),
                                        stripeLength: t.length(style.crosswalkStripeLength),
                                        stripeWidth: t.length(style.crosswalkStripeWidth),
                                        maxCount: style.crosswalkStripes,
                                        minGap: t.length(style.crosswalkStripeMinGap), in: context)
        }
        for end in map.crosswalkEnds where !map.turns.contains(where: { MapGeometry.distance($0, end) < 3 }) {
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
        if let center = map.center, hypot(p.x, p.y) <= center.radius + slack {
            return .center
        }
        if let i = map.endpoints.firstIndex(where: { MapGeometry.distance(p, $0.position) <= h.endpoint + slack }) {
            return .endpoint(i)
        }
        let onRoute = MapGeometry.polylineDistance(p, map.route) <= h.route + slack
        let crosswalk = nearestCrosswalk(p, slack: slack)
        if onRoute, let crosswalk { return .routeOnCrosswalk(crosswalk) }
        if onRoute { return .route }
        if let crosswalk { return .crosswalk(crosswalk, overRoad: roadIndex(at: p) != nil || isOnRing(p)) }
        if let i = map.islands.firstIndex(where: {
            MapGeometry.polylineDistance(p, $0.points) <= $0.width / 2 + h.islandSlack + slack
        }) {
            return .island(i)
        }
        if let island = map.centralIsland, hypot(p.x, p.y) <= island.radius + slack {
            return .centralIsland
        }
        var bestSidewalk: (index: Int, distance: CGFloat)?
        for (i, sidewalk) in map.sidewalks.enumerated() {
            let d = MapGeometry.polylineDistance(p, sidewalk.points)
            if d <= h.sidewalk + slack, d < (bestSidewalk?.distance ?? .infinity) {
                bestSidewalk = (i, d)
            }
        }
        if let bestSidewalk { return .sidewalk(bestSidewalk.index) }
        if isOnRing(p, slack: slack) { return .ring }
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

    private func isOnRing(_ p: CGPoint, slack: CGFloat = 0) -> Bool {
        guard let ring = map.ring else { return false }
        return abs(hypot(p.x, p.y) - ring.radius) <= ring.width / 2 + slack
    }

    private func priority(_ hit: Hit) -> Int {
        switch hit {
        case .turn: return 0
        case .crosswalkEnd: return 1
        case .center: return 2
        case .endpoint: return 3
        case .routeOnCrosswalk: return 4
        case .route: return 5
        case .crosswalk: return 6
        case .island: return 7
        case .centralIsland: return 8
        case .sidewalk: return 9
        case .ring: return 10
        case .road: return 11
        case .none: return 12
        }
    }

    // MARK: Feedback

    private func begin(_ hit: Hit) {
        switch hit {
        case .none:
            feedback.set(.none)
        case .turn:
            feedback.set(.turn)
            speak("Turn", for: hit)
        case .crosswalkEnd:
            feedback.set(.crosswalkEnd)
        case .center:
            feedback.set(.road)
            speak("Center", for: hit)
        case .endpoint(let i):
            feedback.set(.landmark)
            let endpoint = map.endpoints[i]
            if endpoint.kind == .destination { announcedDestination = true }
            speak(endpoint.announcement, for: hit)
        case .routeOnCrosswalk(let i):
            // The crosswalk name says which street and, at the roundabout,
            // whether this half crosses the entry or the exit lane.
            feedback.set(.routeOverCrosswalk)
            speak(crosswalkName(i), for: hit)
        case .route:
            feedback.set(.route)
            speak("Route", for: hit)
        case .crosswalk(let i, let overRoad):
            feedback.set(.crosswalk(overRoad: overRoad))
            speak(crosswalkName(i), for: hit)
        case .island(let i):
            feedback.set(.island)
            speak(map.islands[i].name, for: hit)
        case .centralIsland:
            feedback.set(.none)
            speak(map.centralIsland?.name ?? "Center island", for: hit)
        case .sidewalk(let i):
            feedback.set(.sidewalk)
            speak(sidewalkName(i), for: hit)
        case .ring:
            feedback.set(.road)
            speak(map.ring?.name ?? "Roundabout", for: hit)
        case .road(let i):
            feedback.set(.road)
            speak(map.roads[i].name, for: hit)
        }
    }

    private func speak(_ text: String, for hit: Hit) {
        spokenThisTouch.insert(hit)
        feedback.speak(text)
    }

    private func announcement(for hit: Hit) -> String? {
        switch hit {
        case .none, .crosswalkEnd: return nil
        case .turn: return "Turn"
        case .center: return "Center"
        case .endpoint(let i): return map.endpoints[i].announcement
        case .routeOnCrosswalk(let i): return crosswalkName(i)
        case .route: return "Route"
        case .crosswalk(let i, _): return crosswalkName(i)
        case .island(let i): return map.islands[i].name
        case .centralIsland: return map.centralIsland?.name
        case .sidewalk(let i): return sidewalkName(i)
        case .ring: return map.ring?.name
        case .road(let i): return map.roads[i].name
        }
    }

    private func logName(for hit: Hit) -> String {
        switch hit {
        case .none: return "Background"
        case .turn: return "Route Turn"
        case .crosswalkEnd: return "Crosswalk End"
        case .center: return "Center"
        case .endpoint(let i): return map.endpoints[i].kind == .departure ? "Route Start" : "Route End"
        case .routeOnCrosswalk(let i): return "Route on \(map.crosswalks[i].name)"
        case .route: return "Route"
        case .crosswalk(let i, _): return map.crosswalks[i].name
        case .island(let i): return map.islands[i].name
        case .centralIsland: return "Center island"
        case .sidewalk(let i): return map.sidewalks[i].name
        case .ring: return "Roundabout roadway"
        case .road(let i): return map.roads[i].name
        }
    }

    // MARK: TactileCanvasDelegate

    func canvas(_ canvas: TactileCanvasView, touch phase: CanvasTouchPhase, mm: CGPoint, screen: CGPoint) {
        switch phase {
        case .began:
            spokenThisTouch = []
            announcedDestination = false
            activeHit = .none
            let found = rawHit(at: mm)
            activeHit = found
            begin(found)
            log.touch(.touchDown, element: logName(for: found), screen: screen, mm: mm)
        case .moved:
            let found = hit(at: mm)
            if found != activeHit {
                activeHit = found
                begin(found)
            }
            let now = CACurrentMediaTime()
            if now - lastMoveLog >= 0.1 {
                lastMoveLog = now
                log.touch(.touchMove, element: logName(for: found), screen: screen, mm: mm)
            }
        case .ended, .cancelled:
            log.touch(.touchUp, element: logName(for: activeHit), screen: screen, mm: mm)
            if phase == .ended, !announcedDestination, case .endpoint(let i) = rawHit(at: mm),
               map.endpoints[i].kind == .destination {
                feedback.speak(map.endpoints[i].announcement)
                spokenThisTouch.insert(.endpoint(i))
            }
            feedback.set(.none)
            lastTouchSpoken = spokenThisTouch
            activeHit = .none
        }
    }

    /// What to do at this intersection, when turn-by-turn directions are on.
    private var maneuver: String? {
        guard options.turnByTurn, let composer, let section else { return nil }
        let text = composer.maneuver(section)
        return text.isEmpty ? nil : text
    }

    func canvas(_ canvas: TactileCanvasView, singleTapAt mm: CGPoint, screen: CGPoint) {
        let found = rawHit(at: mm)
        log.event(.gesture, "Single tap", detail: logName(for: found))
        switch found {
        case .turn:
            feedback.turnDing()
            if let maneuver { feedback.speak(maneuver) }
            return
        case .crosswalkEnd:
            return
        case .route, .routeOnCrosswalk:
            feedback.pulse()
            if let maneuver {
                feedback.speak(maneuver)
                return
            }
        default:
            feedback.pulse()
        }
        if !lastTouchSpoken.contains(found), let text = announcement(for: found) {
            feedback.speak(text)
        }
    }

    func canvas(_ canvas: TactileCanvasView, doubleTapAt mm: CGPoint, screen: CGPoint) {
        feedback.pulse()
        requestBack(canvas, gesture: "Double tap")
    }

    func canvasRequestsBack(_ canvas: TactileCanvasView, gesture: String) {
        requestBack(canvas, gesture: gesture)
    }

    private func requestBack(_ canvas: TactileCanvasView, gesture: String) {
        guard !isLeaving else { return }
        isLeaving = true
        log.event(.gesture, "Back", detail: gesture)
        canvas.reset()
        feedback.silence()
        feedback.backTap()
        onBack?()
    }

    func canvasRequestsSection(_ canvas: TactileCanvasView, forward: Bool, gesture: String,
                               voiceOverScroll: Bool) -> Bool {
        log.event(.gesture, forward ? "Next section" : "Previous section", detail: "\(gesture), in a close-up")
        feedback.speak("Go back to the map to change sections.", essential: true)
        return false
    }

    func canvasMagicTap(_ canvas: TactileCanvasView) {
        log.event(.gesture, "Magic tap", detail: "Intersection summary")
        feedback.speak([intro, maneuver].compactMap { $0 }.joined(separator: " "), essential: true)
    }
}
